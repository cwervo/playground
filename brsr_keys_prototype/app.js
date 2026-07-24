// brsr://keys - Browser Keyboard Shortcut Prototype Core Logic

// ==========================================================================
// STATE MANAGEMENT & LOCAL STORAGE
// ==========================================================================

const DEFAULT_FAVORITES = [
  { key: '1', name: 'Google', url: 'https://google.com', favicon: 'G' },
  { key: '2', name: 'Wikipedia', url: 'https://wikipedia.org', favicon: 'W' },
  { key: '3', name: 'GitHub', url: 'https://github.com', favicon: 'Git' },
  { key: '4', name: 'Hacker News', url: 'https://news.ycombinator.com', favicon: 'HN' },
  { key: '5', name: 'Reddit', url: 'https://reddit.com', favicon: 'R' },
  { key: '6', name: 'CSS-Tricks', url: 'https://css-tricks.com', favicon: 'CS' },
  { key: '7', name: 'Medium', url: 'https://medium.com', favicon: 'M' },
  { key: '8', name: 'NYTimes', url: 'https://nytimes.com', favicon: 'NY' },
  { key: '9', name: 'Dev.to', url: 'https://dev.to', favicon: 'D' },
  { key: '0', name: 'History', url: 'brsr://history', favicon: 'H' }
];

let state = {
  tabs: [
    {
      id: generateId(),
      title: 'New Tab',
      url: 'brsr://newtab',
      history: ['brsr://newtab'],
      historyIndex: 0,
      scrollPos: 0,
      isSuspended: false
    }
  ],
  activeTabId: null,
  favorites: [...DEFAULT_FAVORITES],
  history: [
    { title: 'New Tab', url: 'brsr://newtab', timestamp: new Date().toISOString() }
  ],
  isDarkMode: false,
  tabViewActive: false,
  printModalActive: false,
  cheatsheetMinimized: false,
  copyWholePagePending: false,
  copyWholePageTimeout: null
};

// Set initial active tab
state.activeTabId = state.tabs[0].id;

// Load state from LocalStorage if available
function loadState() {
  const savedState = localStorage.getItem('brsr_keys_state');
  if (savedState) {
    try {
      const parsed = JSON.parse(savedState);
      // Validate saved structure
      if (parsed.tabs && parsed.tabs.length > 0) {
        state = parsed;
        // Make sure modals are closed on reload
        state.tabViewActive = false;
        state.printModalActive = false;
      }
    } catch (e) {
      console.error('Failed to load state from localStorage', e);
    }
  }
}

function saveState() {
  localStorage.setItem('brsr_keys_state', JSON.stringify(state));
}

function generateId() {
  return Math.random().toString(36).substring(2, 11);
}

// ==========================================================================
// MOCK PAGE DATABASE & CONTENT GENERATORS
// ==========================================================================

const MOCK_PAGES = {
  'brsr://newtab': {
    title: 'New Tab',
    generate: () => `
      <div class="mock-newtab">
        <div class="newtab-search">
          <h2>brsr://<span>keys</span></h2>
          <div class="newtab-search-bar">
            <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
            <input type="text" id="newtabSearchInput" placeholder="Search Google or type a URL..." autocomplete="off">
          </div>
        </div>

        <div class="newtab-favorites-grid">
          ${state.favorites.map(fav => `
            <div class="newtab-fav-card" data-url="${fav.url}">
              <div class="newtab-fav-icon">${fav.favicon}</div>
              <div class="newtab-fav-name">${fav.name}</div>
            </div>
          `).join('')}
        </div>

        <div class="newtab-guide-card">
          <h3>Keyboard Prototype Guide 🚀</h3>
          <p>This interactive browser mockup is designed around <strong>single-key keyboard shortcuts</strong>. To try them, make sure you click somewhere in this page view to remove focus from input fields.</p>
          <ol>
            <li>Press <strong>d</strong> to toggle between Light and Dark mode.</li>
            <li>Highlight any text in the Wikipedia page and tap <strong>c</strong> to copy it.</li>
            <li>Press <strong>1-9</strong> to switch to tabs 1-9, or <strong>0</strong> to switch to the last tab.</li>
            <li>Press <strong>w</strong> to close the current tab.</li>
            <li>Press <strong>Esc</strong> to toggle the Spaces Tab Overview grid.</li>
            <li>Tap <strong>Shift</strong> to scroll the page downwards exactly 1 pixel.</li>
          </ol>
        </div>
      </div>
    `
  },
  
  'brsr://history': {
    title: 'History',
    generate: () => {
      const items = state.history.map((item, idx) => {
        const time = new Date(item.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
        return `
          <div class="history-item">
            <span class="history-time">${time}</span>
            <div class="history-fav">${item.url.includes('brsr://') ? '★' : getDomainFaviconChar(item.url)}</div>
            <div class="history-title-url">
              <span class="history-title" data-url="${item.url}">${escapeHtml(item.title)}</span>
              <span class="history-url">${escapeHtml(item.url)}</span>
            </div>
            <button class="btn-delete-history-item" data-index="${idx}" title="Remove from History">&times;</button>
          </div>
        `;
      }).reverse().join('');

      return `
        <div class="mock-history">
          <div class="history-header">
            <h2>Browsing History</h2>
            <button class="btn-clear-history" id="btnClearHistory">Clear History</button>
          </div>
          <div class="history-timeline">
            ${items.length ? items : '<p style="text-align: center; color: var(--page-text-dim); padding: 40px;">No history recorded yet.</p>'}
          </div>
        </div>
      `;
    }
  }
};

// Fallback generator for unmocked custom URLs
function generateFallbackPage(url) {
  const isSearch = url.includes('google.com/search') || url.includes('q=');
  if (isSearch) {
    const params = new URLSearchParams(url.substring(url.indexOf('?')));
    const query = params.get('q') || '';
    return MOCK_PAGES['https://google.com'].generate(query);
  }

  const domain = getDomain(url);
  return `
    <div style="max-width: 600px; margin: 40px auto; padding: 24px; border: 1px solid var(--page-border); border-radius: 8px; background-color: var(--page-card-bg); text-align: center;">
      <h2 style="margin-bottom: 12px; font-family: 'Outfit', sans-serif;">Simulated Navigation</h2>
      <p style="color: var(--page-text-dim); margin-bottom: 20px; font-size: 0.9rem;">You navigated to: <code style="font-family: 'Fira Code', monospace; background-color: var(--page-border); padding: 2px 6px; border-radius: 4px; font-size: 0.8rem;">${escapeHtml(url)}</code></p>
      
      <div style="background-color: var(--page-bg); border: 1px dashed var(--page-border); border-radius: 6px; padding: 24px; text-align: left; margin-bottom: 24px;">
        <h4 style="margin-bottom: 8px;">${escapeHtml(domain)} Webpage Mock</h4>
        <p style="font-size: 0.85rem; line-height: 1.5;">This is a generic mock page for the domain <strong>${escapeHtml(domain)}</strong>. Real-world frame loads are blocked due to Security Sandbox policies, so we render clean interactive text elements instead!</p>
        <p style="font-size: 0.85rem; line-height: 1.5; margin-top: 10px;">Feel free to highlight this sentence and tap <strong>c</strong> to test copying text inside simulated pages, or add this page to your favorites bar by hitting <strong>f</strong>!</p>
      </div>

      <button id="btnFallbackHome" style="background-color: var(--page-accent); color: white; border: none; padding: 8px 16px; border-radius: 6px; cursor: pointer; font-size: 0.85rem; font-weight: 500;">
        Back to Home Portal
      </button>
    </div>
  `;
}

// ==========================================================================
// DOM HELPER FUNCTIONS
// ==========================================================================

function getDomain(url) {
  if (url.startsWith('brsr://')) return url;
  try {
    const parsed = new URL(url);
    return parsed.hostname;
  } catch (e) {
    return url;
  }
}

function getDomainFaviconChar(url) {
  const domain = getDomain(url);
  if (domain.startsWith('brsr://')) return '★';
  return domain.replace('www.', '').substring(0, 2).toUpperCase();
}

function escapeHtml(str) {
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

// ==========================================================================
// TOAST NOTIFICATIONS SYSTEM
// ==========================================================================

function showToast(message, type = 'success') {
  const container = document.getElementById('toastContainer');
  if (!container) return;

  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  
  let icon = '✓';
  if (type === 'action') icon = '⚡';
  if (type === 'error') icon = '⚠';
  
  toast.innerHTML = `<span>${icon}</span> ${message}`;
  container.appendChild(toast);

  // Remove from DOM after transition completes
  setTimeout(() => {
    toast.remove();
  }, 2500);
}

// ==========================================================================
// NAVIGATION CONTROLLER
// ==========================================================================

function navigateTo(url, saveHistory = true) {
  // Normalize URLs
  let normalizedUrl = url.trim();
  if (!normalizedUrl) return;

  if (!normalizedUrl.startsWith('brsr://') && !normalizedUrl.startsWith('http://') && !normalizedUrl.startsWith('https://')) {
    // Check if it looks like a domain name
    if (normalizedUrl.includes('.') && !normalizedUrl.includes(' ')) {
      normalizedUrl = 'https://' + normalizedUrl;
    } else {
      // Treat as search query
      normalizedUrl = `https://google.com?q=${encodeURIComponent(normalizedUrl)}`;
    }
  }

  const activeTab = getActiveTab();
  if (!activeTab) return;

  // Track tab history
  if (saveHistory) {
    // If we were navigating back and forth and then made a new navigation, truncate the future history
    if (activeTab.historyIndex < activeTab.history.length - 1) {
      activeTab.history = activeTab.history.slice(0, activeTab.historyIndex + 1);
    }
    activeTab.history.push(normalizedUrl);
    activeTab.historyIndex = activeTab.history.length - 1;
  }

  activeTab.url = normalizedUrl;
  
  // Set tab title based on URL
  let pageTitle = getDomain(normalizedUrl);
  if (MOCK_PAGES[normalizedUrl]) {
    pageTitle = MOCK_PAGES[normalizedUrl].title;
  } else if (normalizedUrl.includes('google.com/search') || normalizedUrl.includes('q=')) {
    const params = new URLSearchParams(normalizedUrl.substring(normalizedUrl.indexOf('?')));
    pageTitle = `${params.get('q') || ''} - Google Search`;
  }
  activeTab.title = pageTitle;

  // Add to global browsing history database
  state.history.push({
    title: pageTitle,
    url: normalizedUrl,
    timestamp: new Date().toISOString()
  });

  // Save layout position
  activeTab.scrollPos = 0;

  saveState();
  renderApp();
  
  // Flash address bar lock/refresh button
  const refreshBtn = document.getElementById('btnRefresh');
  if (refreshBtn) {
    refreshBtn.classList.add('spin');
    setTimeout(() => refreshBtn.classList.remove('spin'), 600);
  }
}

function getActiveTab() {
  return state.tabs.find(t => t.id === state.activeTabId);
}

function handleGoBack() {
  const activeTab = getActiveTab();
  if (activeTab && activeTab.historyIndex > 0) {
    activeTab.historyIndex--;
    activeTab.url = activeTab.history[activeTab.historyIndex];
    
    // Title lookup
    if (MOCK_PAGES[activeTab.url]) {
      activeTab.title = MOCK_PAGES[activeTab.url].title;
    } else {
      activeTab.title = getDomain(activeTab.url);
    }
    
    saveState();
    renderApp();
    showToast('Navigated Back', 'action');
  }
}

function handleGoForward() {
  const activeTab = getActiveTab();
  if (activeTab && activeTab.historyIndex < activeTab.history.length - 1) {
    activeTab.historyIndex++;
    activeTab.url = activeTab.history[activeTab.historyIndex];
    
    // Title lookup
    if (MOCK_PAGES[activeTab.url]) {
      activeTab.title = MOCK_PAGES[activeTab.url].title;
    } else {
      activeTab.title = getDomain(activeTab.url);
    }

    saveState();
    renderApp();
    showToast('Navigated Forward', 'action');
  }
}

// ==========================================================================
// KEYBOARD INTERCEPTOR & KEYDOWN ROUTER
// ==========================================================================

function isInputFieldActive() {
  const el = document.activeElement;
  if (!el) return false;
  
  const tag = el.tagName;
  const isContentEditable = el.hasAttribute('contenteditable') || el.contentEditable === 'true';
  const isInput = tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT';
  
  return isInput || isContentEditable;
}

function registerKeyboardEvents() {
  window.addEventListener('keydown', (e) => {
    // 1. Esc is a global precedence key
    if (e.key === 'Escape') {
      e.preventDefault();
      if (state.printModalActive) {
        closePrintDialog();
        showToast('Print canceled', 'action');
        if (document.activeElement) document.activeElement.blur();
      } else if (state.tabViewActive) {
        toggleTabView();
      } else {
        toggleTabView();
      }
      return;
    }

    // If Tab view is open, handle grid-specific keyboard navigation
    if (state.tabViewActive) {
      handleTabViewKeys(e);
      return;
    }

    // If Print Dialog is active, prevent shortcut leaks and handle Enter to print
    if (state.printModalActive) {
      if (e.key === 'Enter') {
        e.preventDefault();
        triggerPDFDownload();
      }
      return;
    }

    // Determine active input state
    const inputState = isInputFieldActive();
    const statusText = document.getElementById('shortcut-status-text');
    const indicator = document.querySelector('.status-indicator');
    const cheatsheet = document.getElementById('cheatsheet');

    if (inputState) {
      if (statusText) statusText.innerText = 'Shortcuts Paused (Typing)';
      if (indicator) {
        indicator.classList.remove('active');
        indicator.classList.add('typing');
      }
      if (cheatsheet) cheatsheet.classList.add('disabled');
      return;
    }

    // Shortcuts are active! Ensure indicators reflect this
    if (statusText) statusText.innerText = 'Shortcuts Active';
    if (indicator) {
      indicator.classList.add('active');
      indicator.classList.remove('typing');
    }
    if (cheatsheet) cheatsheet.classList.remove('disabled');

    // 2. Suspend mode wake-up key interceptor
    const activeTab = getActiveTab();
    if (activeTab && activeTab.isSuspended) {
      // Any key wakes up the tab
      e.preventDefault();
      unsuspendActiveTab();
      return;
    }

    // 3. Precise Scrolling (Shift = down 6px, Shift+Alt/Opt = up 6px)
    if (e.key === 'Shift') {
      e.preventDefault();
      const pageWrapper = document.getElementById('pageWrapper');
      if (pageWrapper) {
        const step = 6;
        if (e.altKey) {
          pageWrapper.scrollTop -= step;
        } else {
          pageWrapper.scrollTop += step;
        }
        if (activeTab) activeTab.scrollPos = pageWrapper.scrollTop;
      }
      return;
    }

    // Single key letters routing (case sensitive where needed)
    const rawKey = e.key;
    const key = rawKey.toLowerCase();

    // l or / - Focus Omnibar (Address Input)
    if (rawKey === 'l' || rawKey === '/') {
      e.preventDefault();
      const omnibar = document.getElementById('addressInput');
      if (omnibar) {
        omnibar.focus();
        omnibar.select();
        showToast('Omnibar Focused', 'action');
      }
      return;
    }

    // a - Switch to Left Tab (wrap around)
    if (rawKey === 'a') {
      e.preventDefault();
      switchToPrevTab();
      return;
    }

    // d - Switch to Right Tab (wrap around)
    if (rawKey === 'd') {
      e.preventDefault();
      switchToNextTab();
      return;
    }

    // D - Toggle Dark Mode (Shift+D)
    if (rawKey === 'D') {
      e.preventDefault();
      toggleDarkMode();
      return;
    }

    // n - Open New Tab
    if (rawKey === 'n') {
      e.preventDefault();
      createNewTab();
      return;
    }

    // s - Suspend current tab
    if (rawKey === 's') {
      e.preventDefault();
      suspendActiveTab();
      return;
    }

    // f - Favorite current site (Star icon toggle)
    if (rawKey === 'f') {
      e.preventDefault();
      toggleFavoriteCurrentSite();
      return;
    }

    // h - Access history
    if (rawKey === 'h') {
      e.preventDefault();
      if (activeTab && activeTab.url === 'brsr://history') {
        showToast('Shortcut disabled: Already in History', 'error');
      } else {
        navigateTo('brsr://history');
        showToast('Opened History Log', 'action');
      }
      return;
    }

    // c - Copy selected text (Standard selection check)
    if (rawKey === 'c') {
      // Allow Cmd+C or Ctrl+C to do standard copying
      if (e.metaKey || e.ctrlKey) return;
      
      e.preventDefault();
      copyHighlightedText();
      return;
    }

    // p - Print Page / Save as PDF Menu
    if (rawKey === 'p') {
      e.preventDefault();
      openPrintDialog();
      return;
    }

    // w - Close active Tab
    if (rawKey === 'w') {
      e.preventDefault();
      closeTab(state.activeTabId);
      return;
    }

    // Backspace / Delete - Close active Tab
    if (e.key === 'Backspace' || e.key === 'Delete') {
      e.preventDefault();
      closeTab(state.activeTabId);
      return;
    }

    // 1 -> 9 - Switch to Tab 1 -> 9 (1-indexed)
    if (e.key >= '1' && e.key <= '9') {
      e.preventDefault();
      const tabIndex = parseInt(e.key, 10) - 1;
      if (tabIndex < state.tabs.length) {
        switchTab(state.tabs[tabIndex].id);
      } else {
        showToast(`No tab open at index ${tabIndex + 1}`, 'error');
      }
      return;
    }

    // 0 - Switch to Last Tab
    if (e.key === '0') {
      e.preventDefault();
      if (state.tabs.length > 0) {
        const lastIndex = state.tabs.length - 1;
        switchTab(state.tabs[lastIndex].id);
      } else {
        showToast('No tabs are open', 'error');
      }
      return;
    }
  });

  // Track focus transitions to toggle shortcuts indicator
  document.addEventListener('focusin', () => {
    const inputState = isInputFieldActive();
    const statusText = document.getElementById('shortcut-status-text');
    const indicator = document.querySelector('.status-indicator');
    const cheatsheet = document.getElementById('cheatsheet');

    if (inputState) {
      if (statusText) statusText.innerText = 'Shortcuts Paused (Typing)';
      if (indicator) {
        indicator.classList.remove('active');
        indicator.classList.add('typing');
      }
      if (cheatsheet) cheatsheet.classList.add('disabled');
    }
  });

  document.addEventListener('focusout', () => {
    // Delay slightly to check if focus moved to another input
    setTimeout(() => {
      const inputState = isInputFieldActive();
      const statusText = document.getElementById('shortcut-status-text');
      const indicator = document.querySelector('.status-indicator');
      const cheatsheet = document.getElementById('cheatsheet');

      if (!inputState) {
        if (statusText) statusText.innerText = 'Shortcuts Active';
        if (indicator) {
          indicator.classList.add('active');
          indicator.classList.remove('typing');
        }
        if (cheatsheet) cheatsheet.classList.remove('disabled');
      }
    }, 50);
  });
}

// ==========================================================================
// SHORTCUT ACTION IMPLEMENTATIONS
// ==========================================================================

function toggleDarkMode() {
  state.isDarkMode = !state.isDarkMode;
  const browserWindow = document.getElementById('browserWindow');

  if (state.isDarkMode) {
    browserWindow.classList.add('browser-theme-dark');
    browserWindow.classList.remove('browser-theme-light');
    showToast('Dark Mode Enabled', 'action');
  } else {
    browserWindow.classList.add('browser-theme-light');
    browserWindow.classList.remove('browser-theme-dark');
    showToast('Light Mode Enabled', 'action');
  }
  
  saveState();
}

function toggleFavoriteCurrentSite() {
  const activeTab = getActiveTab();
  if (!activeTab) return;

  const currentUrl = activeTab.url;
  const currentTitle = activeTab.title;
  
  // Check if current page is already in favorites
  const existingIdx = state.favorites.findIndex(fav => fav.url === currentUrl);
  
  if (existingIdx !== -1) {
    // Remove from favorites
    const removedFav = state.favorites[existingIdx];
    // Keep slot open by mapping it back to a default empty indicator or clearing it
    state.favorites[existingIdx] = {
      key: removedFav.key,
      name: 'Empty Slot',
      url: 'brsr://newtab',
      favicon: '∅'
    };
    showToast(`Removed from Favorites`, 'action');
  } else {
    // Find first empty/unassigned favorite slot
    const freeSlotIdx = state.favorites.findIndex(fav => fav.url === 'brsr://newtab' || fav.name === 'Empty Slot');
    if (freeSlotIdx !== -1) {
      state.favorites[freeSlotIdx] = {
        key: state.favorites[freeSlotIdx].key,
        name: currentTitle.substring(0, 12),
        url: currentUrl,
        favicon: getDomainFaviconChar(currentUrl)
      };
      showToast(`Added to Favorites`, 'success');
    } else {
      // Overwrite the last favorite (0)
      const lastIdx = state.favorites.length - 1;
      state.favorites[lastIdx] = {
        key: state.favorites[lastIdx].key,
        name: currentTitle.substring(0, 12),
        url: currentUrl,
        favicon: getDomainFaviconChar(currentUrl)
      };
      showToast(`Favorites full. Overwrote last Favorite`, 'action');
    }
  }
  
  saveState();
  renderApp();
}

function copyHighlightedText() {
  const selection = window.getSelection().toString();
  if (selection && selection.trim()) {
    // Clear copy whole page pending
    state.copyWholePagePending = false;
    if (state.copyWholePageTimeout) {
      clearTimeout(state.copyWholePageTimeout);
      state.copyWholePageTimeout = null;
    }
    
    navigator.clipboard.writeText(selection)
      .then(() => {
        const trimmed = selection.length > 35 ? selection.substring(0, 35) + '...' : selection;
        showToast(`Copied text: "${trimmed}"`, 'success');
      })
      .catch(err => {
        showToast('Clipboard write failed', 'error');
        console.error(err);
      });
  } else {
    // No text selected
    if (state.copyWholePagePending) {
      // Copy entire page content
      const pageViewport = document.getElementById('pageViewport');
      const wholeText = pageViewport ? pageViewport.innerText : '';
      
      navigator.clipboard.writeText(wholeText)
        .then(() => {
          const size = (wholeText.length / 1024).toFixed(1) + 'kb';
          showToast(`Copied entire page content (${size}) to clipboard!`, 'success');
        })
        .catch(err => {
          showToast('Clipboard write failed', 'error');
          console.error(err);
        });
        
      state.copyWholePagePending = false;
      if (state.copyWholePageTimeout) {
        clearTimeout(state.copyWholePageTimeout);
        state.copyWholePageTimeout = null;
      }
    } else {
      // Set pending state
      state.copyWholePagePending = true;
      if (state.copyWholePageTimeout) clearTimeout(state.copyWholePageTimeout);
      
      state.copyWholePageTimeout = setTimeout(() => {
        state.copyWholePagePending = false;
        state.copyWholePageTimeout = null;
      }, 3000); // 3 seconds window to double-tap 'c'
      
      const pageViewport = document.getElementById('pageViewport');
      const textLength = pageViewport ? pageViewport.innerText.length : 0;
      const size = (textLength / 1024).toFixed(1) + 'kb';
      
      showToast(`Nothing is selected, press c again to copy the entire contents of this page (${size} of text)`, 'error');
    }
  }
}

// ==========================================================================
// PRINT DIALOG & PDF CONVERTER
// ==========================================================================

function openPrintDialog() {
  state.printModalActive = true;
  const modal = document.getElementById('printModalOverlay');
  const activeTab = getActiveTab();
  
  if (modal && activeTab) {
    modal.classList.add('active');
    
    // Pre-populate URL and titles
    document.getElementById('preview-url-text').innerText = activeTab.url;
    
    // Set default preview layout structure
    const layout = document.getElementById('pdfLayout').value;
    const previewPane = modal.querySelector('.print-preview-pane');
    previewPane.className = `print-preview-pane preview-${layout}`;
  }
}

function closePrintDialog() {
  state.printModalActive = false;
  const modal = document.getElementById('printModalOverlay');
  if (modal) {
    modal.classList.remove('active');
  }
}

function triggerPDFDownload() {
  const activeTab = getActiveTab();
  if (!activeTab) return;

  const layout = document.getElementById('pdfLayout').value;
  const paper = document.getElementById('pdfPaper').value;
  const margins = document.getElementById('pdfMargins').value;
  
  showToast('Generating PDF document...', 'action');
  
  // Simulate a neat document assembly loaders
  setTimeout(() => {
    closePrintDialog();
    
    // Formulate a beautiful mock text/html representation of the page
    const docName = `${activeTab.title.toLowerCase().replace(/[^a-z0-9]/g, '_')}_print.pdf`;
    
    showToast(`PDF Saved successfully: ${docName}`, 'success');
  }, 1200);
}

// ==========================================================================
// TAB CONTROLLERS
// ==========================================================================

function createNewTab(url = 'brsr://newtab') {
  const newTab = {
    id: generateId(),
    title: 'New Tab',
    url: url,
    history: [url],
    historyIndex: 0,
    scrollPos: 0,
    isSuspended: false
  };
  state.tabs.push(newTab);
  state.activeTabId = newTab.id;
  
  saveState();
  renderApp();
  showToast('New Tab Opened', 'success');
}

function closeTab(tabId) {
  const tabIndex = state.tabs.findIndex(t => t.id === tabId);
  if (tabIndex === -1) return;

  const closedTabTitle = state.tabs[tabIndex].title;
  
  state.tabs.splice(tabIndex, 1);

  // If no tabs left, create a fresh blank one
  if (state.tabs.length === 0) {
    state.tabs.push({
      id: generateId(),
      title: 'New Tab',
      url: 'brsr://newtab',
      history: ['brsr://newtab'],
      historyIndex: 0,
      scrollPos: 0,
      isSuspended: false
    });
    state.activeTabId = state.tabs[0].id;
  } else if (state.activeTabId === tabId) {
    // If the closed tab was active, shift focus to nearest remaining tab
    const nextActiveIdx = Math.max(0, tabIndex - 1);
    state.activeTabId = state.tabs[nextActiveIdx].id;
  }

  saveState();
  renderApp();
  
  // Refresh Spaces overlay if open
  if (state.tabViewActive) {
    renderTabViewGrid();
  }

  showToast(`Closed tab: ${closedTabTitle}`, 'action');
}

function switchTab(tabId) {
  const tab = state.tabs.find(t => t.id === tabId);
  if (tab) {
    state.activeTabId = tab.id;
    saveState();
    renderApp();
    showToast(`Switched to tab: ${tab.title}`, 'action');
  }
}

function switchToNextTab() {
  const activeTabIdx = state.tabs.findIndex(t => t.id === state.activeTabId);
  if (activeTabIdx !== -1 && state.tabs.length > 1) {
    const nextIdx = (activeTabIdx + 1) % state.tabs.length;
    switchTab(state.tabs[nextIdx].id);
  }
}

function switchToPrevTab() {
  const activeTabIdx = state.tabs.findIndex(t => t.id === state.activeTabId);
  if (activeTabIdx !== -1 && state.tabs.length > 1) {
    const prevIdx = (activeTabIdx - 1 + state.tabs.length) % state.tabs.length;
    switchTab(state.tabs[prevIdx].id);
  }
}

function suspendActiveTab() {
  const activeTab = getActiveTab();
  if (activeTab) {
    if (activeTab.url === 'brsr://newtab' || activeTab.url === 'brsr://history') {
      showToast('Cannot suspend browser utility pages', 'error');
      return;
    }
    activeTab.isSuspended = true;
    saveState();
    renderApp();
    showToast('Tab suspended to save memory', 'action');
  }
}

function unsuspendActiveTab() {
  const activeTab = getActiveTab();
  if (activeTab && activeTab.isSuspended) {
    activeTab.isSuspended = false;
    saveState();
    renderApp();
    showToast('Tab resumed', 'success');
  }
}

// ==========================================================================
// SPACES GRID TAB VIEW
// ==========================================================================

function toggleTabView() {
  state.tabViewActive = !state.tabViewActive;
  const overlay = document.getElementById('tabViewOverlay');
  
  if (state.tabViewActive) {
    overlay.classList.add('active');
    renderTabViewGrid();
    document.getElementById('tabViewSearch').focus();
    showToast('Spaces Tab View Active', 'action');
  } else {
    overlay.classList.remove('active');
    // Put focus back to the page container
    document.getElementById('pageWrapper').focus();
  }
}

function renderTabViewGrid(filterText = '') {
  const grid = document.getElementById('tabViewGrid');
  if (!grid) return;

  const normalizedFilter = filterText.toLowerCase().trim();
  const filteredTabs = state.tabs.filter(tab => 
    tab.title.toLowerCase().includes(normalizedFilter) || 
    tab.url.toLowerCase().includes(normalizedFilter)
  );

  grid.innerHTML = filteredTabs.map(tab => {
    const isActive = tab.id === state.activeTabId;
    const globalIdx = state.tabs.findIndex(t => t.id === tab.id);
    
    let badgeText = '';
    if (state.tabs.length > 1 && globalIdx === state.tabs.length - 1) {
      badgeText = '0';
    } else if (globalIdx < 9) {
      badgeText = (globalIdx + 1).toString();
    }
    const indexBadge = badgeText ? `<span class="tab-card-index-badge">${badgeText}</span>` : '';
    
    return `
      <div class="tab-card ${isActive ? 'active' : ''}" data-tab-id="${tab.id}">
        <div class="tab-card-header">
          ${indexBadge}
          <div class="tab-card-fav">${tab.url.includes('brsr://') ? '★' : getDomainFaviconChar(tab.url)}</div>
          <span class="tab-card-title">${escapeHtml(tab.title)}</span>
          <button class="tab-card-close-btn" data-tab-id="${tab.id}">&times;</button>
        </div>
        <div class="tab-card-preview">
          ${escapeHtml(tab.url)}
        </div>
        <div class="tab-card-url">${escapeHtml(tab.url)}</div>
      </div>
    `;
  }).join('');
}

function handleTabViewKeys(e) {
  const activeEl = document.activeElement;
  const isSearchActive = (activeEl && activeEl.id === 'tabViewSearch');
  
  const key = e.key;
  const keyLower = key.toLowerCase();
  
  // If we are typing in the search box, ignore letter navigation (WASD, hjkl, jklm)
  const isLetterKey = ['w', 'a', 's', 'd', 'h', 'j', 'k', 'l', 'm'].includes(keyLower);
  if (isSearchActive && isLetterKey) {
    // Let them type!
    return;
  }
  
  const cards = Array.from(document.querySelectorAll('.tab-card'));
  if (!cards.length) return;

  const activeCardIdx = cards.findIndex(c => c.classList.contains('active'));
  let nextIdx = activeCardIdx;

  // Calculate grid columns dynamically
  const grid = document.getElementById('tabViewGrid');
  let cols = 4; // fallback
  if (grid) {
    const gridComputed = window.getComputedStyle(grid);
    const colString = gridComputed.gridTemplateColumns;
    if (colString) {
      cols = colString.split(' ').length;
    }
  }

  // Determine navigation vector
  let step = 0;
  let isNavigating = false;

  // Tab navigation
  if (key === 'Tab') {
    e.preventDefault();
    isNavigating = true;
    step = e.shiftKey ? -1 : 1;
  }
  // Right / Left / Down / Up
  else if (key === 'ArrowRight' || keyLower === 'd' || keyLower === 'l' || keyLower === 'm') {
    e.preventDefault();
    isNavigating = true;
    step = 1;
  }
  else if (key === 'ArrowLeft' || keyLower === 'a' || keyLower === 'h') {
    e.preventDefault();
    isNavigating = true;
    step = -1;
  }
  else if (key === 'ArrowDown' || keyLower === 's' || keyLower === 'j') {
    e.preventDefault();
    isNavigating = true;
    step = cols;
  }
  else if (key === 'ArrowUp' || keyLower === 'w' || keyLower === 'k') {
    e.preventDefault();
    isNavigating = true;
    step = -cols;
  }
  else if (key === 'Enter') {
    e.preventDefault();
    if (activeCardIdx !== -1) {
      const tabId = cards[activeCardIdx].dataset.tabId;
      switchTab(tabId);
      toggleTabView();
    }
    return;
  }

  if (isNavigating) {
    if (activeCardIdx === -1) {
      nextIdx = 0;
    } else {
      nextIdx = activeCardIdx + step;
      // Wrap around logic
      while (nextIdx < 0) {
        nextIdx += cards.length;
      }
      nextIdx = nextIdx % cards.length;
    }

    cards.forEach(c => c.classList.remove('active'));
    cards[nextIdx].classList.add('active');
    
    // Sync active state
    const tabId = cards[nextIdx].dataset.tabId;
    state.activeTabId = tabId;
    saveState();

    // Focus the grid card wrapper itself if they navigate out of search
    if (isSearchActive) {
      document.getElementById('tabViewSearch').blur();
    }
    
    // Ensure scroll into view
    cards[nextIdx].scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  }
}

// ==========================================================================
// APP RENDER ENGINE
// ==========================================================================

function renderApp() {
  const activeTab = getActiveTab();
  if (!activeTab) return;

  // 1. Render Chrome Tabs
  renderChromeTabs();

  // 2. Render Chrome Address Bar
  const addressInput = document.getElementById('addressInput');
  if (addressInput && document.activeElement !== addressInput) {
    addressInput.value = activeTab.url;
  }

  // Back/Forward/Favorite Chrome button disabled rules
  const backBtn = document.getElementById('btnBack');
  if (backBtn) backBtn.disabled = activeTab.historyIndex === 0;

  const forwardBtn = document.getElementById('btnForward');
  if (forwardBtn) forwardBtn.disabled = activeTab.historyIndex === activeTab.history.length - 1;

  // Star Icon Favorited State
  const favBtn = document.getElementById('btnFavorite');
  if (favBtn) {
    const isFavorited = state.favorites.some(fav => fav.url === activeTab.url && fav.name !== 'Empty Slot');
    if (isFavorited) {
      favBtn.classList.add('favorited');
      favBtn.title = "Remove from Favorites (f)";
    } else {
      favBtn.classList.remove('favorited');
      favBtn.title = "Favorite this site (f)";
    }
  }

  // 3. Render Favorites Bar
  renderFavoritesBar();

  // 4. Render Active Viewport Content
  renderViewportContent();
}

function renderChromeTabs() {
  const container = document.getElementById('tabContainer');
  if (!container) return;

  container.innerHTML = state.tabs.map((tab, idx) => {
    const isActive = tab.id === state.activeTabId;
    const isBrsr = tab.url.startsWith('brsr://');
    
    let badgeText = '';
    if (state.tabs.length > 1 && idx === state.tabs.length - 1) {
      badgeText = '0';
    } else if (idx < 9) {
      badgeText = (idx + 1).toString();
    }
    const indexBadge = badgeText ? `<span class="tab-index-badge">${badgeText}</span>` : '';
    
    return `
      <div class="tab ${isActive ? 'active' : ''}" data-tab-id="${tab.id}">
        ${indexBadge}
        <span class="tab-favicon ${isBrsr ? 'custom-fav' : ''}">${isBrsr ? '★' : getDomainFaviconChar(tab.url)}</span>
        <span class="tab-title" title="${escapeHtml(tab.title)}">${escapeHtml(tab.title)}</span>
        <button class="tab-close-btn" data-tab-id="${tab.id}">&times;</button>
      </div>
    `;
  }).join('');
}

function renderFavoritesBar() {
  const container = document.getElementById('favoritesList');
  if (!container) return;

  container.innerHTML = state.favorites.map(fav => {
    const isEmpty = fav.name === 'Empty Slot';
    return `
      <a class="fav-item" data-url="${fav.url}" style="${isEmpty ? 'opacity: 0.5;' : ''}">
        <span>${escapeHtml(fav.name)}</span>
      </a>
    `;
  }).join('');
}

function renderViewportContent() {
  const activeTab = getActiveTab();
  if (!activeTab) return;

  const viewport = document.getElementById('pageViewport');
  if (!viewport) return;

  // Clear existing listeners or inputs to prevent leaks
  viewport.innerHTML = '';

  if (activeTab.isSuspended) {
    viewport.innerHTML = `
      <div class="tab-suspended-screen">
        <div class="suspended-card">
          <div class="suspended-icon-glow">
            <svg class="icon icon-zzz" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M2 22h20M9 13H5v-2l4-4H5m14 11h-4v-2l4-4h-4m2-7h-3V4l3-3h-3" />
            </svg>
          </div>
          <h3>Tab Suspended</h3>
          <p class="suspended-url">${escapeHtml(activeTab.url)}</p>
          <p class="suspended-desc">This page was unloaded from browser memory to conserve CPU and RAM.</p>
          <button class="resume-btn" id="btnResumeTab">Wake Up Page</button>
        </div>
      </div>
    `;
    
    document.getElementById('btnResumeTab').addEventListener('click', () => {
      unsuspendActiveTab();
    });
    
    return;
  }

  const url = activeTab.url;
  const wrapper = document.getElementById('pageWrapper');
  const isInternal = url.startsWith('brsr://');

  // Toggle iframe mode classes
  if (isInternal) {
    viewport.classList.remove('iframe-mode');
    if (wrapper) wrapper.classList.remove('iframe-mode');
  } else {
    viewport.classList.add('iframe-mode');
    if (wrapper) wrapper.classList.add('iframe-mode');
  }

  if (MOCK_PAGES[url]) {
    viewport.innerHTML = MOCK_PAGES[url].generate();
  } else {
    // Render iframe for external sites with active focus warning & extension tip
    viewport.innerHTML = `
      <div class="iframe-container">
        <div class="iframe-focus-hint">
          <span class="hint-shortcuts">⚠️ Shortcuts active unless focused inside page (click chrome to refocus).</span>
          <span class="hint-divider">|</span>
          <span class="hint-warning">ℹ️ Some sites block framing. Install a headers-stripping extension (e.g. "Ignore X-Frame-Options") to bypass.</span>
        </div>
        <iframe src="${escapeHtml(url)}" class="viewport-iframe"></iframe>
      </div>
    `;
  }

  // Scroll viewport container to tab-specific stored offset
  const pageWrapper = document.getElementById('pageWrapper');
  if (pageWrapper && isInternal) {
    pageWrapper.scrollTop = activeTab.scrollPos || 0;
  }
}

// ==========================================================================
// EVENT LISTENERS & IN-VIEWPORT CLICK INTERCEPTORS
// ==========================================================================

function registerGlobalListeners() {
  
  // 1. Chrome Tab Switches & Closes
  const tabContainer = document.getElementById('tabContainer');
  if (tabContainer) {
    tabContainer.addEventListener('click', (e) => {
      const closeBtn = e.target.closest('.tab-close-btn');
      if (closeBtn) {
        e.stopPropagation();
        closeTab(closeBtn.dataset.tabId);
        return;
      }
      
      const tab = e.target.closest('.tab');
      if (tab) {
        switchTab(tab.dataset.tabId);
      }
    });

    // Double-click empty tab bar to create tab
    tabContainer.addEventListener('dblclick', (e) => {
      if (e.target === tabContainer) {
        createNewTab();
      }
    });
  }

  // 2. Chrome Controls
  document.getElementById('btnNewTab').addEventListener('click', () => createNewTab());
  document.getElementById('btnBack').addEventListener('click', handleGoBack);
  document.getElementById('btnForward').addEventListener('click', handleGoForward);
  document.getElementById('btnRefresh').addEventListener('click', () => {
    navigateTo(getActiveTab().url, false);
    showToast('Page Refreshed', 'action');
  });

  // Favorite button
  document.getElementById('btnFavorite').addEventListener('click', toggleFavoriteCurrentSite);

  // Utility Actions on right
  document.getElementById('btnHistory').addEventListener('click', () => navigateTo('brsr://history'));
  document.getElementById('btnDarkMode').addEventListener('click', toggleDarkMode);
  document.getElementById('btnTabView').addEventListener('click', toggleTabView);

  // Address Bar inputs
  const addressInput = document.getElementById('addressInput');
  addressInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      navigateTo(addressInput.value);
      addressInput.blur();
      showToast('Navigating...', 'action');
    }
  });

  // Favorites Bar navigation links
  document.getElementById('favoritesList').addEventListener('click', (e) => {
    const item = e.target.closest('.fav-item');
    if (item) {
      navigateTo(item.dataset.url);
    }
  });

  // 3. In-Viewport Simulated Hyperlinks Interceptor
  const pageWrapper = document.getElementById('pageWrapper');
  if (pageWrapper) {
    pageWrapper.addEventListener('click', (e) => {
      // If the tab is suspended, click to wake it up
      const activeTab = getActiveTab();
      if (activeTab && activeTab.isSuspended) {
        e.preventDefault();
        unsuspendActiveTab();
        return;
      }

      // Find element with data-url attribute
      const link = e.target.closest('[data-url]');
      if (link) {
        e.preventDefault();
        navigateTo(link.dataset.url);
        return;
      }

      // Handle history page item deletions
      const deleteHistoryBtn = e.target.closest('.btn-delete-history-item');
      if (deleteHistoryBtn) {
        const index = parseInt(deleteHistoryBtn.dataset.index);
        state.history.splice(index, 1);
        saveState();
        renderViewportContent();
        showToast('Removed from History', 'action');
        return;
      }

      // Handle clearing history
      if (e.target.id === 'btnClearHistory') {
        state.history = [];
        saveState();
        renderViewportContent();
        showToast('All History Cleared', 'action');
        return;
      }

      // Handle custom google query search buttons
      if (e.target.id === 'btnGoogleSearch' || e.target.id === 'btnGoogleLucky') {
        const searchInput = document.getElementById('googleSearchInput');
        const q = searchInput ? searchInput.value : '';
        if (e.target.id === 'btnGoogleLucky' && !q) {
          navigateTo('https://wikipedia.org');
        } else {
          navigateTo(`https://google.com?q=${encodeURIComponent(q)}`);
        }
        return;
      }

      // Handle fallback go home button
      if (e.target.id === 'btnFallbackHome') {
        navigateTo('brsr://newtab');
        return;
      }
    });

    // In-viewport inputs listeners (Enter triggers search/navs)
    pageWrapper.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        if (e.target.id === 'newtabSearchInput') {
          navigateTo(e.target.value);
        } else if (e.target.id === 'googleSearchInput') {
          navigateTo(`https://google.com?q=${encodeURIComponent(e.target.value)}`);
        }
      }
    });
  }

  // 4. Tab View Overlay grid cards & buttons
  const tabViewGrid = document.getElementById('tabViewGrid');
  if (tabViewGrid) {
    tabViewGrid.addEventListener('click', (e) => {
      const closeBtn = e.target.closest('.tab-card-close-btn');
      if (closeBtn) {
        e.stopPropagation();
        closeTab(closeBtn.dataset.tabId);
        return;
      }

      const card = e.target.closest('.tab-card');
      if (card) {
        switchTab(card.dataset.tabId);
        toggleTabView();
      }
    });
  }

  // Tab View Add Tab Button
  document.getElementById('tabViewAddBtn').addEventListener('click', () => {
    createNewTab();
    toggleTabView();
  });

  // Tab View Search bar
  document.getElementById('tabViewSearch').addEventListener('input', (e) => {
    renderTabViewGrid(e.target.value);
  });

  // 5. Print Modal Dialog Settings Sync & Close Controls
  document.getElementById('btnPrintClose').addEventListener('click', closePrintDialog);
  document.getElementById('btnPrintCancel').addEventListener('click', closePrintDialog);
  document.getElementById('btnPrintSave').addEventListener('click', triggerPDFDownload);

  // Sync print modal layout selections with left preview size classes
  document.getElementById('pdfLayout').addEventListener('change', (e) => {
    const layout = e.target.value;
    const modal = document.getElementById('printModalOverlay');
    const previewPane = modal.querySelector('.print-preview-pane');
    previewPane.className = `print-preview-pane preview-${layout}`;
  });

  // 6. Floating Cheatsheet Minimizer Toggle
  const cheatsheet = document.getElementById('cheatsheet');
  const cheatsheetHeader = document.querySelector('.cheatsheet-header');
  if (cheatsheetHeader) {
    cheatsheetHeader.addEventListener('click', () => {
      state.cheatsheetMinimized = !state.cheatsheetMinimized;
      if (state.cheatsheetMinimized) {
        cheatsheet.classList.add('minimized');
      } else {
        cheatsheet.classList.remove('minimized');
      }
      saveState();
    });
  }

  // Handle Tab sync positions on window scroll
  if (pageWrapper) {
    pageWrapper.addEventListener('scroll', () => {
      const activeTab = getActiveTab();
      if (activeTab) {
        activeTab.scrollPos = pageWrapper.scrollTop;
      }
    });
  }
}

// ==========================================================================
// APP INITIALIZER
// ==========================================================================

function init() {
  loadState();
  registerKeyboardEvents();
  registerGlobalListeners();
  
  // Set cheatsheet minimize position
  const cheatsheet = document.getElementById('cheatsheet');
  if (state.cheatsheetMinimized && cheatsheet) {
    cheatsheet.classList.add('minimized');
  }

  // Setup default theme state
  const browserWindow = document.getElementById('browserWindow');
  if (state.isDarkMode && browserWindow) {
    browserWindow.classList.add('browser-theme-dark');
    browserWindow.classList.remove('browser-theme-light');
  }

  renderApp();
  
  // Auto-focus page content area on start so keyboard shortcuts work immediately!
  setTimeout(() => {
    const wrapper = document.getElementById('pageWrapper');
    if (wrapper) wrapper.focus();
  }, 100);
}

// Start application
window.addEventListener('DOMContentLoaded', init);
