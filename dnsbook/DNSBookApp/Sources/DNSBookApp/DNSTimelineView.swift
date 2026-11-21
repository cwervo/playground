import SwiftUI

struct DNSTimelineView: View {
    @ObservedObject var viewModel: DNSViewModel
    
    var body: some View {
        VStack {
            Text("DNS Access Timeline")
                .font(.largeTitle)
                .bold()
                .padding()
            
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.records.enumerated()), id: \.offset) { index, record in
                        TimelineRow(record: record, isLast: index == viewModel.records.count - 1)
                    }
                }
                .padding()
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct TimelineRow: View {
    let record: DNSRecord
    let isLast: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            // Timestamp
            Text(record.timestamp.formatted(date: .abbreviated, time: .standard))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 150, alignment: .trailing)
            
            // Timeline line and dot
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .shadow(radius: 2)
                
                if !isLast {
                    Rectangle()
                        .fill(Color.blue.opacity(0.3))
                        .frame(width: 2)
                }
            }
            
            // Record Details
            VStack(alignment: .leading, spacing: 4) {
                Text(record.domain)
                    .font(.headline)
                HStack {
                    Text(record.ipAddress)
                        .font(.subheadline)
                        .fontDesign(.monospaced)
                    Spacer()
                    Text(record.recordType)
                        .font(.caption)
                        .padding(4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            .padding(.bottom, 20)
        }
    }
}
