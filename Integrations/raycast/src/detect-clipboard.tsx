import { Action, ActionPanel, Clipboard, Icon, List } from "@raycast/api";
import { usePromise } from "@raycast/utils";
import { detect } from "./bl";
import ResultView from "./ResultView";

export default function DetectClipboard() {
  const { data, isLoading, error } = usePromise(async () => {
    const text = (await Clipboard.readText()) ?? "";
    return { text, results: text ? await detect(text) : [] };
  });
  return (
    <List isLoading={isLoading} searchBarPlaceholder="Tools that fit the clipboard">
      {error ? (
        <List.EmptyView icon={Icon.ExclamationMark} title="Cannot run bl" description={error.message} />
      ) : (
        <List.EmptyView
          icon={Icon.Clipboard}
          title="No matching tool"
          description="The clipboard is empty or nothing recognised it."
        />
      )}
      {(data?.results ?? []).map((r, i) => (
        <List.Item
          key={r.id}
          title={r.name}
          subtitle={r.reason}
          accessories={[{ text: `${Math.round(r.confidence * 100)}%` }, { text: r.id }]}
          icon={i === 0 ? Icon.Star : Icon.Wand}
          actions={
            <ActionPanel>
              <Action.Push
                title="Run on Clipboard"
                icon={Icon.Play}
                target={<ResultView toolId={r.id} toolName={r.name} input={data?.text ?? ""} />}
              />
              <Action.CopyToClipboard title="Copy Tool Id" content={r.id} />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
