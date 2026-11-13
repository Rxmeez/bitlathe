/**
 * @bitlathe {
 *   "name": "Count Words",
 *   "description": "Words, characters, lines, sentences and reading time",
 *   "icon": "textformat.123",
 *   "keywords": ["count", "words", "characters", "statistics", "reading time"]
 * }
 */
function main(input) {
    var t = input.text;
    var words = (t.match(/\S+/g) || []).length;
    var lines = t.length === 0 ? 0 : t.split("\n").length;
    var sentences = (t.match(/[^.!?]+[.!?]+/g) || []).length;
    var chars = Array.from(t).length;
    var noSpace = Array.from(t.replace(/\s/g, "")).length;
    var minutes = words / 230;
    var reading = minutes < 1 ? "under a minute" : Math.round(minutes) + " min";
    input.text = [
        "Words:          " + words,
        "Characters:     " + chars,
        "Without spaces: " + noSpace,
        "Lines:          " + lines,
        "Sentences:      " + sentences,
        "Reading time:   " + reading
    ].join("\n");
}
