# Contributing to flutter-leak-radar

Thanks for your interest in Radar. This is a Melos + Dart pub-workspace
monorepo targeting Dart 3.10 / Flutter 3.38. This guide covers the mechanics
of contributing; see [`AGENTS.md`](AGENTS.md) for the deeper architecture,
safety rules, and conventions this repo enforces (that file is written for
AI coding agents but is equally useful for humans working in this codebase).

## Setup

```bash
git clone https://github.com/tp9imka/flutter-leak-radar.git
cd flutter-leak-radar

dart pub global activate melos   # one-time
melos bootstrap                  # resolve the workspace (shared lockfile)
```

`melos bootstrap` is the workspace-aware equivalent of running `pub get` in
every package — it resolves the whole pub workspace at once so intra-repo
packages (e.g. `flutter_leak_radar` depending on `leak_graph`) link against
the local checkout, not a published version.

## Running the local gate

Run the **same checks CI runs** before opening a PR:

```bash
melos run format-check   # dart format --set-exit-if-changed .
melos run analyze        # dart analyze --fatal-infos, per package
melos run test            # flutter/dart test, per package
melos run custom_lint    # run flutter_leak_radar_lint over the repo (dogfood)

melos run ci             # the full local gate in one command
```

Format before you commit — CI fails on unformatted code:

```bash
dart format .
```

## Repository layout

```
packages/
  flutter_leak_radar/          # Memory runtime (published)
  flutter_perf_radar/          # Performance + Stability runtime (published)
  flutter_leak_radar_lint/     # custom_lint plugin (published)
  radarscope/                  # All-in-one umbrella (published)
  leak_graph/                  # Pure-Dart heap-snapshot analysis (published)
  radar_trace/                 # Pure-Dart tracer core (published)
  radar_ui/                    # Shared design system (published)
  flutter_leak_radar_devtools/ # DevTools extension (internal, publish_to: none)
  radar_workbench/             # Shared analysis engine (internal)
  radar_native/                # Native-heap models (internal)
  radar_native_host/           # Perfetto/adb host tooling + symbolize CLI (internal)
  radar_desktop/               # macOS desktop app (internal, not a package)
docs/                          # architecture notes, specs, publishing docs
example/                       # demo app exercising the suite
site/, website/                # the docs/marketing site (owned separately — see below)
```

Each package is independently versioned — see the package's own
`CHANGELOG.md` and `pubspec.yaml`. Don't lockstep unrelated packages'
versions together.

> `site/` and `website/` are the project's public docs/marketing site and
> have their own build and ownership. Please open a separate PR for changes
> there rather than mixing them with package changes.

## Branch & PR flow

1. Fork or branch from `main`.
2. One logical change per PR — keep diffs surgical, no drive-by reformatting
   of code you didn't otherwise touch.
3. Use [Conventional Commits](https://www.conventionalcommits.org/) with a
   package scope where relevant, e.g.:
   - `feat(flutter_leak_radar): add retained-element heuristic`
   - `fix(flutter_leak_radar_lint): stop flagging late-initialized controllers`
   - `docs(radar_trace): document the track() opt-in`
4. Add tests for new behavior — pure unit tests wherever the logic doesn't
   require a live VM or device; see `AGENTS.md` for the test-tier philosophy
   this repo follows.
5. Make sure `melos run ci` and `melos run custom_lint` are green before
   requesting review. CI runs the same checks (plus a Flutter `stable`/`beta`
   matrix) and must pass before merge.
6. If your change touches a published package's public API or behavior,
   update that package's `CHANGELOG.md`.

## Questions or problems

Open an issue at
[github.com/tp9imka/flutter-leak-radar/issues](https://github.com/tp9imka/flutter-leak-radar/issues).
For security issues, see [`SECURITY.md`](SECURITY.md) instead of a public
issue.
