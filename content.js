document.addEventListener('click', (e) => {
  const target = e.target;
  const selector = getSelector(target);
  chrome.runtime.sendMessage({
    action: "log",
    data: {
      type: "click",
      selector: selector,
      value: target.innerText
    }
  });
}, true);

document.addEventListener('change', (e) => {
  const target = e.target;
  if (target.tagName.toLowerCase() === 'input' || target.tagName.toLowerCase() === 'textarea') {
    const selector = getSelector(target);
    chrome.runtime.sendMessage({
      action: "log",
      data: {
        type: "input",
        selector: selector,
        value: target.value
      }
    });
  }
}, true);

document.addEventListener('keydown', (e) => {
  // We only want to log key presses in input fields
  const target = e.target;
  if (target.tagName.toLowerCase() === 'input' || target.tagName.toLowerCase() === 'textarea') {
    // We can filter out non-character keys if we want
    if (e.key.length === 1) {
        const selector = getSelector(target);
        chrome.runtime.sendMessage({
            action: "log",
            data: {
            type: "keypress",
            selector: selector,
            value: e.key
            }
        });
    }
  }
}, true);

function getSelector(element) {
  if (element.id) {
    return `#${element.id}`;
  }
  if (element.className) {
    const classes = element.className.split(' ').filter(c => c).join('.');
    if(classes) {
      return `${element.tagName.toLowerCase()}.${classes}`;
    }
  }
  let path = [];
  while (element.parentElement) {
    let siblings = Array.from(element.parentElement.children);
    let index = siblings.indexOf(element) + 1;
    let tagName = element.tagName.toLowerCase();
    let nthChild = `:nth-child(${index})`;
    path.unshift(tagName + nthChild);
    element = element.parentElement;
  }
  return path.join(' > ');
}
