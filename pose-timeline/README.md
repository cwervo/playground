# Pose Timeline Processor

This project processes videos to extract pose information using a C++ backend and provides a simple Tcl/Tk GUI for interaction. It's designed to generate frames with pose overlays and videos animating these poses.

**Note:** The MediaPipe integration for actual pose estimation is currently a placeholder due to challenges in accessing the C++ SDK and documentation during development. The application currently processes video frames and generates placeholder outputs.

## Features

*   Processes input video files.
*   Extracts every 100th frame from the input video.
*   Resizes output frames to 720p (1280x720).
*   Saves processed frames as PNG images in `processed-videos/[video_name]/frames/`.
*   Generates a 720p MP4 video (`processed-videos/[video_name]/video_with_overlay.mp4`) from these frames, intended to have pose overlays. (Currently shows placeholder text).
*   Generates a 720p MP4 video (`processed-videos/[video_name]/video_pose_only.mp4`) from these frames, intended to show only pose animations. (Currently shows placeholder text).
*   Simple Tcl/Tk GUI for selecting videos and initiating processing.

## Project Structure

```
pose-timeline/
├── build/                # Build directory for C++ executable
├── processed-videos/     # Output directory for processed frames and videos
│   └── [video_name]/
│       ├── frames/       # Output frames (frame_0.png, frame_1.png, ...)
│       ├── video_with_overlay.mp4
│       └── video_pose_only.mp4
├── src/                  # C++ source files
│   └── main.cpp
├── src-videos/           # Input video files (place your videos here)
├── CMakeLists.txt        # CMake build configuration
├── gui.tcl               # Tcl/Tk GUI script
└── README.md             # This file
```

## Prerequisites

*   **C++ Compiler:** A C++17 compatible compiler (e.g., GCC, Clang).
*   **CMake:** Version 3.10 or higher.
*   **OpenCV:** Development libraries (e.g., `libopencv-dev` on Debian/Ubuntu).
*   **Tcl/Tk:** For running the GUI (e.g., `tcl`, `tk` packages on Debian/Ubuntu).
    *   A desktop environment with an X server is required to run the GUI.

## Build Instructions (C++ Backend)

1.  Navigate to the `pose-timeline` directory.
2.  Create the build directory if it doesn't exist:
    ```bash
    mkdir -p build
    ```
3.  Change to the build directory:
    ```bash
    cd build
    ```
4.  Run CMake to configure the project:
    ```bash
    cmake ..
    ```
5.  Compile the project:
    ```bash
    make
    ```
    This will create the `PoseTimeline` executable in the `pose-timeline/build/` directory.

## Running the Application

### Using the GUI (Recommended if a display is available)

1.  Ensure the C++ backend has been built (see Build Instructions).
2.  Make the `gui.tcl` script executable:
    ```bash
    chmod +x pose-timeline/gui.tcl
    ```
3.  Run the GUI script from the `pose-timeline` directory:
    ```bash
    ./gui.tcl
    ```
    *   Or, if `tclsh` is not in your PATH or the shebang doesn't work:
        ```bash
        tclsh gui.tcl
        ```
4.  In the GUI:
    *   Click "Browse..." to select a video file from your system (e.g., from the `src-videos` folder).
    *   Click "Process Video" to start the processing.
    *   Status messages will be displayed in the GUI and more detailed output in the console where `gui.tcl` was launched.
    *   Output files will be placed in `pose-timeline/processed-videos/[video_name]/`.

### Using the C++ Executable Directly (Command Line)

1.  Ensure the C++ backend has been built.
2.  Run the executable from the `pose-timeline` directory, providing the path to the video file as an argument:
    ```bash
    ./build/PoseTimeline path/to/your/video.mp4
    ```
    For example, to process a video placed in `src-videos`:
    ```bash
    ./build/PoseTimeline src-videos/my_test_video.mp4
    ```
3.  Output files will be generated in `pose-timeline/processed-videos/[video_name]/`.

## Development Notes & Future Work

*   **MediaPipe Integration:** The core task of integrating MediaPipe Pose Landmarker for C++ is pending. This involves:
    *   Setting up the MediaPipe C++ SDK and its dependencies (likely involving Bazel).
    *   Modifying `src/main.cpp` to use MediaPipe for pose detection in the `process_frame_with_mediapipe` function.
    *   Implementing `draw_poses_only` to render just the pose landmarks on a black background.
    *   Updating `CMakeLists.txt` to correctly find and link MediaPipe.
*   **Error Handling:** While basic error checks are in place, more robust error handling can be added, especially for file operations and video processing.
*   **GUI Enhancements:** The Tcl/Tk GUI is basic. It could be enhanced with:
    *   Progress bar for video processing.
    *   Ability to process all videos in `src-videos` automatically.
    *   Displaying thumbnails or previews.
*   **Filesystem Visibility in Sandbox:** During development, there were discrepancies in observing files created by the C++ executable via external `ls` commands within the same tool session. The C++ program's internal checks confirmed file creation. This might be a sandbox-specific behavior.

## Dependencies Installation (Example for Debian/Ubuntu)

```bash
sudo apt-get update
sudo apt-get install -y build-essential cmake libopencv-dev tcl tk
```
This command installs a C++ toolchain, CMake, OpenCV development files, and Tcl/Tk.
