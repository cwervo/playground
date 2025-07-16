let recording = false;
let steps = [];

chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.action === "start") {
    recording = true;
    steps = [];
    sendResponse({ status: "recording" });
  } else if (request.action === "stop") {
    recording = false;
    sendResponse({ status: "stopped", steps: steps });
  } else if (request.action === "log" && recording) {
    processStep(request.data);
  } else if (request.action === "get_status") {
    sendResponse({ recording, steps: generateGuide(steps) });
  }
});

function processStep(data) {
    // We can do some processing here, for example, batching keypresses
    const lastStep = steps.length > 0 ? steps[steps.length - 1] : null;
    if (data.type === 'keypress' && lastStep && lastStep.type === 'input' && lastStep.selector === data.selector) {
        // This keypress is part of a previous input, so we can ignore it
        return;
    }
    if (data.type === 'keypress' && lastStep && lastStep.type === 'keypress' && lastStep.selector === data.selector) {
        lastStep.value += data.value;
    } else {
        steps.push(data);
    }
}

function generateGuide(steps) {
    // For now, we will just return the processed steps.
    // We could add more complex logic here to generate a more readable guide.
    return steps;
}
