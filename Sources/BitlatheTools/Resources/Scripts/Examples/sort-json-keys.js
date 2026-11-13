/**
 * @bitlathe {
 *   "name": "Sort JSON Keys",
 *   "description": "Recursively sort object keys alphabetically",
 *   "icon": "arrow.up.arrow.down",
 *   "keywords": ["json", "sort", "keys", "alphabetical"],
 *   "detect": "^\\s*[\\{\\[]"
 * }
 */
function sortValue(v) {
    if (Array.isArray(v)) return v.map(sortValue);
    if (v && typeof v === "object") {
        var out = {};
        Object.keys(v).sort(function (a, b) { return a < b ? -1 : a > b ? 1 : 0; }).forEach(function (k) { out[k] = sortValue(v[k]); });
        return out;
    }
    return v;
}
function main(input) {
    var parsed;
    try { parsed = JSON.parse(input.text); } catch (e) { input.postError("Not valid JSON: " + e.message); return; }
    input.text = JSON.stringify(sortValue(parsed), null, 2);
}
