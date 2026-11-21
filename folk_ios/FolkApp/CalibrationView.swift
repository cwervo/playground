import SwiftUI
import CoreGraphics

struct CalibrationView: View {
    
    @ObservedObject var viewModel: CalibrationViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Text("Homography Calibration")
                        .font(.largeTitle)
                        .bold()
                        .padding(.top)
                    
                    Text("This maps camera pixel coordinates to the projector's display coordinates. Connect your USB-C projector first.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        InstructionRow(number: "1", text: "Ensure your projector is connected and displaying the calibration grid.")
                        InstructionRow(number: "2", text: "Point your iPhone camera at the projection screen.")
                        InstructionRow(number: "3", text: "Make sure Tag IDs 0, 1, 2, and 3 are clearly visible to the camera at the corners of the projected area.")
                        InstructionRow(number: "4", text: "Keep the phone steady and tap 'Capture Calibration'.")
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    
                    if viewModel.isCalibrated {
                        Text("✅ Calibrated Successfully!")
                            .foregroundColor(.green)
                            .font(.headline)
                            .bold()
                    }
                    
                    Button(action: {
                        viewModel.performCalibration()
                    }) {
                        Text(viewModel.isCalibrating ? "Searching for Tags..." : "Capture Calibration")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(viewModel.isCalibrating ? Color.orange : Color.blue)
                            .cornerRadius(12)
                    }
                    .disabled(viewModel.isCalibrating)
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarItems(trailing: Button("Done") {
                dismiss()
            })
        }
    }
}

struct InstructionRow: View {
    let number: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.blue)
                .clipShape(Circle())
            
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

class CalibrationViewModel: ObservableObject {
    
    @Published var isCalibrating = false
    @Published var isCalibrated = false
    @Published var errorMessage: String? = nil
    
    private var detectedTags: [TagDetection] = []
    
    init() {
        self.isCalibrated = UserDefaults.standard.array(forKey: "homography_matrix") != nil
    }
    
    func updateDetections(_ detections: [TagDetection]) {
        self.detectedTags = detections
    }
    
    func performCalibration() {
        isCalibrating = true
        errorMessage = nil
        
        // Wait 0.5 seconds to capture current stable camera detections
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.processCalibration()
        }
    }
    
    private func processCalibration() {
        defer { isCalibrating = false }
        
        // We need Tag IDs 0, 1, 2, 3 to perform standard corner calibration
        // Tag 0: Top-Left
        // Tag 1: Top-Right
        // Tag 2: Bottom-Right
        // Tag 3: Bottom-Left
        let tag0 = detectedTags.first(where: { $0.id == 0 })
        let tag1 = detectedTags.first(where: { $0.id == 1 })
        let tag2 = detectedTags.first(where: { $0.id == 2 })
        let tag3 = detectedTags.first(where: { $0.id == 3 })
        
        guard let t0 = tag0, let t1 = tag1, let t2 = tag2, let t3 = tag3 else {
            let seen = detectedTags.map { "\($0.id)" }.joined(separator: ", ")
            errorMessage = "Error: Need Tag IDs 0, 1, 2, 3 visible at the corners.\nCurrently see: [\(seen.isEmpty ? "None" : seen)]"
            return
        }
        
        // Get the center point of each tag in camera space (normalized 0...1)
        let c0 = getCenter(t0.corners)
        let c1 = getCenter(t1.corners)
        let c2 = getCenter(t2.corners)
        let c3 = getCenter(t3.corners)
        
        // Target coordinates in projector space.
        // We map to the size of the projector scene (or standard 1920x1080)
        guard let scene = ProjectorDisplayManager.shared.projectorScene else {
            errorMessage = "Error: Projector screen not connected. Please plug in your USB-C display/projector first."
            return
        }
        
        let w = scene.size.width
        let h = scene.size.height
        
        let src = [c0, c1, c2, c3]
        let dest = [
            CGPoint(x: 0, y: h),      // Top-Left (projector has y=0 at bottom, y=h at top)
            CGPoint(x: w, y: h),      // Top-Right
            CGPoint(x: w, y: 0),      // Bottom-Right
            CGPoint(x: 0, y: 0)       // Bottom-Left
        ]
        
        if let solvedHomography = Homography.solve(src: src, dest: dest) {
            scene.setHomography(solvedHomography)
            isCalibrated = true
            errorMessage = nil
            print("Calibration: Solved homography matrix successfully!")
        } else {
            errorMessage = "Error: Failed to solve homography linear system. Check tag corners."
        }
    }
    
    private func getCenter(_ corners: [CGPoint]) -> CGPoint {
        guard corners.count == 4 else { return .zero }
        let x = (corners[0].x + corners[1].x + corners[2].x + corners[3].x) / 4.0
        let y = (corners[0].y + corners[1].y + corners[2].y + corners[3].y) / 4.0
        return CGPoint(x: x, y: y)
    }
}
