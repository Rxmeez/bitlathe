// Converts `bl list --json` / `bl detect --json` (stdin) into Alfred script-filter JSON.
ObjC.import("Foundation");
function run(argv) {
  const mode = argv[0];
  const q = (argv[1] || "").toLowerCase();
  const data = $.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile;
  const raw = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding).js;
  const parsed = JSON.parse(raw);
  let items;
  if (mode === "detect") {
    items = parsed.results.map((r) => ({
      uid: r.id,
      title: r.name,
      subtitle: Math.round(r.confidence * 100) + "% - " + r.reason + " (run on clipboard)",
      arg: r.id,
      match: r.name + " " + r.id,
    }));
    if (items.length === 0) items = [{ title: "No matching tool for the clipboard", valid: false }];
  } else {
    items = parsed
      .filter((t) => !q || (t.id + " " + t.name + " " + t.summary + " " + t.category).toLowerCase().indexOf(q) !== -1)
      .map((t) => ({
        uid: t.id,
        title: t.name,
        subtitle: t.id + " - " + t.summary,
        arg: t.id,
        autocomplete: t.id,
        text: { copy: t.id },
      }));
    if (items.length === 0) items = [{ title: "No tools match \"" + q + "\"", valid: false }];
  }
  return JSON.stringify({ items: items });
}
