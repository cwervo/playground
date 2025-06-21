// Placeholder for background script logic
console.log("Background service worker loaded.");

chrome.runtime.onInstalled.addListener(() => {
  console.log("Flickr EXIF Viewer extension installed.");
});
