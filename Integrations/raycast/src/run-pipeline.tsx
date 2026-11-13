import { Action, ActionPanel, Clipboard, Icon, List } from "@raycast/api";
import { usePromise } from "@raycast/utils";
import { listTools } from "./bl";
import ResultView from "./ResultView";

export default function RunPipeline() {
  const { data, isLoading, error } = usePromise(async () => {
    const pipelines = (await listTools()).filter((t) => t.kind === "pipeline");
    return { pipelines, text: (await Clipboard.readText()) ?? "" };
  });
  return (
    <List isLoading={isLoading} searchBarPlaceholder="Search saved pipelines">
      {error ? (
        <List.EmptyView icon={Icon.ExclamationMark} title="Cannot run bl" description={error.message} />
      ) : (
        <List.EmptyView
          icon={Icon.List}
          title="No saved pipelines"
          description="Create one in Bitlathe's Pipelines view, then it appears here."
        />
      )}
      {(data?.pipelines ?? []).map((p) => (
        <List.Item
          key={p.id}
          title={p.name}
          subtitle={p.summary}
          icon={Icon.ArrowRightCircle}
          actions={
            <ActionPanel>
              <Action.Push
                title="Run on Clipboard"
                icon={Icon.Play}
                target={<ResultView toolId={p.id} toolName={p.name} input={data?.text ?? ""} />}
              />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
