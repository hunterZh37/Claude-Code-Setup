# Claude Code Setup

One script that turns a fresh [Claude Code](https://code.claude.com/docs/en/overview) install into a fast, readable setup. Replies lead with the answer, use glyphs, tables and bars you can read in place, and always end with what you need to do.

## Who it's for

* **People with ADHD**, or anyone who wants to decide fast without wading through prose.
* **New Mac users** setting up Claude Code for the first time. Linux works for everything except the Homebrew casks.
* **Heavy subagent users**, since the rules also shape how subagents report back.

## What a reply looks like

You ask: "should we cache the API answers?"

**Before** (default style):

```
Good question! There are a few ways we could approach caching here. One option
would be to add a time-to-live of about an hour, which is simple but means answers
could be stale. Another would be to version the cache keys so entries are replaced
on deploy. We could also leave it as is. Let me know which you'd prefer!
```

**After** (`adhd-friendly` style):

```
Recommend: version the cache keys, because entries never go stale and no deploy hook is needed.

| Option         | Gain        | Cost   | Undo? |
|----------------|-------------|--------|-------|
| Version keys ← | never stale | 10 min | yes   |
| 1 h TTL        | simplest    | 5 min  | yes   |
| Do nothing     | none        | 0      | n/a   |

Say go and I start.

**Actionables**
! Reply "go", or name another row (~10 s)
```

A build reply looks like this:

```
✓ Date filter added to search results.

✗ **Share link** drops the filter, fixing next
✓ **Filter** works on desktop and mobile

**Done:** filter + 3 tests
**Check:** `npm test` 41/41 pass
**Next:** keep the filter in share links

Actionables: None
```

## Install

**One line** (asks what to install):

```bash
git clone https://github.com/hunterZh37/Claude-Code-Setup.git ~/Claude-Code-Setup && ~/Claude-Code-Setup/setup.sh
```

**Manual**, picking components with flags:

```bash
git clone https://github.com/hunterZh37/Claude-Code-Setup.git
cd Claude-Code-Setup
./setup.sh --dry-run --format --commands --plugins   # preview, writes nothing
./setup.sh --format --commands --plugins --name Sam
```

Needs `bash` and `python3` 3.8 or newer (macOS: `xcode-select --install`). `--tools` also needs [Homebrew](https://brew.sh).

### Flags

| Flag | Does |
|---|---|
| `--format` | Output style + core rules in `~/.claude/CLAUDE.md` |
| `--commands` | `/worked-hours` command and its script |
| `--plugins` | progress-bar plugin. Asks about the extras |
| `--extra-plugins` | Also enables official `frontend-design` and `mattpocock-skills` |
| `--rtk` | Token-saving note for Claude. Needs `rtk`, which you install |
| `--tools` | Brewfile tools and Claude Code |
| `--migrate` | Reformat your existing CLAUDE.md, AGENTS.md and Cursor, Copilot, Gemini or Windsurf rules. See [Migrate](#migrate-an-existing-setup) |
| `--no-llm` | Migrate without a model: add the block, list conflicts |
| `--project PATH` | Also migrate that project's agent files |
| `--all` | format, commands, plugins, rtk and tools (not migrate) |
| `--name NAME` | Who reads the replies. Default "the user" |
| `--yes` | Accept defaults, never prompt |
| `--force-style` | Set `outputStyle` even if you picked another one |
| `--dry-run` | Show every change, make none |

## Components

| Component | Installs | What it does |
|---|---|---|
| **Reply format** | `~/.claude/output-styles/adhd-friendly.md`, a block in `~/.claude/CLAUDE.md`, `outputStyle` in settings | The style sets the full reply format. The CLAUDE.md block repeats the 4 core rules, because output styles never reach subagents and CLAUDE.md does |
| **Subagent rules** | part of the CLAUDE.md block | Subagents report with ✓ or ✗ on line 1, glyph rows, verbatim errors and Actionables. The main agent rewrites them into your format |
| **Commands** | `~/.claude/commands/worked-hours.md`, `~/.claude/scripts/workday-hours.py` | `/worked-hours` reads every Claude Code transcript for a day, merges them into activity blocks and asks you to confirm the hours. `--prefix ~/work` counts only work projects |
| **Plugins** | `enabledPlugins` and `extraKnownMarketplaces` in settings | [progress-bar](https://github.com/hunterZh37/progress-bar-plugin) shows live bars for subagents and long jobs in the status line and a side panel. It sets up its own status line |
| **rtk** | `~/.claude/RTK.md`, imported from CLAUDE.md | Tells Claude that [rtk](https://github.com/rtk-ai/rtk) condenses command output, so it trusts the short form and batches commands |
| **Migrate** | edits your existing agent files, after a diff and a yes | Removes or rewords reply-format rules that fight this format and adds the format block. See below |
| **Tools** | `Brewfile` | `gh`, `jq`, `ripgrep`, `fd`, `uv` and the Ghostty terminal, plus Claude Code from the [official installer](https://code.claude.com/docs/en/setup) |

### How the script stays safe

* **Idempotent.** Unchanged files are skipped. A second run changes nothing.
* **Backups.** Any file it replaces is first copied to `<file>.bak-<timestamp>`.
* **Settings are merged.** Keys you already set are kept. `outputStyle` changes only if it is unset, you confirm, or you pass `--force-style`.
* **CLAUDE.md is shared.** Your own text stays. The rules live between `claude-code-setup:begin` and `end` markers, and only that block is rewritten.
* **No silent binaries.** rtk and herdr are linked, never downloaded. Claude Code installs only after you say yes.

## After install

Steps only you can do. The script prints them too.

| Step | How |
|---|---|
| **Sign in** | Run `claude` and follow the login prompt |
| **GitHub** | `gh auth login` |
| **Browser** | Install [Claude in Chrome](https://claude.ai/chrome) (optional) |
| **rtk** | Install it, run `rtk init -g`, then `./setup.sh --rtk --format` |
| **Plugins** | Accept the marketplace prompt on first start, or `/plugin install progress-bar@progress-bar` |
| **Restart** | Quit and reopen Claude Code so the output style loads |
| **Verify** | Run `/output-style` and check `adhd-friendly` is selected |

## Migrate an existing setup

Already have rules for Claude Code or another agent? `--migrate` brings them in line with this format. Only reply-format rules change (length, headings, bullets, tables, emoji, tone, openings, endings, summaries). Project facts, commands, workflows, coding conventions and safety rules stay byte for byte.

```bash
./setup.sh --migrate --dry-run --project ~/code/my-app   # see every diff first
./setup.sh --migrate --project ~/code/my-app
./setup.sh --migrate --no-llm                            # no model, block + conflict list
```

**What it looks at**

| Scope | Files |
|---|---|
| **You** | `~/.claude/CLAUDE.md` and its `@imports`, `output-styles/`, `agents/`, `commands/` |
| **Project** | `CLAUDE.md`, `CLAUDE.local.md`, `AGENTS.md`, `GEMINI.md`, `.cursorrules`, `.cursor/rules/`, `.github/copilot-instructions.md`, `.windsurfrules` |

Project files are touched only with `--project` or when you say yes to the prompt.

**How it works**

1. **Detect** the files above and list them.
2. **Analyze** each one and list the format rules that clash with this format.
3. **Rewrite.** Your own `claude -p` (no tools, nothing saved) gets the file and the format spec. It may delete or reword only the lines listed as clashing, and adds a one-line "Migrated by Claude-Code-Setup" note. Its output is pinned in `~/.claude/.claude-code-setup/migrate-<time>/` so you can diff it.
4. **Check.** Every other line must come back once, byte for byte and in the same order, with its own line ending. Frontmatter is never touched. If the model drops, moves, duplicates, edits or invents a line, its version is rejected.
5. **Add the block.** Claude Code files get the 4 core rules. Files for other agents get the full format as a portable markdown block, because output styles only work in Claude Code. Cursor gets a new `.cursor/rules/claude-code-setup-format.mdc`.
6. **Confirm.** You see a unified diff per file and answer y or N (or pass `--yes`). Each changed file is backed up and `./uninstall.sh` restores it.

**Never sent to a model:** files that look like they hold a key, token or password, files over 200 KB and binary files. They get the block only, and the reason is printed.

**Example**

Before, `CLAUDE.md`:

```
- Be friendly and use emoji to keep things fun.
- Never use tables, write prose instead.
- Always end with a summary of what you did.
- Run `npm test` before every commit.
- Never push to main without asking.
```

After:

```
- Run `npm test` before every commit.
- Never push to main without asking.
<!-- Migrated by Claude-Code-Setup: reply-format rules reconciled, see .bak file for the original -->

<!-- claude-code-setup:begin ... -->
# Replies to Sam
...the 4 core rules...
<!-- claude-code-setup:end -->
```

With `--no-llm` the file keeps all five lines, gets the block, and the run prints the three clashing lines for you to fix:

```
! 3 format rule(s) conflict with the new format. Resolve them by hand:
  ~/.claude/CLAUDE.md:1: - Be friendly and use emoji to keep things fun.
      (the target uses plain glyphs (✓ ✗ ! … ○), never emoji)
```

## Customize

* **Your name:** re-run with `--name Sam`. The block and style are re-rendered.
* **Rules:** edit `templates/` in this repo and re-run, or edit `~/.claude/output-styles/adhd-friendly.md` directly. Text outside the managed block in `CLAUDE.md` is never touched.
* **Logging hours:** `/worked-hours` stops at a confirmed number. Add a Step 4 to `~/.claude/commands/worked-hours.md` to append it to a spreadsheet or doc.
* **Optional extras:** [herdr](https://herdr.dev) is a terminal workspace for coding agents that pairs with the progress-bar panel. Install it from its site if you want it.

## Compare formats (optional)

`bench/` is an A/B harness that runs the same 12 coding tasks with Claude Code's default replies and with this format, then counts words before the answer and before your action. It uses your own `claude` login. See [bench/README.md](bench/README.md). No results are published yet.

## Uninstall

```bash
./uninstall.sh --dry-run   # preview
./uninstall.sh
```

It restores every file setup replaced from its backup, deletes files setup created, removes the CLAUDE.md block and removes only the settings keys setup added (if you changed one since, it is left alone). Backups are kept.

## Tests

```bash
tests/run-tests.sh
```

Runs setup, migrate and uninstall against throwaway `HOME` folders, with a fake `claude` for the model step, so it never calls a model. Parts: `core` (install, re-run, uninstall, hours script), `migrate`, `stress` (no python or brew, Linux, zsh, spaces and unicode in paths, symlinks, read-only files, interrupts, broken settings, CRLF, duplicate blocks) and `bench` (the harness, stubbed). `tests/run-tests.sh migrate` runs one part. It runs `shellcheck` when installed.

**Known limits:** a path containing a tab breaks the uninstall record. `--prefix` in the hours script matches folder names, so `~/my-app` also counts `~/my/app`. The interactive tests need macOS `script` and are skipped elsewhere.

## Why the format looks like this

The rules come from a review of perception, decision and instruction-following research. Short version:

| Rule | Basis | Source |
|---|---|---|
| **Answer and a pick first** | Defaults shift choices (d ≈ 0.68). People defer when no option clearly wins | [Jachimowicz et al. 2019](https://www.cambridge.org/core/journals/behavioural-public-policy/article/when-and-why-defaults-influence-decisions-a-metaanalysis-of-default-effects/67AF6972CC2ECA3D9B5D3B0FA7AE2F0F), [Dhar 1997](https://bear.warrington.ufl.edu/brenner/mar7588/Papers/dhar-jcr1997.pdf) |
| **Glyph status rows** | A ✗ among ✓ is found without reading (pre-attentive pop-out) | [Cleveland and McGill, summary](https://info3312.infosci.cornell.edu/ae/graphical-perception.html) |
| **Bars for amounts** | Length on a common scale is read more accurately than angle or area | [Cleveland and McGill, summary](https://info3312.infosci.cornell.edu/ae/graphical-perception.html) |
| **Tables for exact values** | Tables win for exact lookup, graphs for patterns (cognitive fit) | [Vessey and Galletta 1991](https://ideas.repec.org/a/inm/orisre/v2y1991i1p63-84.html) |
| **Read in place** | ADHD affects visuospatial working memory more than verbal, so visuals must sit beside their numbers | [Martinussen et al. 2005](https://pubmed.ncbi.nlm.nih.gov/15782085/) |
| **Short chunks** | Working memory holds about 4 chunks | [Cowan 2001](https://pubmed.ncbi.nlm.nih.gov/11515286/) |
| **Startable actions** | If-then plans tied to a cue help follow-through (d = 0.65), including in ADHD | [Gawrilow et al. 2011](https://www.socmot.uni-konstanz.de/sites/default/files/Gawrilow_Gollwitzer_Oettingen_Executive_Function_JSCP_2011.pdf) |
| **Few rules, no conflicts** | Compliance drops as instructions multiply, with early ones favored | [IFScale 2025](https://arxiv.org/abs/2507.11538), [Lost in the Middle](https://aclanthology.org/2024.tacl-1.9/) |
| **Two examples** | Examples are one of the most reliable ways to steer format | [Anthropic prompting guide](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices) |
| **Rules in two places** | Output styles skip subagents, CLAUDE.md reaches them | [Output styles](https://code.claude.com/docs/en/output-styles), [Subagents](https://code.claude.com/docs/en/sub-agents) |

**Evidence gap:** no study tests terminal glyphs or AI reply formats with ADHD adults. Those rules are inferred from the general research above.

## What's not included

| Left out | Why |
|---|---|
| **Secrets** | No API keys, tokens, `env` or plugin config values. Sign in yourself after install |
| **Memory, transcripts, progress files** | Personal history, not setup |
| **Session restart helpers** | Tied to one person's terminal wrappers |
| **Organization skills and project rules** | Specific to one workplace |
| **Doc logging for hours** | Tied to one planner document. See Customize to add your own |
| **Binaries** | rtk and herdr are linked to their official installers |

## License

MIT. Copyright 2026 Hunter Zhang. See [LICENSE](LICENSE).
