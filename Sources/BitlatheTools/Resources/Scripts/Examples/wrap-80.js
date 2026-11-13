/**
 * @bitlathe {
 *   "name": "Wrap at 80 Columns",
 *   "description": "Hard-wrap long lines at 80 columns on word boundaries, keeping indentation",
 *   "icon": "text.alignleft",
 *   "keywords": ["wrap", "columns", "80", "line length", "reflow"]
 * }
 */
var WIDTH = 80;
function wrapLine(line) {
    if (line.length <= WIDTH) return line;
    var indent = line.match(/^\s*/)[0];
    var words = line.trim().split(/\s+/);
    var out = [], cur = indent;
    words.forEach(function (w) {
        if (cur.trim().length > 0 && cur.length + 1 + w.length > WIDTH) { out.push(cur); cur = indent + w; }
        else cur += (cur.trim().length > 0 ? " " : "") + w;
    });
    out.push(cur);
    return out.join("\n");
}
function main(input) {
    input.text = input.text.split("\n").map(wrapLine).join("\n");
}
