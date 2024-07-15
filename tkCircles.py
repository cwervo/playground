import cv2
import numpy as np
from PIL import Image, ImageTk
import tkinter as tk

# Create a window
window = tk.Tk()

# Create a canvas
canvas = tk.Canvas(window, width=640, height=480)
canvas.pack()

# Access the camera feed
cap = cv2.VideoCapture(0)

def update_image():
    # Capture a frame
    ret, frame = cap.read()

    # Convert to grayscale
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

    # Perform circle detection
    circles = cv2.HoughCircles(gray, cv2.HOUGH_GRADIENT, 1, 20, param1=50, param2=30, minRadius=0, maxRadius=0)

    # Highlight circles
    if circles is not None:
        circles = np.uint16(np.around(circles))
        for i in circles[0,:]:
            cv2.circle(frame, (i[0], i[1]), i[2], (0, 255, 0), 2)

    # Convert the image from BGR color (which OpenCV uses) to RGB color
    rgb_image = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

    # Convert the Image object into a TkPhoto object
    tk_image = ImageTk.PhotoImage(image=Image.fromarray(rgb_image))

    # Put the image on the canvas
    canvas.create_image(0, 0, image=tk_image, anchor='nw')

    # Call this function again after 10 milliseconds
    window.after(10, update_image)

# Start the process
update_image()

# Start the Tkinter event loop
window.mainloop()
