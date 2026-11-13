/**
 * @bitlathe {
 *   "name": "Reverse Lines",
 *   "description": "Reverse the order of lines",
 *   "icon": "arrow.up.and.down.text.horizontal",
 *   "keywords": ["reverse", "lines", "flip", "order"]
 * }
 */
function main(input) {
    input.text = input.text.split("\n").reverse().join("\n");
}
