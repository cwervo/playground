document.addEventListener('DOMContentLoaded', () => {
  const startButton = document.getElementById('start');
  const stopButton = document.getElementById('stop');
  const statusDiv = document.getElementById('status');
  const stepsDiv = document.getElementById('steps');

  chrome.runtime.sendMessage({ action: "get_status" }, (response) => {
    if (response.recording) {
      statusDiv.textContent = "Recording...";
      startButton.disabled = true;
      stopButton.disabled = false;
    } else {
      statusDiv.textContent = "Stopped.";
      startButton.disabled = false;
      stopButton.disabled = true;
      if (response.steps && response.steps.length > 0) {
        displaySteps(response.steps);
      }
    }
  });

  startButton.addEventListener('click', () => {
    chrome.runtime.sendMessage({ action: "start" }, (response) => {
      if (response.status === "recording") {
        statusDiv.textContent = "Recording...";
        stepsDiv.innerHTML = '';
        startButton.disabled = true;
        stopButton.disabled = false;
      }
    });
  });

  stopButton.addEventListener('click', () => {
    chrome.runtime.sendMessage({ action: "stop" }, (response) => {
      if (response.status === "stopped") {
        statusDiv.textContent = "Stopped.";
        startButton.disabled = false;
        stopButton.disabled = true;
        displaySteps(response.steps);
      }
    });
  });

  function displaySteps(steps) {
    stepsDiv.innerHTML = '';
    const ol = document.createElement('ol');
    steps.forEach((step, index) => {
      const li = document.createElement('li');
      if (step.type === 'click') {
        li.textContent = `Clicked on "${step.value}" (${step.selector})`;
      } else if (step.type === 'input') {
        li.textContent = `Entered "${step.value}" into ${step.selector}`;
      } else if (step.type === 'keypress') {
        li.textContent = `Typed "${step.value}" into ${step.selector}`;
      }
      ol.appendChild(li);
    });
    stepsDiv.appendChild(ol);
    const copyButton = document.createElement('button');
    copyButton.textContent = 'Copy to Clipboard';
    copyButton.addEventListener('click', () => {
        const textToCopy = Array.from(ol.children).map(li => li.textContent).join('\n');
        navigator.clipboard.writeText(textToCopy);
    });
    stepsDiv.appendChild(copyButton);
  }
});
