/**
 * @bitlathe {
 *   "name": "Extract Emails",
 *   "description": "Pull unique email addresses out of any text, one per line",
 *   "icon": "envelope",
 *   "keywords": ["email", "extract", "addresses", "mailto"]
 * }
 */
function main(input) {
    var found = input.text.match(/[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}/g) || [];
    var seen = {}, unique = [];
    found.forEach(function (e) { var k = e.toLowerCase(); if (!seen[k]) { seen[k] = true; unique.push(e); } });
    if (unique.length === 0) { input.postInfo("No email addresses found."); input.text = ""; return; }
    input.postInfo(unique.length + " unique address" + (unique.length === 1 ? "" : "es") + " (" + found.length + " total).");
    input.text = unique.join("\n");
}
