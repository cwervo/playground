package main

import (
	"flag"
	"fmt"
	"image"
	"image/color/palette"
	"image/draw"
	"image/gif"
	"log"
	"os"

	"gocv.io/x/gocv"
)

func main() {
	// Define command-line flags for input/output files and the frame skip interval.
	inputFile := flag.String("i", "", "Path to the input video file. (Required)")
	outputFile := flag.String("o", "output.gif", "Path for the output GIF file.")
	frameSkip := flag.Int("s", 10, "Frame skip interval. Higher values mean a choppier, more 'stop-motion' look.")
	delay := flag.Int("d", 10, "Delay between frames in 1/100ths of a second.")

	flag.Parse()

	// Validate that the input file was provided.
	if *inputFile == "" {
		log.Println("Error: Input video file path is required.")
		flag.Usage()
		os.Exit(1)
	}

	// --- Video Processing ---

	// Open the video file using GoCV.
	vc, err := gocv.VideoCaptureFile(*inputFile)
	if err != nil {
		log.Fatalf("Error opening video file: %v", err)
	}
	defer vc.Close()

	fmt.Printf("Processing video: %s\n", *inputFile)

	var images []*image.Paletted
	var delays []int
	img := gocv.NewMat()
	defer img.Close()

	frameCount := 0
	processedFrames := 0

	// Loop through the video frames.
	for {
		if ok := vc.Read(&img); !ok {
			// If we can't read a frame, we've likely reached the end of the video.
			fmt.Println("Reached end of video.")
			break
		}
		if img.Empty() {
			continue
		}

		// Apply the frame skip logic.
		if frameCount%*frameSkip == 0 {
			// Convert the gocv.Mat to a standard Go image.Image.
			frame, err := img.ToImage()
			if err != nil {
				log.Printf("Warning: Could not convert frame %d to image: %v", frameCount, err)
				continue
			}

			// Create a new paletted image. GIFs require a limited color palette.
			bounds := frame.Bounds()
			palettedImage := image.NewPaletted(bounds, palette.Plan9)

			// Draw the original frame onto the paletted image.
			// This quantizes the colors to fit the palette.
			draw.Draw(palettedImage, palettedImage.Rect, frame, bounds.Min, draw.Over)

			// Add the processed frame and its delay to our slices.
			images = append(images, palettedImage)
			delays = append(delays, *delay)
			processedFrames++
			fmt.Printf("\rProcessed frame %d", processedFrames)
		}
		frameCount++
	}
	fmt.Println("\nFinished processing frames.")

	if len(images) == 0 {
		log.Fatal("No frames were extracted from the video. Try a lower frame skip value.")
	}

	// --- GIF Creation ---

	fmt.Printf("Creating GIF: %s\n", *outputFile)

	// Create the output file.
	f, err := os.Create(*outputFile)
	if err != nil {
		log.Fatalf("Error creating output file: %v", err)
	}
	defer f.Close()

	// Encode the frames into a GIF.
	err = gif.EncodeAll(f, &gif.GIF{
		Image: images,
		Delay: delays,
	})

	if err != nil {
		log.Fatalf("Error encoding GIF: %v", err)
	}

	fmt.Println("Successfully created stop-motion GIF!")
}

