import numpy as np
import matplotlib.pyplot as plt
import cv2

cap = cv2.VideoCapture(1)

while True:
    ret, image = cap.read()
    if ret:
        grayscale = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    else:
        print("Failed to retrieve frame. Check camera availability.")
        break
    # convert to grayscale
    grayscale = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    # perform edge detection
    edges = cv2.Canny(grayscale, 30, 100)
    # detect lines in the image using hough lines technique
    lines = cv2.HoughLinesP(edges, 1, np.pi/180, 60, np.array([]), 50, 5)
    # iterate over the output lines and draw them

    # if length of lines is greater than 0
    if lines is not None:
        for line in lines:
            for x1, y1, x2, y2 in line:
                cv2.line(image, (x1, y1), (x2, y2), (255, 0, 0), 3)
                cv2.line(edges, (x1, y1), (x2, y2), (255, 0, 0), 3)
    # show images
    cv2.imshow("image", image)
    cv2.imshow("grayscale", grayscale)
    # if edges exists show edges
    # if edges is not None:
    #     cv2.imshow("edges", edges)

    # convert BGR to RGB to be suitable for showing using matplotlib library
    image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
    # make a copy of the original image
    cimage = image.copy()
    # convert image to grayscale
    image = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    # apply a blur using the median filter
    image = cv2.medianBlur(image, 5)
    # finds the circles in the grayscale image using the Hough transform
    circles = cv2.HoughCircles(image=image, method=cv2.HOUGH_GRADIENT, dp=1, minDist=1, param1=50, param2=30, minRadius=50)
    # circles = cv2.HoughCircles(image=image, method=cv2.HOUGH_GRADIENT, dp=1, minDist=1, param1=50, param2=30, minRadius=0, maxRadius=80)

    print(circles)
    if circles is not None:
        for co, i in enumerate(circles[0, :], start=1):
            print('found circle #{}'.format(co))
            # draw the outer circle in green
            cv2.circle(cimage,(int(i[0]),int(i[1])),int(i[2]),(0,255,0),2)
            # draw the center of the circle in red
            cv2.circle(cimage,(int(i[0]),int(i[1])),2,(0,0,255),3)

            
        # print the number of circles detected
        print("Number of circles detected:", co)
        # save the image, convert to BGR to save with proper colors
        # cv2.imwrite("coins_circles_detected.png", cimage)
        # show the image
        plt.imshow(cimage)
        plt.show()

    if cv2.waitKey(1) == ord("q"):
        break
cap.release()
cv2.destroyAllWindows()