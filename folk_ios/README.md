# Folk iOS Workspace

This workspace contains the source code and architectural planning for a high-performance iOS port of the Folk physical computing environment.

## Contents

* **`FolkEngine.swift`**: A fully functional, thread-safe, pure Swift prototype of the reactive database engine. It supports:
  * Primitives: `claim()`, `wish()`, and `when()`.
  * Cascading garbage collection (when parent claims are retracted, dependent matches and child statements are recursively removed).
  * Destructors: registering cleanup closures that run automatically when claims/wishes are retracted.
  * Thread-local parent match tracking, enabling nested reactive queries (joins).
* **Architecture Plan**: The detailed architectural design document mapping out the camera vision pipeline, projector outputs, and GPU/Metal-based rendering is saved in the app data directory. You can find it at:
  * `/Users/cwervo/.gemini/antigravity-cli/brain/ebf86623-d05b-46df-b65c-00188c8cd531/ios_folk_architecture_plan.md`

## Running the Engine Tests

The engine includes a built-in test suite that verifies the reactive database joins and retraction cascades. You can run it from the command line:

```bash
swift -D DEBUG FolkEngine.swift
```

## Next Steps for iOS Integration

To build the full iOS app in Xcode:
1. **AVFoundation Video Capture**: Implement a view controller that spins up an `AVCaptureSession`, grabs Y-plane grayscale buffers, and passes them to the AprilTag library.
2. **AprilTag Integration**: Add the official C `apriltag` library to your Xcode project and use a bridging header to access it from Swift.
3. **Geometry Store**: Use a separate cache for high-frequency coordinates to prevent database retraction/re-evaluation storms (Topology-Geometry separation).
4. **External Projector Window**: Listen for `UIScreenDidConnectNotification` to create a secondary UIWindow on the projector.
5. **Rendering & Homography**: Render outlines using SpriteKit (`SKShapeNode`) or Metal, using a simple DLT homography solver to map camera points to projector coordinates.
