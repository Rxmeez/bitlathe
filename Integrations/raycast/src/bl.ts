import { execFile, spawn } from "child_process";
import { existsSync } from "fs";
import { homedir } from "os";
import { getPreferenceValues } from "@raycast/api";

export interface BLTool {
  id: string;
  name: string;
  summary: string;
  category: string;
  kind: "native" | "script" | "pipeline";
}

export interface BLDetection {
  id: string;
  name: string;
  confidence: number;
  reason: string;
}

export function blPath(): string {
  const { blPath: configured } = getPreferenceValues<Preferences>();
  if (configured && configured.trim()) return configured.trim().replace(/^~/, homedir());
  const candidates = ["/usr/local/bin/bl", "/opt/homebrew/bin/bl", `${homedir()}/.local/bin/bl`];
  const found = candidates.find((p) => existsSync(p));
  if (!found) {
    throw new Error(
      "bl not found. Install it from Bitlathe > Settings > Integrations, or set the path in this extension's preferences.",
    );
  }
  return found;
}

/** Run `bl` with arguments and optional stdin. Rejects with bl's stderr on non-zero exit. */
export function runBL(args: string[], stdin = ""): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawn(blPath(), args);
    let out = "";
    let err = "";
    child.stdout.on("data", (d) => (out += d));
    child.stderr.on("data", (d) => (err += d));
    child.on("error", reject);
    child.on("close", (code) =>
      code === 0 ? resolve(out) : reject(new Error(err.trim() || `bl exited with code ${code}`)),
    );
    child.stdin.on("error", () => undefined);
    child.stdin.end(stdin);
  });
}

export async function listTools(): Promise<BLTool[]> {
  return JSON.parse(await runBL(["list", "--json"])) as BLTool[];
}

export async function detect(text: string): Promise<BLDetection[]> {
  const parsed = JSON.parse(await runBL(["detect", "--json"], text)) as { results: BLDetection[] };
  return parsed.results;
}

/** Run a tool, or a saved pipeline (ids of the form pipeline.<slug>), on the given text. */
export function runTool(id: string, text: string): Promise<string> {
  if (id.startsWith("pipeline.")) return runBL(["pipeline", id.slice("pipeline.".length)], text);
  return runBL([id], text);
}

export function toolURL(id: string, input: string, action: "open" | "copy" = "open"): string {
  return `bitlathe://tool/${encodeURIComponent(id)}?input=${encodeURIComponent(input)}&action=${action}`;
}

export function openURL(url: string): Promise<void> {
  return new Promise((resolve, reject) => execFile("/usr/bin/open", [url], (e) => (e ? reject(e) : resolve())));
}
