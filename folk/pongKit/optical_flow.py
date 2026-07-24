import cv2
import numpy as np
import sys
import os

input_vid = sys.argv[1]
output_img = sys.argv[2]

cap = cv2.VideoCapture(input_vid)
ret, frame1 = cap.read()
if not ret:
    sys.exit(1)

# we want 25fps. the video is ~25fps, so we just read frames.
prvs = cv2.cvtColor(frame1, cv2.COLOR_BGR2GRAY)
hsv = np.zeros_like(frame1)
hsv[..., 1] = 255 # saturation is max

frames = []
trail_canvas = np.zeros_like(frame1, dtype=np.float32)

while(1):
    ret, frame2 = cap.read()
    if not ret:
        break
    
    next_gray = cv2.cvtColor(frame2, cv2.COLOR_BGR2GRAY)
    
    # Calculate optical flow
    flow = cv2.calcOpticalFlowFarneback(prvs, next_gray, None, 0.5, 3, 15, 3, 5, 1.2, 0)
    
    mag, ang = cv2.cartToPolar(flow[..., 0], flow[..., 1])
    hsv[..., 0] = ang*180/np.pi/2
    hsv[..., 2] = cv2.normalize(mag, None, 0, 255, cv2.NORM_MINMAX)
    
    rgb = cv2.cvtColor(hsv, cv2.COLOR_HSV2BGR)
    
    # Add onion skinning (trails)
    # Decay the trail canvas
    trail_canvas *= 0.85
    # Add the current optical flow magnitude
    trail_canvas = np.maximum(trail_canvas, rgb.astype(np.float32))
    
    final_frame = trail_canvas.astype(np.uint8)
    frames.append(final_frame)
    
    prvs = next_gray

cap.release()

# Now we tile the frames 10x8
th, tw = int(final_frame.shape[0] * 160 / final_frame.shape[1]), 160
contact_sheet = np.zeros((th * 8, tw * 10, 3), dtype=np.uint8)

for i, f in enumerate(frames[:80]): # Up to 80 frames
    row = i // 10
    col = i % 10
    if row >= 8: break
    resized = cv2.resize(f, (tw, th))
    contact_sheet[row*th:(row+1)*th, col*tw:(col+1)*tw] = resized

cv2.imwrite(output_img, contact_sheet)
print(f"Saved to {output_img}")
