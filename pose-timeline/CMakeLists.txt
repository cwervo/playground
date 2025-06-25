cmake_minimum_required(VERSION 3.10)
project(PoseTimeline)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED True)

# Find OpenCV
find_package(OpenCV REQUIRED)
include_directories(${OpenCV_INCLUDE_DIRS})

# Add executable
add_executable(PoseTimeline src/main.cpp)

# Link OpenCV libraries
target_link_libraries(PoseTimeline ${OpenCV_LIBS})

# MediaPipe will be added here later
# find_package(MediaPipe REQUIRED)
# target_link_libraries(PoseTimeline MediaPipe::mediapipe)
