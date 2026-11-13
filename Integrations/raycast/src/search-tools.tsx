import { Action, ActionPanel, Clipboard, Icon, List, closeMainWindow, showHUD } from "@raycast/api";
import { usePromise } from "@raycast/utils";
import { listTools, openURL, runTool, toolURL } from "./bl";
import ResultView, { failToast } from "./ResultView";

export default function SearchTools() {
  const { data, isLoading, error } = usePromise(async () => (await listTools()).filter((t) => t.kind !== "pipeline"));
  const byCategory = new Map<string, NonNullable<typeof data>>();
  for (const t of data ?? []) byCategory.set(t.category, [...(byCategory.get(t.category) ?? []), t]);

  return (
    <List isLoading={isLoading} searchBarPlaceholder="Search Bitlathe tools">
      {error ? <List.EmptyView icon={Icon.ExclamationMark} title="Cannot run bl" description={error.message} /> : null}
      {[...byCategory.entries()].map(([category, tools]) => (
        <List.Section key={category} title={category}>
          {tools.map((t) => (
            <List.Item
              key={t.id}
              title={t.name}
              subtitle={t.summary}
              keywords={[t.id, t.category]}
              accessories={[{ text: t.id }]}
              actions={
                <ActionPanel>
                  <Action
                    title="Open in Bitlathe"
                    icon={Icon.AppWindow}
                    onAction={async () => {
                      try {
                        const clip = (await Clipboard.readText()) ?? "";
                        await openURL(toolURL(t.id, clip, "open"));
                        await closeMainWindow();
                      } catch (e) {
                        await failToast(e);
                      }
                    }}
                  />
                  <Action.Push
                    title="Run on Clipboard"
                    icon={Icon.Play}
                    shortcut={{ modifiers: ["cmd"], key: "return" }}
                    target={<RunOnClipboard id={t.id} name={t.name} />}
                  />
                  <Action
                    title="Run on Clipboard and Copy"
                    icon={Icon.Clipboard}
                    shortcut={{ modifiers: ["cmd", "shift"], key: "return" }}
                    onAction={async () => {
                      try {
                        const out = await runTool(t.id, (await Clipboard.readText()) ?? "");
                        await Clipboard.copy(out.replace(/\n$/, ""));
                        await showHUD(`${t.name}: copied result`);
                      } catch (e) {
                        await failToast(e);
                      }
                    }}
                  />
                  <Action.CopyToClipboard title="Copy Tool Id" content={t.id} />
                </ActionPanel>
              }
            />
          ))}
        </List.Section>
      ))}
    </List>
  );
}

function RunOnClipboard({ id, name }: { id: string; name: string }) {
  const { data } = usePromise(async () => (await Clipboard.readText()) ?? "");
  if (data === undefined) return <List isLoading />;
  return <ResultView toolId={id} toolName={name} input={data} />;
}
