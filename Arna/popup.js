document.addEventListener('DOMContentLoaded', () => {
  const loginView = document.getElementById('login');
  const mainView = document.getElementById('main');
  const apiKeyInput = document.getElementById('apiKey');
  const loginBtn = document.getElementById('loginBtn');
  const logoutBtn = document.getElementById('logoutBtn');
  const tabsContainer = document.getElementById('tabs');
  const saveBtn = document.getElementById('saveBtn');

  // Check for stored API key
  chrome.storage.sync.get('arenaApiKey', ({ arenaApiKey }) => {
    if (arenaApiKey) {
      showMainView();
    } else {
      showLoginView();
    }
  });

  // Login
  loginBtn.addEventListener('click', () => {
    const apiKey = apiKeyInput.value;
    if (apiKey) {
      chrome.storage.sync.set({ arenaApiKey: apiKey }, () => {
        showMainView();
      });
    }
  });

  // Logout
  logoutBtn.addEventListener('click', () => {
    chrome.storage.sync.remove('arenaApiKey', () => {
      showLoginView();
    });
  });

  // Save selected tabs
  saveBtn.addEventListener('click', async () => {
    const selectedTabs = Array.from(tabsContainer.querySelectorAll('input:checked'))
      .map(input => ({
        url: input.dataset.url,
        title: input.dataset.title,
      }));

    if (selectedTabs.length === 0) {
      alert('Please select at least one tab to save.');
      return;
    }

    const { arenaApiKey } = await chrome.storage.sync.get('arenaApiKey');
    const channel = prompt('Enter the Are.na channel slug to save to:');

    if (!channel) return;

    for (const tab of selectedTabs) {
      try {
        await fetch(`https://api.are.na/v2/channels/${channel}/blocks`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${arenaApiKey}`,
          },
          body: JSON.stringify({
            source: tab.url,
            title: tab.title,
          }),
        });
      } catch (error) {
        console.error('Error saving to Are.na:', error);
        alert('An error occurred while saving to Are.na. Check the console for details.');
      }
    }

    alert('Selected tabs saved to Are.na!');
  });

  function showLoginView() {
    loginView.style.display = 'block';
    mainView.style.display = 'none';
  }

  function showMainView() {
    loginView.style.display = 'none';
    mainView.style.display = 'block';
    loadTabs();
  }

  function loadTabs() {
    chrome.tabs.query({}, (tabs) => {
      tabsContainer.innerHTML = '';
      for (const tab of tabs) {
        const tabEl = document.createElement('div');
        tabEl.className = 'tab';
        tabEl.innerHTML = `
          <input type="checkbox" data-url="${tab.url}" data-title="${tab.title}">
          <span>${tab.title}</span>
        `;
        tabsContainer.appendChild(tabEl);
      }
    });
  }
});
