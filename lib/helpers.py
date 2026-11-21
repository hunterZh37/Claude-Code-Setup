#!/usr/bin/env python3
"""Small text helpers for setup.sh and uninstall.sh.

  helpers.py render SRC OUT NAME        fill {{NAME}} and {{NAME_CAP}}
  helpers.py block-apply FILE BLOCK OUT write FILE with the managed block set to BLOCK
  helpers.py block-remove FILE OUT      write FILE without the managed block
  helpers.py has-outside FILE TEXT      exit 0 if TEXT appears outside the managed block
"""
import os
import re
import sys

BEGIN = "<!-- claude-code-setup:begin (managed by setup.sh, edits inside are replaced) -->"
END = "<!-- claude-code-setup:end -->"
BLOCK_RE = re.compile(r"\n*<!-- claude-code-setup:begin[^\n]*-->\n.*?<!-- claude-code-setup:end -->\n?", re.S)


def read(path):
    if not os.path.exists(path):
        return ""
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def write(path, text):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def main(argv):
    cmd = argv[1]
    if cmd == "render":
        src, out, name = argv[2], argv[3], argv[4]
        cap = name[:1].upper() + name[1:]
        write(out, read(src).replace("{{NAME_CAP}}", cap).replace("{{NAME}}", name))
    elif cmd == "block-apply":
        path, block, out = argv[2], read(argv[3]).strip("\n"), argv[4]
        text = read(path)
        managed = f"{BEGIN}\n{block}\n{END}\n"
        if BLOCK_RE.search(text):
            lead = "\n\n" if BLOCK_RE.search(text).start() > 0 else ""
            new = BLOCK_RE.sub(lambda m: lead + managed, text, count=1)
        elif text.strip():
            new = text.rstrip("\n") + "\n\n" + managed
        else:
            new = managed
        write(out, new)
    elif cmd == "block-remove":
        path, out = argv[2], argv[3]
        text = BLOCK_RE.sub("\n", read(path))
        text = text.strip("\n")
        write(out, text + "\n" if text else "")
    elif cmd == "has-outside":
        text = BLOCK_RE.sub("\n", read(argv[2]))
        return 0 if argv[3] in text else 1
    else:
        print(f"unknown command {cmd}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
