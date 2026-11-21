---
description: Personalize the answer-first reply format, add its core rules to ~/.claude/CLAUDE.md and set it as your output style (preview, then confirm)
argument-hint: "[your name]"
allowed-tools: Bash, AskUserQuestion
---

Install the parts of the answer-first format a plugin can't ship by itself: an output
style with the user's name in it, the 4 core rules as a managed block in
`~/.claude/CLAUDE.md` (the only place subagents read them), and `outputStyle` in
`~/.claude/settings.json`. It runs the same installer as `./setup.sh --format`, with the
same rules: existing text is kept, every changed file is backed up first, settings are
merged without overwriting the user's keys, and `uninstall.sh` undoes it.

Arguments: `$ARGUMENTS` (optional: the name replies should use).

## Step 1. Name

If no name was given, ask with AskUserQuestion: "Name Claude should use for you in replies
and rules?" with the options "the user" (default) and "Other". Use one line, no newlines.

## Step 2. Preview

Run the dry run and show its full output. It lists every file it would create or back up
and update, with a diff for changed files, and the settings keys it would set:

```
bash "${CLAUDE_PLUGIN_ROOT}/setup.sh" --format --dry-run --yes --name "<name>"
```

If it reports an error (for example an invalid settings.json), show it verbatim and stop.

## Step 3. Confirm

Ask with AskUserQuestion whether to apply exactly these changes. If the dry run said
"kept your outputStyle", also ask whether to switch the output style (default: keep).
Stop if the answer is no.

## Step 4. Apply

```
bash "${CLAUDE_PLUGIN_ROOT}/setup.sh" --format --yes --name "<name>" [--force-style]
```

Add `--force-style` only if the user chose to switch the output style. Show the output.
Then tell the user to restart Claude Code and run `/output-style` to check that
`adhd-friendly` is selected. To undo: `bash "${CLAUDE_PLUGIN_ROOT}/uninstall.sh"`.
