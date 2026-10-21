/// `.claude/skills/astromech/SKILL.md` written by `astromech init`.
const skillTemplate = '''---
name: astromech
description: Check, verify or reproduce something in the running Flutter app on a simulator, or see a code change on screen right after a hot reload - reuses a saved astromech flow if one fits, otherwise plans the path from the code, runs it in one call and saves it (astromech CLI + astromech_driver). Use for any "check X on the simulator / device", "does the screen show Y after my change", or writing a device flow.
---

# astromech

The device is never the slow part (a whole flow takes ~3-7 s) - the model is. So plan whole paths up front and run them in ONE call.

- **Yourself, in the main session**, when you know the ids: `astromech run --inline '[...]'`.
- **`astromech check "<what to check>"`** to hand it off without spending main-session context: a Haiku agent with thinking OFF in a separate process. Don't dispatch a subagent for this - it inherits the session's thinking and is ~2x slower.

Nothing project-specific has to be passed: the device is the one booted simulator, the app is the one running debug build with `registerAstromech()`. Project hints for agents live in `astromech/HINTS.md`.

## Commands

```bash
astromech list                                   # saved flows (astromech/flows/**)
astromech run astromech/flows/<app>/<flow>.yaml  # run one, seconds, no model
astromech run --timeout 3 --inline '[{goHome: true}, {tap: {id: x}}, {waitFor: {text: "Y"}}]' --describe-after
astromech run --inline '[...]' --save-as astromech/flows/<app>/<what>.yaml --title "<what it checks>"
```

`--describe-after` prints the screen (ids, texts, values) after the steps; a FAIL stops, prints the screen and saves `build/astromech/<flow>/failure.png`. Steps are validated before anything runs.

## Steps

Each step map has exactly ONE key:

| Step | Example | Notes |
|---|---|---|
| `goHome` | `goHome: true` | closes screens / sheets / dialogs back to the first screen (via Navigator) |
| `tap` | `tap: { id: submit_button }` / `{ text: "OK" }` / `{ anyOf: [{id: a}, {id: b}] }` | waits for it, taps once it stopped moving |
| optional | `tap: { id: intro_ok, optional: true, timeout: 1 }` | skipped if it never shows (one-off popups) |
| `type` | `type: abc12` | into the focused field - tap it first |
| `waitFor` / `waitGone` | `waitFor: { text: "Saved" }` | text matches visible text or label |
| `assert` | `assert: { id: user_input, value: ABC12 }` | `value` / `text` / `label` of an id |
| `screenshot` | `screenshot: result.png` | to `build/astromech/<flow>/` |
| `describe` | `describe: true` | print what is on screen |
| `reload` / `restart` | `reload: true` | hot reload / restart (VS Code session or `flutter run --pid-file`) |

Ids are `Semantics(identifier: ...)` values or `ValueKey<String>`s. "Only X" = `waitFor` X + `waitGone` for each other value (on-screen only - no scrolling yet). A saved flow must start and end with `goHome` and contain no test data (record numbers, names, counts).

## Dev loop: change code, see it on the same screen

`reload: true` / `restart: true` work with either way of running the app:
- **F5 in VS Code** (Dart extension) - nothing to set up; astromech asks the IDE through the Dart Tooling Daemon, like its reload button.
- **`flutter run ... --pid-file build/astromech/flutter_run.pid`** in a terminal - astromech signals that process, like pressing r / R.

Then edit the code -> `astromech run --timeout 3 --inline '[{reload: true}, {waitFor: {text: "..."}}]'` (~1-1.5 s). `restart: true` drops screen state. When the change doesn't show, look for a compile error in the IDE debug console / `flutter run` output.

## Safety

- Read-only by default: don't tap actions that create or change data (submit, approve, delete...) unless asked for that exact action.
- Never relaunch the app to check a hot-reloaded change - a relaunch runs the installed binary without it.
''';

/// `astromech/HINTS.md` written by `astromech init` - project knowledge for agents.
const hintsTemplate = '''# astromech hints

Short project facts that save the check agent from searching. Keep it under ~15 lines.

<!-- Examples - replace with your project's:
- Feature code: lib/features/<feature>/view.dart; ids in lib/features/<feature>/identifiers.dart.
- Shared ids: dialog OK `dialog_primary_button`, sheet close `sheet_close`, header help `header_help`.
- One-off popups after login: intro `intro_got_it` (optional).
- `header_menu` is the menu, not help.
-->
''';
