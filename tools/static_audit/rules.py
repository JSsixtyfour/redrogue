"""The audit rules. Each returns a list of Finding dicts:
    {rule, file, line, label, msg, severity}
severity: "bug" (fails `make audit` unless allowlisted) or "info" (reported only).

Rule ids match CODE_SWEEP_2026-09-27.md in Red Rogue Files:
  A1 stack balance            A2 hardware state (SRAM/WRAM bank/IME)
  B1 plain cross-bank call    B1f fragile same-bank-by-luck call
  B2 cross-bank data pointer  B3 HOME -> ROMX plain call
  B4 far-call callee reads a destroyed register
  B5 caller reads a register a far call destroyed
  B6 bank switch from ROMX    B7 documented contract vs real clobbers
  B8 `pop af` discards the flags a branch needs
  C1 fall-through into data / off a section
  C2 dispatch table without a length assert
  C3 text-script traps        D1 unreachable code
  D2 "same bank" claims       D3 hygiene
"""
from __future__ import annotations

import re
import subprocess
from collections import Counter, defaultdict

import flow as flowmod
from lib import FAR_CALL, FAR_JUMP, REPO, TOP_OBJECTS, Item, Program, pinned_sections

HOME_SWITCHERS = {"SetCurBank", "BankswitchCommon", "BankswitchHome", "BankswitchBack",
                  "SwitchToMapRomBank"}
FAR_COPIERS = {"FarCopyData", "FarCopyData2", "FarCopyData3", "FarCopyDataDouble",
               "CopyVideoData", "CopyVideoDataDouble", "FarCopyBytes", "CopyVideoDataAlternate",
               "FarPlaceString", "FarCopyDataDouble2", "CopyVideoDataDoubleAlternate",
               "FarCopyDataAutoBank"}
FLOW_SEVERITY = {"A1": "bug", "A2": "bug", "B4": "bug", "B5": "bug", "B8": "bug", "C1": "bug"}


def F(rule, it: Item, label, msg, severity="bug"):
    return {"rule": rule, "file": it.file, "line": it.line, "label": label or "",
            "msg": msg, "severity": severity, "idx": it.idx}


_VANILLA = {}


def vanilla_lines(file):
    """Code lines of `file` as it was at the pret/pokered merge-base (None if new)."""
    if file not in _VANILLA:
        from lib import MERGE_BASE
        r = subprocess.run(["git", "show", f"{MERGE_BASE}:{file}"], cwd=REPO,
                           capture_output=True, text=True, encoding="utf-8", errors="ignore")
        if r.returncode != 0:
            _VANILLA[file] = None
        else:
            _VANILLA[file] = {code_key(l) for l in r.stdout.splitlines()} - {""}
    return _VANILLA[file]


def code_key(line):
    return re.sub(r"\s+", " ", line.split(";")[0]).strip()


_RAW = {}


def is_vanilla_routine(p: Program, idx):
    """True if every code line of the routine holding item idx is unchanged
    from pret/pokered: the behaviour is inherited, not something Red Rogue added."""
    it = p.items[idx]
    van = vanilla_lines(it.file)
    if not van:
        return False
    par = p.parent_of(it)
    start = p.def_index(par, it) if par else None
    if start is None or p.items[start].file != it.file:
        return False
    first = p.items[start].line
    last = None
    for j in range(start + 1, len(p.items)):
        x = p.items[j]
        if x.kind == "label" and x.is_global:
            last = x.line if x.file == it.file else None
            break
    if it.file not in _RAW:
        _RAW[it.file] = (REPO / it.file).read_text(encoding="utf-8", errors="ignore").splitlines()
    raw = _RAW[it.file]
    end = (last - 1) if last and last > first else min(len(raw), first + 400)
    body = [code_key(l) for l in raw[first - 1:end]]
    return all(k in van for k in body if k)


def site_bank(p: Program, it: Item):
    """ROM bank the item executes from (0 = HOME), or None (RAM/LOAD/unknown)."""
    if it.load or it.section is None:
        return None
    s = p.rom.sections.get(it.section)
    if s is None or not s.region.startswith("ROM"):
        return None
    return s.bank


def jump_target(it: Item):
    if it.kind != "instr" or it.op not in ("call", "jp", "jr") or not it.args:
        return None
    t = it.args[-1]
    if t.lower() in ("hl", "[hl]"):
        return None
    return t


# --------------------------------------------------------------------------
# Flow-engine rules: A1 A2 B4 B5 B8 C1
# --------------------------------------------------------------------------

def run_flow(p: Program):
    fl = flowmod.Flow(p)
    labels = flowmod.code_entries(p)
    fl.solve(labels)
    out = []
    seen = set()
    for f in fl.run_findings(labels):
        if not p.in_scope(f.item):
            continue
        label = p.parent_of(f.item) or f.entry
        # merge-depth findings repeat on every item of a loop body: keep one per routine
        key = (f.rule, label, f.msg.split("(")[0]) if f.rule == "A1" else (f.rule, f.item.idx, f.msg)
        if key in seen:
            continue
        seen.add(key)
        sev = FLOW_SEVERITY.get(f.rule, "bug")
        if f.rule == "A2" and ("SRAM still enabled" in f.msg or "SRAM bank (rRAMB) left" in f.msg):
            # House convention (vanilla save.asm does it too): SRAM is left
            # open / on its last bank between steps and closed by a finaliser.
            # What actually breaks is touching SRAM closed or on the wrong
            # bank - those stay bug-level.
            sev = "info"
        out.append(F(f.rule, f.item, label, f.msg, sev))
    return out, fl, labels


# --------------------------------------------------------------------------
# B1 / B1f / B3 / B6: control transfers and bank switches
# --------------------------------------------------------------------------

def section_directives(p: Program):
    d = {}
    for it in p.items:
        if it.kind == "directive" and it.op == "section" and it.section not in d:
            d[it.section] = it.args[0] if it.args else ""
    return d


def is_floating(p: Program, name: str, directives):
    if name in pinned_sections():
        return False
    text = directives.get(name, "")
    return not re.search(r"BANK\s*\[|ROMX\s*\[|ROM0", text, re.I)


def rule_calls(p: Program):
    out = []
    directives = section_directives(p)
    for it in p.items:
        if not p.in_scope(it):
            continue
        sb = site_bank(p, it)
        if sb is None:
            continue
        here = p.parent_of(it)

        # B6: switching banks from inside ROMX code maps the running code away
        if sb != 0 and it.kind == "instr":
            t = jump_target(it)
            dst = it.args[0].lower().replace(" ", "") if it.args else ""
            if (it.op == "call" and t in HOME_SWITCHERS) or \
                    (it.op in ("ld", "ldh") and dst in ("[rromb]", "[$2000]", "[$2100]")) or \
                    it.op in ("homecall", "homecall_sf"):
                prev = [x for x in p.items[max(0, it.idx - 12):it.idx] if x.kind == "instr"]
                restores = len(prev) >= 2 and prev[-2].text.replace(" ", "") == "popaf" and \
                    prev[-1].text.replace(" ", "").lower() == "ldh[hloadedrombank],a"
                if restores:
                    out.append(F("B6", it, here,
                                 f"`{it.text}` re-maps a bank saved by this routine: a no-op when "
                                 f"that is its own bank ${sb:02X} (vanilla pattern)", "info"))
                else:
                    out.append(F("B6", it, here,
                                 f"`{it.text}` switches the ROM bank from ROMX code (bank ${sb:02X}); "
                                 "the next instruction is fetched from whatever bank is now mapped"))

        t = jump_target(it)
        if t is None:
            continue
        lab = p.resolve(t, it)
        tb, region = p.label_loc(lab, it)
        if tb is None or region not in ("HOME", "ROMX"):
            continue
        tsec = p.label_section(lab, it)
        if region == "ROMX" and sb != 0 and tb != sb:
            out.append(F("B1", it, here,
                         f"plain `{it.op}` from bank ${sb:02X} to `{lab}` in bank ${tb:02X}: "
                         "executes whatever bank $%02X has at that address" % sb))
        elif region == "ROMX" and sb != 0 and tsec and it.section and tsec != it.section \
                and (is_floating(p, it.section, directives) or is_floating(p, tsec, directives)):
            out.append(F("B1f", it, here,
                         f"plain `{it.op}` to `{lab}` works only because SECTIONs "
                         f"\"{it.section}\" and \"{tsec}\" both landed in bank ${sb:02X}; "
                         "at least one floats, so a layout change can split them", "info"))
        elif region == "ROMX" and sb == 0:
            out.append(("B3", it, here, lab, tb))
    # B3: HOME -> ROMX needs an explicit switch to BANK(target) earlier in the routine
    b3 = [x for x in out if isinstance(x, tuple)]
    out = [x for x in out if not isinstance(x, tuple)]
    for _, it, here, lab, tb in b3:
        start = p.label_at.get(here, it.idx)
        body = " ".join(x.text for x in p.items[start:it.idx])
        banks = set()
        for m in re.finditer(r"BANK\(\s*([\w.]+)\s*\)", body):
            b = p.label_loc(m.group(1), it)[0]
            if b is not None:
                banks.add(b)
        if tb in banks:
            continue
        if re.search(r"hLoadedROMBank|SwitchToMapRomBank|BankswitchBack|wPredefParentBank", body):
            why = "switches to a computed/restored bank first; confirm it is $%02X" % tb
            sev = "info"
        else:
            why = "no switch to BANK(%s) precedes it in this routine: relies on the caller's bank" % lab
            sev = "info"
        out.append(F("B3", it, here, f"HOME `{it.op} {lab}` (bank ${tb:02X}): {why}", sev))
    return out


# --------------------------------------------------------------------------
# B2: pointers into another ROMX bank
# --------------------------------------------------------------------------

def trampolines(p: Program):
    """Routines that far-jump a pointer into ONE fixed bank:
    `ld b, BANK(X)` ... `jp Bankswitch` within their first few instructions
    (e.g. EffectCallBattleCore). -> {label: bank}"""
    out = {}
    items = p.items
    for name, idx in p.label_at.items():
        if not items[idx].is_global:
            continue
        bank, n, j = None, 0, idx + 1
        while j < len(items) and n < 5:
            x = items[j]
            if x.kind == "instr":
                n += 1
                m = re.match(r"ld\s+b\s*,\s*BANK\(\s*([\w.]+)\s*\)", x.text, re.I)
                if m:
                    bank = p.label_loc(m.group(1), x)[0]
                if x.op == "jp" and jump_target(x) == "Bankswitch" and bank is not None:
                    out[name] = bank
                    break
                if x.op in ("ret", "reti"):
                    break
            elif x.kind == "label" and x.is_global:
                break
            j += 1
    return out


def rule_b2(p: Program):
    out = []
    items = p.items
    tramp = trampolines(p)
    for it in items:
        if it.kind != "instr" or it.op != "ld" or len(it.args) != 2 or not p.in_scope(it):
            continue
        reg = it.args[0].lower()
        if reg not in ("hl", "de", "bc"):
            continue
        lab = p.resolve(it.args[1].strip(), it)
        tb, region = p.label_loc(lab, it)
        sb = site_bank(p, it)
        if tb is None or region != "ROMX" or sb in (None, 0) or tb == sb:
            continue
        ok = False
        # `ld b, BANK(X)` / `ld a, BANK(X)` just BEFORE the pointer load also counts.
        j, n = it.idx - 1, 0
        while j >= 0 and n < 3:
            x = items[j]
            if x.kind == "label" and x.is_global:
                break
            if x.kind == "instr":
                n += 1
                if "BANK(" in x.text.upper():
                    ok = True
            j -= 1
        # Then look ahead through the routine for a bank-aware consumer.
        j, n = it.idx + 1, 0
        while not ok and j < len(items) and n < 30:
            x = items[j]
            if x.kind == "label" and x.is_global:
                break
            if x.kind == "instr":
                n += 1
                if "BANK(" in x.text.upper():
                    ok = True
                    break
                if x.op in FAR_CALL | FAR_JUMP and x.args:
                    fb = p.label_loc(x.args[0], x)[0]
                    if reg == "de" and fb == tb:
                        ok = True  # de survives the far call into the pointer's own bank
                        break
                    if reg in ("hl", "bc"):
                        ok = True  # the far call destroys the pointer: never dereferenced here
                        break
                t = jump_target(x)
                if t and t in FAR_COPIERS:
                    ok = True
                    break
                if t and t in tramp:
                    ok = tramp[t] == tb
                    if not ok:
                        out.append(F("B2", it, p.parent_of(it),
                                     f"`{it.text}` (bank ${tb:02X}) is handed to `{t}`, which "
                                     f"jumps into bank ${tramp[t]:02X}"))
                        ok = True  # reported above with the precise reason
                    break
                if x.op in ("ret", "reti") and len(x.args) == 0:
                    break
            j += 1
        if ok:
            continue
        out.append(F("B2", it, p.parent_of(it),
                     f"`{it.text}` takes a pointer into bank ${tb:02X} from bank ${sb:02X} "
                     "with no bank-aware consumer in sight: any dereference here reads bank "
                     f"${sb:02X}'s bytes"))
    return out


# --------------------------------------------------------------------------
# B7: documented register contract vs computed clobbers
# --------------------------------------------------------------------------

REGTOK = {"a": "a", "b": "b", "c": "c", "d": "d", "e": "e", "h": "h", "l": "l",
          "af": "a", "bc": "bc", "de": "de", "hl": "hl"}
STOP = {"and", "only", "the", "registers", "register", "regs", "flags", "f", "all", "of", "both"}


def reg_list(text):
    toks = [t for t in re.split(r"[,/&\s`]+", text.strip()) if t]
    regs = set()
    for t in toks:
        tl = t.lower()
        if tl in REGTOK:
            regs |= set(REGTOK[tl])
        elif tl in STOP:
            continue
        else:
            return None
    return regs or None


def parse_contract(comments):
    preserved, clobbers, clobbers_all = set(), set(), False
    listed = False
    for c in comments:
        for m in re.finditer(r"clobber(?:s|ed)?\s*:?\s*([^.;()\n\-]*)", c, re.I):
            txt = m.group(1)
            if re.search(r"\b(everything|all|any|anything)\b", txt, re.I):
                clobbers_all = True
                continue
            r = reg_list(txt)
            if r:
                clobbers |= r
                listed = True
        m = re.search(r"preserves? (every|all) (register|reg)s?(?:\s+except\s+([^.;()\n\-]*))?",
                      c, re.I)
        if m and not negated(c, m.start()):
            keep = set("abcdehl")
            if m.group(3):
                keep -= reg_list(m.group(3).replace("flags", "")) or set()
            preserved |= keep
        for m in re.finditer(r"preserv(?:es|ed|e)\s*:?\s*([^.;()\n\-]*)", c, re.I):
            if negated(c, m.start()):
                continue
            r = reg_list(m.group(1))
            if r:
                preserved |= r
        # "d PRESERVED" / "(bc, d preserved)" - not "survives", which in these
        # headers describes what Bankswitch keeps, not what the routine keeps
        for m in re.finditer(r"\b((?:(?:af|bc|de|hl|[abcdehl])[,/ ]+(?:and\s+)?)*"
                             r"(?:af|bc|de|hl|[abcdehl]))\s+(?:is\s+|are\s+)?"
                             r"(?:preserved|untouched)\b", c, re.I):
            if negated(c, m.start()):
                continue
            preserved |= reg_list(m.group(1)) or set()
    return preserved, (clobbers if listed else None), clobbers_all


def negated(text, pos):
    return bool(re.search(r"\b(not|never|no|doesn't|don't|cannot|can't)\b[^.;]{0,12}$",
                          text[max(0, pos - 20):pos], re.I))


def header_comments(p: Program, idx):
    items = p.items
    out = []
    j = idx - 1
    while j >= 0 and items[j].kind == "directive" and not items[j].op and items[j].comment:
        out.append(items[j].comment)
        j -= 1
    if items[idx].comment:
        out.append(items[idx].comment)
    j = idx + 1
    while j < len(items) and items[j].kind == "directive" and not items[j].op and items[j].comment:
        out.append(items[j].comment)
        j += 1
    return out


def rule_b7(p: Program, fl, labels):
    out = []
    for lab in labels:
        idx = p.label_at.get(lab)
        if idx is None or not p.in_scope(p.items[idx]):
            continue
        s = fl.summaries.get(lab)
        if s is None or s.opaque:
            continue
        pres, clob, clob_all = parse_contract(header_comments(p, idx))
        real = set(s.clobbers) - {"f"}
        bad = sorted(pres & real)
        if bad:
            out.append(F("B7", p.items[idx], lab,
                         f"header says {'/'.join(bad)} preserved, but the routine (with its "
                         f"callees) can return them changed: real clobbers {''.join(sorted(real))}"))
        if clob is not None and not clob_all:
            extra = sorted(real - clob - pres)
            if extra:
                out.append(F("B7", p.items[idx], lab,
                             f"header's clobber list ({''.join(sorted(clob))}) omits "
                             f"{'/'.join(extra)}, which it (or a callee) also changes", "info"))
    return out


# --------------------------------------------------------------------------
# C2: dispatch tables
# --------------------------------------------------------------------------

def rule_c2(p: Program):
    out = []
    items = p.items
    raw = {}
    for it in items:
        if it.kind != "label" or not it.is_global or not p.in_scope(it):
            continue
        j, n = it.idx + 1, 0
        codeptrs = 0
        while j < len(items) and items[j].kind in ("data", "directive") and n < 400:
            x = items[j]
            if x.kind == "data" and x.op == "dw":
                for a in x.args:
                    t = p.label_at.get(p.resolve(a.strip(), x))
                    if t is not None and flowmod_is_code(p, t):
                        codeptrs += 1
            n += 1
            j += 1
        if codeptrs < 3:
            continue
        if it.file not in raw:
            raw[it.file] = (REPO / it.file).read_text(encoding="utf-8", errors="ignore").splitlines()
        lines = raw[it.file]
        end = items[j - 1].line if j - 1 > it.idx else it.line
        # the table's own lines plus the one after it (where assert_table_length goes)
        window = "\n".join(lines[max(0, it.line - 1): min(len(lines), end + 1)])
        if re.search(r"table_width|assert_table_length|assert_list_length|ASSERT", window):
            continue
        out.append(F("C2", it, it.label,
                     f"jump table of {codeptrs} routine pointers with no table_width/"
                     "assert_table_length: an index past the end jumps into whatever follows",
                     "info"))
    return out


def flowmod_is_code(p: Program, idx):
    j = idx + 1
    while j < len(p.items) and (p.items[j].kind == "label" or
                                (p.items[j].kind == "directive" and not p.items[j].op)):
        j += 1
    return j < len(p.items) and p.items[j].kind == "instr"


# --------------------------------------------------------------------------
# C3: text-script traps
# --------------------------------------------------------------------------

def text_end_flow(p: Program, fl):
    """A Flow whose `term` set holds TextScriptEnd and every routine that can
    only leave through it (the shared `call TalkToTrainer / jp TextScriptEnd`
    tails trainer texts `jr` into), so a text_asm handler's bc check only
    counts exits that really return into the text stream."""
    ft = flowmod.Flow(p)
    ft.summaries = dict(fl.summaries)
    ft.term = {"TextScriptEnd"}
    cands = set()
    for it in p.items:
        if it.kind == "instr" and jump_target(it) == "TextScriptEnd":
            par = p.parent_of(it)
            if par:
                cands.add(par)
    for _ in range(4):
        grew = False
        for lab in sorted(cands - ft.term):
            if lab not in p.label_at:
                continue
            ft.analyze(lab)
            if ft.last_exits and ft.last_exits <= {"term"}:
                ft.term.add(lab)
                grew = True
        if not grew:
            break
    return ft


def rule_c3(p: Program, fl):
    out = []
    items = p.items
    ft = text_end_flow(p, fl)
    for k, it in enumerate(items):
        if it.kind != "data" or not p.in_scope(it):
            continue
        # C3a: "...@" immediately followed by prompt/done orphans the wait
        if it.macro in ("text", "line", "cont", "para", "next", "page") and it.args \
                and it.args[-1].rstrip().endswith('@"'):
            j = k + 1
            while j < len(items) and items[j].kind in ("directive",) and not items[j].op:
                j += 1
            if j < len(items) and items[j].kind == "data" and items[j].macro in ("prompt", "done"):
                out.append(F("C3", it, p.parent_of(it),
                             f"string ends in \"@\" right before `{items[j].macro}`: PlaceString "
                             f"stops at the @, so the {items[j].macro} never waits"))
        # C3b: text_far A / <command> / text_far B: A must end in "@"
        if it.macro == "text_far" and it.op == "dab" and it.args:
            j = k + 1
            between = []
            while j < len(items) and items[j].kind in ("data", "directive"):
                x = items[j]
                if x.kind == "data" and x.macro == "text_far" and x.op == "dab":
                    break
                if x.kind == "data" and x.macro in ("text_end", "done", "prompt"):
                    between = None
                    break
                if x.kind == "data" and x.macro and x.macro != "text_far":
                    between.append(x.macro)
                j += 1
            if between and j < len(items) and items[j].macro == "text_far":
                first = it.args[0].strip()
                fi = p.label_at.get(first)
                if fi is not None:
                    last = None
                    m = fi + 1
                    while m < len(items) and m < fi + 400:
                        x = items[m]
                        if x.kind == "data" and x.macro in ("done", "prompt"):
                            last = None  # the box is ended by the control char: fine
                            break
                        if x.kind == "data" and x.macro == "text_end":
                            break
                        if x.kind == "data" and x.macro in ("text", "line", "cont", "para", "next"):
                            last = x
                        if x.kind == "label" and x.is_global:
                            break
                        m += 1
                    if last is not None and not last.args[-1].rstrip().endswith('@"'):
                        out.append(F("C3", it, p.parent_of(it),
                                     f"`text_far {first}` is split from the next text_far by "
                                     f"{', '.join(between)}, but {first} does not end its string "
                                     "in \"@\": the print loop eats text_end and prints the next "
                                     "half twice"))
        # C3c: text_asm handler must keep bc (the text cursor) when it returns
        if it.macro == "text_asm":
            j = k + 1
            while j < len(items) and items[j].kind != "instr":
                if items[j].kind == "data":
                    break
                j += 1
            if j >= len(items) or items[j].kind != "instr":
                continue
            name = f"@text_asm:{it.file}:{it.line}"
            p.label_at[name] = j
            ft.called.add(name)
            s = ft.analyze(name)
            if not s.opaque and ({"b", "c"} & set(s.clobbers)) and not returns_ending_text(p, j):
                out.append(F("C3", items[j], p.parent_of(items[j]),
                             "text_asm handler can return with bc changed: bc is the live text "
                             "cursor, so following text drifts (push bc / pop bc around it)"))
    return out


def returns_ending_text(p: Program, j):
    """Every `ret` in the handler is preceded by `ld hl, <...>TextScriptEndingText`,
    i.e. the text stream is ended, so the cursor in bc no longer matters."""
    rets, ending = 0, 0
    last_hl = ""
    m = j
    while m < len(p.items) and m < j + 200:
        x = p.items[m]
        if x.kind == "data" or (x.kind == "label" and x.is_global and m != j):
            break
        if x.kind == "instr" and x.op == "ld" and x.args and x.args[0].lower() == "hl":
            last_hl = x.args[1] if len(x.args) > 1 else ""
        if x.kind == "instr" and x.op == "ret" and not x.args:
            rets += 1
            ending += last_hl.endswith("TextScriptEndingText")
        m += 1
    return rets > 0 and rets == ending


def text_asm_ends_script(p: Program, j):
    """True if every visible exit of the handler is `jp TextScriptEnd` (no return)."""
    m = j
    while m < len(p.items) and m < j + 200:
        x = p.items[m]
        if x.kind == "data" or (x.kind == "label" and x.is_global and m != j):
            return False
        if x.kind == "instr" and x.op in ("ret", "reti"):
            return False
        if x.kind == "instr" and x.op == "jp" and jump_target(x) == "TextScriptEnd" \
                and len(x.args) == 1:
            return True
        m += 1
    return False


# --------------------------------------------------------------------------
# D1 / D2 / D3
# --------------------------------------------------------------------------

TERMINATORS = {"ret", "reti", "jp", "jr"}


def rule_d1(p: Program):
    """Code nobody can reach: a label with no references, after an unconditional exit."""
    refs = Counter()
    word = re.compile(r"\.?[A-Za-z_][\w.]*")
    for it in p.items:
        if it.kind in ("instr", "data", "directive") and it.text:
            for w in word.findall(it.text):
                refs[w] += 1
                if w.startswith("."):
                    par = p.parent_of(it)
                    if par:
                        refs[par + w] += 1
    out = []
    items = p.items
    for it in items:
        if it.kind != "label" or not p.in_scope(it):
            continue
        name = it.label
        short = name.split(".")[-1]
        if refs[name] or (not it.is_global and refs["." + short]):
            continue
        # previous real item must be an unconditional exit
        j = it.idx - 1
        while j >= 0 and items[j].kind in ("directive", "label") and not (
                items[j].kind == "directive" and items[j].op == "section"):
            j -= 1
        prev = items[j] if j >= 0 else None
        if prev is None or prev.kind != "instr":
            continue
        uncond = (prev.op in ("ret", "reti") and not prev.args) or \
            (prev.op in ("jp", "jr") and len(prev.args) == 1) or prev.op in FAR_JUMP \
            or prev.op == "predef_jump"
        if not uncond:
            continue
        nxt = it.idx + 1
        while nxt < len(items) and (items[nxt].kind == "label" or
                                    (items[nxt].kind == "directive" and not items[nxt].op)):
            if items[nxt].kind == "label" and refs[items[nxt].label]:
                break
            nxt += 1
        if nxt < len(items) and items[nxt].kind == "instr":
            out.append(F("D1", it, name, "unreferenced code after an unconditional exit: dead",
                         "info"))
    return out


def rule_d2(p: Program):
    out = []
    claim = re.compile(r"same (bank|section)|plain call is fine|no farcall needed|"
                       r"same-bank|in this bank|co-?located", re.I)
    items = p.items
    for it in items:
        if not it.comment or not p.in_scope(it) or not claim.search(it.comment):
            continue
        for j in range(it.idx, min(len(items), it.idx + 6)):
            x = items[j]
            t = jump_target(x)
            if t is None:
                continue
            lab = p.resolve(t, x)
            tb, region = p.label_loc(lab, x)
            sb = site_bank(p, x)
            if tb is None or sb is None or region != "ROMX":
                break
            tsec = p.label_section(lab, x)
            if tb != sb:
                out.append(F("D2", x, p.parent_of(x),
                             f"comment claims co-residence, but `{lab}` is in bank ${tb:02X} "
                             f"and this code is in bank ${sb:02X}"))
            elif tsec and x.section and tsec != x.section:
                out.append(F("D2", x, p.parent_of(x),
                             f"comment claims co-residence with `{lab}`: true today (bank "
                             f"${sb:02X}) but they are different SECTIONs "
                             f"(\"{x.section}\" vs \"{tsec}\")", "info"))
            break
    return out


def rule_d3(programs):
    out = []
    seen = set()
    for p in programs:
        seen |= p.walker.files_seen
    tracked = subprocess.run(["git", "ls-files", "*.asm"], cwd=REPO, capture_output=True,
                             text=True).stdout.splitlines() if (REPO / ".git").exists() else []
    for f in tracked:
        if f.startswith(("tmp/", "tools/")) or f in seen:
            continue
        if f.endswith(tuple(f"{t}.asm" for t in TOP_OBJECTS)):
            continue
        if f in ("includes.asm", "buildid.asm", "rgbdscheck.asm", "layout.link"):
            continue
        out.append({"rule": "D3", "file": f, "line": 1, "label": "",
                    "msg": "tracked .asm that no ROM INCLUDEs: dead file (or a missing INCLUDE)",
                    "severity": "info"})
    for d in ("tmp/worktrees", ".claude/worktrees"):
        path = REPO / d
        if path.is_dir():
            kids = [x.name for x in path.iterdir() if x.is_dir()]
            if kids:
                out.append({"rule": "D3", "file": d, "line": 1, "label": "",
                            "msg": f"{len(kids)} stale worktree(s) ({', '.join(sorted(kids)[:8])}"
                                   f"{'...' if len(kids) > 8 else ''}); rglob-based audits "
                                   "will scan them", "severity": "info"})
    return out
