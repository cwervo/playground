#include <opencv2/opencv.hpp>
#include <iostream>
 
extern "C" {
    #include "OpenCVWrapper.h"
 
    int getWidthOfImage(cv_image_t img) {
        return img.width;
    }
 
    cv::Mat convertToMat(const cv_image_t& img) {
        int type = 0;
 
        // Determine the correct type based on number of components
        if (img.components == 1) {
            type = CV_8UC1; // Grayscale
        } else if (img.components == 3) {
            type = CV_8UC3; // RGB
        } else {
            // Add more cases if needed
            throw std::runtime_error("Unsupported number of components");
        }
 
        // Create cv::Mat with the given size, type, and data
        // Note: The step is the number of bytes per row
        return cv::Mat(img.height, img.width, type, img.data, img.bytesPerRow);
    }
 
    cv_image_t convertToImageT(const cv::Mat& mat) {
        cv_image_t img;
 
        img.width = static_cast<uint32_t>(mat.cols);
        img.height = static_cast<uint32_t>(mat.rows);
        int type = mat.type();
        if (type == CV_8UC1) {
            img.components = 1;
        } else if (type == CV_8UC3) {
            img.components = 3;
        }
        img.bytesPerRow = static_cast<uint32_t>(mat.step); // or mat.step1()
 
        // Allocate memory for the data
        size_t dataSize = mat.step * mat.rows; // or mat.total() * mat.elemSize()
        img.data = new uint8_t[dataSize];
 
        // Copy the data from the cv::Mat
        std::memcpy(img.data, mat.data, dataSize);
 
        return img;
    }
 
    cv_image_t myAdaptiveThreshold(cv_image_t img) {
        cv::Mat inputImage = convertToMat(img);
        cv::Mat outputImage;
        adaptiveThreshold(inputImage, outputImage, 255, cv::ADAPTIVE_THRESH_MEAN_C, cv::THRESH_BINARY, 11, 2);
        return convertToImageT(outputImage);
    }
}