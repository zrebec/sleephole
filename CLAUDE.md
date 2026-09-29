@AGENTS.md

## Claude Code specifics

* Start every session by reading `docs/IMPLEMENTATION_PLAN.md` (status board §0) — you have no memory of
  earlier sessions; the plan is the memory. Update §0 and §12 at each checkpoint.
* Reply to the owner in **Slovak**; write code and docs in English.
* The sprite renderer (`tools/render/render_sprites.swift`, SceneKit + ModelIO) must be run with the Bash
  sandbox disabled — inside the sandbox ModelIO silently loads empty models.
* Xcode-dependent commands (`xcodebuild`, simulator) need Xcode installed (owner task in F0); `swift test`
  for `SleepCore` works with the Command Line Tools alone.
* Don't spawn subagents unless the owner asks; phases are small enough to do inline.
