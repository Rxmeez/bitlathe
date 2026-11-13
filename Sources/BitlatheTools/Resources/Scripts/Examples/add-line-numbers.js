/**
 * @bitlathe {
 *   "name": "Add Line Numbers",
 *   "description": "Prefix every line with its right-aligned line number",
 *   "icon": "list.number",
 *   "keywords": ["line", "numbers", "number", "prefix", "cat -n"]
 * }
 */
function main(input) {
    var lines = input.text.split("\n");
    var width = String(lines.length).length;
    input.text = lines.map(function (l, i) {
        var n = String(i + 1);
        while (n.length < width) n = " " + n;
        return n + "  " + l;
    }).join("\n");
}
