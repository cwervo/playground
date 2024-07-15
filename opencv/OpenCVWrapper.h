#ifndef OPENCV_WRAPPER_H
#define OPENCV_WRAPPER_H
 
#ifdef __cplusplus
extern "C" {
#endif
 
typedef struct {
    uint32_t width;
    uint32_t height;
    int components;
    uint32_t bytesPerRow;
    uint8_t *data;
} cv_image_t;
 
int getWidthOfImage(cv_image_t img);
 
cv_image_t myAdaptiveThreshold(cv_image_t img);
 
#ifdef __cplusplus
}
#endif
 
#endif // OPENCV_WRAPPER_H
