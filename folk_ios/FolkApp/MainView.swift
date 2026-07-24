import SwiftUI
import AVFoundation

struct MainView: View {
    
    @StateObject private var viewModel = MainViewModel()
    @State private var showCalibration = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Camera Preview with overlay
                    CameraPreviewView(session: viewModel.cameraSession)
                        .frame(height: 240)
                        .cornerRadius(12)
                        .padding()
                        .shadow(radius: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(UIColor.separator), lineWidth: 1)
                                .padding()
                        )
                    
                    // Status Indicators
                    HStack(spacing: 16) {
                        StatusCard(
                            title: "Projector Status",
                            status: viewModel.isProjectorConnected ? "Connected" : "Disconnected",
                            color: viewModel.isProjectorConnected ? .green : .red,
                            icon: "projector"
                        )
                        
                        StatusCard(
                            title: "Calibration",
                            status: viewModel.isCalibrated ? "Calibrated" : "Not Calibrated",
                            color: viewModel.isCalibrated ? .green : .orange,
                            icon: "scope"
                        )
                    }
                    .padding(.horizontal)
                    
                    // Database Claims Panel
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Reactive Tuple Database")
                                .font(.headline)
                                .bold()
                            Spacer()
                            Text("\(viewModel.activeClaimsCount) claims active")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        
                        ScrollView {
                            Text(viewModel.databaseDump)
                                .font(.system(.footnote, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(8)
                        }
                        .padding(.horizontal)
                    }
                    .padding(.top)
                    
                    Spacer()
                    
                    // Calibration and Control Button
                    Button(action: {
                        showCalibration = true
                    }) {
                        Text("Calibrate Projector")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.blue)
                            .cornerRadius(12)
                            .padding()
                    }
                }
            }
            .navigationTitle("Folk iOS Engine")
            .sheet(isPresented: $showCalibration) {
                CalibrationView(viewModel: viewModel.calibrationViewModel)
            }
            .onAppear {
                viewModel.startEngine()
            }
        }
    }
}

struct StatusCard: View {
    let title: String
    let status: String
    let color: Color
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(status)
                    .font(.subheadline)
                    .bold()
                    .foregroundColor(color)
            }
            Spacer()
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession?
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        
        if let session = session {
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(previewLayer)
            context.coordinator.previewLayer = previewLayer
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.previewLayer?.frame = uiView.bounds
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

class MainViewModel: ObservableObject, CameraManagerDelegate {
    
    @Published var isProjectorConnected = false
    @Published var isCalibrated = false
    @Published var activeClaimsCount = 0
    @Published var databaseDump = ""
    @Published var cameraSession: AVCaptureSession? = nil
    
    let engine = FolkEngine()
    let calibrationViewModel = CalibrationViewModel()
    
    private var timer: Timer?
    
    func startEngine() {
        // 1. Start Projector External Display Manager
        ProjectorDisplayManager.shared.start()
        isProjectorConnected = ProjectorDisplayManager.shared.externalWindow != nil
        isCalibrated = UserDefaults.standard.array(forKey: "homography_matrix") != nil
        
        // 2. Register Built-in programs in FolkEngine
        registerPrograms()
        
        // 3. Start Camera and setup frame tracker delegation
        CameraManager.shared.delegate = self
        CameraManager.shared.start { [weak self] success in
            guard let self = self else { return }
            if success {
                print("MainViewModel: Camera started.")
                self.cameraSession = CameraManager.shared.captureSession
            }
        }
        
        // 4. Set up database updates poll timer (10Hz)
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.databaseDump = self.engine.dumpDatabase()
            self.activeClaimsCount = self.engine.activeStatementCount()
            self.isProjectorConnected = ProjectorDisplayManager.shared.externalWindow != nil
            self.isCalibrated = UserDefaults.standard.array(forKey: "homography_matrix") != nil
        }
        
        // Observe screen connections
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: UIScreen.didConnectNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: UIScreen.didDisconnectNotification, object: nil)
    }
    
    @objc private func screensChanged() {
        DispatchQueue.main.async {
            self.isProjectorConnected = ProjectorDisplayManager.shared.externalWindow != nil
        }
    }
    
    func cameraManager(_ manager: CameraManager, didUpdateDetections detections: [TagDetection]) {
        // Feed camera tag detections to the calibration viewModel when open
        calibrationViewModel.updateDetections(detections)
    }
    
    private func registerPrograms() {
        // Program 1: Automatically wishes to outline any active tag green
        engine.when(["tag", "/id/", "is", "active"]) { [weak self] bindings, ctx in
            guard let self = self else { return }
            let id = bindings["id"]!
            self.engine.wish(["tag", id, "is", "outlined", "green"])
        }
        
        // Program 2: Listens for outline wishes and registers outline drawings on the Projector Scene
        engine.when(["wish", "tag", "/id/", "is", "outlined", "/color/"]) { bindings, ctx in
            guard let id = Int(bindings["id"]!),
                  let colorStr = bindings["color"] else { return }
            
            let colorMap: [String: UIColor] = [
                "green": .green, "red": .red, "blue": .blue, "orange": .orange
            ]
            let color = colorMap[colorStr] ?? .green
            
            DispatchQueue.main.async {
                if let scene = ProjectorDisplayManager.shared.projectorScene {
                    _ = scene.registerOutline(for: id, color: color)
                    
                    // Register retraction cleanup
                    ctx.onRetract {
                        scene.unregisterOutline(for: id)
                    }
                }
            }
        }
    }
    
    deinit {
        timer?.invalidate()
        CameraManager.shared.stop()
    }
}
