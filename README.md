# ADHD-friendly replies for Claude Code

Claude Code replies that lead with the answer, show status as glyphs and tables, and end with what you must do. One command sets it up.

## Install

**Plugin** (inside Claude Code):

```
/plugin install adhd-friendly --marketplace hunterZh37/Claude-Code-Setup
/adhd-friendly:setup
```

**Script** (in a terminal):

```bash
git clone https://github.com/hunterZh37/Claude-Code-Setup.git ~/Claude-Code-Setup && ~/Claude-Code-Setup/setup.sh
```

Both ask your name. The plugin shows a preview and asks once. The script shows a diff before it changes any file you wrote.

> [!TIP]
> Older Claude Code rejects `--marketplace`. Run `/plugin marketplace add hunterZh37/Claude-Code-Setup`, then `/plugin install adhd-friendly@adhd-friendly`.

## Before and after

You ask: "should we cache the API answers?"

**Before** (default):

```
Good question! There are a few ways we could approach caching here. One option
would be to add a time-to-live of about an hour, which is simple but means answers
could be stale. Another would be to version the cache keys so entries are replaced
on deploy. We could also leave it as is. Let me know which you'd prefer!
```

**After** (`adhd-friendly`):

```
Recommend: version the cache keys, because entries never go stale and no deploy hook is needed.

| Option         | Gain        | Cost   | Undo? |
|----------------|-------------|--------|-------|
| Version keys ← | never stale | 10 min | yes   |
| 1 h TTL        | simplest    | 5 min  | yes   |
| Do nothing     | none        | 0      | n/a   |

**Actionables**
! Reply "go", or name another row (~10 s)
```

## What you get

| Part | Where | Does |
|---|---|---|
| **Output style** | `~/.claude/output-styles/adhd-friendly.md` | The full reply format, with your name |
| **Core rules** | a marked block in `~/.claude/CLAUDE.md` | The 4 core rules, plus how subagents report. Output styles never reach subagents, `CLAUDE.md` does |
| **Progress bars** | `~/.claude/settings.json` | Turns on [progress-bar](https://github.com/hunterZh37/progress-bar-plugin): live bars for subagents and long jobs |
| **Migration** | your existing agent files | Rewrites reply-format rules that clash with this format. [How](#migration) |
| **claude.ai texts** | `~/.claude/.claude-code-setup/web/` | Text to paste into claude.ai. [How](#claudeai) |

## Safe to run

* **Backups:** every file it changes is copied to `<file>.bak-<timestamp>` first.
* **Your text stays:** in `CLAUDE.md`, only the block between the `claude-code-setup` markers is rewritten.
* **Settings merge:** your keys stay. `outputStyle` changes only if unset or you say yes.
* **Re-runs:** a second run changes nothing and keeps your name.
* **Nothing private:** no keys, tokens, binaries or personal history ship in this repo.

## After install

1. **Restart** Claude Code.
2. **Check:** run `/output-style` and make sure `adhd-friendly` is selected.
3. **Progress bars:** accept the progress-bar marketplace prompt on first start.

## Migration

Setup also fixes your existing rules, so they stop fighting the new format.

| Changes | Never changes |
|---|---|
| Rules on length, headings, bullets, tables, emoji, tone, openings, endings, summaries | Project facts, commands, workflows, coding conventions, safety rules, frontmatter |

| Scope | Files |
|---|---|
| **You** | `~/.claude/CLAUDE.md` and its `@imports`, `output-styles/`, `agents/`, `commands/` |
| **Project** | `CLAUDE.md`, `CLAUDE.local.md`, `AGENTS.md`, `GEMINI.md`, `.cursorrules`, `.cursor/rules/`, `.github/copilot-instructions.md`, `.windsurfrules` |

Project files change only when you run setup inside the project and say yes.

**How it stays exact**

1. **Find** clashing lines in each file.
2. **Rewrite** with your own `claude -p`. It may only delete or reword those lines.
3. **Check** that every other line comes back byte for byte, in order. Any other change rejects the rewrite.
4. **Ask:** you see a diff per file and answer y or N.

Files that look like they hold a secret, files over 200 KB and binary files are never sent to a model. Without `claude` installed, setup lists the clashing lines for you to fix by hand.

**Example**

```diff
- - Be friendly and use emoji to keep things fun.
- - Never use tables, write prose instead.
- - Always end with a summary of what you did.
  - Run `npm test` before every commit.
  - Never push to main without asking.
+ <!-- Migrated by Claude-Code-Setup: reply-format rules reconciled, see .bak file for the original -->
+ <!-- claude-code-setup:begin -->
+ # Replies to Sam
+ ...the 4 core rules...
+ <!-- claude-code-setup:end -->
```

## claude.ai

> [!NOTE]
> Only for Claude on the web (claude.ai) and in the desktop app chat. Claude Code does not need this.

claude.ai settings have no API, so setup only writes the text and copies the short one to your clipboard. You paste it.

| File | Paste into | Applies to |
|---|---|---|
| `preferences.md` | Settings → Your Claude → Instructions | every chat |
| `style.md` | a custom Style (Styles menu) | chats with that Style on |
| `project-instructions.md` | a Project's instructions | that Project |

## Uninstall

```bash
~/Claude-Code-Setup/uninstall.sh
```

Plugin install: ask Claude to run `uninstall.sh` from the plugin's folder, then `/plugin uninstall adhd-friendly@adhd-friendly`.

Restores every backed-up file, removes what setup added and keeps any settings key you changed since.

<details>
<summary><b>Why the format looks like this</b> (research)</summary>

| Rule | Basis | Source |
|---|---|---|
| **Answer and a pick first** | Defaults shift choices (d ≈ 0.68). People defer when no option clearly wins | [Jachimowicz et al. 2019](https://www.cambridge.org/core/journals/behavioural-public-policy/article/when-and-why-defaults-influence-decisions-a-metaanalysis-of-default-effects/67AF6972CC2ECA3D9B5D3B0FA7AE2F0F), [Dhar 1997](https://bear.warrington.ufl.edu/brenner/mar7588/Papers/dhar-jcr1997.pdf) |
| **Glyph status rows** | A ✗ among ✓ is found without reading (pre-attentive pop-out) | [Cleveland and McGill, summary](https://info3312.infosci.cornell.edu/ae/graphical-perception.html) |
| **Bars for amounts** | Length on a common scale is read more accurately than angle or area | [Cleveland and McGill, summary](https://info3312.infosci.cornell.edu/ae/graphical-perception.html) |
| **Tables for exact values** | Tables win for exact lookup, graphs for patterns | [Vessey and Galletta 1991](https://ideas.repec.org/a/inm/orisre/v2y1991i1p63-84.html) |
| **Read in place** | ADHD affects visuospatial working memory more than verbal | [Martinussen et al. 2005](https://pubmed.ncbi.nlm.nih.gov/15782085/) |
| **Short chunks** | Working memory holds about 4 chunks | [Cowan 2001](https://pubmed.ncbi.nlm.nih.gov/11515286/) |
| **Startable actions** | If-then plans help follow-through (d = 0.65), including in ADHD | [Gawrilow et al. 2011](https://www.socmot.uni-konstanz.de/sites/default/files/Gawrilow_Gollwitzer_Oettingen_Executive_Function_JSCP_2011.pdf) |
| **Few rules, no conflicts** | Compliance drops as instructions multiply | [IFScale 2025](https://arxiv.org/abs/2507.11538), [Lost in the Middle](https://aclanthology.org/2024.tacl-1.9/) |
| **Two examples** | Examples reliably steer format | [Anthropic prompting guide](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices) |
| **Rules in two places** | Output styles skip subagents, CLAUDE.md reaches them | [Output styles](https://code.claude.com/docs/en/output-styles), [Subagents](https://code.claude.com/docs/en/sub-agents) |

**Evidence gap:** no study tests terminal glyphs or AI reply formats with ADHD adults. Those rules are inferred from the research above.

</details>

<details>
<summary><b>For contributors</b> (tests, benchmark)</summary>

* **Tests:** `tests/run-tests.sh` runs setup, migrate and uninstall in throwaway `HOME` folders with a fake `claude`. `tests/run-tests.sh migrate` runs one part.
* **Benchmark:** `bench/` runs 12 coding tasks with the default replies and with this format. See [bench/README.md](bench/README.md). No results published yet.
* **Known limits:** a path with a tab breaks the uninstall record. Interactive tests need macOS `script`.

</details>

MIT license. Copyright 2026 Hunter Zhang. See [LICENSE](LICENSE).

**Actionables**
! Run the install line above (~1 min)
