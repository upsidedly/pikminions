# Architecture

Pikminions is one SwiftPM executable target plus a pure test target. Feature folders organize source without adding module boundaries or changing runtime ownership. Antille is the only package dependency; `CSQLite` exposes the macOS SQLite library.

## Source map

All paths below are under `Sources/PikminionsApp`.

| Folder | Responsibility | Start here |
| --- | --- | --- |
| `Application` | Launch modes, app delegate, main window, observable app state | `PikminionsApplication.swift`, `SquadView.swift`, `SquadModel.swift` |
| `Agents` | Source-independent records, ordering, command payloads, completion detection | `AgentModels.swift`, `AgentCommands.swift` |
| `Companions` | Artwork, custom looks, motion, desktop panels, placement, sprite export | `PikminArt.swift`, `DesktopHeads.swift` |
| `Conversations` | Conversation state, speech, replies, question forms, native bubble windows | `ConversationState.swift`, `ConversationWindows.swift` |
| `Integrations` | T3/Codex access, protocol parsing, credentials, recorded metadata, sample source | `AgentSources.swift`, `T3ConversationParser.swift` |
| `Island` | Shared versus embedded destination policy | `IslandDestination.swift` |
| `Support` | Bounded subprocesses, original chirps, app-icon rendering | `ProcessRunner.swift` |
| `Checks` | CLI regressions and explicitly invoked live-canary tooling | `Checks.swift` |

`Tests/PikminionsTests` contains pure Swift Testing cases. `Tests/NativeFixtures` builds separate sample apps against the real views and window controllers. Those tools exclude the launcher's object file when linking a fixture entry point, so keep the single `@main` launcher in `PikminionsApplication.swift`.

## State and data flow

`PikminionsDelegate` creates one `SquadModel`. The model owns preferences and agent presentation on the main actor, starts/stops polling and idle work, and coordinates desktop windows, conversations, and the island. Views bind to it rather than opening source connections themselves.

`AgentSources` is an actor. It owns T3 sessions, monotonically ordered metadata snapshots, question access, and a bounded recent-output cache. It delegates protocol transport to `T3Socket`/`T3MCPClient`, credential storage to `PikminKeychain`, and Codex discovery to `CodexSource` with a read-only `SQLiteMetadata` fallback. Source parsers return values rather than mutating views.

`T3ConversationParser` converts bounded history and live events into `ConversationLine` values. Visible turn items preserve inherited fork history; omitted text can resolve against local messages. Streaming and final events share a message ID. Reasoning and events for other threads must never enter visible speech.

`ConversationCoordinator` owns per-thread conversation state, native panels, and subscription/operation tasks. Partial output grows the same message; stale results must not replace newer output or reopen dismissed speech. Drafts stay in memory through presentation changes. Explicit submissions go through `AgentSources` and `AgentCommands`.

`DesktopSquadController` owns floating AppKit panels and gesture motion. Pure placement, pendulum, idle, and sleep types support deterministic checks. `SquadModel` publishes Antille activities with stable identities and revisions. The shared host is used only after pairing succeeds; otherwise the embedded controller keeps docking available. Antille owns the island renderer and host protocol.

## Contracts to preserve

- Agent/thread/run/message IDs describe different lifetimes. Renaming or changing a look does not change conversation identity.
- Main-actor UI state and actor-owned source state must not be merged. Owned tasks are cancelled on replacement or shutdown; revision checks reject outdated async results.
- The compact island contains active or waiting agents. Retained completed agents can remain available in expanded content without occupying a compact slot.
- Normal credentials use the existing silent Keychain policy and fail closed. Fixture credentials remain in memory; fixture startup disables live connections and external effects.
- Conversation text and drafts stay in memory. Preferences, looks, positions, and deduplication IDs are local persisted settings. Keep new storage decisions explicit.

See [CONTRIBUTING.md](../CONTRIBUTING.md) for the commands that exercise these boundaries.
