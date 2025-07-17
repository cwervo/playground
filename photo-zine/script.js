const uploadContainer = document.getElementById('upload-container');
const fileInput = document.getElementById('file-input');
const photoContainer = document.getElementById('photo-container');
const generateZineBtn = document.getElementById('generate-zine-btn');

uploadContainer.addEventListener('dragover', (e) => {
    e.preventDefault();
    uploadContainer.classList.add('dragover');
});

uploadContainer.addEventListener('dragleave', () => {
    uploadContainer.classList.remove('dragover');
});

uploadContainer.addEventListener('drop', (e) => {
    e.preventDefault();
    uploadContainer.classList.remove('dragover');
    const files = e.dataTransfer.files;
    handleFiles(files);
});

fileInput.addEventListener('change', () => {
    const files = fileInput.files;
    handleFiles(files);
});

function handleFiles(files) {
    for (const file of files) {
        if (file.type.startsWith('image/')) {
            const reader = new FileReader();
            reader.onload = () => {
                const img = new Image();
                img.src = reader.result;
                img.onload = () => {
                    EXIF.getData(img, function() {
                        const lat = EXIF.getTag(this, "GPSLatitude");
                        const lon = EXIF.getTag(this, "GPSLongitude");
                        const location = (lat && lon) ? `${lat.join(', ')} ${lon.join(', ')}` : 'Location not found';

                        const photoItem = document.createElement('div');
                        photoItem.classList.add('photo-item');
                        photoItem.innerHTML = `
                            <img src="${reader.result}" alt="${file.name}">
                            <div class="location">${location}</div>
                            <div class="note" contenteditable="true">Add a note...</div>
                        `;
                        photoContainer.appendChild(photoItem);
                    });
                };
            };
            reader.readAsDataURL(file);
        }
    }
}

generateZineBtn.addEventListener('click', () => {
    const zineWindow = window.open('', '_blank');
    const zineContent = `
        <html>
            <head>
                <title>Photo Zine</title>
                <style>
                    body { font-family: sans-serif; }
                    .page {
                        display: grid;
                        grid-template-columns: 1fr 1fr;
                        grid-template-rows: 1fr 1fr;
                        height: 100vh;
                        page-break-after: always;
                    }
                    .zine-item { padding: 20px; }
                    img { max-width: 100%; height: auto; }
                    .location { font-size: 0.8em; color: #666; }
                    .note { margin-top: 10px; }
                </style>
            </head>
            <body>
                ${generateZineHTML()}
            </body>
        </html>
    `;
    zineWindow.document.write(zineContent);
});

function generateZineHTML() {
    let html = '';
    const photoItems = photoContainer.querySelectorAll('.photo-item');
    for (let i = 0; i < photoItems.length; i += 4) {
        html += '<div class="page">';
        for (let j = i; j < i + 4 && j < photoItems.length; j++) {
            html += `<div class="zine-item">${photoItems[j].innerHTML}</div>`;
        }
        html += '</div>';
    }
    return html;
}
