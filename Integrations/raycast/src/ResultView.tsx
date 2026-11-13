import { Action, ActionPanel, Detail, Clipboard, showHUD, showToast, Toast } from "@raycast/api";
import { usePromise } from "@raycast/utils";
import { runTool } from "./bl";

export default function ResultView({ toolId, toolName, input }: { toolId: string; toolName: string; input: string }) {
  const { data, error, isLoading } = usePromise(runTool, [toolId, input]);
  const text = data?.replace(/\n$/, "") ?? "";
  const markdown = error
    ? `# ${toolName} failed\n\n\`\`\`\n${error.message}\n\`\`\``
    : isLoading
      ? ""
      : "```\n" + text + "\n```";
  return (
    <Detail
      navigationTitle={toolName}
      isLoading={isLoading}
      markdown={markdown}
      actions={
        !error && !isLoading ? (
          <ActionPanel>
            <Action
              title="Copy Result"
              onAction={async () => {
                await Clipboard.copy(text);
                await showHUD("Copied result");
              }}
            />
            <Action
              title="Paste Result"
              shortcut={{ modifiers: ["cmd"], key: "return" }}
              onAction={async () => {
                await Clipboard.paste(text);
              }}
            />
            <Action.CopyToClipboard
              title="Copy Result (keep Window)"
              content={text}
              shortcut={{ modifiers: ["cmd", "shift"], key: "c" }}
            />
          </ActionPanel>
        ) : undefined
      }
    />
  );
}

export async function failToast(e: unknown) {
  await showToast({
    style: Toast.Style.Failure,
    title: "Bitlathe",
    message: e instanceof Error ? e.message : String(e),
  });
}
