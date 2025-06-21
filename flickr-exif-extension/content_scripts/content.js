// Flickr content script
console.log("Flickr content script loaded. EXIF library should be available.");

// Function to find the main image on a Flickr page
function getMainImage() {
  // Heuristic: Flickr often has a main image element.
  // This selector might need adjustment based on actual Flickr page structure.
  // Common patterns: 'photo-well-media-scrappy-view' for image, or inside 'view photo-well-view'
  // Or a more direct approach if an ID is consistent.
  // Let's try to find an image that looks like the main one.
  let mainImage = document.querySelector('.main-photo-container img'); // Example selector
  if (!mainImage) {
    // Fallback: Look for a large image, possibly with 'role="main"' or specific data attributes
    const images = Array.from(document.querySelectorAll('img'));
    images.sort((a,b) => (b.naturalWidth * b.naturalHeight) - (a.naturalWidth * a.naturalHeight));
    if (images.length > 0 && images[0].naturalWidth > 300) { // Heuristic for "main" image
        mainImage = images[0];
    }
  }
  if (!mainImage) {
      // More robust selector for Flickr's current structure (as of late 2023/early 2024)
      // The main image is often within a div with class "view photo-well-view" or similar.
      // And the image itself might be `img.main-photo` or have a specific test ID.
      // Let's try a selector that has been observed on Flickr photo pages:
      mainImage = document.querySelector('img.main-photo'); // This is a common class for the main image
      if (!mainImage) {
        // Fallback to the image inside the "photo-notes-scrappy-view" which contains the image without notes overlay
        const photoContainer = document.querySelector('.photo-notes-scrappy-view');
        if (photoContainer) {
             mainImage = photoContainer.querySelector('img');
        }
      }
  }
   if (!mainImage) {
        // Fallback for newer Flickr structures (if they change again)
        // Try to find the largest image on the page if specific selectors fail
        const allImages = document.getElementsByTagName('img');
        let largestImage = null;
        let maxArea = 0;
        for (let i = 0; i < allImages.length; i++) {
            if (allImages[i].src.includes('live.staticflickr.com')) { // Filter for Flickr content images
                const area = allImages[i].offsetWidth * allImages[i].offsetHeight;
                if (area > maxArea) {
                    maxArea = area;
                    largestImage = allImages[i];
                }
            }
        }
        mainImage = largestImage;
    }


  return mainImage;
}

chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.action === "getExifData") {
    console.log("Content script received request for EXIF data.");
    const imageElement = getMainImage();

    if (imageElement) {
      console.log("Main image found:", imageElement.src);
      // Ensure the image is loaded before trying to get EXIF data
      // The EXIF.getData function in the library might handle this,
      // or we might need to explicitly wait for onload.
      // Our placeholder exif.js simulates async loading.

      // Make sure the image CORS policy allows reading its data if it's cross-origin
      // For Flickr, the main image should be from the same origin or allow cross-origin use for this.
      // If not, fetching the image via background script might be needed.
      // For now, assume direct access is possible.
      imageElement.crossOrigin = "Anonymous"; // Try to enable CORS

      EXIF.getData(imageElement, function() {
        const allTags = EXIF.getAllTags(this);
        console.log("EXIF data retrieved:", allTags);
        if (Object.keys(allTags).length > 0) {
          sendResponse({ status: "success", data: allTags, imageUrl: this.src, pageUrl: window.location.href });
        } else {
          sendResponse({ status: "error", message: "No EXIF data found in image.", imageUrl: this.src, pageUrl: window.location.href });
        }
      });
    } else {
      console.error("Main image not found on the page.");
      sendResponse({ status: "error", message: "Main image not found." });
    }
    return true; // Indicates that the response will be sent asynchronously
  }
});

// Announce that the content script is ready (optional)
console.log("Flickr content script is active and listening for messages.");
