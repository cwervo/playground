# brsr://keys — Keyboard Shortcut Browser Prototype

> [!WARNING]
> **Experimental / Beta Software**
> This project is a prototype mockup under active development. Features are experimental, subject to change at any time, and might contain unfinished UX components.

`brsr://keys` is an interactive simulation of a single-key keyboard shortcut-driven browser. The primary design goal is to enable rapid, mouse-free web navigation using simple, single-character shortcuts that automatically pause when typing inside input fields and resume when navigating.

---

## 🚀 How to Run Locally

This prototype is built using **Vite**, vanilla CSS, and vanilla JavaScript. 

### Prerequisites
Make sure you have [Node.js](https://nodejs.org/) installed.

### Installation & Launch
1. Navigate to the prototype directory:
   ```bash
   cd brsr_keys_prototype
   ```
2. Install dependencies:
   ```bash
   npm install
   ```
3. Start the local development server:
   ```bash
   npm run dev
   ```
4. Open the local address shown in your terminal (usually `http://localhost:5173`) in any modern web browser.

---

## ⌨️ Keyboard Shortcuts

Shortcuts only trigger when you are **not** actively typing inside input fields or textareas.

| Key | Action | Details |
| :--- | :--- | :--- |
| **`1` – `9`** | Switch Tab | Instantly focus tab index `1` to `9` (1-indexed). |
| **`0`** | Switch to Last Tab | Instantly focus the last open tab in the browser. |
| **`a`** | Prev Tab | Switches to the left tab (wraps around). |
| **`d`** | Next Tab | Switches to the right tab (wraps around). |
| **`D` (Shift+D)** | Toggle Theme | Toggles the browser color theme (forces color inversion filter on the viewport iframe). |
| **`l` / `/`** | Focus Omnibar | Focuses the address input bar for quick typing. |
| **`f`** | Toggle Favorite | Adds or removes the current site from the Favorites bar. |
| **`h`** | Browse History | Navigates to `brsr://history` (disabled if already there). |
| **`c`** | Copy Text | Copies highlighted text (standard `⌘+C`/`Ctrl+C` still works). Tap twice to copy the entire page content. |
| **`p`** | Save as PDF | Opens the print preview layout configured as "Save Page as PDF". |
| **`w` / `Backspace` / `Delete`** | Close Tab | Closes the current active tab. |
| **`Shift`** | Precise Scroll Down | Scrolls the active page viewport downwards exactly `6px`. |
| **`Shift + Alt/Opt`** | Precise Scroll Up | Scrolls the active page viewport upwards exactly `6px`. |

---

## 🎨 Interactive Mock Pages Included
Inside the simulator, you can navigate using the address bar or links to:
- `brsr://newtab`: The startup hub with your bookmarks grid and quick guide.
- `brsr://history`: An interactive timeline of your browser history with deletion options.
- `https://google.com`: An emulated search engine with mock search results.
- `https://wikipedia.org`: A simulated Wikipedia article on keyboard shortcuts, perfect for testing highlighted text copy routines.

---

## License
Licensed under the Apache License, Version 2.0. See the `LICENSE` file for details.
