#!/usr/bin/env python3
"""Inventory every dialogue text in the tree: vanilla, Gen 2 port, or new.

Each text body (the text/line/cont/para/next/page strings under one label) is
compared, as a word stream so rewrapping doesn't hide a match, against:
  - vanilla Red/Blue: the pret tree this project forked from (`git archive
    6f5265e0^`, the parent of the first project commit)
  - Gen 2: tmp/pokegold (Gold only; Crystal-only lines read as NEW)

Status:
  VANILLA         same words as a vanilla text (possibly moved or rewrapped)
  VANILLA-EDITED  most of its word trigrams come from one vanilla text
  GEN2            same words as a pokegold text
  GEN2-EDITED     most of its word trigrams come from one pokegold text
  NEW             none of the above

AI provenance (`--claude-logs`, `--codex-logs`) is by RECORD, not style: a
string is tagged when a Claude Code Edit/Write or a Codex apply_patch ADDED a
line carrying it (Edit context lines that were already there don't count).
Logs only reach back as far as they were kept, and text an AI wrote through a
generator script isn't visible, so an untagged string is "author unknown",
never "human". Style-based AI detection doesn't work on two-line strings.

  python tools/text_inventory.py --vanilla DIR [--gen2 tmp/pokegold]
      [--claude-logs ~/.claude/projects] [--codex-logs ~/.codex/sessions]
      --out-md TEXT_INVENTORY.md --out-csv TEXT_INVENTORY.csv
"""
import argparse
import csv
import json
import re
import subprocess
import time
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCAN_DIRS = ("text", "data", "scripts", "engine", "home", "custom_functions")
KW = r"(text|line|cont|para|next|page)"
STR_LINE = re.compile(r'^\s*' + KW + r'\s+"(.*)"\s*(?:;.*)?$')
RAM_LINE = re.compile(r"^\s*text_(?:ram|decimal|bcd)\s+(\w+)")
END_LINE = re.compile(r"^\s*(done|prompt|text_end|text_promptbutton)\b")
GLOBAL_LABEL = re.compile(r"^\s*([A-Za-z_]\w*)::?")
LOCAL_LABEL = re.compile(r"^\s*(\.\w+):{0,2}\s*(?:;.*)?$")
CODEX_PATCH_LITERAL = re.compile(r'apply_patch\(\s*"((?:[^"\\]|\\.)*)"')
CODEX_PATCH_TEMPLATE = re.compile(r"apply_patch\(\s*`([^`]*)`")
PLACEHOLDER = re.compile(r"(?i)insert|\btodo\b|\btbd\b|placeholder|lorem|fixme|text here|\?\?\?|write me|\bxxx\b")


DB_LINE = re.compile(r'^\s*db\s+"(.*)"\s*(?:;.*)?$')


def bodies(path, rel, allow_db=False):
    """Yield (rel, line, label, [fragments]) for every text body in one file.
    allow_db also reads `db "..."` strings: Gen 2 writes dex entries that way.
    Off for this tree, where `db` strings are names, not dialogue."""
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return
    scope = label = None
    frags, start = [], 0

    def flush():
        if any(f for f in frags if f != "<RAM>"):
            yield (rel, start, label or "?", list(frags))
        frags.clear()

    for n, raw in enumerate(lines, 1):
        m = GLOBAL_LABEL.match(raw)
        if m:
            yield from flush()
            scope = label = m.group(1)
            continue
        m = LOCAL_LABEL.match(raw)
        if m:
            yield from flush()
            label = (scope or "") + m.group(1)
            continue
        m = STR_LINE.match(raw)
        if m:
            if not frags:
                start = n
            frags.append(m.group(2))
            continue
        m = DB_LINE.match(raw) if allow_db else None
        if m:
            if not frags:
                start = n
            frags.append(m.group(1))
            if "@" in m.group(1):
                yield from flush()
            continue
        if RAM_LINE.match(raw) and frags:
            frags.append("<RAM>")
            continue
        if END_LINE.match(raw):
            yield from flush()
    yield from flush()


def normalize(frags):
    out = ""
    for f in frags:
        f = f.replace("@", "").replace("…", "...").strip()
        if out.endswith("-") and not out.endswith("--"):
            out = out[:-1] + f  # rejoin a hyphenated wrap: "to-" + "gether"
        else:
            out = (out + " " + f) if out else f
    return re.sub(r"\s+", " ", out).upper().strip()


def trigrams(s):
    w = s.split()
    return {tuple(w[i:i + 3]) for i in range(len(w) - 2)}


class Corpus:
    def __init__(self, items):
        self.items = items  # [(rel, label, norm)]
        self.exact = {norm for _, _, norm in items}
        self.blob = " | ".join(norm for _, _, norm in items)
        self.by_label = {label: norm for _, label, norm in items}
        self.index = defaultdict(set)
        for i, (_, _, norm) in enumerate(items):
            for t in trigrams(norm):
                self.index[t].add(i)

    def same_words(self, norm):
        return norm in self.exact or (len(norm) >= 16 and norm in self.blob)

    def nearest(self, norm):
        """(share of norm's trigrams found in the best single text, that text)."""
        tg = trigrams(norm)
        if len(tg) < 2:
            return 0.0, None
        hits = Counter()
        for t in tg:
            for i in self.index.get(t, ()):
                hits[i] += 1
        if not hits:
            return 0.0, None
        i, n = hits.most_common(1)[0]
        return n / len(tg), self.items[i]


def load_tree(root, files, allow_db=False):
    items = []
    for p in files:
        rel = f"{root.name}/{p.relative_to(root).as_posix()}"
        for _, _, label, frags in bodies(p, rel, allow_db):
            items.append((rel, label, normalize(frags)))
    return items


def added_lines_claude(log_dir):
    """Lines Claude Code Edit/Write/MultiEdit tool calls added."""
    for path in Path(log_dir).rglob("*.jsonl"):
        with open(path, encoding="utf-8", errors="replace") as fh:
            for raw in fh:
                if '"tool_use"' not in raw:
                    continue
                try:
                    msg = json.loads(raw).get("message", {})
                except ValueError:
                    continue
                content = msg.get("content")
                if not isinstance(content, list):
                    continue
                for c in content:
                    if not isinstance(c, dict) or c.get("type") != "tool_use":
                        continue
                    inp = c.get("input") or {}
                    pairs = []
                    if c.get("name") == "Edit":
                        pairs.append((inp.get("old_string", ""), inp.get("new_string", "")))
                    elif c.get("name") == "MultiEdit":
                        pairs += [(e.get("old_string", ""), e.get("new_string", ""))
                                  for e in inp.get("edits", [])]
                    elif c.get("name") == "Write":
                        pairs.append(("", inp.get("content", "")))
                    for old, new in pairs:
                        before = {l.strip() for l in str(old).splitlines()}
                        for l in str(new).splitlines():
                            if l.strip() not in before:
                                yield l


def added_lines_codex(log_dir):
    """`+` lines of every apply_patch a Codex tool call carried."""
    for path in Path(log_dir).rglob("*.jsonl"):
        with open(path, encoding="utf-8", errors="replace") as fh:
            for raw in fh:
                if "Begin Patch" not in raw:
                    continue
                try:
                    payload = json.loads(raw).get("payload", {})
                except ValueError:
                    continue
                if payload.get("type") not in ("function_call", "custom_tool_call"):
                    continue
                src = payload.get("input") or payload.get("arguments") or ""
                if not isinstance(src, str):
                    src = json.dumps(src)
                # Codex's exec tool runs JS: the patch is a string literal,
                # `tools.apply_patch("*** Begin Patch\n...")`, escapes and all.
                patches = []
                for lit in CODEX_PATCH_LITERAL.findall(src):
                    try:
                        patches.append(json.loads('"' + lit + '"'))
                    except ValueError:
                        pass
                patches += CODEX_PATCH_TEMPLATE.findall(src)
                if not patches and "\n*** Begin Patch" in src:
                    patches.append(src)  # a bare apply_patch tool input
                inside = False
                for l in "\n".join(patches).splitlines():
                    if "*** Begin Patch" in l:
                        inside = True
                    elif "*** End Patch" in l:
                        inside = False
                    elif inside and l.startswith("+") and not l.startswith("+++"):
                        yield l[1:]


def blame_dates(rel):
    """line number -> commit date (YYYY-MM-DD) of the commit that last touched it."""
    out = subprocess.run(["git", "blame", "--line-porcelain", "--", rel], cwd=ROOT,
                         capture_output=True, text=True, encoding="utf-8", errors="replace").stdout
    dates, n, when = {}, 0, ""
    for l in out.splitlines():
        if l.startswith("committer-time "):
            when = time.strftime("%Y-%m-%d", time.localtime(int(l.split()[1])))
        elif l.startswith("\t"):
            n += 1
            dates[n] = when
    return dates


def oldest_log(log_dir):
    """Earliest record timestamp in any log. Not mtime: resuming a session
    rewrites its file, so an August log can carry an October mtime."""
    oldest = None
    for p in Path(log_dir).rglob("*.jsonl"):
        with open(p, encoding="utf-8", errors="replace") as fh:
            for _, raw in zip(range(20), fh):
                m = re.search(r'"timestamp":\s*"(\d{4}-\d\d-\d\d)', raw)
                if m:
                    oldest = min(oldest or m.group(1), m.group(1))
                    break
    return oldest


def ai_index(sources):
    strings, labels = defaultdict(set), defaultdict(set)
    for name, lines in sources:
        for l in lines:
            m = STR_LINE.match(l)
            if m and len(m.group(2).strip("@ ")) >= 8:
                strings[m.group(2).strip()].add(name)
                continue
            m = GLOBAL_LABEL.match(l)
            if m and l.rstrip().endswith(":"):
                labels[m.group(1)].add(name)
    return strings, labels


SECTION_NOTES = {
    "Placeholders": "Matched a placeholder pattern (INSERT, TODO, TBD, ???...). Listed whatever their status.",
    "NEW": "No vanilla or Gen 2 source found. Either your writing or AI writing; see the AI column.",
    "REWRITTEN": "Occupies a vanilla text's label, but the words are new. The original is shown for reference.",
    "VANILLA-EDITED": "Mostly a vanilla text (share of its word triples found in the closest original), with changes.",
    "GEN2-EDITED": "Mostly a Gold/Crystal text, with changes.",
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vanilla", required=True, type=Path)
    ap.add_argument("--gen2", type=Path, action="append",
                    help="Gen 2 reference tree; repeat for Gold + Crystal (default tmp/pokegold)")
    ap.add_argument("--claude-logs", type=Path)
    ap.add_argument("--codex-logs", type=Path)
    ap.add_argument("--out-md", required=True, type=Path)
    ap.add_argument("--out-csv", required=True, type=Path)
    args = ap.parse_args()

    tracked = subprocess.run(["git", "ls-files", "*.asm"], cwd=ROOT, capture_output=True,
                             text=True, check=True).stdout.split()
    files = [ROOT / f for f in tracked if f.split("/")[0] in SCAN_DIRS]
    vanilla = Corpus(load_tree(args.vanilla, sorted(args.vanilla.rglob("*.asm"))))
    gen2 = Corpus([item for d in (args.gen2 or [ROOT / "tmp/pokegold"])
                   for item in load_tree(d, sorted(d.rglob("*.asm")), allow_db=True)])

    sources = []
    if args.claude_logs:
        sources.append(("Claude", added_lines_claude(args.claude_logs)))
    if args.codex_logs:
        sources.append(("Codex", added_lines_codex(args.codex_logs)))
    ai_strings, ai_labels = ai_index(sources)

    rows, counts = [], Counter()
    for p in files:
        rel = p.relative_to(ROOT).as_posix()
        for _, line, label, frags in bodies(p, rel):
            norm = normalize(frags)
            ref, score = "", 0.0
            if vanilla.same_words(norm):
                status = "VANILLA"
            elif gen2.same_words(norm):
                status = "GEN2"
            else:
                vs, vref = vanilla.nearest(norm)
                gs, gref = gen2.nearest(norm)
                if max(vs, gs) >= 0.5:
                    status, score, r = (("VANILLA-EDITED", vs, vref) if vs >= gs
                                        else ("GEN2-EDITED", gs, gref))
                    ref = f"{r[0]}:{r[1]}: {r[2]}"
                elif label in vanilla.by_label:
                    # a vanilla text's slot, but its words are new
                    status, score = "REWRITTEN", vs
                    ref = f"vanilla:{label}: {vanilla.by_label[label]}"
                else:
                    status = "NEW"
            who = set(ai_labels.get(label.split(".")[0], ()))
            created = bool(who)
            for f in frags:
                who |= ai_strings.get(f.strip(), set())
            ai = ("/".join(sorted(who)) + (" (created label)" if created else " (lines)")) if who else ""
            ph = "yes" if PLACEHOLDER.search(" ".join(frags)) else ""
            counts[status] += 1
            if status != "VANILLA" and status != "GEN2" or ph:
                rows.append({"status": status, "ai": ai, "placeholder": ph, "file": rel,
                             "line": line, "label": label, "text": " / ".join(frags),
                             "reference": ref, "similarity": f"{score:.0%}" if score else "",
                             "your_text": ""})

    # When was each listed text last committed, and did any AI log exist then?
    coverage = sorted(((d, n) for n, d in
                       (("Claude", args.claude_logs and oldest_log(args.claude_logs)),
                        ("Codex", args.codex_logs and oldest_log(args.codex_logs))) if d),
                      reverse=True)
    blames = {}
    for r in rows:
        if r["file"] not in blames:
            blames[r["file"]] = blame_dates(r["file"])
        when = blames[r["file"]].get(r["line"], "")
        r["committed"] = when
        seen = [n for d, n in coverage if when and when >= d]
        r["logs_cover"] = "+".join(seen) if seen else "none"

    rows.sort(key=lambda r: (r["placeholder"] != "yes", r["file"], r["line"]))
    with open(args.out_csv, "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.DictWriter(fh, fieldnames=["status", "ai", "committed", "logs_cover", "placeholder",
                                           "file", "line", "label", "text", "reference",
                                           "similarity", "your_text"])
        w.writeheader()
        w.writerows(rows)

    def cell(s):
        return str(s).replace("|", "\\|")

    def ai_cell(r):
        if r["ai"]:
            return r["ai"]
        return "none logged" if r["logs_cover"] != "none" else "predates logs"

    ai_rows = [r for r in rows if r["ai"]]
    clean = sum(1 for r in rows if not r["ai"] and r["logs_cover"] != "none")
    dark = sum(1 for r in rows if not r["ai"] and r["logs_cover"] == "none")
    md = [
        "# Text Inventory",
        "",
        f"Generated by `tools/text_inventory.py`. {sum(counts.values())} text bodies scanned in "
        f"{', '.join(SCAN_DIRS)}.",
        "",
        "| Status | Count |", "|---|---|",
        *[f"| {k} | {counts[k]} |" for k in ("VANILLA", "VANILLA-EDITED", "REWRITTEN", "GEN2",
                                              "GEN2-EDITED", "NEW")],
        f"| placeholder pattern hit | {sum(1 for r in rows if r['placeholder'])} |",
        f"| listed rows with a logged AI edit | {len(ai_rows)} |",
        f"| listed rows, logs cover their date, no AI edit logged | {clean} |",
        f"| listed rows committed before any log exists | {dark} |",
        "",
        "Logs on this machine start: " + (", ".join(f"{n} {d}" for d, n in coverage) or "none given")
        + ". `committed` is the date of the commit that last touched the text's first line "
        "(uncommitted work shows as the last commit's date or today).",
        "",
        "VANILLA and GEN2 texts are counted but not listed. The CSV next to this file has every "
        "listed row plus a blank `your_text` column for replacements.",
        "",
        "**AI tags are records, not guesses.** `Claude`/`Codex` means a logged edit by that tool "
        "added the label (`created label`) or one of its lines (`lines`). `none logged` means the "
        "logs cover that date and show no AI edit to it: probably yours, though text an AI wrote "
        "through a generator script is invisible. `predates logs` means no record exists either "
        "way.",
        "",
    ]
    for title, pred in (("Placeholders", lambda r: r["placeholder"]),
                        ("NEW", lambda r: r["status"] == "NEW" and not r["placeholder"]),
                        ("REWRITTEN", lambda r: r["status"] == "REWRITTEN" and not r["placeholder"]),
                        ("VANILLA-EDITED", lambda r: r["status"] == "VANILLA-EDITED" and not r["placeholder"]),
                        ("GEN2-EDITED", lambda r: r["status"] == "GEN2-EDITED" and not r["placeholder"])):
        sel = [r for r in rows if pred(r)]
        md += [f"## {title} ({len(sel)})", "", SECTION_NOTES[title], ""]
        if not sel:
            md += ["None.", ""]
            continue
        by_file = defaultdict(list)
        for r in sel:
            by_file[r["file"]].append(r)
        has_ref = title not in ("NEW", "Placeholders")
        for f, rs in by_file.items():
            md += [f"### {f}", "", "| Line | Label | AI | Committed | Text |" + (" Original |" if has_ref else ""),
                   "|---|---|---|---|---|" + ("---|" if has_ref else "")]
            for r in rs:
                extra = (f" {cell(r['similarity'])} {cell(r['reference'].split(': ', 1)[-1])} |"
                         if has_ref else "")
                md.append(f"| {r['line']} | `{cell(r['label'])}` | {cell(ai_cell(r))} | {r['committed']} "
                          f"| {cell(r['text'])} |{extra}")
            md.append("")
    args.out_md.write_text("\n".join(md) + "\n", encoding="utf-8")
    print(" ".join(f"{k}={v}" for k, v in counts.items()), f"listed={len(rows)} ai={len(ai_rows)}")


if __name__ == "__main__":
    main()
