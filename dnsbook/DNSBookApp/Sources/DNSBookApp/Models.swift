import Foundation

struct DNSRecord: Identifiable, Hashable {
    let id = UUID()
    let domain: String
    let ipAddress: String
    let timestamp: Date
    let recordType: String
}

class DNSViewModel: ObservableObject {
    @Published var records: [DNSRecord] = []
    
    init() {
        generateMockData()
    }
    
    func generateMockData() {
        let domains = [
            "google.com", "apple.com", "github.com", "stackoverflow.com", 
            "twitter.com", "api.weather.com", "news.ycombinator.com", "wikipedia.org",
            "openai.com", "mail.google.com"
        ]
        let types = ["A", "AAAA", "CNAME"]
        var mock: [DNSRecord] = []
        
        let now = Date()
        for _ in 0..<200 {
            let domain = domains.randomElement()!
            let record = DNSRecord(
                domain: domain,
                ipAddress: "192.168.\(Int.random(in: 0...255)).\(Int.random(in: 1...255))",
                timestamp: now.addingTimeInterval(TimeInterval(-Int.random(in: 1...86400 * 7))), // past 7 days
                recordType: types.randomElement()!
            )
            mock.append(record)
        }
        self.records = mock.sorted(by: { $0.timestamp > $1.timestamp })
    }
    
    var groupedByDomain: [String: [DNSRecord]] {
        Dictionary(grouping: records, by: { $0.domain })
    }
}
