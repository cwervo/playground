const DB_NAME = 'meta-camera-db';
const DB_VERSION = 1;
const STORE_NAME = 'photos';

let db;

function openDB() {
    return new Promise((resolve, reject) => {
        if (db) {
            return resolve(db);
        }

        const request = indexedDB.open(DB_NAME, DB_VERSION);

        request.onerror = (event) => {
            reject('Error opening IndexedDB');
        };

        request.onsuccess = (event) => {
            db = event.target.result;
            resolve(db);
        };

        request.onupgradeneeded = (event) => {
            const db = event.target.result;
            db.createObjectStore(STORE_NAME, { keyPath: 'id', autoIncrement: true });
        };
    });
}

function addPhoto(photoBlob, metadataBlob) {
    return new Promise(async (resolve, reject) => {
        const db = await openDB();
        const transaction = db.transaction([STORE_NAME], 'readwrite');
        const store = transaction.objectStore(STORE_NAME);
        const request = store.add({ photo: photoBlob, metadata: metadataBlob });

        request.onerror = (event) => {
            reject('Error adding photo to IndexedDB');
        };

        request.onsuccess = (event) => {
            resolve(event.target.result);
        };
    });
}

function getPhotos() {
    return new Promise(async (resolve, reject) => {
        const db = await openDB();
        const transaction = db.transaction([STORE_NAME], 'readonly');
        const store = transaction.objectStore(STORE_NAME);
        const request = store.getAll();

        request.onerror = (event) => {
            reject('Error getting photos from IndexedDB');
        };

        request.onsuccess = (event) => {
            resolve(event.target.result);
        };
    });
}
