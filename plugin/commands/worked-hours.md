---
description: Summarize today's worked hours from Claude Code transcripts and confirm them
argument-hint: "[YYYY-MM-DD] [--prefix PATH]"
allowed-tools: Bash, AskUserQuestion
---

Summarize the hours worked on a day, computed from Claude Code transcripts, and confirm
the figure with the user.

Arguments (all optional): `$ARGUMENTS`
- A `YYYY-MM-DD` token is the day. Defaults to today in local time.
- `--prefix PATH` counts only projects under that folder (for example `~/work`).

## Step 1. Compute the hours

Never guess or estimate hours. Derive them from the transcripts:

```
python3 -I "${CLAUDE_PLUGIN_ROOT}/templates/scripts/workday-hours.py" $ARGUMENTS
```

It prints the day's activity blocks (split on gaps over 20 minutes), ACTIVE hours,
WALL hours, and a suggested figure rounded to the nearest quarter hour.

If it reports no activity, stop and say so. Do not invent a number.

## Step 2. Summarize

Show the blocks as status rows, then a short bullet list of what was accomplished
today, drawn from this session's work. Keep it factual.

## Step 3. Confirm

Ask which figure is right using AskUserQuestion, offering the suggested value first,
then ACTIVE and WALL. Report the confirmed figure on line 1.

## Optional extension

To log the confirmed hours somewhere (a spreadsheet, a Google Doc, an invoice file),
add a Step 4 here that writes one row with the date, hours and the summary. Re-read
the target first and never write a row for a date that already has one.
