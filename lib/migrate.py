#!/usr/bin/env python3
"""Reformat an existing agent harness (CLAUDE.md, AGENTS.md, Cursor rules...) to the
answer-first reply format. Called by `setup.sh --migrate`.

  migrate.py has-project DIR        exit 0 if DIR holds agent instruction files
  migrate.py run [options]          detect, analyze, rewrite, diff, confirm, write

Only reply-format rules are in scope. Everything else is kept byte for byte:
* --no-llm adds the managed format block and lists conflicting lines to fix by hand.
* LLM mode also asks the user's own `claude -p` to delete or reconcile conflicting
  format rules, then checks that every non-format line survived.
Every write shows a unified diff first, needs a yes, makes a *.bak-<stamp> backup and
is recorded in the setup manifest so uninstall.sh can restore it.
"""
import argparse
import difflib
import glob
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers import BLOCK_RE, apply_block, atomic_copy  # noqa: E402

MIGRATED_NOTE = "<!-- Migrated by Claude-Code-Setup"
MAX_LLM_BYTES = 200_000     # larger files are not sent to the model
MAX_READ_BYTES = 5_000_000  # larger files are skipped entirely

# Files at the root of a project, and what kind of block they get.
PROJECT_FILES = [
    ("CLAUDE.md", "claude"),
    ("CLAUDE.local.md", "claude"),
    (".claude/CLAUDE.md", "claude"),
    ("AGENTS.md", "portable"),
    ("GEMINI.md", "portable"),
    (".github/copilot-instructions.md", "portable"),
    (".windsurfrules", "portable"),
    (".cursorrules", "portable"),
]
CURSOR_NEW = ".cursor/rules/claude-code-setup-format.mdc"
BLOCK_KINDS = {"claude", "portable", "portable-new"}
LABELS = {
    "claude": "Claude Code instructions",
    "portable": "other agent's instructions",
    "portable-new": "new Cursor rule",
    "import": "imported by CLAUDE.md",
    "style": "output style",
    "agent": "subagent",
    "command": "slash command",
    "cursor-rule": "Cursor rule",
}

FORMAT_RE = re.compile(
    r"\b(concise|brief|terse|verbose|succinct|wordy|length|shorter|longer|headings?|headers?|"
    r"bullets?|bullet points|numbered lists?|tables?|emojis?|tone|friendly|formal|casual|"
    r"summar(y|ies|ize|ise)|recap|preamble|sign[- ]?off|markdown|bold|italics?|formatting|"
    r"format your|respon(se|ses|d)|repl(y|ies)|paragraphs?|greeting|end (each|every|your|with))\b",
    re.I,
)
NEG = r"(never|don'?t|do not|avoid|no|without)\b"
CONFLICTS = [
    (re.compile(r"\b(end|finish|close|conclude|wrap)\w*\b.*\b(summar|recap)|\bsummar\w*\b.*\b(at|in) the end\b", re.I),
     "the target ends every reply with Actionables, not a summary"),
    (re.compile(NEG + r".*\btables?\b", re.I), "the target uses tables for options and metrics"),
    (re.compile(r"\b(use|add|include|with|love|lots of)\b.*\bemojis?\b|^[^a-z]*emojis? (are|is) (great|fine|welcome)", re.I),
     "the target uses plain glyphs (✓ ✗ ! … ○), never emoji"),
    (re.compile(NEG + r".*\b(bullets?|bullet points|lists?)\b", re.I), "the target uses bullets for 3+ parallel items"),
    (re.compile(NEG + r".*\b(headings?|headers?)\b", re.I), "the target uses short headings for multi-part replies"),
    (re.compile(r"\b(start|begin|open)\w*\b.*\b(restat\w*|summar\w*|context|background|greeting|acknowledg\w*)", re.I),
     "the target puts the answer on line 1"),
    (re.compile(r"\b(detailed|thorough|exhaustive|long|lengthy|verbose)\b.*\b(explanations?|answers?|responses?|replies)\b", re.I),
     "the target keeps chunks short and states outcomes"),
    (re.compile(r"\bplain (text|prose)\b|\bno markdown\b|\bwithout markdown\b", re.I),
     "the target uses markdown tables, bold and code"),
]
SECRET_PATTERNS = [
    ("Anthropic/OpenAI style key", re.compile(r"\bsk-[A-Za-z0-9_-]{16,}")),
    ("GitHub token", re.compile(r"\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}|\bgithub_pat_[A-Za-z0-9_]{20,}")),
    ("Slack token", re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}")),
    ("AWS access key", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("Google API key", re.compile(r"\bAIza[0-9A-Za-z_-]{30,}")),
    ("live API key", re.compile(r"\b[a-z]{2,10}_(live|test)_[A-Za-z0-9]{12,}")),
    ("private key", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("JWT", re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.")),
    ("key or password assignment",
     re.compile(r"(?i)\b(api[_-]?key|secret|token|passw(or)?d|bearer)\b[\"']?\s*[:=]\s*[\"']?[A-Za-z0-9_\-./+=]{12,}")),
]


# ---------- small utilities ----------
def read(path):
    with open(path, encoding="utf-8", errors="replace", newline="") as fh:
        return fh.read()


def unreadable(path):
    """Why a file cannot be migrated, or None."""
    if not os.path.exists(path):
        return None
    if not os.path.isfile(path):
        return "not a regular file"
    if os.path.getsize(path) > MAX_READ_BYTES:
        return f"larger than {MAX_READ_BYTES // 1_000_000} MB"
    with open(path, "rb") as fh:
        data = fh.read()
    if b"\0" in data:
        return "binary file"
    try:
        data.decode("utf-8")
    except UnicodeDecodeError:
        return "not UTF-8 text"
    return None


def block_inner(text):
    m = BLOCK_RE.search(text)
    if not m:
        return None
    lines = m.group(0).strip("\r\n").splitlines()
    return "\n".join(lines[1:-1])


def render(text, name):
    return text.replace("{{NAME_CAP}}", name[:1].upper() + name[1:]).replace("{{NAME}}", name)


def strip_frontmatter(text):
    if text.startswith("---\n"):
        end = text.find("\n---\n", 4)
        if end != -1:
            return text[end + 5:].lstrip("\n")
    return text


def with_block(text, block):
    return apply_block(text, block)


def sha(text):
    return hashlib.sha256(text.encode()).hexdigest()


def tilde(path):
    home = os.path.expanduser("~")
    return "~" + path[len(home):] if path.startswith(home + os.sep) else path


# ---------- detection ----------
def imports_of(path):
    """@path imports in a CLAUDE.md, resolved like Claude Code does (relative to the file)."""
    out = []
    for m in re.finditer(r"(?:^|\s)@((?:~|\.{1,2})?/?[\w.\-/]+\.md)\b", read(path)):
        p = os.path.expanduser(m.group(1))
        if not os.path.isabs(p):
            p = os.path.join(os.path.dirname(path), p)
        p = os.path.normpath(p)
        if os.path.isfile(p) and p not in out:
            out.append(p)
    return out


def detect_project(proj):
    found = []
    for rel, kind in PROJECT_FILES:
        p = os.path.join(proj, rel)
        if os.path.isfile(p):
            found.append(("project", kind, p))
    rules = os.path.join(proj, ".cursor", "rules")
    if os.path.isdir(rules):
        for p in sorted(glob.glob(os.path.join(rules, "*.md")) + glob.glob(os.path.join(rules, "*.mdc"))):
            if not p.endswith(CURSOR_NEW.split("/")[-1]):
                found.append(("project", "cursor-rule", p))
        found.append(("project", "portable-new", os.path.join(proj, CURSOR_NEW)))
    return found


def detect_user(claude_dir, skip):
    found = []
    md = os.path.join(claude_dir, "CLAUDE.md")
    if os.path.isfile(md):
        found.append(("user", "claude", md))
        found += [("user", "import", p) for p in imports_of(md)]
    for sub, kind in (("output-styles", "style"), ("agents", "agent"), ("commands", "command")):
        for p in sorted(glob.glob(os.path.join(claude_dir, sub, "**", "*.md"), recursive=True)):
            found.append(("user", kind, p))
    seen, out = set(), []
    for scope, kind, p in found:
        rp = os.path.realpath(p)
        if rp in seen or rp in skip or ".bak-" in p:
            continue
        seen.add(rp)
        out.append((scope, kind, p))
    return out


# ---------- analysis ----------
def analyze(text):
    """Return (format_lines, conflicts) as lists of (line_no, text[, reason]).
    Lines inside code fences and inside the managed block are ignored."""
    fmt, conflicts = [], []
    span = BLOCK_RE.search(text)
    block_lines = set()
    if span:
        a = text.count("\n", 0, span.start()) + 1
        b = text.count("\n", 0, span.end()) + 1
        block_lines = set(range(a, b + 1))
    fence = False
    lines = text.splitlines()
    front = set()
    if lines and lines[0].strip() == "---":  # YAML frontmatter is never a format rule
        for j in range(1, len(lines)):
            if lines[j].strip() == "---":
                front = set(range(1, j + 2))
                break
    for i, line in enumerate(lines, 1):
        if i in front:
            continue
        if line.lstrip().startswith("```"):
            fence = not fence
            continue
        if fence or i in block_lines or not line.strip():
            continue
        if FORMAT_RE.search(line):
            fmt.append((i, line))
            for rx, why in CONFLICTS:
                if rx.search(line):
                    conflicts.append((i, line.strip(), why))
                    break
    return fmt, conflicts


def find_secret(text):
    for i, line in enumerate(text.splitlines(), 1):
        for label, rx in SECRET_PATTERNS:
            if rx.search(line):
                return i, label
    return None


# ---------- LLM rewrite ----------
def call_llm(claude_bin, prompt):
    cmd = [claude_bin, "-p", "--output-format", "text", "--no-session-persistence", "--tools", ""]
    try:
        r = subprocess.run(cmd, input=prompt, capture_output=True, text=True, timeout=600)
    except (OSError, subprocess.TimeoutExpired) as e:
        return None, f"could not run {claude_bin}: {e}"
    if r.returncode != 0:
        return None, f"{claude_bin} -p exited {r.returncode}: {(r.stderr or r.stdout).strip()[:500]}"
    out = r.stdout
    m = re.search(r"<migrated_file>\n?(.*?)\n?</migrated_file>", out, re.S)
    if not m:
        return None, "the reply had no <migrated_file> section"
    changes = re.search(r"<changes>\n?(.*?)\n?</changes>", out, re.S)
    body = m.group(1)
    return (body if body.endswith("\n") else body + "\n", changes.group(1).strip() if changes else "", out), None


def restore_endings(original, migrated):
    """Give every line the model kept its original line ending (LF, CRLF, mixed);
    new lines get the file's most common ending."""
    ends = {}
    for raw in original.splitlines(True):
        body = raw.rstrip("\r\n")
        ends.setdefault(body, []).append(raw[len(body):] or "\n")
    crlf = original.count("\r\n")
    common = "\r\n" if crlf and crlf * 2 >= original.count("\n") else "\n"
    lines = migrated.replace("\r\n", "\n").split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    out = []
    for line in lines:
        q = ends.get(line)
        out.append(line + (q.pop(0) if q else common))
    return "".join(out)


def integrity(original, migrated):
    """Problems with the model's version. Only the lines analyze() flags as
    conflicting may change: each may be deleted or replaced in place by at most
    one reworded format rule. Every other line must come back once, byte for
    byte, in the same order. Nothing may be added anywhere else."""
    from collections import Counter
    orig = original.splitlines()
    changeable = {n for n, _, _ in analyze(original)[1]}
    want, slots, gap = [], [], 0  # slots[k] = conflict lines between want[k-1] and want[k]
    for i, ln in enumerate(orig, 1):
        if not ln.strip() or ln.startswith(MIGRATED_NOTE):
            continue
        if i in changeable:
            gap += 1
        else:
            slots.append(gap)
            want.append(ln)
            gap = 0
    slots.append(gap)
    keep = set(want)
    got, extra, bad_place = [], Counter(), []
    k = 0  # protected lines seen so far
    for ln in migrated.splitlines():
        if not ln.strip() or ln.startswith(MIGRATED_NOTE):
            continue
        if ln in keep and k < len(want) and ln == want[k]:
            got.append(ln)
            k += 1
        elif ln in keep:
            got.append(ln)  # out of order or duplicated, reported below
        elif FORMAT_RE.search(ln) and extra[k] < slots[k]:
            extra[k] += 1  # a reworded rule where a conflicting one stood
        else:
            bad_place.append(ln)
    problems = []
    cw, cg = Counter(want), Counter(got)
    lost = list((cw - cg).elements())
    dup = list((cg - cw).elements())
    if lost:
        problems.append((f"dropped {len(lost)} non-format line(s)", lost))
    if bad_place or dup:
        added = bad_place + dup
        problems.append((f"added {len(added)} line(s) that are not format rules or not in place of one", added))
    if not problems and got != want:
        problems.append(("moved non-format lines out of their order", []))
    return problems


# ---------- interaction ----------
class Ui:
    def __init__(self, yes, tty):
        self.yes, self.tty = yes, tty

    def ask(self, q, default=False):
        if self.yes:
            return default if default is not None else True
        if not self.tty:
            return False
        hint = "[Y/n]" if default else "[y/N]"
        try:
            with open("/dev/tty", "r+") as t:
                t.write(f"{q} {hint} ")
                t.flush()
                ans = t.readline().strip()
        except OSError:
            return False
        return default if not ans else ans.lower().startswith("y")


def record(manifest, path, bak, digest):
    os.makedirs(os.path.dirname(manifest), exist_ok=True)
    rows = read(manifest).splitlines() if os.path.exists(manifest) else []
    if any(r.split("\t")[:2] == ["migrate", path] for r in rows):
        return
    with open(manifest, "a") as fh:
        fh.write(f"migrate\t{path}\t{bak}\t{digest}\n")


# ---------- main run ----------
def run(a):
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    claude_block = render(read(os.path.join(repo, "templates", "CLAUDE.md.tmpl")), a.name)
    spec = strip_frontmatter(render(read(os.path.join(repo, "templates", "output-styles", "adhd-friendly.md.tmpl")), a.name))
    portable_block = ("# Reply format\n\n"
                      "Added by Claude-Code-Setup so agents other than Claude Code follow the same format.\n\n"
                      + spec)
    cursor_head = "---\ndescription: Reply format from Claude-Code-Setup\nalwaysApply: true\n---\n"
    prompt_tmpl = read(os.path.join(repo, "templates", "migrate-prompt.md"))
    manifest = os.path.join(a.state_dir, "manifest.tsv")
    checked_path = os.path.join(a.state_dir, "migrate-checked.json")
    checked = json.loads(read(checked_path)) if os.path.exists(checked_path) else {}
    ui = Ui(a.yes, a.tty)

    skip = {os.path.realpath(os.path.join(a.claude_dir, p))
            for p in ("output-styles/adhd-friendly.md", "commands/worked-hours.md", "RTK.md")}
    files = detect_user(a.claude_dir, skip)
    if a.project:
        files += detect_project(os.path.abspath(a.project))
    seen, unique = set(), []
    for f in files:  # AGENTS.md is often a symlink to CLAUDE.md: handle each real file once
        rp = os.path.realpath(f[2])
        if rp not in seen:
            seen.add(rp)
            unique.append(f)
    files = unique

    print("Found:")
    if not files:
        print("○ no agent instruction files, nothing to migrate")
        return 0
    for scope, kind, p in files:
        state = "" if os.path.exists(p) else " (would be created)"
        print(f"  {scope:7} {LABELS[kind]:28} {tilde(p)}{state}")

    portable = [f for f in files if f[1] in ("portable", "portable-new")]
    portable_ok = False
    if portable:
        portable_ok = ui.ask(f"Add the reply format as a portable block to {len(portable)} file(s) other agents "
                             f"read (output styles only work in Claude Code)?", True)
        if not portable_ok:
            print("○ portable blocks skipped")

    llm = a.mode == "llm"
    pin_dir = None
    if llm:
        pin_dir = tempfile.mkdtemp(prefix="ccs-migrate-") if a.dry_run else os.path.join(a.state_dir, f"migrate-{a.stamp}")
        os.makedirs(pin_dir, exist_ok=True)

    todo_conflicts, written, declined = [], 0, 0
    for scope, kind, path in files:
        label = tilde(path)
        if kind in ("portable", "portable-new") and not portable_ok:
            continue
        why = unreadable(path)
        if why:
            print(f"\n! skipped {label}: {why}")
            continue
        text = read(path) if os.path.exists(path) else ""
        fmt, conflicts = analyze(text)
        secret = find_secret(text)
        new = text
        model_noop = False  # the model found no format rule to change
        print(f"\n{label}  ({LABELS[kind]}: {len(fmt)} format line(s), {len(conflicts)} conflict(s))")

        if llm and conflicts and kind != "portable-new":
            if secret:
                print(f"! not sent to the model: line {secret[0]} looks like a {secret[1]}. Block only, fix conflicts by hand.")
            elif len(text.encode()) > MAX_LLM_BYTES:
                print(f"! not sent to the model: larger than {MAX_LLM_BYTES // 1000} KB. Block only, fix conflicts by hand.")
            elif MIGRATED_NOTE in text:
                print("○ already migrated, model not called")
            elif checked.get(os.path.realpath(path)) == sha(text):
                print("○ checked before with no conflicts, model not called")
            else:
                body = BLOCK_RE.sub("\n", text).rstrip("\r\n") + "\n" if BLOCK_RE.search(text) else text
                bom = body.startswith("\ufeff")
                sent = body[1:] if bom else body  # the model never sees (or drops) a BOM
                allowed = "\n".join(f"- line {n}: {ln}" for n, ln, _ in analyze(sent)[1])
                prompt = (prompt_tmpl.replace("{{FORMAT_SPEC}}", spec).replace("{{FILE_PATH}}", label)
                          .replace("{{FILE_KIND}}", LABELS[kind]).replace("{{CONFLICT_LINES}}", allowed)
                          .replace("{{FILE_CONTENT}}", sent))
                print(f"… asking {a.claude_bin} -p to reconcile the format rules")
                res, err = call_llm(a.claude_bin, prompt)
                if err:
                    print(f"✗ model step failed, falling back to block only: {err}")
                else:
                    migrated, changes, raw = res
                    pin = os.path.join(pin_dir, re.sub(r"[^A-Za-z0-9._-]", "_", label.strip("~/.")))
                    with open(pin + ".migrated", "w") as fh:
                        fh.write(migrated)
                    with open(pin + ".reply.txt", "w") as fh:
                        fh.write(raw)
                    print(f"✓ model output pinned at {pin}.migrated")
                    if changes:
                        print("  Model's changes:\n" + "\n".join("    " + c for c in changes.splitlines()))
                    migrated = restore_endings(sent, migrated)
                    problems = integrity(sent, migrated)
                    for what, lines in problems:
                        print(f"✗ the model {what}" + (":" if lines else ""))
                        for line in lines[:20]:
                            print(f"    {line}")
                    if problems:
                        if a.yes or not ui.ask("  Use the model's version anyway?", False):
                            print("○ model version rejected, block only")
                            migrated = None
                    if migrated is not None:
                        model_noop = migrated == sent
                        new = ("\ufeff" if bom else "") + migrated
                        if BLOCK_RE.search(text):
                            new = with_block(new, block_inner(text))
                        conflicts = analyze(new)[1]

        if kind in BLOCK_KINDS and not BLOCK_RE.search(new):
            if kind == "claude":
                new = with_block(new, claude_block)
            elif kind == "portable":
                new = with_block(new, portable_block)
            else:
                new = cursor_head + "\n" + with_block("", portable_block)

        for n, line, why in conflicts:
            todo_conflicts.append((label, n, line, why))

        if new == text:
            if model_noop and not a.dry_run:
                checked[os.path.realpath(path)] = sha(text)
            print("○ unchanged")
            continue
        diff = difflib.unified_diff(text.splitlines(True), new.splitlines(True),
                                    fromfile=f"{label} (now)", tofile=f"{label} (migrated)")
        for d in diff:  # secrets stay out of terminal logs too
            for _, rx in SECRET_PATTERNS:
                d = rx.sub("[redacted]", d)
            sys.stdout.write(d if d.endswith("\n") else d + "\n")
        if a.dry_run:
            print("… dry run, not written")
            continue
        if os.path.exists(path) and not os.access(path, os.W_OK):
            print(f"! skipped {label}: it is read-only")
            declined += 1
            continue
        if not ui.ask(f"Write {label}?", True if a.yes else False):
            print("○ skipped" + ("" if ui.tty or ui.yes else " (no terminal: re-run with --yes to write)"))
            declined += 1
            continue
        bak = "NONE"
        if os.path.exists(path):
            bak = f"{path}.bak-{a.stamp}"
            shutil.copy2(path, bak)
        else:
            os.makedirs(os.path.dirname(path), exist_ok=True)
        fd, tmp = tempfile.mkstemp(prefix="ccs-migrate-")
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as fh:
            fh.write(new)
        record(manifest, path, bak, sha(new))
        try:
            atomic_copy(tmp, path)
        finally:
            os.remove(tmp)
        written += 1
        if model_noop:
            checked[os.path.realpath(path)] = sha(new)
        print(f"✓ wrote {label}" + (f" (backup: {tilde(bak)})" if bak != "NONE" else " (new file)"))

    if checked and not a.dry_run:
        os.makedirs(a.state_dir, exist_ok=True)
        with open(checked_path, "w") as fh:
            json.dump(checked, fh, indent=1)

    print()
    if todo_conflicts:
        print(f"! {len(todo_conflicts)} format rule(s) conflict with the new format. Resolve them by hand:")
        for label, n, line, why in todo_conflicts:
            print(f"  {label}:{n}: {line}\n      ({why})")
    else:
        print("✓ no conflicting format rules left")
    print(f"Migrate: {written} file(s) written, {declined} skipped" + (" (dry run)" if a.dry_run else ""))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["run", "has-project"])
    ap.add_argument("dir", nargs="?")
    ap.add_argument("--claude-dir")
    ap.add_argument("--state-dir")
    ap.add_argument("--project", default="")
    ap.add_argument("--mode", choices=["llm", "no-llm"], default="no-llm")
    ap.add_argument("--name", default="the user")
    ap.add_argument("--stamp", default="manual")
    ap.add_argument("--claude-bin", default="claude")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--yes", action="store_true")
    ap.add_argument("--tty", action="store_true")
    a = ap.parse_args()
    if a.cmd == "has-project":
        return 0 if a.dir and [f for f in detect_project(a.dir) if os.path.exists(f[2])] else 1
    if not a.claude_dir or not a.state_dir:
        sys.exit("error: run needs --claude-dir and --state-dir")
    return run(a)


if __name__ == "__main__":
    sys.exit(main())
