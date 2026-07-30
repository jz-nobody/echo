# Echo

> A multi-AI-agent status aggregator embedded in the Mac notch — monitor every coding agent and handle approvals in real time, without ever switching windows.

Echo lives in the notch at the top of your Mac. While you browse, write, or work on anything else, you can see the live status of all your AI coding agents, get completion notifications, and approve permissions or answer prompts right from the notch panel — no need to open each agent's chat window.

> Completely free — no activation code required.

*中文说明：[README.md](README.md)*

---

## Contents

- [Why Echo](#why-echo)
- [Supported agents](#supported-agents)
- [Features](#features)
- [Status types](#status-types)
- [Tech stack](#tech-stack)
- [Architecture](#architecture)
- [Build & run](#build--run)
- [Project layout](#project-layout)
- [Development conventions](#development-conventions)
- [License](#license)

## Why Echo

When you run several AI coding agents (Claude Code / Codex / QoderWork / Qoder) in parallel, you normally have to juggle multiple terminals and windows just to know which one is running, which is blocked waiting for your approval, and which has finished. Echo aggregates all of that into a single spot in the notch:

- **Collapsed**: one glance tells you the aggregate state (is any agent waiting on you, has anything finished)
- **Expanded**: full session list plus each session's current action, todos, and subagents
- **When approval/answer is needed**: handle it right in the notch panel, no need to switch back to the terminal

## Supported agents

| Agent | Integration | Status |
|-------|-------------|--------|
| **Claude Code** | Watches `~/.claude/sessions` session files + IPC hooks; parses title/todos/subagents from the JSONL transcript | ✅ |
| **Codex** | Reads `~/.codex/state_5.sqlite` (read-only) to discover sessions + hooks; parallel-spawned subagents are grouped under their parent task's subagent list (by `parent_thread_id`) instead of flooding the list | ✅ |
| **QoderWork** | MCP HTTP API (`127.0.0.1`) + hooks; multiple chats merged into a workspace session | ✅ |
| **Qoder** | Watches `~/.qoder/projects` transcripts + hooks | ✅ |
| OpenCode / Gemini CLI | Planned | 🔲 |

Each agent forwards events (PreToolUse / PostToolUse / UserPromptSubmit / Stop / SubagentStart, …) through a hook bridge installed at `~/.agent-island/bin/agent-island-bridge`, over a Unix domain socket. When the bridge can't reach the app it falls back to a neutral pass-through (`{}`), so it never blocks the agent.

## Features

- **Notch-resident**: compact aggregate status when collapsed, full session list on hover
- **Live status**: aggregated across agents by priority (waiting > running > done > idle)
- **Permission panel**: diff preview, allow / deny, keyboard shortcuts, "always allow", auto-approve
- **Choice panel**: single-select / multi-select / free text, with grouped answers for multi-question prompts
- **Confirmation queue**: approval requests from multiple agents are queued
- **Subagent nesting**: Codex parallel subagents are grouped under the parent task; only active ones shown, finished ones auto-collapse
- **Smart suppression**: no panel pops up while you're already watching that agent's terminal (frontmost-app detection)
- **Click to jump**: click a session to focus the agent's terminal window (Accessibility API)
- **Pixel-art pet animation**: a desk pet that switches with state (idle / running / compacting / asking)
- **Sound cues**: event sounds for done / asking / compaction-complete / idle reminder, configurable
- **Notification filtering**: filter noisy sessions by title keyword
- **Launch at login**

## Status types

| Status | Meaning |
|--------|---------|
| `idle` | Waiting, no active work |
| `thinking` | Model reasoning |
| `reading` | Read-type tools (Read/Grep/Glob/WebFetch…) |
| `editing` | Write-type tools (Edit/Write…) |
| `executing` | Exec-type tools (Bash, etc.) |
| `compacting` | Context compaction |
| `waitingConfirmation` | Waiting for your approval/answer (highest priority) |
| `completed` | Turn finished |

Process-liveness check: if an active session's agent process has exited, it is moved to idle / cleaned up — so a session never gets stuck "running" after a network drop or crash.

## Tech stack

- **Language**: Pure Swift 5.9+
- **UI**: SwiftUI + AppKit (NSPanel for notch-level window positioning)
- **Platform**: macOS 14+ (Sonoma), universal (Apple Silicon + Intel)
- **Build**: Swift Package Manager
- **Dependencies**: none
- **Bundle ID**: `com.agentisland.app`

## Architecture

Unidirectional data flow, protocol isolation, dependency injection (via SwiftUI environment — no singletons):

```
Agent data sources   (hook events / session files / SQLite / MCP)
        │
   BridgeServer          actor — central dispatch: routes hooks by agent type,
        │                owns the session state machine and confirmation queue
        ▼
   SessionManager        @MainActor @Observable: polling + hook-notification
        │                dual path; session filtering / sound events / idle reminders
        ▼
        UI               notch bar / expanded panel / confirmation panels / settings
```

- **BridgeServer (actor)**: single owner of all session/confirmation state. Dispatches each agent's hooks by tag; `discoverAllSessions()` runs session discovery, stale cleanup, and process-liveness checks each cycle.
- **IPC**: `IPCServer` listens on a Unix domain socket; the CLI-side `agent-island-bridge` forwards hook JSON messages; `HookInstaller` installs hooks into each agent's settings.
- **SessionManager**: `@Observable`; `pollOnce()` polls on a timer (1s active / 5s idle) and also updates instantly on `statusChanged` notifications; `SessionEventDetector` emits sound events, `SessionFilter` drops noise.
- **Session state machine**: `SessionState.apply(_ event:)` maps hook events (UserPromptSubmit / PreToolUse / PostToolUse / Stop / PreCompact / PermissionRequest…) to a `SessionStatus`, and guards `waitingConfirmation` against progress-event overrides.
- **Protocol isolation**: the UI never imports concrete data-source implementations; adding an agent just means registering an `AgentConfig` and wiring the dispatch.

## Build & run

```bash
# Dev build + tests (365+ unit and integration tests)
cd AgentIsland
swift build
swift test

# Package a release (universal DMG)
./scripts/build-dmg.sh   # run from the repo root; output at build/Echo.dmg
```

To open the ad-hoc-signed app for the first time: right-click → Open, or allow it under System Settings → Privacy & Security; or run `xattr -cr /Applications/Echo.app`.

On first run it installs the hook bridge to `~/.agent-island/bin/` and registers hooks in the config of each detected agent (`~/.claude/settings.json`, `~/.codex/hooks.json`, …).

## Project layout

```
AgentIsland/                 Swift Package (internal module name kept as AgentIsland)
  Sources/
    App/            App entry point (SwiftUI + AppKit lifecycle)
    Core/           BridgeServer / SessionManager / state machine / models / logic
    Adaptors/       Claude Code conversation/log parsing
    Infrastructure/ Windowing / IPC / hook install / settings / notch detection
    Networking/     MCP client (JSON-RPC)
    UI/             Notch bar / expanded panel / confirmation panels / settings / animations
  Tests/            365+ unit and integration tests
  BridgeCLI/        agent-island-bridge (hook-forwarding CLI)
  Resources/        Icons / sounds / SVG animations
scripts/build-dmg.sh         Packaging script (produces Echo.app / Echo.dmg)
```

> Note: the shipped product is branded **Echo**; the internal Swift module and directory are still named `AgentIsland`, with Bundle ID `com.agentisland.app`.

## Development conventions

- Use `@Observable` (not `ObservableObject`), `async/await` (not completion handlers)
- Mark UI changes `@MainActor`; keep files under 200 lines
- No force unwraps / no silent `try?`; use `DesignTokens` for colors and sizes
- Dependency injection via `.environment()`, no singletons
- No external package dependencies; no analytics / network calls; never read user source code
- `main` always builds and runs; every commit is a safe rollback point

## License

Private project. All rights reserved.
