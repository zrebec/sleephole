@AGENTS.md

## Claude Code specifics

* Start every session by reading `docs/IMPLEMENTATION_PLAN.md` (status board §0) — you have no memory of
  earlier sessions; the plan is the memory. Update §0 and §12 at each checkpoint.
* Reply to the owner in **Slovak**; write code and docs in English.
* The sprite renderer (`tools/render/render_sprites.swift`, SceneKit + ModelIO) must be run with the Bash
  sandbox disabled — inside the sandbox ModelIO silently loads empty models.
* Xcode-dependent commands (`xcodebuild`, simulator) need Xcode installed (owner task in F0); `swift test`
  for `SleepCore` needs the Xcode toolchain too – prefix it with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (the Command Line Tools lack the Testing macros).
* **Opus plans, Sonnet builds (owner 2026-10-03, see AGENTS.md "WHO DOES WHAT"):** the main session (Claude Opus)
  analyses, plans and reviews; implementation tasks go to subagents started with the Agent tool and
  `model: "sonnet"` (Claude Sonnet 5.5). This replaces the old "don't spawn subagents" rule.
