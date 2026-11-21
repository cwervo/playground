import SwiftUI

struct NodeNetworkView: View {
    @ObservedObject var viewModel: DNSViewModel
    @State private var selectedDomain: String? = nil
    @State private var showPages = false
    
    var body: some View {
        ZStack {
            // Lines from center to nodes
            GeometryReader { geometry in
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                let radius: CGFloat = min(geometry.size.width, geometry.size.height) / 2.5
                
                let domains = Array(viewModel.groupedByDomain.keys).sorted()
                let angleStep = (2 * .pi) / Double(max(1, domains.count))
                
                ForEach(Array(domains.enumerated()), id: \.offset) { index, domain in
                    let angle = angleStep * Double(index)
                    let x = center.x + radius * CGFloat(cos(angle))
                    let y = center.y + radius * CGFloat(sin(angle))
                    let targetPoint = CGPoint(x: x, y: y)
                    
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: targetPoint)
                    }
                    .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                    
                    // Domain Node
                    Button(action: {
                        selectedDomain = domain
                        showPages = true
                    }) {
                        VStack {
                            Image(systemName: "globe")
                                .font(.title)
                                .foregroundColor(.blue)
                            Text(domain)
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(Circle())
                        .shadow(radius: 3)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .position(targetPoint)
                }
                
                // Center Node
                VStack {
                    Image(systemName: "book.closed.fill")
                        .font(.largeTitle)
                        .foregroundColor(.purple)
                    Text("DNS Phonebook")
                        .font(.headline)
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
                .clipShape(Circle())
                .shadow(radius: 5)
                .position(center)
            }
        }
        .sheet(isPresented: $showPages) {
            if let domain = selectedDomain, let records = viewModel.groupedByDomain[domain] {
                DomainPagesView(domain: domain, records: records)
                    .frame(width: 600, height: 400)
            }
        }
    }
}

struct DomainPagesView: View {
    let domain: String
    let records: [DNSRecord]
    @Environment(\.dismiss) var dismiss
    
    @State private var currentIndex: Int = 0
    
    var body: some View {
        VStack {
            HStack {
                Text("DNS Records for \(domain)")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding()
            
            if records.isEmpty {
                Text("No records found.")
            } else {
                ZStack {
                    ForEach(Array(records.enumerated()), id: \.offset) { index, record in
                        if index >= currentIndex {
                            PageView(record: record, index: index, total: records.count)
                                .offset(x: CGFloat(index - currentIndex) * 5, y: CGFloat(index - currentIndex) * 5)
                                .zIndex(Double(records.count - index))
                                .gesture(
                                    DragGesture()
                                        .onEnded { value in
                                            if value.translation.width < -50 || value.translation.width > 50 {
                                                withAnimation {
                                                    if currentIndex < records.count - 1 {
                                                        currentIndex += 1
                                                    }
                                                }
                                            }
                                        }
                                )
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                
                HStack {
                    Button("Previous") {
                        withAnimation {
                            if currentIndex > 0 { currentIndex -= 1 }
                        }
                    }
                    .disabled(currentIndex == 0)
                    
                    Text("Page \(currentIndex + 1) of \(records.count)")
                    
                    Button("Next") {
                        withAnimation {
                            if currentIndex < records.count - 1 { currentIndex += 1 }
                        }
                    }
                    .disabled(currentIndex == records.count - 1)
                }
                .padding()
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct PageView: View {
    let record: DNSRecord
    let index: Int
    let total: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(record.domain)
                    .font(.headline)
                Spacer()
                Text(record.recordType)
                    .font(.subheadline)
                    .padding(4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)
            }
            Divider()
            Text("IP: \(record.ipAddress)")
                .font(.system(.body, design: .monospaced))
            Text("Accessed: \(record.timestamp.formatted())")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            HStack {
                Spacer()
                Text("\(index + 1)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 300, height: 200)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.2), radius: 5, x: 2, y: 2)
        // Add a paper-like texture or color
        .background(Color(red: 0.98, green: 0.96, blue: 0.9)) 
    }
}
