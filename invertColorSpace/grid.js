// grid.js
// Grid rendering logic for color space inversion comparison

// Color pairs
const colorPairs = [
  {
    fg: "green",
    bg: "red",
    fgHex: "#22c55e",
    bgHex: "#ef4444",
    label: "Green on Red",
  },
  {
    fg: "yellow",
    bg: "navy",
    fgHex: "#eab308",
    bgHex: "#1e293b",
    label: "Gold on Navy",
  },
];

// Color spaces to compare
const colorSpaces = ["RGB", "HSL", "LAB"];

let reversed = false;

function renderColorWheel(fg, invFg) {
  // Simple SVG color wheel: left half original, right half inverted
  return `<svg width="32" height="32" viewBox="0 0 32 32" style="position:absolute;top:8px;left:8px;z-index:1;">
    <defs>
      <linearGradient id="grad" x1="0" y1="0" x2="32" y2="0" gradientUnits="userSpaceOnUse">
        <stop offset="0%" stop-color="${fg}" />
        <stop offset="50%" stop-color="${fg}" />
        <stop offset="50%" stop-color="${invFg}" />
        <stop offset="100%" stop-color="${invFg}" />
      </linearGradient>
    </defs>
    <circle cx="16" cy="16" r="14" fill="url(#grad)" stroke="#fff" stroke-width="2" />
  </svg>`;
}

function renderGrid() {
  const grid = document.getElementById("colorGrid");
  grid.innerHTML = "";
  // Header row
  const headerRow = document.createElement("div");
  headerRow.className = "contents";
  headerRow.innerHTML = `<div></div>${colorSpaces
    .map((space) => `<div class=\"font-bold text-center\">${space}</div>`)
    .join("")}`;
  grid.appendChild(headerRow);
  // For each color pair, render a row
  colorPairs.forEach((pair) => {
    // Label cell
    const labelCell = document.createElement("div");
    labelCell.className = "flex items-center justify-center font-semibold";
    labelCell.innerText = pair.label;
    grid.appendChild(labelCell);
    // For each color space, render cell
    colorSpaces.forEach((space) => {
      // Original
      const origFg = pair.fgHex;
      const origBg = pair.bgHex;
      // Inverted
      const invFg = invertColor(origFg, space);
      const invBg = invertColor(origBg, space);
      // If reversed, swap
      const fg = reversed ? invFg : origFg;
      const bg = reversed ? invBg : origBg;
      // Color wheel SVG
      const wheel = renderColorWheel(origFg, invFg);
      // Cell
      const cell = document.createElement("div");
      cell.className =
        "relative flex flex-col items-center justify-center p-4 rounded shadow";
      cell.style.background = bg;
      cell.innerHTML = `
        ${wheel}
        <div class=\"text-xs mb-2\">${space}</div>
        <span class=\"px-2 py-1 rounded text-lg font-bold\" style=\"background:${fg};color:${bg};margin-top:16px;\">A</span>
        <div class=\"text-xs mt-2\">FG: ${fg}<br>BG: ${bg}</div>
      `;
      grid.appendChild(cell);
    });
  });
}

document.getElementById("reverseBtn").onclick = function () {
  reversed = !reversed;
  renderGrid();
};

renderGrid();
