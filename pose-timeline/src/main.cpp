#include <iostream>
#include <string>
#include <vector>
#include <filesystem>
#include "opencv2/opencv.hpp"
#include "opencv2/videoio.hpp"
#include "opencv2/highgui.hpp"
#include "opencv2/imgproc.hpp"

namespace fs = std::filesystem;

// Placeholder for MediaPipe integration
// This function will eventually take a cv::Mat, process it with MediaPipe,
// and return a cv::Mat with pose overlays.
cv::Mat process_frame_with_mediapipe(cv::Mat frame) {
    // For now, just return the frame as is
    cv::putText(frame, "MediaPipe Placeholder", cv::Point(50, 50),
                cv::FONT_HERSHEY_SIMPLEX, 1, cv::Scalar(0, 255, 0), 2);
    return frame;
}

// Placeholder for drawing only poses
// This function will take pose data and draw it on a black background.
cv::Mat draw_poses_only(const cv::Mat& reference_frame_size /*, pose_data */) {
    cv::Mat pose_only_frame = cv::Mat::zeros(reference_frame_size.size(), CV_8UC3);
    cv::putText(pose_only_frame, "Pose-Only Placeholder", cv::Point(50, 50),
                cv::FONT_HERSHEY_SIMPLEX, 1, cv::Scalar(255, 255, 255), 2);
    return pose_only_frame;
}

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <video_path>" << std::endl;
        return -1;
    }
    std::string video_path = argv[1];
    std::string video_name = fs::path(video_path).stem().string();
    std::cout << "Derived video_name: [" << video_name << "]" << std::endl; // Debug print

    std::string output_frames_dir = "processed-videos/" + video_name + "/frames/";
    std::string output_video_overlay_path = "processed-videos/" + video_name + "/video_with_overlay.mp4";
    std::string output_video_pose_only_path = "processed-videos/" + video_name + "/video_pose_only.mp4";

    // Create output directories if they don't exist
    std::cout << "Attempting to create directory: " << output_frames_dir << std::endl;
    try {
        if (fs::create_directories(output_frames_dir)) {
            std::cout << "Successfully created directory: " << output_frames_dir << std::endl;
        } else {
            // This case might mean the directory already existed or some other non-error condition depending on the specific create_directories behavior
            if (fs::exists(output_frames_dir)) {
                 std::cout << "Directory already existed: " << output_frames_dir << std::endl;
            } else {
                 std::cerr << "Warning: fs::create_directories returned false but directory does not exist: " << output_frames_dir << std::endl;
            }
        }
    } catch (const fs::filesystem_error& e) {
        std::cerr << "Filesystem error creating directory " << output_frames_dir << ": " << e.what() << std::endl;
        return -1; // Exit if we can't create the directory
    }
    if (!fs::exists(output_frames_dir)) {
        std::cerr << "Error: Directory was not created and does not exist: " << output_frames_dir << std::endl;
        return -1;
    }


    cv::VideoCapture cap(video_path);
    if (!cap.isOpened()) {
        std::cerr << "Error: Could not open video file " << video_path << std::endl;
        return -1;
    }

    double fps = cap.get(cv::CAP_PROP_FPS);
    int frame_width = static_cast<int>(cap.get(cv::CAP_PROP_FRAME_WIDTH));
    int frame_height = static_cast<int>(cap.get(cv::CAP_PROP_FRAME_HEIGHT));
    cv::Size frame_size(frame_width, frame_height);
    cv::Size target_size(1280, 720); // 720p

    // Video writers
    std::cout << "Attempting to open VideoWriter for overlay: " << output_video_overlay_path << std::endl;
    cv::VideoWriter video_writer_overlay(output_video_overlay_path, cv::VideoWriter::fourcc('m', 'p', '4', 'v'), fps / 100.0, target_size); // Adjust FPS for 1/100th frame
    if (!video_writer_overlay.isOpened()) {
        std::cerr << "Error: Could not open video_writer_overlay for path: " << output_video_overlay_path << std::endl;
        // Not returning -1 here to see if frame saving works, but this is an error.
    } else {
        std::cout << "Successfully opened video_writer_overlay for path: " << output_video_overlay_path << std::endl;
    }

    std::cout << "Attempting to open VideoWriter for pose-only: " << output_video_pose_only_path << std::endl;
    cv::VideoWriter video_writer_pose_only(output_video_pose_only_path, cv::VideoWriter::fourcc('m', 'p', '4', 'v'), fps / 100.0, target_size);
    if (!video_writer_pose_only.isOpened()) {
        std::cerr << "Error: Could not open video_writer_pose_only for path: " << output_video_pose_only_path << std::endl;
    } else {
        std::cout << "Successfully opened video_writer_pose_only for path: " << output_video_pose_only_path << std::endl;
    }

    cv::Mat frame;
    long frame_count = 0;
    int saved_frame_idx = 0;

    std::cout << "Processing video: " << video_name << std::endl;

    while (cap.read(frame)) {
        if (frame.empty()) {
            std::cerr << "Warning: Read an empty frame." << std::endl;
            continue;
        }

        if (frame_count % 100 == 0) {
            cv::Mat resized_frame;
            cv::resize(frame, resized_frame, target_size);

            // Process with MediaPipe (placeholder)
            cv::Mat processed_frame = process_frame_with_mediapipe(resized_frame.clone()); // Clone to avoid modifying resized_frame directly

            // Save frame with overlay
            std::string frame_filename = output_frames_dir + "frame_" + std::to_string(saved_frame_idx) + ".png";
            std::cout << "Attempting to save frame: " << frame_filename << std::endl;
            if (!cv::imwrite(frame_filename, processed_frame)) {
                std::cerr << "Error: Could not save frame " << frame_filename << std::endl;
            } else {
                std::cout << "Saved frame: " << frame_filename << std::endl;
                if (!fs::exists(frame_filename)) {
                    std::cerr << "Error: cv::imwrite reported success, but file does not exist: " << frame_filename << std::endl;
                }
            }

            // Add to overlay video
            if (video_writer_overlay.isOpened()) {
                video_writer_overlay.write(processed_frame);
            } else {
                std::cerr << "Skipping write to video_writer_overlay (not opened): " << output_video_overlay_path << std::endl;
            }

            // Generate and add to pose-only video (placeholder)
            cv::Mat pose_only_frame = draw_poses_only(resized_frame /*, actual_pose_data */);
            if (video_writer_pose_only.isOpened()) {
                video_writer_pose_only.write(pose_only_frame);
            } else {
                 std::cerr << "Skipping write to video_writer_pose_only (not opened): " << output_video_pose_only_path << std::endl;
            }

            saved_frame_idx++;
        }
        frame_count++;
    }

    cap.release();
    std::cout << "Releasing video_writer_overlay..." << std::endl;
    video_writer_overlay.release();
    std::cout << "Releasing video_writer_pose_only..." << std::endl;
    video_writer_pose_only.release();

    std::cout << "Video processing complete for " << video_name << std::endl;
    std::cout << "Output frames saved in: " << output_frames_dir << std::endl;
    std::cout << "Overlay video saved as: " << output_video_overlay_path << std::endl;
    std::cout << "Pose-only video saved as: " << output_video_pose_only_path << std::endl;

    return 0;
}
