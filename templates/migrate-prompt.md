You are migrating one instruction file of an AI coding assistant to a new reply format.
Work only on the text between <file> tags. You have no tools. Output only the result.

## Target reply format

<format_spec>
{{FORMAT_SPEC}}
</format_spec>

## The file

Path: {{FILE_PATH}}
Kind: {{FILE_KIND}}

<file>
{{FILE_CONTENT}}
</file>

## What to do

1. Sort every rule in the file into one of two groups.
   * **Format rules** say how replies look or sound: length, conciseness, headings,
     bullets, tables, bold, emoji, tone, greetings, openings, endings, summaries, recaps.
   * **Everything else**: project facts, commands, paths, workflows, coding conventions,
     testing, safety and permission rules, tool usage, frontmatter.
2. Keep everything else byte-for-byte. Same words, order, headings, whitespace and code
   blocks. Never fix typos, reword or reorder it.
3. You may change only these lines, which conflict with the target format. Every
   other line must come back exactly as it is, even if it looks like a format rule:

{{CONFLICT_LINES}}

   For each of them, using the target's priority order:
   * Delete a format rule that contradicts the target (for example "end every reply
     with a summary", "never use tables", "use emoji").
   * Reword a format rule that partly fits so it agrees with the target.
   * Keep format rules that already agree, or that only add detail the target lacks.
   * Do not paste the target format into the file. It is installed separately.
4. If you changed anything, add this one line at the very end of the file:
   `<!-- Migrated by Claude-Code-Setup: reply-format rules reconciled, see .bak file for the original -->`
   If nothing conflicts, return the file unchanged with no note.
5. Never add secrets, URLs or facts that are not in the file.

## Output

Return the complete migrated file between <migrated_file> and </migrated_file> tags,
then a list of the format rules you deleted or reworded between <changes> and </changes>
tags, one per line as "deleted: <old text>" or "reworded: <old text> -> <new text>".
Nothing else.
