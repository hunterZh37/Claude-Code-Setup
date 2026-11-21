#!/usr/bin/env python3
"""Generate the plugin's files from templates/, so the plugin never forks them.

  python3 lib/build-plugin.py           write plugin/ files
  python3 lib/build-plugin.py --check   exit 1 if plugin/ is out of date

The plugin is the repository root (see .claude-plugin/), so its commands call
setup.sh, lib/ and templates/ in place through ${CLAUDE_PLUGIN_ROOT}.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME = "the user"  # a plugin can't ask for a name at install. /adhd-friendly:setup personalizes


def render(path):
    text = open(os.path.join(ROOT, path), encoding="utf-8").read()
    return text.replace("{{NAME_CAP}}", NAME[:1].upper() + NAME[1:]).replace("{{NAME}}", NAME)


def outputs():
    style = render("templates/output-styles/adhd-friendly.md.tmpl")
    return {
        "plugin/output-styles/adhd-friendly.md": style,
    }


def main():
    check = "--check" in sys.argv
    stale = []
    for rel, text in outputs().items():
        path = os.path.join(ROOT, rel)
        current = open(path, encoding="utf-8").read() if os.path.exists(path) else None
        if current != text:
            stale.append(rel)
            if not check:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, "w", encoding="utf-8") as fh:
                    fh.write(text)
    if check and stale:
        print("out of date, run python3 lib/build-plugin.py: " + ", ".join(stale), file=sys.stderr)
        return 1
    for rel in stale:
        print(f"wrote {rel}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
