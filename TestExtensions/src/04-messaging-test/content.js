chrome.runtime.onMessage.addListener(function(message) {
  console.log("Trident Messaging Test content script received:", message);
});
