# Bitlathe for AI agents (MCP)

`bl mcp` serves Bitlathe's tools over the [Model Context Protocol](https://modelcontextprotocol.io), so Claude Code,
Claude Desktop and other agents can get exact results (a Base64 decode, a hash, a JWT's claims, a cron schedule)
instead of guessing them. It speaks JSON-RPC 2.0 over stdio, one message per line, and runs entirely on your Mac.

## Set up

Claude Code:

```sh
claude mcp add bitlathe -- /Applications/Bitlathe.app/Contents/Helpers/bl mcp
```

If you installed `bl` on your `PATH` (Settings › Integrations › Install bl…), `claude mcp add bitlathe -- bl mcp` works too.

Other clients (Claude Desktop and anything that reads an `mcpServers` file):

```json
{
  "mcpServers": {
    "bitlathe": { "command": "/Applications/Bitlathe.app/Contents/Helpers/bl", "args": ["mcp"] }
  }
}
```

Settings › Integrations shows both, with the right path for your copy and a Copy button.

## Tools

| Tool | What it does |
|---|---|
| `detect` | Recognises text and ranks the tools that fit, with the options to use. |
| `smart_run` | Recognises the input and runs the best tool, like the app's Smart Box. Chains when the result is itself data (Base64 that hides JSON). Understands `3 uuid v7`, `password 24`, `now`, `lorem 2 sentences`. |
| `run_tool` | Runs one tool by id with typed options. Unknown options and invalid choices are errors that list the valid ones. Binary input via `input_base64`. |
| `list_tools` | Every tool with its id, summary, and options as a schema (type, default, allowed values). Filter with `query` or `category`. |
| `run_pipeline` | Runs tools in a chain: an expression such as `base64.text mode=decode \| json.format`, or a pipeline saved in the app. |

Text results come back as text content; facts (such as a timestamp's parts or a certificate's fields) as a second
block and as `structuredContent`; images as image content. Tools with side effects are not exposed. All tools are
marked read-only.

## Try it by hand

```sh
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"smart_run","arguments":{"input":"eyJhIjoxfQ=="}}}' \
  | bl mcp
```

## Notes

- Supported protocol versions: 2025-06-18, 2025-03-26 and 2024-11-05.
- `bl mcp` reads your saved pipelines and user scripts, like the rest of the CLI. It does not use the Smart Box's
  learned preferences, so agents get the same answer for the same input every time.
- The protocol code is `MCPServer` in BitlatheCore; tests are in `Tests/BitlatheTests/MCPServerTests.swift`.
