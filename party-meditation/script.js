// --- DOM Element References ---
const canvas = document.getElementById('cameraCanvas');

// --- WebGL State & Configuration ---
let gl;
let shaderProgramInfo;
let positionBuffer;
let startTime = Date.now();
let mouse = [0.5, 0.5];

// --- Shader Definitions ---
const vertexShaderSource = `
    attribute vec4 aVertexPosition;
    void main(void) {
        gl_Position = aVertexPosition;
    }
`;

const fragmentShaderSource = `
    precision highp float;
    uniform vec2 u_resolution;
    uniform float u_time;
    uniform vec2 u_mouse;
    uniform float u_chaos;

    // 2D Random
    float random (in vec2 st) {
        return fract(sin(dot(st.xy,
                             vec2(12.9898,78.233)))
                     * 43758.5453123);
    }

    // 2D Noise based on Morgan McGuire @morgan3d
    // https://www.shadertoy.com/view/4dS3Wd
    float noise (in vec2 st) {
        vec2 i = floor(st);
        vec2 f = fract(st);

        // Four corners in 2D of a tile
        float a = random(i);
        float b = random(i + vec2(1.0, 0.0));
        float c = random(i + vec2(0.0, 1.0));
        float d = random(i + vec2(1.0, 1.0));

        vec2 u = f * f * (3.0 - 2.0 * f);

        return mix(a, b, u.x) +
                (c - a)* u.y * (1.0 - u.x) +
                (d - b) * u.x * u.y;
    }

    void main() {
        vec2 st = gl_FragCoord.xy/u_resolution.xy;
        st.x *= u_resolution.x/u_resolution.y;

        // Add time to the noise parameters
        float n = noise(st * u_chaos + u_time * 0.1 + u_mouse.x);

        // Create a color palette
        vec3 color1 = vec3(0.96, 0.76, 0.76); // Warm
        vec3 color2 = vec3(0.6, 0.7, 0.98); // Cool

        // Mix the colors based on the noise value
        vec3 color = mix(color1, color2, n);

        gl_FragColor = vec4(color, 1.0);
    }
`;

function initializeWebGL() {
    gl = canvas.getContext('webgl');
    if (!gl) {
        alert('WebGL not supported!');
        return;
    }

    const vertexShader = compileShader(gl, gl.VERTEX_SHADER, vertexShaderSource);
    const fragmentShader = compileShader(gl, gl.FRAGMENT_SHADER, fragmentShaderSource);
    const shaderProgram = gl.createProgram();
    gl.attachShader(shaderProgram, vertexShader);
    gl.attachShader(shaderProgram, fragmentShader);
    gl.linkProgram(shaderProgram);

    if (!gl.getProgramParameter(shaderProgram, gl.LINK_STATUS)) {
        console.error('Unable to initialize the shader program: ' + gl.getProgramInfoLog(shaderProgram));
        return null;
    }

    shaderProgramInfo = {
        program: shaderProgram,
        attribLocations: {
            vertexPosition: gl.getAttribLocation(shaderProgram, 'aVertexPosition'),
        },
        uniformLocations: {
            resolution: gl.getUniformLocation(shaderProgram, 'u_resolution'),
            time: gl.getUniformLocation(shaderProgram, 'u_time'),
            mouse: gl.getUniformLocation(shaderProgram, 'u_mouse'),
            chaos: gl.getUniformLocation(shaderProgram, 'u_chaos'),
        },
    };

    positionBuffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer);
    const positions = [
        -1.0, -1.0,
         1.0, -1.0,
        -1.0,  1.0,
         1.0,  1.0,
    ];
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(positions), gl.STATIC_DRAW);

    renderLoop();
}

function compileShader(gl, type, source) {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        console.error('An error occurred compiling the shaders: ' + gl.getShaderInfoLog(shader));
        gl.deleteShader(shader);
        return null;
    }
    return shader;
}

function renderLoop() {
    resizeCanvasToDisplaySize(gl.canvas);
    gl.viewport(0, 0, gl.canvas.width, gl.canvas.height);

    gl.clearColor(0.0, 0.0, 0.0, 1.0);
    gl.clear(gl.COLOR_BUFFER_BIT);

    gl.useProgram(shaderProgramInfo.program);

    gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer);
    gl.vertexAttribPointer(
        shaderProgramInfo.attribLocations.vertexPosition,
        2, gl.FLOAT, false, 0, 0);
    gl.enableVertexAttribArray(
        shaderProgramInfo.attribLocations.vertexPosition);

    gl.uniform2f(shaderProgramInfo.uniformLocations.resolution, gl.canvas.width, gl.canvas.height);
    gl.uniform1f(shaderProgramInfo.uniformLocations.time, (Date.now() - startTime) / 1000.0);
    gl.uniform2fv(shaderProgramInfo.uniformLocations.mouse, mouse);
    gl.uniform1f(shaderProgramInfo.uniformLocations.chaos, 5.0); // Default chaos value

    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);

    requestAnimationFrame(renderLoop);
}

function resizeCanvasToDisplaySize(canvas) {
    const displayWidth  = canvas.clientWidth;
    const displayHeight = canvas.clientHeight;
    if (canvas.width  !== displayWidth ||
        canvas.height !== displayHeight) {
        canvas.width  = displayWidth;
        canvas.height = displayHeight;
        return true;
    }
    return false;
}

function handleOrientation(event) {
    const x = event.beta;  // In degree in the range [-180,180]
    const y = event.gamma; // In degree in the range [-90,90]

    // Normalize the values to be between 0 and 1
    mouse[0] = (y + 90) / 180;
    mouse[1] = (x + 180) / 360;
}

window.addEventListener('deviceorientation', handleOrientation);
window.onload = initializeWebGL;
