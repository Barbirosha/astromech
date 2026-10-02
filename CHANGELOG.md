# Changelog

## Unreleased

- `reload` / `restart` also work for apps started with F5 in VS Code: through the Dart Tooling Daemon (`Editor.hotReload` / `Editor.hotRestart`) when no `flutter run --pid-file` is running.
- `reload` with no code change fails after 15 s with an explanation instead of waiting 60 s.

## 0.1.0

- `astromech_driver`: `registerAstromech()` with `ext.astromech.find / tap / enterText / describe / goHome / isHome`; hit-test visibility, ids under `MergeSemantics`, taps once the target stopped moving, typing through input formatters, `Navigator`-based go-home with PopScope detection.
- `astromech` CLI: `run` (inline or flow file, step validation, `--describe-after`, `--timeout`, `--save-as`), `list`, `check` (thinking-free Haiku agent via `claude -p`), `init`; auto-detects the booted simulator and the running app; hot reload / restart via the `flutter run` pid file; native backend via mobilecli.
