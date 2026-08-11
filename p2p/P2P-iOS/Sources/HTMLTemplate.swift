import Foundation
import UIKit

struct HTMLTemplate {

    static func generateHTML(for image: UIImage, texts: [RecognizedTextBlock], showText: Bool) -> String {
        var imageDataStr = ""
        if let jpegData = image.jpegData(compressionQuality: 0.9) {
            imageDataStr = "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
        }

        var textDivs = ""
        for (index, block) in texts.enumerated() {
            let left = block.boundingBox.minX * 100.0
            let width = block.boundingBox.width * 100.0
            let height = block.boundingBox.height * 100.0
            let top = (1.0 - block.boundingBox.maxY) * 100.0

            let displayStyle = showText ? "block" : "none"
            textDivs += """
            <div id="text-\(index)" class="text-block" style="left: \(left)%; top: \(top)%; width: \(width)%; height: \(height)%; display: \(displayStyle);">
                <div class="content" contenteditable="true">\(block.text.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;"))</div>
                <div class="resizer ne"></div>
                <div class="resizer nw"></div>
                <div class="resizer se"></div>
                <div class="resizer sw"></div>
            </div>
            """
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
            <style>
                body {
                    margin: 0;
                    padding: 0;
                    background-color: #222;
                    display: flex;
                    justify-content: center;
                    align-items: flex-start;
                    min-height: 100vh;
                    touch-action: none;
                }
                .container {
                    position: relative;
                    display: inline-block;
                    max-width: 100%;
                }
                .container img {
                    max-width: 100%;
                    height: auto;
                    display: block;
                }
                .text-block {
                    position: absolute;
                    box-sizing: border-box;
                    border: 1px dashed rgba(255, 255, 255, 0.6);
                    background-color: rgba(255, 255, 255, 0.15);
                    color: #fff;
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                    cursor: move;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                }
                .text-block .content {
                    width: 100%;
                    height: 100%;
                    outline: none;
                    overflow: hidden;
                    text-align: center;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    font-size: 14px;
                }
                .resizer {
                    width: 16px;
                    height: 16px;
                    background: #fff;
                    border: 1px solid #000;
                    position: absolute;
                }
                .resizer.nw { top: -8px; left: -8px; }
                .resizer.ne { top: -8px; right: -8px; }
                .resizer.sw { bottom: -8px; left: -8px; }
                .resizer.se { bottom: -8px; right: -8px; }
            </style>
        </head>
        <body>
            <div class="container" id="container">
                <img src="\(imageDataStr)" alt="Background Image" draggable="false" />
                \(textDivs)
            </div>

            <script>
                const container = document.getElementById('container');
                const textBlocks = document.querySelectorAll('.text-block');

                textBlocks.forEach(block => {
                    let isDragging = false;
                    let isResizing = false;
                    let currentResizer = null;
                    let startX, startY, startLeft, startTop, startWidth, startHeight;

                    function pointFromEvent(e) {
                        if (e.touches && e.touches.length > 0) {
                            return { x: e.touches[0].clientX, y: e.touches[0].clientY };
                        }
                        return { x: e.clientX, y: e.clientY };
                    }

                    function startInteraction(e) {
                        const target = e.target;
                        if (target.classList.contains('resizer')) {
                            isResizing = true;
                            currentResizer = target;
                        } else if (target.classList.contains('content') && target === document.activeElement) {
                            return;
                        } else {
                            isDragging = true;
                        }

                        const p = pointFromEvent(e);
                        startX = p.x;
                        startY = p.y;

                        const rect = block.getBoundingClientRect();
                        const containerRect = container.getBoundingClientRect();

                        startLeft = ((rect.left - containerRect.left) / containerRect.width) * 100;
                        startTop = ((rect.top - containerRect.top) / containerRect.height) * 100;
                        startWidth = (rect.width / containerRect.width) * 100;
                        startHeight = (rect.height / containerRect.height) * 100;

                        e.preventDefault();
                    }

                    function moveInteraction(e) {
                        if (!isDragging && !isResizing) return;

                        const p = pointFromEvent(e);
                        const containerRect = container.getBoundingClientRect();
                        const dx = (p.x - startX) / containerRect.width * 100;
                        const dy = (p.y - startY) / containerRect.height * 100;

                        if (isDragging) {
                            block.style.left = (startLeft + dx) + '%';
                            block.style.top = (startTop + dy) + '%';
                        } else if (isResizing) {
                            if (currentResizer.classList.contains('se')) {
                                block.style.width = (startWidth + dx) + '%';
                                block.style.height = (startHeight + dy) + '%';
                            } else if (currentResizer.classList.contains('sw')) {
                                block.style.width = (startWidth - dx) + '%';
                                block.style.height = (startHeight + dy) + '%';
                                block.style.left = (startLeft + dx) + '%';
                            } else if (currentResizer.classList.contains('ne')) {
                                block.style.width = (startWidth + dx) + '%';
                                block.style.height = (startHeight - dy) + '%';
                                block.style.top = (startTop + dy) + '%';
                            } else if (currentResizer.classList.contains('nw')) {
                                block.style.width = (startWidth - dx) + '%';
                                block.style.height = (startHeight - dy) + '%';
                                block.style.top = (startTop + dy) + '%';
                                block.style.left = (startLeft + dx) + '%';
                            }
                        }
                        e.preventDefault();
                    }

                    function endInteraction() {
                        isDragging = false;
                        isResizing = false;
                        currentResizer = null;
                    }

                    block.addEventListener('mousedown', startInteraction);
                    window.addEventListener('mousemove', moveInteraction);
                    window.addEventListener('mouseup', endInteraction);

                    block.addEventListener('touchstart', startInteraction, { passive: false });
                    window.addEventListener('touchmove', moveInteraction, { passive: false });
                    window.addEventListener('touchend', endInteraction);
                });

                window.toggleTextVisibility = function(show) {
                    const blocks = document.querySelectorAll('.text-block');
                    blocks.forEach(block => {
                        block.style.display = show ? 'block' : 'none';
                    });
                };
            </script>
        </body>
        </html>
        """
    }
}
