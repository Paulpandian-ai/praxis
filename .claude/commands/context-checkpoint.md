---
description: Save current plan and progress to docs/checkpoints/ before /clear
allowed-tools: Read, Write, Bash
---

# Context checkpoint

You're about to run out of useful context. Before /clear, dump:

1. **What I was doing**: 1-2 sentences.
2. **Files modified this session**: list with one-line description per file.
3. **Decisions made**: what design choices we settled on, with brief rationale.
4. **Next steps**: ordered list of what to do next session.
5. **Open questions**: anything I asked you that's still unresolved.
6. **Gotchas discovered**: anything surprising about the codebase that the next session should know.

Save to `docs/checkpoints/<YYYY-MM-DD-HH-MM>-<short-slug>.md`.

After saving, output:
- The file path.
- A one-paragraph "next session opener" I can paste at the start of a fresh session.

The opener should reference CLAUDE.md and the checkpoint file, and lead with the most important next step.
