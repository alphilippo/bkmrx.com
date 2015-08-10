chrome.runtime.onMessage.addListener(function(a, b, c) {
    var d = window.getSelection().toString();
    c({
        selection: d
    })
});