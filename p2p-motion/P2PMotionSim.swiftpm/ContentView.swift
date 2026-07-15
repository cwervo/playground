import SwiftUI

struct ContentView: View {
    @StateObject private var sim = SimModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Motion-triggered mini camera on a beetle streams JPEG frames to a hub across the room (Iyer et al., Science Robotics 2020, UW). Photos persist on this device — no network.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    RoomView(sim: sim)
                        .aspectRatio(Room.w / Room.h, contentMode: .fit)
                        .background(Color(white: 0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    HStack(alignment: .top, spacing: 14) {
                        viewfinderPanel
                        metersPanel
                    }

                    controlsPanel
                    statsPanel
                    LogView(lines: sim.log)
                    GalleryView(sim: sim)
                }
                .padding()
            }
            .navigationTitle("p2p-motion")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(white: 0.04).ignoresSafeArea())
        }
    }

    private var viewfinderPanel: some View {
        VStack(spacing: 4) {
            Group {
                if let vf = sim.viewfinder {
                    Image(uiImage: vf)
                        .resizable()
                        .interpolation(.none)
                } else {
                    Color.black
                }
            }
            .frame(width: 200, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.gray.opacity(0.4)))
            Text("viewfinder · 160×120 mono")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var metersPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("node state:")
                Text(sim.state.rawValue)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(.orange.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.orange)
                Text(sim.stateNote).foregroundStyle(.secondary).font(.caption)
            }
            .font(.callout.monospaced())

            meter("energy store", value: sim.charge / 100,
                  label: "\(Int(sim.charge))%", tint: .green)
            meter("accel (motion)", value: sim.beetle.accel,
                  label: String(format: "%.2f g", sim.beetle.accel), tint: .orange)
            meter("link quality", value: 1 - sim.linkLoss,
                  label: sim.linkLoss >= 1 ? "blocked" : "\(Int((1 - sim.linkLoss) * 100))%",
                  tint: sim.linkLoss >= 1 ? .red : .green)
            meter("tx progress",
                  value: sim.transfer.map { Double($0.sent) / Double($0.total) } ?? 0,
                  label: sim.transfer.map { "\($0.sent)/\($0.total)" } ?? "idle", tint: .blue)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func meter(_ name: String, value: Double, label: String, tint: Color) -> some View {
        HStack {
            Text(name).font(.caption).foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            ProgressView(value: max(0, min(1, value))).tint(tint)
            Text(label).font(.caption.monospaced())
                .frame(width: 56, alignment: .trailing)
        }
    }

    private var controlsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("link", selection: $sim.link) {
                    ForEach(LinkType.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
                Spacer()
                Button(sim.paused ? "▶ resume" : "⏸ pause") { sim.paused.toggle() }
                    .buttonStyle(.bordered)
                Button("👉 nudge beetle") { sim.nudge() }
                    .buttonStyle(.bordered)
            }
            slider("jpeg quality", value: $sim.quality, in: 0.1...0.9,
                   label: String(format: "%.2f", sim.quality))
            slider("wake threshold", value: $sim.wakeThreshold, in: 0.05...0.6,
                   label: String(format: "%.2f g", sim.wakeThreshold))
            slider("harvest rate", value: $sim.harvestRate, in: 0...1,
                   label: "\(Int(sim.harvestRate * 100))%")
            slider("extra pkt loss", value: $sim.extraLoss, in: 0...0.6,
                   label: "\(Int(sim.extraLoss * 100))%")
        }
        .padding(12)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func slider(_ name: String, value: Binding<Double>, in range: ClosedRange<Double>, label: String) -> some View {
        HStack {
            Text(name).font(.caption).foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Slider(value: value, in: range)
            Text(label).font(.caption.monospaced())
                .frame(width: 56, alignment: .trailing)
        }
    }

    private var statsPanel: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                stat("photos stored", "\(sim.store.photos.count)")
                stat("storage used", "\(sim.store.totalBytes / 1024) KB")
                stat("frames captured", "\(sim.framesCaptured)")
            }
            GridRow {
                stat("packets acked", "\(sim.packetsAcked)")
                stat("packets lost", "\(sim.packetsLost)")
                stat("energy spent", "\(Int(sim.energySpent)) mJ")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func stat(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k.uppercased()).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(v).font(.callout.monospaced())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - room canvas

struct RoomView: View {
    @ObservedObject var sim: SimModel

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / Room.w
            ctx.scaleBy(x: s, y: s)
            drawRoom(&ctx)
        }
        .overlay(
            // tap the room to send the beetle there (map back to room space)
            GeometryReader { geo in
                Color.clear.contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { p in
                        let s = geo.size.width / Room.w
                        sim.send(to: CGPoint(x: p.x / s, y: p.y / s))
                    }
            }
        )
    }

    private func drawRoom(_ ctx: inout GraphicsContext) {
        let b = sim.beetle
        let hub = Room.hub

        // floor grid
        var grid = Path()
        for x in stride(from: 0.0, to: Room.w, by: 41) {
            grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: Room.h))
        }
        for y in stride(from: 0.0, to: Room.h, by: 41) {
            grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: Room.w, y: y))
        }
        ctx.stroke(grid, with: .color(Color(white: 0.12)), lineWidth: 1)

        // obstacles
        for o in Room.obstacles {
            let rect = CGRect(x: o.x - o.r, y: o.y - o.r, width: 2 * o.r, height: 2 * o.r)
            ctx.fill(Path(ellipseIn: rect), with: .color(Color(white: 0.16)))
            ctx.stroke(Path(ellipseIn: rect), with: .color(Color(white: 0.24)), lineWidth: 1)
        }

        // link line
        let blocked = sim.link.needsLoS && Room.lineBlocked(from: CGPoint(x: b.x, y: b.y), to: hub)
        var line = Path()
        line.move(to: CGPoint(x: b.x, y: b.y)); line.addLine(to: hub)
        let lineColor: Color = blocked ? .red.opacity(0.5) : (sim.transfer != nil ? .blue.opacity(0.7) : .gray.opacity(0.25))
        ctx.stroke(line, with: .color(lineColor), style: StrokeStyle(lineWidth: 1, dash: [5, 6]))

        // in-flight packets
        for pkt in sim.particles {
            let x = b.x + (hub.x - b.x) * pkt.progress
            let y = b.y + (hub.y - b.y) * pkt.progress + sin(pkt.progress * 9) * pkt.wobble
            let r: Double = pkt.ok ? 2.4 : 3
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
                     with: .color(pkt.ok ? .blue : .red))
        }

        // hub
        let hubRect = CGRect(x: hub.x - 26, y: hub.y - 20, width: 52, height: 40)
        ctx.fill(Path(roundedRect: hubRect, cornerRadius: 6), with: .color(.green.opacity(0.15)))
        ctx.stroke(Path(roundedRect: hubRect, cornerRadius: 6), with: .color(.green), lineWidth: 1.5)
        ctx.draw(Text("HUB").font(.system(size: 10, design: .monospaced)).foregroundColor(.green),
                 at: CGPoint(x: hub.x, y: hub.y - 3))
        ctx.draw(Text("store+proc").font(.system(size: 8, design: .monospaced)).foregroundColor(.green),
                 at: CGPoint(x: hub.x, y: hub.y + 10))
        var antenna = Path()
        antenna.move(to: CGPoint(x: hub.x, y: hub.y - 20)); antenna.addLine(to: CGPoint(x: hub.x, y: hub.y - 34))
        ctx.stroke(antenna, with: .color(.green), lineWidth: 1.5)
        ctx.fill(Path(ellipseIn: CGRect(x: hub.x - 2.5, y: hub.y - 38.5, width: 5, height: 5)), with: .color(.green))

        // FOV wedge
        var wedge = Path()
        wedge.move(to: CGPoint(x: b.x, y: b.y))
        wedge.addArc(center: CGPoint(x: b.x, y: b.y), radius: 86,
                     startAngle: .radians(b.heading - .pi / 6), endAngle: .radians(b.heading + .pi / 6),
                     clockwise: false)
        wedge.closeSubpath()
        ctx.fill(wedge, with: .color(.orange.opacity(sim.state == .tx ? 0.14 : 0.06)))

        // beetle + camera board
        var bc = ctx
        bc.translateBy(x: b.x, y: b.y)
        bc.rotate(by: .radians(b.heading))
        let body = Color(red: 0.17, green: 0.12, blue: 0.08)
        bc.fill(Path(ellipseIn: CGRect(x: -13, y: -8, width: 26, height: 16)), with: .color(body))
        bc.fill(Path(ellipseIn: CGRect(x: 6, y: -4, width: 10, height: 8)), with: .color(body))
        for sSign in [-1.0, 1.0] {
            for lx in [-6.0, 0, 6.0] {
                var leg = Path()
                leg.move(to: CGPoint(x: lx, y: sSign * 6))
                leg.addLine(to: CGPoint(x: lx + 3, y: sSign * (11 + 2 * sin(b.wiggle + lx))))
                bc.stroke(leg, with: .color(body), lineWidth: 1)
            }
        }
        bc.fill(Path(CGRect(x: -7, y: -4.5, width: 9, height: 9)), with: .color(.orange))
        bc.fill(Path(ellipseIn: CGRect(x: -4.7, y: -2.2, width: 4.4, height: 4.4)), with: .color(.black))
    }
}

// MARK: - log

struct LogView: View {
    let lines: [LogLine]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(lines) { line in
                        (Text(String(format: "[%6.1fs] ", line.t)).foregroundColor(.secondary)
                         + Text(prefix(line.kind) + " ").foregroundColor(color(line.kind))
                         + Text(line.text))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(line.id)
                    }
                }
                .padding(8)
            }
            .frame(height: 150)
            .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 10))
            .onChange(of: lines.count) { _ in
                if let last = lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private func prefix(_ k: LogLine.Kind) -> String {
        switch k { case .cam: return "cam"; case .link: return "link"; case .hub: return "hub"; case .error: return "err" }
    }
    private func color(_ k: LogLine.Kind) -> Color {
        switch k { case .cam: return .orange; case .link: return .blue; case .hub: return .green; case .error: return .red }
    }
}
