/**
 * @bitlathe {
 *   "name": "Strip ANSI Codes",
 *   "description": "Remove terminal colour and cursor escape sequences",
 *   "icon": "terminal",
 *   "keywords": ["ansi", "escape", "terminal", "colour", "color", "console"],
 *   "detect": "\\u001b\\["
 * }
 */
function main(input) {
    var before = input.text.length;
    input.text = input.text
        .replace(/\u001b\][^\u0007\u001b]*(?:\u0007|\u001b\\)/g, "")
        .replace(/\u001b\[[0-9;?]*[ -\/]*[@-~]/g, "")
        .replace(/\u001b[@-Z\\-_]/g, "");
    var removed = before - input.text.length;
    if (removed === 0) input.postInfo("No ANSI escape sequences found.");
}
