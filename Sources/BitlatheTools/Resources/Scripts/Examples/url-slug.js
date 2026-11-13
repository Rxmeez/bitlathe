/**
 * @bitlathe {
 *   "name": "URL-Safe Slug",
 *   "description": "Turn text into a lowercase, hyphenated URL slug (one per line)",
 *   "icon": "link",
 *   "keywords": ["slug", "url", "kebab", "permalink"]
 * }
 */
function slugify(s) {
    return s.normalize("NFD").replace(/[̀-ͯ]/g, "")
        .toLowerCase().replace(/&/g, " and ").replace(/['’]/g, "")
        .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
}
function main(input) {
    input.text = input.text.split("\n").map(slugify).join("\n");
}
