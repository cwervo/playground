import Foundation
import Swifter
import AppKit

class GoogleAuth {
    let clientId = ProcessInfo.processInfo.environment["GOOGLE_CLIENT_ID"] ?? ""
    let clientSecret = ProcessInfo.processInfo.environment["GOOGLE_CLIENT_SECRET"] ?? ""
    let redirectURI = "http://127.0.0.1:8080"
    
    func authenticate() async throws -> TokenInfo {
        print("Starting local server on port 8080...")
        let server = HttpServer()
        
        try server.start(8080)
        
        let authURLString = "https://accounts.google.com/o/oauth2/v2/auth?client_id=\(clientId)&redirect_uri=\(redirectURI)&response_type=code&scope=https://www.googleapis.com/auth/calendar.readonly&access_type=offline&prompt=consent"
        
        guard let url = URL(string: authURLString) else {
            throw NSError(domain: "Auth", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid auth URL"])
        }
        
        print("Opening browser for authentication...")
        NSWorkspace.shared.open(url)
        
        let code = await withCheckedContinuation { continuation in
            var resumed = false
            server["/"] = { request in
                if !resumed, let c = request.queryParams.first(where: { $0.0 == "code" })?.1 {
                    resumed = true
                    continuation.resume(returning: c)
                    return .ok(.htmlBody("Authentication successful! You can close this tab and return to the terminal."))
                }
                return .badRequest(.text("No code found"))
            }
        }
        
        server.stop()
        
        print("Got auth code, exchanging for token...")
        return try await exchangeCodeForToken(code: code)
    }
    
    func exchangeCodeForToken(code: String) async throws -> TokenInfo {
        let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyString = "client_id=\(clientId)&client_secret=\(clientSecret)&code=\(code)&grant_type=authorization_code&redirect_uri=\(redirectURI)"
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpRes = response as? HTTPURLResponse, httpRes.statusCode != 200 {
            if let errString = String(data: data, encoding: .utf8) {
                print("Error exchanging code: \(errString)")
            }
            throw NSError(domain: "Auth", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to exchange token"])
        }
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        
        return TokenInfo(
            accessToken: tokenResponse.access_token,
            refreshToken: tokenResponse.refresh_token,
            expiresIn: tokenResponse.expires_in,
            expirationDate: Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))
        )
    }
    
    func refreshAccessTokenIfNeeded(config: inout AppConfig) async throws {
        guard let tokenInfo = config.tokenInfo else {
            throw NSError(domain: "Auth", code: 3, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        if tokenInfo.expirationDate > Date().addingTimeInterval(60) {
            return // Still valid
        }
        
        guard let refreshToken = tokenInfo.refreshToken else {
            throw NSError(domain: "Auth", code: 4, userInfo: [NSLocalizedDescriptionKey: "No refresh token available. Please re-authenticate."])
        }
        
        let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyString = "client_id=\(clientId)&client_secret=\(clientSecret)&refresh_token=\(refreshToken)&grant_type=refresh_token"
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        
        config.tokenInfo?.accessToken = tokenResponse.access_token
        config.tokenInfo?.expiresIn = tokenResponse.expires_in
        config.tokenInfo?.expirationDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))
        config.save()
    }
}

struct TokenResponse: Codable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int
    let token_type: String
}
