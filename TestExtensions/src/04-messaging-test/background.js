chrome.runtime.onMessage.addListener(function(message) {
  console.log("Trident Messaging Test background received:", message);
});
