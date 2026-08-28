// Wrap p5.js sketch in a function to be instantiated
const sketch = (p) => {
  let circleSize = 100; // Initial size of the circle
  let mic, fft;
  let selfieTexture = null; // To store the selfie texture

  p.setup = function() {
    p.createCanvas(p.windowWidth, p.windowHeight, p.WEBGL);
    mic = new p5.AudioIn();
    mic.start();
    fft = new p5.FFT();
    fft.setInput(mic);
    window.sketchInstance = p; // Make sketch instance globally available
    p.selfieTexture = null; // Initialize selfieTexture on the instance
  };

  p.draw = function() {
    p.background(0, 0, 0, 0); // Transparent background
    let volume = mic.getLevel();
    circleSize = p.map(volume, 0, 1, 50, 300);

    if (p.selfieTexture) {
      p.texture(p.selfieTexture);
      p.noStroke();
    } else {
      p.fill(255, 100, 150);
      p.stroke(255);
      p.strokeWeight(2);
    }
    p.ellipse(0, 0, circleSize, circleSize);
  };

  p.windowResized = function() {
    p.resizeCanvas(p.windowWidth, p.windowHeight);
  };

  // This function will be called from index.html via window.sketchInstance
  p.setSelfieTextureFromUrl = function(imageUrl) {
    p.loadImage(imageUrl, img => {
      p.selfieTexture = img; // Set the texture on the sketch instance
      console.log("Selfie texture updated in sketch from URL.");
    }, err => {
      console.error("Error loading selfie image in sketch:", err);
    });
  };
};

// The script in index.html should call:
// window.sketchInstance.setSelfieTextureFromUrl(imageDataUrl);
