/**
 * @bitlathe {
 *   "name": "JSON to Markdown Table",
 *   "description": "Turn a JSON array of objects into a GitHub-flavoured Markdown table",
 *   "icon": "tablecells",
 *   "keywords": ["json", "markdown", "table", "gfm", "convert"],
 *   "detect": "^\\s*\\[\\s*\\{"
 * }
 */
function cell(v) {
    if (v === null || v === undefined) return "";
    var s = typeof v === "object" ? JSON.stringify(v) : String(v);
    return s.replace(/\|/g, "\\|").replace(/\r?\n/g, " ");
}
function main(input) {
    var rows;
    try { rows = JSON.parse(input.text); } catch (e) { input.postError("Not valid JSON: " + e.message); return; }
    if (!Array.isArray(rows) || rows.length === 0) { input.postError("Expected a non-empty JSON array of objects."); return; }
    var cols = [];
    rows.forEach(function (r) {
        if (r === null || typeof r !== "object" || Array.isArray(r)) return;
        Object.keys(r).forEach(function (k) { if (cols.indexOf(k) < 0) cols.push(k); });
    });
    if (cols.length === 0) { input.postError("The array contains no objects."); return; }
    var lines = ["| " + cols.map(cell).join(" | ") + " |", "| " + cols.map(function () { return "---"; }).join(" | ") + " |"];
    rows.forEach(function (r) {
        var o = (r !== null && typeof r === "object" && !Array.isArray(r)) ? r : {};
        lines.push("| " + cols.map(function (c) { return cell(o[c]); }).join(" | ") + " |");
    });
    input.text = lines.join("\n");
}
