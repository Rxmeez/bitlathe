/**
 * @bitlathe {
 *   "name": "camelCase to snake_case",
 *   "description": "Convert camelCase and PascalCase identifiers to snake_case",
 *   "icon": "textformat.abc",
 *   "keywords": ["camel", "snake", "case", "identifier", "rename"],
 *   "detect": "^[a-z]+(?:[A-Z][a-z0-9]*)+$"
 * }
 */
function main(input) {
    input.text = input.text.replace(/[A-Za-z_][A-Za-z0-9_]*/g, function (w) {
        return w.replace(/([A-Z]+)([A-Z][a-z])/g, "$1_$2").replace(/([a-z0-9])([A-Z])/g, "$1_$2").toLowerCase();
    });
}
