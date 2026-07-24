import Foundation

struct TokenInfo: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresIn: Int
    var expirationDate: Date
}

struct AppConfig: Codable {
    var tokenInfo: TokenInfo?
    var selectedCalendarIDs: [String] = []
    
    static let configURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".calendar_reader_config.json")
    }()
    
    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return AppConfig()
        }
        return config
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: Self.configURL)
        }
    }
}
