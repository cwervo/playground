import ArgumentParser
import Foundation

@main
struct CalendarReader: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A CLI tool to read out your Google Calendar for the next hour.",
        subcommands: [Auth.self, SelectCalendars.self, Read.self],
        defaultSubcommand: Read.self
    )
}

extension CalendarReader {
    struct Auth: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Authenticate with Google.")
        
        mutating func run() async throws {
            checkCredentials()
            let auth = GoogleAuth()
            let tokenInfo = try await auth.authenticate()
            
            var config = AppConfig.load()
            config.tokenInfo = tokenInfo
            config.save()
            print("Successfully authenticated and saved tokens!")
        }
    }
    
    struct SelectCalendars: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Select which calendars to read from.")
        
        mutating func run() async throws {
            checkCredentials()
            var config = AppConfig.load()
            let auth = GoogleAuth()
            try await auth.refreshAccessTokenIfNeeded(config: &config)
            
            guard let accessToken = config.tokenInfo?.accessToken else {
                print("Not authenticated. Run 'auth' subcommand first.")
                return
            }
            
            let api = CalendarAPI()
            let calendars = try await api.getCalendars(accessToken: accessToken)
            
            if calendars.isEmpty {
                print("No calendars found.")
                return
            }
            
            print("Available Calendars:")
            for (index, calendar) in calendars.enumerated() {
                print("\(index + 1). \(calendar.summary)")
            }
            print("\nEnter the numbers of the calendars you want to select, separated by commas (e.g., 1,3):")
            
            if let input = readLine() {
                let indices = input.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                let selectedIDs = indices.compactMap { idx -> String? in
                    if idx > 0 && idx <= calendars.count {
                        return calendars[idx - 1].id
                    }
                    return nil
                }
                config.selectedCalendarIDs = selectedIDs
                config.save()
                print("Saved \(selectedIDs.count) selected calendars.")
            }
        }
    }
    
    struct Read: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Read out the events for the next hour.")
        
        mutating func run() async throws {
            checkCredentials()
            var config = AppConfig.load()
            let auth = GoogleAuth()
            try await auth.refreshAccessTokenIfNeeded(config: &config)
            
            guard let accessToken = config.tokenInfo?.accessToken else {
                print("Not authenticated. Run 'auth' subcommand first.")
                return
            }
            
            if config.selectedCalendarIDs.isEmpty {
                print("No calendars selected. Please run 'select-calendars' first.")
                return
            }
            
            let api = CalendarAPI()
            var allEvents: [(String, EventEntry)] = []
            
            let calendars = try await api.getCalendars(accessToken: accessToken)
            let calendarMap = Dictionary(uniqueKeysWithValues: calendars.map { ($0.id, $0.summary) })
            
            for calId in config.selectedCalendarIDs {
                let events = try await api.getEvents(for: calId, accessToken: accessToken)
                let calName = calendarMap[calId] ?? "Unknown Calendar"
                for event in events {
                    allEvents.append((calName, event))
                }
            }
            
            let formatter = ISO8601DateFormatter()
            let displayFormatter = DateFormatter()
            displayFormatter.timeStyle = .short
            
            var textToSpeak = "Here is your calendar for the next hour. "
            if allEvents.isEmpty {
                textToSpeak += "You have no events."
            } else {
                for (calName, event) in allEvents {
                    let summary = event.summary ?? "Busy"
                    if let dateTimeStr = event.start?.dateTime, let date = formatter.date(from: dateTimeStr) {
                        let timeString = displayFormatter.string(from: date)
                        textToSpeak += "At \(timeString), \(summary) on \(calName). "
                    } else if let _ = event.start?.date {
                        textToSpeak += "All day event: \(summary) on \(calName). "
                    }
                }
            }
            
            print(textToSpeak)
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            process.arguments = [textToSpeak]
            try process.run()
            process.waitUntilExit()
        }
    }
}

func checkCredentials() {
    let clientId = ProcessInfo.processInfo.environment["GOOGLE_CLIENT_ID"] ?? ""
    let clientSecret = ProcessInfo.processInfo.environment["GOOGLE_CLIENT_SECRET"] ?? ""
    if clientId.isEmpty || clientSecret.isEmpty {
        print("--------------------------------------------------")
        print("Warning: GOOGLE_CLIENT_ID or GOOGLE_CLIENT_SECRET")
        print("environment variable is not set.")
        print("Please set them before running this app to authenticate properly.")
        print("Example:")
        print("export GOOGLE_CLIENT_ID='your_client_id'")
        print("export GOOGLE_CLIENT_SECRET='your_client_secret'")
        print("--------------------------------------------------")
    }
}
