#include <opencv2/opencv.hpp>
#include <opencv2/imgcodecs.hpp>
#include "opencv2/highgui.hpp"
#include <opencv2/imgproc.hpp>
#include <iostream>
 
using namespace std;
using namespace cv;

extern "C" {
    #include "templateMatcherWrapper.h"

    // --------------- begin template matcher original
    bool use_mask;
    Mat img; Mat templ; Mat mask; Mat result;
    int match_method;
    double matchLocX;
    double matchLocY;
    double getMatchLocX() {
      return matchLocX;
    }
    double getMatchLocY() {
      return matchLocY;
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

    void runMatcher (char* imgPath, cv_image_t frameImg) {
      // img = imread(samples::findFile("/home/folk/folk-images/frame.jpg"), IMREAD_GRAYSCALE);
      img = convertToMat(frameImg);
      // templ = imread(samples::findFile( "/home/folk/folk-images/slice.jpg"), IMREAD_GRAYSCALE);
      templ = imread(samples::findFile(imgPath), IMREAD_GRAYSCALE);

      if(img.empty() || templ.empty() || (use_mask && mask.empty())) {
        cout << "Can't read one of the images" << endl;
      } else {
        MatchingMethod( 0, 0 );
      }
    }

    void MatchingMethod( int, void* ) {
      Mat img_display;
      
      // cout << "img mat: " << img.size() << " | " << img.empty() << endl;
      // cout << "img mat: " << templ.size() << " | " << templ.empty() << endl;
      img.copyTo( img_display );
      int result_cols = img.cols - templ.cols + 1;
      int result_rows = img.rows - templ.rows + 1;
      result.create( result_rows, result_cols, CV_32FC1 );

      match_method = TM_CCORR_NORMED;

      bool method_accepts_mask = (TM_SQDIFF == match_method || match_method == TM_CCORR_NORMED);
      if (use_mask && method_accepts_mask)
        { matchTemplate( img, templ, result, match_method, mask); }
      else
        { matchTemplate( img, templ, result, match_method); }
      normalize( result, result, 0, 1, NORM_MINMAX, -1, Mat() );
      double minVal; double maxVal; Point minLoc; Point maxLoc;
      Point matchLoc;
      minMaxLoc( result, &minVal, &maxVal, &minLoc, &maxLoc, Mat() );
      if( match_method  == TM_SQDIFF || match_method == TM_SQDIFF_NORMED ) {
        matchLoc = minLoc;
      } else {
        matchLoc = maxLoc;
      }

      matchLocX = matchLoc.x;
      matchLocY = matchLoc.y;

      Scalar green = Scalar(0,255,0);
      rectangle( img_display, matchLoc, Point( matchLoc.x + templ.cols , matchLoc.y + templ.rows ), green, 2, 8, 0 );
      rectangle( result, matchLoc, Point( matchLoc.x + templ.cols , matchLoc.y + templ.rows ), green, 2, 8, 0 );

      // cout << "matchLoc: " << matchLoc << endl;
      // cout << img_display.size() << endl;
      imwrite("/home/folk/folk-images/result.jpg", img_display);
    }
}