import Foundation

struct CalendarListResponse: Codable {
    let items: [CalendarEntry]
}

struct CalendarEntry: Codable {
    let id: String
    let summary: String
}

struct EventsResponse: Codable {
    let items: [EventEntry]?
}

struct EventEntry: Codable {
    let summary: String?
    let start: EventDateTime?
    let end: EventDateTime?
}

struct EventDateTime: Codable {
    let dateTime: String?
    let date: String?
}

class CalendarAPI {
    func getCalendars(accessToken: String) async throws -> [CalendarEntry] {
        let url = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpRes = response as? HTTPURLResponse, httpRes.statusCode != 200 {
            if let errString = String(data: data, encoding: .utf8) {
                print("Failed to fetch calendars: \(errString)")
            }
            return []
        }
        let listResponse = try JSONDecoder().decode(CalendarListResponse.self, from: data)
        return listResponse.items
    }
    
    func getEvents(for calendarId: String, accessToken: String) async throws -> [EventEntry] {
        let now = Date()
        let nextHour = now.addingTimeInterval(3600)
        
        let formatter = ISO8601DateFormatter()
        let timeMin = formatter.string(from: now)
        let timeMax = formatter.string(from: nextHour)
        
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.googleapis.com"
        components.path = "/calendar/v3/calendars/\(calendarId)/events"
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: timeMin),
            URLQueryItem(name: "timeMax", value: timeMax),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime")
        ]
        
        guard let url = components.url else {
            print("Failed to construct URL for calendar events.")
            return []
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            print("Failed to fetch events for \(calendarId). HTTP \(httpResponse.statusCode)")
            if let errString = String(data: data, encoding: .utf8) {
                print("Error details: \(errString)")
            }
            return []
        }
        
        let eventsResponse = try JSONDecoder().decode(EventsResponse.self, from: data)
        return eventsResponse.items ?? []
    }
}
