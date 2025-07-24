const cameraContainer = document.getElementById('camera-container');
const cameraStream = document.getElementById('camera-stream');
const captureBtn = document.getElementById('capture-btn');

async function startCamera() {
    try {
        const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } });
        cameraStream.srcObject = stream;
    } catch (err) {
        console.error('Error accessing camera:', err);
    }
}

function getLocation() {
    return new Promise((resolve, reject) => {
        if (!navigator.geolocation) {
            reject('Geolocation is not supported by your browser');
        } else {
            navigator.geolocation.getCurrentPosition(resolve, reject);
        }
    });
}

captureBtn.addEventListener('click', async () => {
    const canvas = document.createElement('canvas');
    canvas.width = cameraStream.videoWidth;
    canvas.height = cameraStream.videoHeight;
    const ctx = canvas.getContext('2d');
    ctx.drawImage(cameraStream, 0, 0, canvas.width, canvas.height);

    const qrCodeDataUrl = await QRCode.toDataURL(window.location.href);
    const qrCodeImage = new Image();
    qrCodeImage.src = qrCodeDataUrl;
    qrCodeImage.onload = () => {
        const qrCodeSize = Math.min(canvas.width, canvas.height) / 4;
        ctx.drawImage(qrCodeImage, canvas.width - qrCodeSize - 10, canvas.height - qrCodeSize - 10, qrCodeSize, qrCodeSize);

        await new Promise(async (resolve) => {
            const photoBlob = await new Promise(resolve => canvas.toBlob(resolve, 'image/png'));
            const location = await getLocation();
            const metadata = {
                date: new Date().toISOString(),
                location: {
                    latitude: location.coords.latitude,
                    longitude: location.coords.longitude,
                },
                url: window.location.href,
            };
            const metadataBlob = new Blob([JSON.stringify(metadata, null, 2)], { type: 'application/json' });

            await addPhoto(photoBlob, metadataBlob);
            resolve();
        });
    };
});

startCamera();
