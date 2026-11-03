# Contributing to Pikminions

Bug fixes, interaction improvements, accessibility work, and tests are welcome. For a larger change, open an issue describing the problem and proposed behavior before investing in an implementation.

## Set up

You need macOS 14 or later, a Swift 6 toolchain, Git, and Python 3. Install Xcode or the Command Line Tools so the macOS SDK, SQLite headers, and app-signing tools are available. No package manager dependencies are required for a normal source build.

```sh
git clone https://github.com/upsidedly/pikminions.git
cd pikminions
swift build --jobs 2
```

Swift Package Manager resolves the public [Antille](https://github.com/upsidedly/antille) dependency using `Package.resolved`. Keep that pin unless your change deliberately updates it. To work on both projects, set `ANTILLE_PACKAGE_PATH` to an existing Antille checkout; unset it before checking a change intended to use the published dependency.

See the [architecture guide](docs/architecture.md) for the source map, state ownership, and important contracts.

## Run checks

```sh
swift test --jobs 2
.build/debug/PikminionsApp --check --fixture
```

`swift test` runs pure Swift Testing cases without launching the app or contacting a service. The second command exercises the existing state, rendering-model, streaming, and conversation-access checks with sample data. Keep `--fixture`: it selects isolated preferences, in-memory credentials, and the sample source. A T3 installation or account is not needed for these checks.

The [Checks workflow](.github/workflows/checks.yml) runs formatting, tests, and native fixture checks on macOS for pushes to `main` and pull requests. It uses the published Antille dependency and does not need T3 credentials.

For a change to a native interaction, use the relevant sample app as well:

```sh
# Desktop panel sizes, spawn placement, and sleep/wake lifecycle.
python3 scripts/build-head-size-fixture.py --check --spawn-check --sleep-check

# Native menu stability; this briefly opens and closes a sample context menu.
python3 scripts/build-head-size-fixture.py --menu-check

# Conversation, Markdown, question, and streaming speech controls.
python3 scripts/build-bubble-fixture.py
open dist/PikminionsBubbleFixture.app
```

These builders use separate fixture identities. They do not require real conversations. Close sample apps when finished. An assertion about geometry or state does not establish how dragging or animation feels; inspect the actual interaction when it changes. Report the checks you ran and any display, input, or accessibility cases you could not exercise. Use targeted checks for a focused change rather than repeating unrelated suites.

## Run the app

```sh
python3 scripts/build.py --fixture
open dist/PikminionsFixture.app
```

This packages a silent sample app with separate preferences. It also regenerates the icon and head images in `docs/assets`; review those files before committing them.

For real T3 connections, build the normal bundle with `python3 scripts/build.py` and open `dist/Pikminions.app`. Connect through its Connections tab. A local rebuild can have a different signing identity, so reconnecting T3 and pairing Antille may be necessary. Do not change Keychain access permissions or approve security prompts as a workaround. Avoid replacing a running installed copy while testing a source change.

## Code style

Use the repository's `.swift-format` configuration with the formatter bundled with Swift:

```sh
swift format format --in-place --recursive Sources Tests Package.swift
swift format lint --strict --recursive Sources Tests Package.swift
```

Keep changes within the relevant feature folder. Prefer a small concrete value or function over a new abstraction with a single use. Preserve actor isolation, explicit task cancellation, stable conversation/message IDs, and the fixture boundary. Keep UI state on the main actor and network/process ownership in the integration layer.

Add a regression at the smallest useful layer. Put pure tests in `Tests/PikminionsTests`, native sample apps in `Tests/NativeFixtures`, and fixture integration checks in `Sources/PikminionsApp/Checks`. The CLI checks remain in the executable because the packaging and native-fixture tools use that entry point.

## Submit a change

- Keep the pull request focused. Describe the problem, resulting behavior, and actual verification.
- Use Conventional Commits, for example `fix(conversations): preserve drafts on reconnect` or `test(integrations): cover omitted message text`.
- Do not commit `.build`, `dist`, credentials, environment files, personal work logs, or screenshots containing real conversation text. Redact logs before attaching them to an issue.
- Keep the MPL-2.0 headers in source files. Original contributions use the existing [license](LICENSE); see [provenance](PROVENANCE.md) for the separate Nintendo character and trademark rights.

For a bug report, include the app version, macOS version, expected result, reproduction steps, and whether it also happens with sample agents. Please do not include tokens, Keychain data, or private thread content.
