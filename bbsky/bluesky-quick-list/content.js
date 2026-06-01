
/**
 * Bluesky Quick List Adder
 * content.js
 * * This script injects an "Add to new list +" button into the user profile
 * dropdown menu on bsky.app. It streamlines the workflow of creating a new
 * list and adding a user to it.
 */

console.log("Bluesky Quick List Adder: Script Injected.");

// --- Core Functions ---

/**
 * Shows a temporary notification message at the top of the screen.
 * @param {string} message The message to display.
 * @param {boolean} isError True if the message is an error, false for success.
 */
function showNotification(message, isError = false) {
    const notification = document.createElement('div');
    notification.textContent = message;
    notification.style.position = 'fixed';
    notification.style.top = '20px';
    notification.style.left = '50%';
    notification.style.transform = 'translateX(-50%)';
    notification.style.padding = '12px 24px';
    notification.style.borderRadius = '8px';
    notification.style.color = 'white';
    notification.style.backgroundColor = isError ? '#d32f2f' : '#43a047';
    notification.style.zIndex = '9999';
    notification.style.boxShadow = '0 4px 12px rgba(0,0,0,0.2)';
    notification.style.opacity = '0';
    notification.style.transition = 'opacity 0.3s ease-in-out';
    
    document.body.appendChild(notification);
    
    // Fade in
    setTimeout(() => {
        notification.style.opacity = '1';
    }, 10);
    
    // Fade out and remove after 3 seconds
    setTimeout(() => {
        notification.style.opacity = '0';
        setTimeout(() => {
            notification.remove();
        }, 300);
    }, 3000);
}


/**
 * Retrieves session information (auth token, user DID) from localStorage.
 * @returns {object|null} An object with { accessJwt, did } or null if not found.
 */
function getSession() {
    try {
        const sessionData = localStorage.getItem('bsky-session');
        if (!sessionData) {
            console.error("Bluesky session data not found in localStorage.");
            return null;
        }
        const session = JSON.parse(sessionData);
        if (session.accessJwt && session.did) {
            return {
                accessJwt: session.accessJwt,
                did: session.did
            };
        }
    } catch (error) {
        console.error("Error parsing Bluesky session data:", error);
    }
    return null;
}

/**
 * Fetches the DID for a user from their handle.
 * @param {string} handle The user's handle (e.g., "jay.bsky.team").
 * @returns {Promise<string|null>} The user's DID or null on failure.
 */
async function getDidForHandle(handle) {
    try {
        const response = await fetch(`https://bsky.social/xrpc/com.atproto.identity.resolveHandle?handle=${handle}`);
        if (!response.ok) throw new Error(`API Error: ${response.statusText}`);
        const data = await response.json();
        return data.did;
    } catch (error) {
        console.error("Failed to resolve handle to DID:", error);
        showNotification("Error: Could not find user's DID.", true);
        return null;
    }
}

/**
 * The main workflow function that is triggered by the button click.
 */
async function addToListWorkflow() {
    console.log("Starting 'Add to New List' workflow...");

    // 1. Get the new list name from the user
    const listName = prompt("Enter the name for the new list:");
    if (!listName) {
        console.log("User cancelled list creation.");
        return;
    }

    // 2. Get session and profile info
    const session = getSession();
    if (!session) {
        showNotification("Error: Could not get login session.", true);
        return;
    }

    const pathParts = window.location.pathname.split('/');
    const targetHandle = pathParts[pathParts.length - 1];
    const targetDid = await getDidForHandle(targetHandle);
    if (!targetDid) return;

    const { accessJwt, did: currentUserDid } = session;

    try {
        // 3. API Call: Create the new list
        showNotification("Creating new list...");
        const createListResponse = await fetch('https://bsky.social/xrpc/com.atproto.repo.createRecord', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${accessJwt}`
            },
            body: JSON.stringify({
                repo: currentUserDid,
                collection: 'app.bsky.graph.list',
                record: {
                    name: listName,
                    purpose: 'app.bsky.graph.defs#modlist',
                    createdAt: new Date().toISOString(),
                    '$type': 'app.bsky.graph.list'
                }
            })
        });

        if (!createListResponse.ok) throw new Error(`List creation failed: ${createListResponse.statusText}`);
        const listData = await createListResponse.json();
        const listUri = listData.uri;
        console.log("Successfully created list with URI:", listUri);

        // 4. API Call: Add the user to the newly created list
        showNotification(`Adding ${targetHandle} to "${listName}"...`);
        const addMemberResponse = await fetch('https://bsky.social/xrpc/com.atproto.repo.createRecord', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${accessJwt}`
            },
            body: JSON.stringify({
                repo: currentUserDid,
                collection: 'app.bsky.graph.listitem',
                record: {
                    subject: targetDid,
                    list: listUri,
                    createdAt: new Date().toISOString(),
                    '$type': 'app.bsky.graph.listitem'
                }
            })
        });

        if (!addMemberResponse.ok) throw new Error(`Adding user failed: ${addMemberResponse.statusText}`);
        console.log("Successfully added user to the list.");
        showNotification("Success! User added to new list.", false);

    } catch (error) {
        console.error("Workflow failed:", error);
        showNotification(`Error: ${error.message}`, true);
    }
}


// --- DOM Manipulation ---

/**
 * Creates and injects the custom button into the dropdown menu.
 * @param {HTMLElement} menu The dropdown menu element.
 */
function injectButton(menu) {
    const buttonId = 'new-list-button';
    // Avoid adding the button if it already exists
    if (menu.querySelector(`#${buttonId}`)) {
        return;
    }
    
    // Find the existing "Add to lists" button to insert our button before or after it.
    // We clone it to easily replicate its style.
    const existingButtons = menu.querySelectorAll('div[role="menuitem"]');
    if (existingButtons.length === 0) return;

    const referenceButton = existingButtons[existingButtons.length - 1]; // Insert after the last item
    const newButton = referenceButton.cloneNode(true);
    
    // Clear any existing content and set our own
    newButton.id = buttonId;
    newButton.innerHTML = ''; // Clear cloned content
    const buttonText = document.createElement('span');
    buttonText.textContent = "Add to new list +";
    newButton.appendChild(buttonText);
    
    // Add our click listener
    newButton.addEventListener('click', (e) => {
        e.stopPropagation(); // Prevent menu from closing immediately
        addToListWorkflow();
    });
    
    // Insert into the menu
    referenceButton.parentNode.appendChild(newButton);
    console.log("Custom button injected.");
}

// --- Entry Point ---

// Bluesky loads content dynamically, so we need to wait for the menu to appear.
// A MutationObserver is the most reliable way to do this.
const observer = new MutationObserver((mutationsList, observer) => {
    for (const mutation of mutationsList) {
        if (mutation.type === 'childList') {
            mutation.addedNodes.forEach(node => {
                // Check if the added node is the menu container we're looking for
                if (node.nodeType === 1 && node.getAttribute('role') === 'menu') {
                    console.log("Detected menu added to DOM.");
                    injectButton(node);
                }
            });
        }
    }
});

// Start observing the entire document body for additions.
observer.observe(document.body, { childList: true, subtree: true });
