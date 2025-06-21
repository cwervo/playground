document.addEventListener('DOMContentLoaded', () => {
  const exifDataContainer = document.getElementById('exif-data-container');
  const archiveBtn = document.getElementById('archiveBtn');
  const archivedItemsContainer = document.getElementById('archived-items-container');
  const archivedCountSpan = document.getElementById('archived-count');
  const statusMessageContainer = document.getElementById('status-message-container');
  let statusMessageTimeout = null;

  let currentExifData = null;
  let currentImageUrl = null;
  let currentPageUrl = null;

  exifDataContainer.innerHTML = '<p style="text-align:center; color:#606770; padding:10px;">Checking current Flickr page for EXIF data...</p>';

  function showStatusMessage(message, type = 'success') {
    if (statusMessageTimeout) {
      clearTimeout(statusMessageTimeout);
    }
    statusMessageContainer.innerHTML = '';
    const p = document.createElement('p');
    p.textContent = message;
    p.className = `status-message status-${type}`;
    statusMessageContainer.appendChild(p);

    statusMessageTimeout = setTimeout(() => {
      if (statusMessageContainer.contains(p)) {
        statusMessageContainer.removeChild(p);
      }
      statusMessageTimeout = null;
    }, 4000);
  }

  function triggerDownload(filename, content, mimeType) {
    const a = document.createElement('a');
    a.href = `data:${mimeType};charset=utf-8,${encodeURIComponent(content)}`;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    showStatusMessage(`Export of ${filename} initiated.`, 'success');
  }

  function displayExifData(data) {
    exifDataContainer.innerHTML = '';
    const ul = document.createElement('ul');
    ul.style.listStyleType = 'none'; // Ensure no bullets
    ul.style.paddingLeft = '0'; // Remove default padding
    for (const key in data) {
      if (Object.prototype.hasOwnProperty.call(data, key)) {
        const li = document.createElement('li');
        li.style.padding = '3px 0'; // Small padding for items
        li.textContent = `${key}: ${data[key]}`;
        ul.appendChild(li);
      }
    }
    exifDataContainer.appendChild(ul);
  }

  function displayError(message, container = exifDataContainer) {
    if (container) {
      container.innerHTML = '';
      const p = document.createElement('p');
      p.textContent = `Error: ${message}`;
      p.style.color = '#721c24';
      p.style.fontWeight = 'bold';
      p.style.padding = '10px';
      p.style.textAlign = 'center';
      container.appendChild(p);
    }
    showStatusMessage(message, 'error');
  }

  function exportItemAsXMP(item) {
    let xmpContent = `<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Flickr EXIF Extension v0.1">
  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
    <rdf:Description rdf:about=""
        xmlns:exif="http://ns.adobe.com/exif/1.0/"
        xmlns:tiff="http://ns.adobe.com/tiff/1.0/"
        xmlns:dc="http://purl.org/dc/elements/1.1/"
        xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/">
`;
    const addTag = (namespace, tagName, value) => {
      if (value !== undefined && value !== null && String(value).trim() !== '') {
        return `      <${namespace}:${tagName}>${String(value).trim().replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')}</${namespace}:${tagName}>
`;
      }
      return '';
    };
    const addDcCreator = (value) => {
      if (value !== undefined && value !== null && String(value).trim() !== '') {
          return `      <dc:creator><rdf:Seq><rdf:li>${String(value).trim().replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')}</rdf:li></rdf:Seq></dc:creator>
`;
      }
      return '';
    };
    const addIso = (value) => {
       if (value !== undefined && value !== null && String(value).trim() !== '') {
          return `      <exif:ISOSpeedRatings><rdf:Seq><rdf:li>${String(value).trim()}</rdf:li></rdf:Seq></exif:ISOSpeedRatings>
`;
      }
      return '';
    };

    xmpContent += addTag('tiff', 'Make', item.exifData.Make);
    xmpContent += addTag('tiff', 'Model', item.exifData.Model);
    let fNum = item.exifData.FNumber;
    if (fNum && !String(fNum).startsWith('f/')) fNum = String(fNum);
    xmpContent += addTag('exif', 'FNumber', fNum);
    xmpContent += addTag('exif', 'ExposureTime', item.exifData.ExposureTime);
    xmpContent += addIso(item.exifData.ISOSpeedRatings);
    let focal = item.exifData.FocalLength;
    if (focal && String(focal).includes('mm')) focal = String(focal).replace(/\s*mm/i,'');
    xmpContent += addTag('exif', 'FocalLength', focal);
    let dto = item.exifData.DateTimeOriginal;
    if (dto && dto.length === 19 && dto[4] === ':' && dto[7] === ':') {
      dto = `${dto.substring(0,4)}-${dto.substring(5,7)}-${dto.substring(8,10)}T${dto.substring(11,13)}:${dto.substring(14,16)}:${dto.substring(17,19)}`;
    }
    xmpContent += addTag('exif', 'DateTimeOriginal', dto);
    xmpContent += addTag('dc', 'source', item.pageUrl);
    xmpContent += addDcCreator(item.exifData.Artist || item.exifData.XPAuthor);

xmpContent += `    </rdf:Description>
  </rdf:RDF>
</x:xmpmeta>`;

    let baseFilename = 'photo_metadata';
    if (item.imageUrl) {
      const namePart = item.imageUrl.substring(item.imageUrl.lastIndexOf('/') + 1).split('?')[0];
      const dotIndex = namePart.lastIndexOf('.');
      if (dotIndex > 0) {
        baseFilename = namePart.substring(0, dotIndex);
      } else if (namePart) {
        baseFilename = namePart;
      }
    } else if (item.pageUrl) {
       const match = item.pageUrl.match(/photos\/[^\/]+\/([^\/]+)\/?/);
       if (match && match[1] && !/^\d+$/.test(match[1])) {
          baseFilename = match[1];
       } else if (match && match[1]) {
          baseFilename = `flickr_${match[1]}`;
       }
    }
    triggerDownload(`${baseFilename}.xmp`, xmpContent, 'application/rdf+xml');
  }

  function loadAndDisplayArchivedItems() {
    archivedItemsContainer.innerHTML = '<p style="text-align:center; color:#606770; padding:10px;">Loading archived items...</p>';
    chrome.storage.local.get({ archivedPhotos: [] }, (result) => {
      if (chrome.runtime.lastError) {
        console.error("Storage get error:", chrome.runtime.lastError.message);
        showStatusMessage(`Error loading archived items: ${chrome.runtime.lastError.message}`, 'error');
        archivedItemsContainer.innerHTML = '<p style="text-align:center; color:red;">Error loading items.</p>';
        if (archivedCountSpan) archivedCountSpan.textContent = '(?)';
        return;
      }
      const archives = result.archivedPhotos;
      archivedItemsContainer.innerHTML = '';

      if (archivedCountSpan) {
        archivedCountSpan.textContent = `(${archives.length})`;
      }

      if (archives.length === 0) {
        archivedItemsContainer.innerHTML = '<p style="text-align:center; color:#606770; padding:10px;">No items archived yet.</p>';
        return;
      }

      const ul = document.createElement('ul');
      archives.forEach((item, index) => {
        const li = document.createElement('li');

        const itemInfo = document.createElement('div');
        itemInfo.classList.add('item-info');

        const titleLink = document.createElement('a');
        titleLink.href = item.pageUrl;
        titleLink.textContent = item.imageUrl.substring(item.imageUrl.lastIndexOf('/') + 1).split('?')[0] || `Photo from ${item.pageUrl.substring(0,40)}...`;
        titleLink.target = '_blank';
        itemInfo.appendChild(titleLink);

        const dateSpan = document.createElement('span');
        dateSpan.classList.add('date');
        dateSpan.textContent = `Archived: ${new Date(item.archivedAt).toLocaleDateString()}`;
        itemInfo.appendChild(dateSpan);
        li.appendChild(itemInfo);

        const itemActions = document.createElement('div');
        itemActions.classList.add('item-actions');

        const xmpBtn = document.createElement('button');
        xmpBtn.textContent = 'XMP';
        xmpBtn.title = 'Export as XMP';
        xmpBtn.onclick = () => { exportItemAsXMP(item); };
        itemActions.appendChild(xmpBtn);

        const deleteBtn = document.createElement('button');
        deleteBtn.textContent = 'Delete';
        deleteBtn.title = 'Delete this item';
        deleteBtn.onclick = () => { deleteArchivedItem(index); };
        itemActions.appendChild(deleteBtn);
        li.appendChild(itemActions);
        ul.appendChild(li);
      });
      archivedItemsContainer.appendChild(ul);
    });
  }

  function deleteArchivedItem(indexToDelete) {
    chrome.storage.local.get({ archivedPhotos: [] }, (result) => {
      if (chrome.runtime.lastError) {
        showStatusMessage(`Error reading archives for deletion: ${chrome.runtime.lastError.message}`, 'error');
        return;
      }
      let archives = result.archivedPhotos;
      archives.splice(indexToDelete, 1);
      chrome.storage.local.set({ archivedPhotos: archives }, () => {
        if (chrome.runtime.lastError) {
          showStatusMessage(`Error deleting item: ${chrome.runtime.lastError.message}`, 'error');
        } else {
          showStatusMessage('Item deleted successfully.', 'success');
          loadAndDisplayArchivedItems();
        }
      });
    });
  }

  chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
    if (tabs.length === 0) {
      displayError("Could not find active tab. Open a Flickr photo page.");
      currentExifData = null; currentImageUrl = null; currentPageUrl = null;
      loadAndDisplayArchivedItems();
      return;
    }
    const activeTab = tabs[0];

    if (activeTab.url && activeTab.url.includes("flickr.com/photos/")) {
      chrome.tabs.sendMessage(
        activeTab.id,
        { action: "getExifData" },
        (response) => {
          if (chrome.runtime.lastError) {
            console.error("Error sending message to content script:", chrome.runtime.lastError.message);
            displayError(`Could not connect to the Flickr page. Ensure it's a photo page and try reloading. (${chrome.runtime.lastError.message})`);
            currentExifData = null; currentImageUrl = null; currentPageUrl = null;
          } else if (response) {
            if (response.status === "success") {
              displayExifData(response.data);
              currentExifData = response.data;
              currentImageUrl = response.imageUrl;
              currentPageUrl = response.pageUrl;
              // showStatusMessage("EXIF data loaded successfully from page.", "success"); // Optional success message
            } else {
              displayError(response.message || "Failed to get EXIF data from page.");
              currentExifData = null; currentImageUrl = null; currentPageUrl = null;
            }
          } else {
            displayError("No response from page. It might not be a compatible Flickr photo page or the extension needs an update.");
            currentExifData = null; currentImageUrl = null; currentPageUrl = null;
          }
          loadAndDisplayArchivedItems();
        }
      );
    } else {
      displayError("This extension works on Flickr photo pages. (e.g. flickr.com/photos/user/photoid)");
      currentExifData = null; currentImageUrl = null; currentPageUrl = null;
      loadAndDisplayArchivedItems();
    }
  });

  if (archiveBtn) {
    archiveBtn.addEventListener('click', () => {
      if (currentExifData && currentImageUrl && currentPageUrl) {
        const newArchiveItem = {
          pageUrl: currentPageUrl,
          imageUrl: currentImageUrl,
          exifData: currentExifData,
          archivedAt: new Date().toISOString()
        };
        chrome.storage.local.get({ archivedPhotos: [] }, (result) => {
          if (chrome.runtime.lastError) {
            showStatusMessage(`Error reading archives: ${chrome.runtime.lastError.message}`, 'error');
            return;
          }
          const archives = result.archivedPhotos;
          archives.push(newArchiveItem);
          chrome.storage.local.set({ archivedPhotos: archives }, () => {
            if (chrome.runtime.lastError) {
              showStatusMessage(`Archive failed: ${chrome.runtime.lastError.message}`, 'error');
            } else {
              showStatusMessage('Photo data archived successfully!', 'success');
              loadAndDisplayArchivedItems();
            }
          });
        });
      } else {
        showStatusMessage('No EXIF data available to archive. Ensure data is loaded from a Flickr page.', 'error');
      }
    });
  }

  document.getElementById('exportAllJsonBtn').addEventListener('click', () => {
    chrome.storage.local.get({ archivedPhotos: [] }, (result) => {
      if (chrome.runtime.lastError) {
        showStatusMessage(`Error reading archives for JSON export: ${chrome.runtime.lastError.message}`, 'error');
        return;
      }
      const archives = result.archivedPhotos;
      if (archives.length === 0) {
        showStatusMessage("No archived items to export.", "error");
        return;
      }
      const jsonString = JSON.stringify(archives, null, 2);
      triggerDownload('flickr_archives_all.json', jsonString, 'application/json');
    });
  });

  document.getElementById('exportAllCsvBtn').addEventListener('click', () => {
    chrome.storage.local.get({ archivedPhotos: [] }, (result) => {
      if (chrome.runtime.lastError) {
        showStatusMessage(`Error reading archives for CSV export: ${chrome.runtime.lastError.message}`, 'error');
        return;
      }
      const archives = result.archivedPhotos;
      if (archives.length === 0) {
        showStatusMessage("No archived items to export.", "error");
        return;
      }
      const headers = ['PageURL', 'ImageURL', 'ArchivedAt', 'Make', 'Model', 'FNumber', 'ExposureTime', 'ISOSpeedRatings', 'FocalLength', 'DateTimeOriginal', 'Artist'];
      let csvContent = headers.join(',') + '\n';

      archives.forEach(item => {
        const row = [
          item.pageUrl || '',
          item.imageUrl || '',
          item.archivedAt || '',
          item.exifData.Make || '',
          item.exifData.Model || '',
          item.exifData.FNumber || '',
          item.exifData.ExposureTime || '',
          item.exifData.ISOSpeedRatings || '',
          (item.exifData.FocalLength || '').replace(/\s*mm/i,''),
          item.exifData.DateTimeOriginal || '',
          item.exifData.Artist || item.exifData.XPAuthor || ''
        ];
        csvContent += row.map(val => `"${String(val).replace(/"/g, '""')}"`).join(',') + '\n';
      });
      triggerDownload('flickr_archives_all.csv', csvContent, 'text/csv');
    });
  });

});
