# Agent Island

> A multi-AI-agent status aggregator embedded in the Mac notch — monitor every coding agent and handle approvals in real time, without ever switching windows.

Agent Island lives in the notch at the top of your Mac. While you browse, write, or work on anything else, you can see the live status of all your AI coding agents, get completion notifications, and approve permissions or answer prompts right from the notch panel — no need to open each agent's chat window.

*中文说明：[README.md](README.md)*

---

## Supported agents

| Agent | Integration | Status |
|-------|-------------|--------|
| **Claude Code** | Session-file watching (`~/.claude/sessions`) + IPC hooks | ✅ |
| **Codex** | SQLite session discovery (`state_5.sqlite`) + hooks; subagents nested under their parent task | ✅ |
| **QoderWork** | MCP HTTP API + hooks | ✅ |
| **Qoder** | Session-file watching + hooks | ✅ |
| OpenCode / Gemini CLI | Planned | 🔲 |

## Features

- **Notch-resident**: compact aggregate status when collapsed, full session list on hover
- **Live status**: idle / thinking / reading / editing / running / compacting / asking / done, aggregated across agents
- **Interactive approvals**: permission panel (diff preview, keyboard shortcuts) + choice panel (single / multi-select / free text)
- **Subagent nesting**: parallel-spawned subagents are grouped under their parent task instead of flooding the list
- **Smart suppression**: no panel pops up while you're already watching that agent's terminal
- **Click to jump**: click a session to focus the agent's terminal window (Accessibility API)
- **Pixel-art pet animation** + **sound cues**: a desk pet and audio feedback that switch with agent state
- **Notification filtering** + **launch at login**

> Completely free — no activation code required.

## Tech stack

- **Language**: Pure Swift 5.9+
- **UI**: SwiftUI + AppKit (NSPanel for notch-level windows)
- **Platform**: macOS 14+ (Sonoma), universal (Apple Silicon + Intel)
- **Build**: Swift Package Manager
- **Dependencies**: none
- **Bundle ID**: `com.agentisland.app`

## Architecture

Unidirectional data flow, protocol isolation, dependency injection (via SwiftUI environment — no singletons):

```
Agent data sources (hooks / files / SQLite / MCP)
        │
   BridgeServer  (actor — central dispatch)
        │
   SessionManager  (@MainActor @Observable)
        │
        UI  (notch bar / expanded panel / confirmation panels)
```

- **BridgeServer**: an actor that dispatches hooks by agent type and owns session/confirmation state
- **IPC**: Unix domain socket; the CLI-side `agent-island-bridge` forwards hook events
- **SessionManager**: drives the UI via both polling and hook notifications

See [`arc.md`](arc.md) (architecture), [`prd.md`](prd.md) (requirements), and [`design.md`](design.md) (visual/interaction) — these are written in Chinese.

## Build & run

```bash
# Dev build + tests
cd AgentIsland
swift build
swift test

# Package a release (universal DMG)
./scripts/build-dmg.sh   # run from the repo root; output at build/Echo.dmg
```

To open the ad-hoc-signed app for the first time: right-click → Open, or allow it under System Settings → Privacy & Security.

## Development conventions

- `@Observable` (not `ObservableObject`), `async/await` (not completion handlers)
- Mark UI changes `@MainActor`; keep files under 200 lines
- No force unwraps / no silent `try?`; use `DesignTokens` for colors and sizes
- Each step on its own feature branch; `main` always builds and runs
- Update `devlog/YYYY-MM-DD.md` at the end of every work session

Full conventions in [`CLAUDE.md`](CLAUDE.md) and [`docs/`](docs/).

## Project layout

```
AgentIsland/
  Sources/
    App/            App entry point (SwiftUI + AppKit lifecycle)
    Core/           BridgeServer / SessionManager / models / business logic
    Adaptors/       Claude Code conversation parsing
    Infrastructure/ Windowing / IPC / hook install / settings
    Networking/     MCP client (JSON-RPC)
    UI/             Notch bar / expanded panel / confirmation panels / settings / animations
  Tests/            365+ unit and integration tests
  BridgeCLI/        agent-island-bridge (hook-forwarding CLI)
scripts/build-dmg.sh
docs/               Workflow / coding standards / adaptor contract / testing strategy
devlog/             Daily development logs
```

## License

Private project. All rights reserved.
