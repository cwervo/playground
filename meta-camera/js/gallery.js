const gallery = document.getElementById('gallery');

async function loadGallery() {
    const photos = await getPhotos();
    photos.forEach(photoData => {
        const item = document.createElement('div');
        item.classList.add('gallery-item');

        const img = document.createElement('img');
        img.src = URL.createObjectURL(photoData.photo);
        item.appendChild(img);

        const metadata = document.createElement('div');
        metadata.classList.add('metadata');
        const metadataReader = new FileReader();
        metadataReader.onload = (e) => {
            const metadataText = e.target.result;
            const metadataJson = JSON.parse(metadataText);
            metadata.innerHTML = `<p>Date: ${new Date(metadataJson.date).toLocaleString()}</p>
                                  <p>Location: ${metadataJson.location.latitude}, ${metadataJson.location.longitude}</p>`;
        };
        metadataReader.readAsText(photoData.metadata);
        item.appendChild(metadata);

        gallery.appendChild(item);
    });
}

loadGallery();
