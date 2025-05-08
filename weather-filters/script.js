// --- DOM Element References ---
const cameraCanvas = document.getElementById('cameraCanvas');
const grantAccessBtn = document.getElementById('grantAccessBtn');
const filterButtonsContainer = document.getElementById('filterButtons');
const video = document.createElement('video'); 
video.autoplay = true; // Autoplay once stream is set
video.muted = true; // Muting is often required for autoplay, especially on mobile
video.setAttribute('playsinline', ''); // Crucial for iOS Safari

// --- WebGL State & Configuration ---
let gl; 
let currentShaderProgramInfo; 
let positionBuffer;       
let texCoordBuffer;       
let videoTexture;         
let currentFilterName = 'none'; 
let animationFrameId = null; // To manage the requestAnimationFrame loop

// --- Shader Definitions ---
const vertexShaderSource = `
    attribute vec4 aVertexPosition; 
    attribute vec2 aTexCoord;       
    varying highp vec2 vTexCoord;   
    void main(void) {
        gl_Position = aVertexPosition; 
        vTexCoord = aTexCoord;         
    }
`;

const fragmentShaders = {
    'none': `precision mediump float;
varying highp vec2 vTexCoord;
uniform sampler2D uSampler;
void main(void) {
    gl_FragColor = texture2D(uSampler, vTexCoord);
}`,
    'grayscale': `precision mediump float;
varying highp vec2 vTexCoord;
uniform sampler2D uSampler;
void main(void) {
    vec4 color = texture2D(uSampler, vTexCoord);
    float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    gl_FragColor = vec4(vec3(gray), color.a); 
}`,
    'sepia': `precision mediump float;
varying highp vec2 vTexCoord;
uniform sampler2D uSampler;
void main(void) {
    vec4 color = texture2D(uSampler, vTexCoord);
    float r = color.r * 0.393 + color.g * 0.769 + color.b * 0.189;
    float g = color.r * 0.349 + color.g * 0.686 + color.b * 0.168;
    float b = color.r * 0.272 + color.g * 0.534 + color.b * 0.131;
    gl_FragColor = vec4(min(r, 1.0), min(g, 1.0), min(b, 1.0), color.a);
}`,
    'invert': `precision mediump float;
varying highp vec2 vTexCoord;
uniform sampler2D uSampler;
void main(void) {
    vec4 color = texture2D(uSampler, vTexCoord);
    gl_FragColor = vec4(1.0 - color.rgb, color.a); 
}`,
    'cloudy': `precision mediump float;
varying highp vec2 vTexCoord;
uniform sampler2D uSampler;
void main(void) {
    vec4 color = texture2D(uSampler, vTexCoord);
    float avg = (color.r + color.g + color.b) / 3.0;
    vec3 cooler = mix(color.rgb, vec3(avg * 0.8, avg * 0.9, avg * 1.1), 0.3); 
    float desatFactor = 0.2; 
    vec3 desaturated = mix(cooler, vec3(dot(cooler, vec3(0.299, 0.587, 0.114))), desatFactor);
    gl_FragColor = vec4(desaturated, color.a);
}`,
    'moonlight': `precision mediump float;
varying highp vec2 vTexCoord;
uniform sampler2D uSampler;
void main(void) {
    vec4 color = texture2D(uSampler, vTexCoord);
    vec3 brightenedColor = color.rgb * 1.4;
    float luminance = dot(brightenedColor, vec3(0.2126, 0.7152, 0.0722));
    vec3 blueTint = vec3(0.6, 0.8, 1.0); 
    vec3 moonlightColor = mix(brightenedColor, brightenedColor * blueTint, smoothstep(0.3, 0.8, luminance) * 0.6);
    moonlightColor = (moonlightColor - 0.5) * 1.2 + 0.5;
    gl_FragColor = vec4(clamp(moonlightColor, 0.0, 1.0), color.a);
}`,
    'sunlight': `precision mediump float;
varying highp vec2 vTexCoord;
uniform sampler2D uSampler;
void main(void) {
    vec4 originalColor = texture2D(uSampler, vTexCoord);
    vec3 warmCastColor = vec3(1.0, 0.98, 0.85); 
    vec3 colorWithCast = mix(originalColor.rgb, warmCastColor, 0.12);
    vec2 flarePosition = vec2(0.2, 0.8); 
    float distToFlare = distance(vTexCoord, flarePosition);
    float flareIntensity = smoothstep(0.4, 0.05, distToFlare) * 0.55; 
    vec3 flareColor = vec3(1.0, 0.95, 0.7) * flareIntensity; 
    vec3 finalColor = clamp(colorWithCast + flareColor, 0.0, 1.0);
    gl_FragColor = vec4(finalColor, originalColor.a);
}`
};

// --- Filter Button Configuration ---
const filterButtonData = [
    { name: 'none', text: 'Normal', icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 18a6 6 0 0 0 0-12v12Z"/></svg>' },
    { name: 'grayscale', text: 'Grayscale', icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2"/><path d="M3 12h18"/></svg>' },
    { name: 'sepia', text: 'Sepia', icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3c-1.93 0-3.68.73-4.95 1.95S4.27 7.07 4.27 9c0 1.2.38 2.31.97 3.26L3 17h18l-2.24-4.74c.59-.95.97-2.06.97-3.26 0-1.93-.73-3.68-1.95-4.95S13.93 3 12 3Z"/><path d="M12 12v1"/></svg>'},
    { name: 'invert', text: 'Invert', icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22C6.477 22 2 17.523 2 12S6.477 2 12 2s10 4.477 10 10-4.477 10-10 10zm0-2a8 8 0 1 0 0-16 8 8 0 0 0 0 16z"/><path d="M12 6v12"/></svg>'},
    { name: 'cloudy', text: 'Cloudy', icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z"/><path d="M22 10a4.5 4.5 0 0 0-4.5-4.5M17.5 19H9"/></svg>'},
    { name: 'moonlight', text: 'Moonlight', icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/><path d="M19 3v4M21 5h-4"/></svg>'},
    { name: 'sunlight', text: 'Sunlight', icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2"/><path d="M12 20v2"/><path d="m4.93 4.93 1.41 1.41"/><path d="m17.66 17.66 1.41 1.41"/><path d="M2 12h2"/><path d="M20 12h2"/><path d="m6.34 17.66-1.41 1.41"/><path d="m19.07 4.93-1.41 1.41"/></svg>'},
];

// --- Core Functions ---

async function setupCamera() {
    try {
        // Request camera stream
        const stream = await navigator.mediaDevices.getUserMedia({
            video: {
                facingMode: 'user', 
                width: { ideal: 1280 }, 
                height: { ideal: 720 }
                // aspectRatio: { ideal: 16/9 } // Alternative to width/height
            }
        });
        video.srcObject = stream;
        
        // Wait for video metadata to be loaded
        video.onloadedmetadata = () => {
            // Attempt to play the video. User interaction (button click) has already occurred.
            video.play().then(() => {
                console.log("Video playback started.");
                adjustCanvasToVideo(); 
                initializeWebGL();     
                
                if (gl) { 
                    createFilterButtons(); 
                    if (animationFrameId) cancelAnimationFrame(animationFrameId); // Cancel previous loop if any
                    renderLoop(); // Start the rendering loop
                    grantAccessBtn.style.display = 'none'; 
                    filterButtonsContainer.style.display = 'flex'; 
                }
            }).catch(playError => {
                console.error("Error attempting to play video:", playError);
                alert("Video playback failed. This might be due to browser restrictions or an issue with the camera feed.");
            });
        };
        video.onerror = (e) => {
            console.error("Video error:", e);
            alert("An error occurred with the video stream.");
        };

    } catch (err) {
        console.error("Error accessing camera:", err.name, err.message);
        let alertMessage = "Could not access the camera. Please ensure permissions are granted and no other application is using it.";
        if (err.name === "NotAllowedError") {
            alertMessage = "Camera access was denied. Please grant permission in your browser settings and refresh the page.";
        } else if (err.name === "NotFoundError") {
            alertMessage = "No camera was found. Please ensure a camera is connected and enabled.";
        } else if (err.name === "NotReadableError") {
            alertMessage = "The camera is currently in use by another application or a hardware error occurred.";
        }
        alert(alertMessage);
        grantAccessBtn.textContent = "Camera Access Failed";
        grantAccessBtn.style.backgroundColor = "#dc3545"; 
    }
}

function adjustCanvasToVideo() {
    if (!video.videoWidth || !video.videoHeight) {
        console.warn("Video dimensions not yet available for adjustCanvasToVideo");
        return;
    }
    cameraCanvas.width = video.videoWidth;
    cameraCanvas.height = video.videoHeight;
    const aspectRatio = video.videoWidth / video.videoHeight;
    const container = cameraCanvas.parentElement;
    let displayWidth = container.clientWidth;
    let displayHeight = displayWidth / aspectRatio;
    
    // Ensure filterButtonsContainer is visible to get its offsetHeight, or use a fallback
    const buttonsHeight = filterButtonsContainer.style.display !== 'none' ? filterButtonsContainer.offsetHeight : 70; // Fallback height
    const maxHeight = window.innerHeight - (buttonsHeight + 40); 

    if (displayHeight > maxHeight && maxHeight > 0) { 
        displayHeight = maxHeight;
        displayWidth = displayHeight * aspectRatio;
    }
    cameraCanvas.style.width = `${displayWidth}px`;
    cameraCanvas.style.height = `${displayHeight}px`;
    if (gl) {
        gl.viewport(0, 0, gl.canvas.width, gl.canvas.height);
    }
}

function initializeWebGL() {
    gl = cameraCanvas.getContext('webgl', { 
        premultipliedAlpha: false,
        antialias: false, // Can save some performance, often not needed for video
        powerPreference: 'low-power' // Suggest low power for battery on mobile
    }); 
    if (!gl) {
        alert("WebGL is not supported or disabled on your browser. Filters will not work.");
        console.error("WebGL not supported!");
        return;
    }
    if (!switchShaderProgram(fragmentShaders['none'])) {
        console.error("Failed to initialize default shader program.");
        gl = null; 
        return; 
    }
    // Quad vertices
    const positions = new Float32Array([-1.0, -1.0,  1.0, -1.0, -1.0,  1.0, 1.0,  1.0,]);
    positionBuffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, positions, gl.STATIC_DRAW);
    
    // Texture coordinates (Y-flipped for video)
    const texCoords = new Float32Array([0.0, 1.0, 1.0, 1.0, 0.0, 0.0, 1.0, 0.0]);
    texCoordBuffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, texCoordBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, texCoords, gl.STATIC_DRAW);
    
    // Video texture setup
    videoTexture = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, videoTexture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    
    gl.viewport(0, 0, gl.canvas.width, gl.canvas.height);
}

function compileShader(type, source) {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        const shaderType = type === gl.VERTEX_SHADER ? "vertex" : "fragment";
        console.error(`Error compiling ${shaderType} shader:`, gl.getShaderInfoLog(shader));
        console.log("Shader source:\n", source); 
        gl.deleteShader(shader);
        return null;
    }
    return shader;
}

function switchShaderProgram(fsSource) {
    if (!gl) return false; // Ensure gl context is available

    const vertexShader = compileShader(gl.VERTEX_SHADER, vertexShaderSource);
    const fragmentShader = compileShader(gl.FRAGMENT_SHADER, fsSource);
    if (!vertexShader || !fragmentShader) {
        if (vertexShader) gl.deleteShader(vertexShader);
        if (fragmentShader) gl.deleteShader(fragmentShader);
        return false;
    }
    const newProgram = gl.createProgram();
    gl.attachShader(newProgram, vertexShader);
    gl.attachShader(newProgram, fragmentShader);
    gl.linkProgram(newProgram);
    if (!gl.getProgramParameter(newProgram, gl.LINK_STATUS)) {
        console.error("Error linking shader program:", gl.getProgramInfoLog(newProgram));
        gl.deleteProgram(newProgram); 
        gl.deleteShader(vertexShader);
        gl.deleteShader(fragmentShader);
        return false;
    }
    if (currentShaderProgramInfo && currentShaderProgramInfo.program) {
        gl.deleteProgram(currentShaderProgramInfo.program);
    }
    currentShaderProgramInfo = {
        program: newProgram,
        attribLocations: {
            vertexPosition: gl.getAttribLocation(newProgram, 'aVertexPosition'),
            textureCoord: gl.getAttribLocation(newProgram, 'aTexCoord'),
        },
        uniformLocations: {
            sampler: gl.getUniformLocation(newProgram, 'uSampler'),
        },
    };
    gl.detachShader(newProgram, vertexShader); 
    gl.detachShader(newProgram, fragmentShader);
    gl.deleteShader(vertexShader);
    gl.deleteShader(fragmentShader);
    return true; 
}

function createFilterButtons() {
    filterButtonsContainer.innerHTML = filterButtonData.map(btn => `
        <button data-filter="${btn.name}" class="${btn.name === currentFilterName ? 'active' : ''}" title="Apply ${btn.text} filter">
            ${btn.icon}
            <span>${btn.text}</span>
        </button>
    `).join('');
    filterButtonsContainer.querySelectorAll('button').forEach(button => {
        button.addEventListener('click', (e) => {
            // Prevent double-taps/zooming on iOS for buttons
            e.preventDefault(); 
            const filterName = e.currentTarget.dataset.filter;
            applyFilter(filterName);
        });
    });
}

function applyFilter(filterName) {
    if (!gl) { 
        console.error("WebGL context not available. Cannot apply filter.");
        return;
    }
    if (!fragmentShaders[filterName]) {
        console.warn(`Filter "${filterName}" not found in fragmentShaders object.`);
        return;
    }
    if (filterName === currentFilterName && currentShaderProgramInfo && currentShaderProgramInfo.program) return; 
    
    console.log(`Attempting to apply filter: ${filterName}`);
    if (switchShaderProgram(fragmentShaders[filterName])) {
        currentFilterName = filterName;
        const activeButton = filterButtonsContainer.querySelector('button.active');
        if (activeButton) activeButton.classList.remove('active');
        const newActiveButton = filterButtonsContainer.querySelector(`button[data-filter="${filterName}"]`);
        if (newActiveButton) newActiveButton.classList.add('active');
        console.log(`Successfully applied filter: ${filterName}`);
    } else {
        console.error(`Failed to apply filter: ${filterName}. Attempting to revert to 'none'.`);
        if (currentFilterName !== 'none') { 
            if (switchShaderProgram(fragmentShaders['none'])) {
                currentFilterName = 'none';
                const activeButton = filterButtonsContainer.querySelector('button.active');
                if (activeButton) activeButton.classList.remove('active');
                const noneButton = filterButtonsContainer.querySelector(`button[data-filter="none"]`);
                if (noneButton) noneButton.classList.add('active');
            } else {
                console.error("CRITICAL: Failed to revert to 'none' filter. WebGL rendering may be broken.");
            }
        }
    }
}

function renderLoop() {
    animationFrameId = requestAnimationFrame(renderLoop); 
    if (!gl || !currentShaderProgramInfo || !currentShaderProgramInfo.program || video.paused || video.ended || video.readyState < video.HAVE_ENOUGH_DATA) {
        return; 
    }
    // Update video texture (only if video has updated, though texImage2D is often idempotent if content hasn't changed)
    // For performance, some apps check video.currentTime against a stored last time.
    // However, for real-time filters, updating every frame is usually desired.
    gl.bindTexture(gl.TEXTURE_2D, videoTexture);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, video);
    
    gl.useProgram(currentShaderProgramInfo.program);
    
    gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer);
    gl.vertexAttribPointer(currentShaderProgramInfo.attribLocations.vertexPosition, 2, gl.FLOAT, false, 0, 0 );
    gl.enableVertexAttribArray(currentShaderProgramInfo.attribLocations.vertexPosition);
    
    gl.bindBuffer(gl.ARRAY_BUFFER, texCoordBuffer);
    gl.vertexAttribPointer(currentShaderProgramInfo.attribLocations.textureCoord, 2, gl.FLOAT, false, 0, 0 );
    gl.enableVertexAttribArray(currentShaderProgramInfo.attribLocations.textureCoord);
    
    gl.activeTexture(gl.TEXTURE0); 
    gl.bindTexture(gl.TEXTURE_2D, videoTexture); // Ensure correct texture is bound before drawing
    gl.uniform1i(currentShaderProgramInfo.uniformLocations.sampler, 0);
    
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4); 
}

// --- Event Listeners ---
if (grantAccessBtn) {
    grantAccessBtn.addEventListener('click', setupCamera);
}
window.addEventListener('resize', adjustCanvasToVideo); 

// Add a listener for when the page becomes visible again (e.g., switching tabs)
// This can help restart the video or rendering if it was paused by the browser.
document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
        if (video.srcObject && video.paused) {
            video.play().catch(e => console.warn("Failed to resume video on visibility change:", e));
        }
        // If renderLoop was stopped, you might need to restart it here,
        // but requestAnimationFrame usually handles pausing/resuming with visibility.
    } else {
        // Optionally, you could explicitly cancelAnimationFrame here if power saving is critical
        // if (animationFrameId) cancelAnimationFrame(animationFrameId);
    }
});

// Initial UI setup if needed
adjustCanvasToVideo(); // Adjust canvas size on initial load based on current window size
