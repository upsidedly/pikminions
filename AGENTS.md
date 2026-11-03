# Repository guidance

Pikminions is a macOS 14+ Swift 6 app built with Swift Package Manager. Antille supplies the shared island library. Read `CONTRIBUTING.md` for setup and `docs/architecture.md` for the source map.

## Commands

```sh
swift build --jobs 2
swift test --jobs 2
.build/debug/PikminionsApp --check --fixture
swift format lint --strict --recursive Sources Tests Package.swift
```

Use `swift format format --in-place` with the repository configuration on files you change. Native fixture commands are in `CONTRIBUTING.md`; run the ones affected by the change.

## Boundaries

- `SquadModel` owns app state on the main actor. `AgentSources` owns source access, sessions, and output caching in an actor. Keep those ownership boundaries and cancellation/version checks intact.
- T3 parsing belongs in `Integrations/T3ConversationParser.swift`; it must stay free of I/O. Credential access goes through `PikminKeychain` and Antille's silent credential policy.
- Preserve stable agent, thread, run, and message identities. Recorded Codex history must remain distinguishable from live agents and cannot receive commands.
- Keep fixture runs isolated. Use `--fixture` for app-level checks; do not connect to live threads, send messages, or alter installed apps to verify an ordinary source change.
- Do not log credentials or private conversation contents. Do not change global system settings, signing identities, or permission policies to simplify a test.
- Preserve existing gestures, menu tracking, bubble drafts, Reduce Motion behavior, and shared/embedded island fallback when refactoring.

## Changes

Keep patches focused and dependencies minimal. Add a regression for changed behavior, inspect the actual native interaction when it changes, and state which checks ran. A build alone does not verify UI behavior.

Use Conventional Commits. Keep generated bundles, build caches, local task notes, and private data out of Git. Preserve the MPL-2.0 source headers and character-rights notices. Do not publish, push, or modify release assets unless the task authorizes it.
