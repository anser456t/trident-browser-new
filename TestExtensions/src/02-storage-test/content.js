chrome.storage.local.get(["visitCount"]).then(function(result) {
  var count = (result.visitCount || 0) + 1;
  chrome.storage.local.set({ visitCount: count }).then(function() {
    console.log("Trident Storage Test: visit count is now " + count);
  });
});
