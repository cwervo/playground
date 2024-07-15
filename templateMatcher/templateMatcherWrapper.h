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
 
void MatchingMethod( int, void* );
void runMatcher(char* imgPath, cv_image_t frameImg);
 
double getMatchLocX();
double getMatchLocY();

#ifdef __cplusplus
}
#endif
 
#endif // OPENCV_WRAPPER_H