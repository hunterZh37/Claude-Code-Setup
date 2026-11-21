#!/usr/bin/env python3
"""Small text helpers for setup.sh and uninstall.sh.

  helpers.py render SRC OUT NAME        fill {{NAME}} and {{NAME_CAP}}
  helpers.py block-apply FILE BLOCK OUT write FILE with the managed block set to BLOCK
  helpers.py block-remove FILE OUT      write FILE without the managed block
  helpers.py has-outside FILE TEXT      exit 0 if TEXT appears outside the managed block
  helpers.py hash FILE                  print a sha256 of FILE ("-" if missing)
  helpers.py write SRC DEST             atomically replace DEST (through symlinks) with SRC
  helpers.py is-text FILE               exit 0 if FILE is UTF-8 text (no NUL bytes)
"""
import hashlib
import os
import re
import shutil
import sys
import tempfile

BEGIN = "<!-- claude-code-setup:begin (managed by setup.sh, edits inside are replaced) -->"
END = "<!-- claude-code-setup:end -->"
# Tolerates CRLF files and older begin-marker wording.
BLOCK_RE = re.compile(
    r"(?:\r?\n)*<!-- claude-code-setup:begin[^\n]*-->\r?\n.*?<!-- claude-code-setup:end -->(?:\r?\n)?", re.S)


def read(path):
    if not os.path.exists(path):
        return ""
    with open(path, encoding="utf-8", errors="surrogateescape", newline="") as fh:
        return fh.read()


def write(path, text):
    with open(path, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
        fh.write(text)


def atomic_copy(src, dest):
    """Replace dest with src via a temp file + rename in the same folder, so an
    interrupt never leaves a half-written file. A symlink is followed, not replaced."""
    real = os.path.realpath(dest)
    d = os.path.dirname(real)
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".ccs-tmp-")
    os.close(fd)
    try:
        shutil.copyfile(src, tmp)
        if os.path.exists(real):
            shutil.copymode(real, tmp)
        os.replace(tmp, real)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)


def apply_block(text, block):
    nl = "\r\n" if "\r\n" in text else "\n"
    managed = nl.join([BEGIN] + block.strip("\r\n").splitlines() + [END]) + nl
    matches = list(BLOCK_RE.finditer(text))
    if matches:
        lead = nl * 2 if matches[0].start() > 0 else ""
        out, pos = [], 0
        for i, m in enumerate(matches):  # keep the first spot, drop duplicates
            out.append(text[pos:m.start()])
            if i == 0:
                out.append(lead + managed)
            elif m.start() > 0 and m.end() < len(text):
                out.append(nl)  # keep the line break the dropped block sat between
            pos = m.end()
        out.append(text[pos:])
        return "".join(out)
    if text.strip():
        return text.rstrip("\r\n") + nl * 2 + managed
    return managed


def remove_block(text):
    nl = "\r\n" if "\r\n" in text else "\n"
    text = BLOCK_RE.sub(nl, text).strip("\r\n")
    return text + nl if text else ""


def main(argv):
    cmd = argv[1]
    if cmd == "render":
        src, out, name = argv[2], argv[3], argv[4]
        cap = name[:1].upper() + name[1:]
        write(out, read(src).replace("{{NAME_CAP}}", cap).replace("{{NAME}}", name))
    elif cmd == "block-apply":
        write(argv[4], apply_block(read(argv[2]), read(argv[3])))
    elif cmd == "block-remove":
        write(argv[3], remove_block(read(argv[2])))
    elif cmd == "has-outside":
        return 0 if argv[3] in BLOCK_RE.sub("\n", read(argv[2])) else 1
    elif cmd == "hash":
        p = argv[2]
        if os.path.isfile(p):
            with open(p, "rb") as fh:
                print(hashlib.sha256(fh.read()).hexdigest())
        else:
            print("-")
    elif cmd == "write":
        atomic_copy(argv[2], argv[3])
    elif cmd == "is-text":
        p = argv[2]
        if not os.path.exists(p):
            return 0
        if not os.path.isfile(p):
            return 1
        with open(p, "rb") as fh:
            data = fh.read()
        if b"\0" in data:
            return 1
        try:
            data.decode("utf-8")
        except UnicodeDecodeError:
            return 1
        return 0
    else:
        print(f"unknown command {cmd}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
