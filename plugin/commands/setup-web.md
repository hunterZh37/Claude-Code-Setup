---
description: Print the answer-first format as paste-ready text for claude.ai and the desktop app
argument-hint: "[your name]"
allowed-tools: Bash, AskUserQuestion
---

Claude on the web can't be configured by a script, so this prints text for the user to
paste. Nothing opens a browser or touches claude.ai.

Arguments: `$ARGUMENTS` (optional: the name replies should use; default "the user").

1. Render the three texts with the name. This also copies the short one to the clipboard
   when pbcopy, wl-copy or xclip exists:

   ```
   bash "${CLAUDE_PLUGIN_ROOT}/setup.sh" --web --yes --name "<name>"
   ```

2. Print each file in full inside its own code block, so it can be copied as is:
   * `~/.claude/.claude-code-setup/web/preferences.md`: every chat. Paste into the profile
     preferences box in claude.ai Settings.
   * `~/.claude/.claude-code-setup/web/style.md`: a custom Style created from the Styles menu.
   * `~/.claude/.claude-code-setup/web/project-instructions.md`: one Project's instructions.

3. Say that menu names on claude.ai may change, and that the preferences text is already on
   the clipboard if the run said so.
