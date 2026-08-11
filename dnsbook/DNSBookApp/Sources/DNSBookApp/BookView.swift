import SwiftUI

struct BookView: View {
    @ObservedObject var viewModel: DNSViewModel
    @State private var selectedDomain: String? = nil
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Left Page
                BookPage(isLeftPage: true) {
                    VStack {
                        Text("Index")
                            .font(.custom("Palatino", size: 32))
                            .bold()
                            .padding(.top, 40)
                            .padding(.bottom, 20)
                        
                        let domains = Array(viewModel.groupedByDomain.keys).sorted()
                        List(domains, id: \.self) { domain in
                            Button(action: {
                                withAnimation {
                                    selectedDomain = domain
                                }
                            }) {
                                HStack {
                                    Text(domain)
                                        .font(.custom("Palatino", size: 18))
                                        .foregroundColor(.black)
                                    Spacer()
                                    Text("\(viewModel.groupedByDomain[domain]?.count ?? 0)")
                                        .font(.custom("Palatino", size: 16))
                                        .foregroundColor(.gray)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .scrollContentBackground(.hidden)
                    }
                    .padding(.horizontal, 40)
                }
                .frame(width: geometry.size.width / 2)
                
                // Right Page
                BookPage(isLeftPage: false) {
                    VStack {
                        if let domain = selectedDomain, let records = viewModel.groupedByDomain[domain] {
                            Text(domain)
                                .font(.custom("Palatino", size: 28))
                                .bold()
                                .padding(.top, 40)
                                .padding(.bottom, 20)
                            
                            List(records) { record in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(record.ipAddress)
                                            .font(.custom("Courier", size: 16))
                                            .bold()
                                        Spacer()
                                        Text(record.recordType)
                                            .font(.custom("Courier", size: 14))
                                    }
                                    Text(record.timestamp.formatted())
                                        .font(.custom("Palatino", size: 14))
                                        .foregroundColor(.gray)
                                    Divider()
                                }
                                .padding(.vertical, 4)
                            }
                            .scrollContentBackground(.hidden)
                        } else {
                            VStack {
                                Spacer()
                                Text("Select a domain from the Index")
                                    .font(.custom("Palatino", size: 20))
                                    .foregroundColor(.gray)
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, 40)
                }
                .frame(width: geometry.size.width / 2)
            }
            .background(Color(white: 0.1).edgesIgnoringSafeArea(.all)) // Desk background
            .padding(40)
        }
    }
}

struct BookPage<Content: View>: View {
    let isLeftPage: Bool
    let content: Content
    
    init(isLeftPage: Bool, @ViewBuilder content: () -> Content) {
        self.isLeftPage = isLeftPage
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            // Paper background
            Color(red: 0.96, green: 0.94, blue: 0.88)
            
            // Faux 3D spine shading
            HStack(spacing: 0) {
                if isLeftPage {
                    Spacer()
                    LinearGradient(
                        gradient: Gradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.3)]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 40)
                } else {
                    LinearGradient(
                        gradient: Gradient(colors: [Color.black.opacity(0.3), Color.black.opacity(0.0)]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 40)
                    Spacer()
                }
            }
            
            // Content
            content
        }
        .cornerRadius(10, corners: isLeftPage ? [.topLeft, .bottomLeft] : [.topRight, .bottomRight])
        .shadow(color: .black.opacity(0.5), radius: 10, x: isLeftPage ? -5 : 5, y: 10)
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: RectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RectCorner: OptionSet {
    let rawValue: Int
    static let topLeft = RectCorner(rawValue: 1 << 0)
    static let topRight = RectCorner(rawValue: 1 << 1)
    static let bottomLeft = RectCorner(rawValue: 1 << 2)
    static let bottomRight = RectCorner(rawValue: 1 << 3)
    static let allCorners: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: RectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = NSBezierPath()
        
        let tl = corners.contains(.topLeft) ? radius : 0
        let tr = corners.contains(.topRight) ? radius : 0
        let bl = corners.contains(.bottomLeft) ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0
        
        let w = rect.size.width
        let h = rect.size.height
        
        path.move(to: NSPoint(x: w / 2.0, y: 0))
        path.line(to: NSPoint(x: w - tr, y: 0))
        path.appendArc(withCenter: NSPoint(x: w - tr, y: tr), radius: tr, startAngle: 270, endAngle: 360)
        path.line(to: NSPoint(x: w, y: h - br))
        path.appendArc(withCenter: NSPoint(x: w - br, y: h - br), radius: br, startAngle: 0, endAngle: 90)
        path.line(to: NSPoint(x: bl, y: h))
        path.appendArc(withCenter: NSPoint(x: bl, y: h - bl), radius: bl, startAngle: 90, endAngle: 180)
        path.line(to: NSPoint(x: 0, y: tl))
        path.appendArc(withCenter: NSPoint(x: tl, y: tl), radius: tl, startAngle: 180, endAngle: 270)
        path.close()

        return Path(path.cgPath)
    }
}
