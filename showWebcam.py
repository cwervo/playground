import cv2

def show_webcam():
    # Open the default camera (you can change the index if you have multiple cameras)
    cap = cv2.VideoCapture(1)

    while True:
        # Read a frame from the camera
        ret, frame = cap.read()

        # Display the frame in a window
        cv2.imshow('Webcam', frame)

        # Exit the loop if 'q' key is pressed
        if cv2.waitKey(1) & 0xFF == ord('q'):
            break

    # Release the camera and close the window
    cap.release()
    cv2.destroyAllWindows()

if __name__ == "__main__":
    show_webcam()
