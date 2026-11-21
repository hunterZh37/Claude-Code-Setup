---
description: Set up the adhd-friendly format in one step: your name, CLAUDE.md core rules, output style, progress-bar plugin, claude.ai texts, and a migration of your existing rules (preview, then confirm)
argument-hint: "[your name]"
allowed-tools: Bash, AskUserQuestion
---

Install the parts of the adhd-friendly format a plugin can't ship by itself, and bring the
user's existing rules in line with it. It runs the same installer as `./setup.sh`, with the
same rules: existing text is kept, every changed file is backed up first, settings are
merged without overwriting the user's keys, and `uninstall.sh` undoes it.

What it sets up:
* the output style with the user's name, and the 4 core rules as a managed block in
  `~/.claude/CLAUDE.md` (the only place subagents read them), plus `outputStyle` in settings
* the progress-bar plugin in `~/.claude/settings.json`
* the claude.ai texts in `~/.claude/.claude-code-setup/web/`
* a migration of existing reply-format rules in `~/.claude/` (CLAUDE.md, output styles,
  agents, commands). Only clashing format lines change. Everything else stays byte for byte

Arguments: `$ARGUMENTS` (optional: the name replies should use).

## Step 1. Name

If no name was given, ask with AskUserQuestion: "Name Claude should use for you in replies
and rules?" with the options "the user" (default) and "Other". Use one line, no newlines.

## Step 2. Preview

Run the dry run and show its full output. It lists every file it would create or back up
and update, with a diff for each changed file, and the settings keys it would set:

```
bash "${CLAUDE_PLUGIN_ROOT}/setup.sh" --format --plugins --web --migrate --dry-run --yes --name "<name>"
```

If it reports an error (for example an invalid settings.json), show it verbatim and stop.

## Step 3. Confirm

Ask with AskUserQuestion whether to apply these changes. If the dry run said
"kept your outputStyle", also ask whether to switch the output style (default: keep).
Stop if the answer is no. Say that the migration asks a model again on apply, so its
wording can differ a little from the preview, and that the same line checks apply.

## Step 4. Apply

```
bash "${CLAUDE_PLUGIN_ROOT}/setup.sh" --format --plugins --web --migrate --yes --name "<name>" [--force-style]
```

Add `--force-style` only if the user chose to switch the output style. Show the output.
Then print `~/.claude/.claude-code-setup/web/preferences.md` in a code block and say to
paste it into claude.ai under Settings, Your Claude, Instructions (it is also on the
clipboard if the run said so). Tell the user to restart Claude Code and run `/output-style`
to check that `adhd-friendly` is selected. To undo: `bash "${CLAUDE_PLUGIN_ROOT}/uninstall.sh"`.
