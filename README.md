# astromech

Drive a running Flutter debug app from scripts and AI agents — like an astromech droid plugged into a ship: it sits inside the app and works its systems from there.

> **Beta.** iOS only for now, built for AI agents and tuned against Claude.

- **Fast**: widgets are found inside the app over the VM service, ~0.1–0.5 s per step instead of seconds for OS accessibility dumps.
- **Sees what users see**: only the route on top (hit-test based), ids hidden from the OS tree by `MergeSemantics` (checkboxes, radios) included.
- **Agent-friendly**: whole paths run in one call, steps are validated before touching the device, and a failure prints the screen.
- **Flows**: a passing run is saved as a YAML flow and replays in seconds without a model.
- **Dev loop**: hot reload from the CLI and check the same screen right after a code change.

Two packages:

| Package | Where | What |
|---|---|---|
| `astromech_driver` | in your app | `registerAstromech()` — VM service extensions `ext.astromech.*` (debug builds only) |
| `astromech` | your machine | the `astromech` CLI: `run`, `list`, `check`, `init` |

## Setup

```bash
# 1. The CLI (compiled, ~0.02 s start)
git clone <this repo> && astromech/tool/install.sh

# 2. In your Flutter app (not on pub.dev yet - a git or path dependency)
flutter pub add astromech_driver --git-url <astromech repo url> --git-path packages/astromech_driver --git-ref main
#   or: flutter pub add astromech_driver --path <path to astromech>/packages/astromech_driver
```

```dart
void main() {
  runApp(const MyApp());
  registerAstromech(); // no-op and tree-shaken outside debug builds
}
```

```bash
# 3. In your project
astromech init        # astromech/flows/, astromech/HINTS.md, .claude/skills/astromech/
# run the app as usual: F5 in VS Code, or
flutter run --pid-file build/astromech/flutter_run.pid
astromech run --inline '[{describe: true}]'
```

The device is the one booted iOS simulator and the app is the one running debug build with the driver (found via mDNS) — `--device` / `--app` / `--vm-service` / `--pid-file` only when several run at once.

## Commands

```bash
astromech run --inline '[{goHome: true}, {tap: {id: filter_button}}, {waitFor: {text: "Filter: done"}}]'
astromech run astromech/flows/shop/checkout.yaml
astromech run --inline '[...]' --save-as astromech/flows/shop/checkout.yaml --title "Checkout shows the total"
astromech list
astromech check "Filtering tasks by done shows only done tasks"   # Haiku agent, thinking off; needs `claude`
```

Options: `--describe-after` (print the screen after the steps), `--timeout <s>` (default step timeout), `--backend native` (OS accessibility tree via [mobilecli](https://github.com/mobile-next/mobilecli) — any app, slower).

## Steps

Each step map has exactly one key:

| Step | Example |
|---|---|
| `goHome` | `goHome: true` — closes screens, sheets and dialogs back to the first screen (via `Navigator`, no ids) |
| `tap` | `tap: { id: x }`, `tap: { text: "OK" }`, `tap: { anyOf: [{id: a}, {id: b}] }` — waits for it, taps once it stopped moving |
| optional | `tap: { id: intro_ok, optional: true, timeout: 1 }` — skipped if it never shows |
| `type` | `type: abc12` — into the focused field, through its input formatters |
| `waitFor` / `waitGone` | `waitFor: { text: "Saved" }`, `waitGone: { id: spinner, timeout: 5 }` |
| `assert` | `assert: { id: note_input, value: ABC12 }` (or `text:` / `label:`) |
| `screenshot` | `screenshot: result.png` → `build/astromech/<flow>/` |
| `describe` | `describe: true` — ids, texts and values on screen |
| `reload` / `restart` | hot reload / restart — of a VS Code debug session (via the Dart Tooling Daemon) or of `flutter run --pid-file` |
| `button`, `launch`, `terminate` | via mobilecli |

Ids are `Semantics(identifier: ...)` values or `ValueKey<String>`s. Saved flows must start and end on the first screen (`goHome`).

## Agents

`astromech init` installs a Claude Code skill that tells the session to plan whole paths and run them in one call, or hand the check to `astromech check` — a headless Claude Code process on Haiku with thinking off, prompt built into the CLI, project facts from `astromech/HINTS.md`. Keep `HINTS.md` short: where ids live, shared ids (dialog buttons, sheet close, help icon), one-off popups. Without it the agent has to search the code and takes noticeably longer.

### Measured against Mobile MCP

Same tasks, both on Claude Haiku 4.5 without thinking (one run each unless noted):

| Task | Mobile MCP | astromech agent | astromech, saved flow |
|---|---|---|---|
| Filter with checkboxes under MergeSemantics | FAIL, 245 s, $0.44 | PASS, 57 s, $0.09 | 2 s |
| Form field + QR modal | PASS, 93 s, $0.08 | PASS, 45 s, $0.06 | 3 s |
| Sort before / after compare | wrong "sorting is broken", 389 s, $0.82 | PASS, 27 s, $0.04 | — |
| 5 code changes + hot reload (median of 3) | 72.5 s, $0.135 | 50.8 s, $0.083 | — |

## Limits

- Debug builds started with `flutter run` (the VM service is needed); iOS simulator. Android is not supported yet.
- Only what is on screen — no scrolling yet.
- Hot reload needs the app started with F5 in VS Code (Dart extension) or `flutter run --pid-file`; Android Studio / IntelliJ sessions are untested. Changes in `main()` or static state need `restart: true`.

## Repository

```
packages/astromech_driver   Flutter package (in the app)
packages/astromech          CLI
example/                    example app + flows (astromech/flows/example)
tool/install.sh             compiles and installs the CLI
```

`dart analyze`, `dart test` (packages/astromech), `flutter test` (packages/astromech_driver, example).
