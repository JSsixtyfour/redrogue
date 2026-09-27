"""Shared plumbing for the Red Rogue static audits.

The model is deliberately the assembler's, not a guess from filenames:
- Every ROM is walked from its real top-level objects (Makefile rom_obj) through
  INCLUDE, with that ROM's IF DEF(_RED/_BLUE/_DEBUG) conditionals applied, so a
  file nothing INCLUDEs never appears and an INCLUDEd file that opens its own
  SECTION correctly ends the parent's section (ROM_BIBLE / memory instance 8).
- Each emitted line knows its SECTION, and the ROM's .map says which bank that
  section landed in and whether the layout pinned it.
- Project macros are expanded inline, EXCEPT the bank-crossing family and
  predef, which stay as pseudo-ops because their register contract is exactly
  what the audits test:

    farcall/callfar/rfarcall   entry: only d, e reach the callee (a=b=bank,
                               c=low(.Return) or dba byte, hl=target address)
                               exit : a, b, c garbage (saved bank / saved F);
                               d, e, h, l and flags come back from the callee
    farjp/jpfar/rfarjp         entry as farcall, then the routine is left
    predef                     entry: only bc reaches the target (a = bank,
                               de = .done, hl = target); exit: a, f garbage
    homecall                   callee sees a = its bank; exit a, f garbage
    homecall_sf                callee sees a = its bank; exit a, b, c garbage
"""
from __future__ import annotations

import os
import re
import subprocess
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path

# STATIC_AUDIT_REPO points the audits at another source tree (e.g. an old
# commit exported with `git archive`) to check that a rule still catches a
# historic bug. Such a tree needs no build; rules that need a .sym say so.
REPO = Path(os.environ.get("STATIC_AUDIT_REPO") or Path(__file__).resolve().parents[2])
MERGE_BASE = "fbcf7d0e19a3a2db505440d3ccd3d40ca996c15c"  # pret/pokered
ROMS = {
    "pokered": {"_RED"},
    "pokeblue": {"_BLUE"},
    "pokeblue_debug": {"_BLUE", "_DEBUG"},
}
TOP_OBJECTS = ["audio", "home", "main", "maps", "ram", "text",
               "gfx/pics", "gfx/sprites", "gfx/tilesets"]

REG8 = ("a", "f", "b", "c", "d", "e", "h", "l")
PAIRS = {"af": ("a", "f"), "bc": ("b", "c"), "de": ("d", "e"), "hl": ("h", "l"),
         "sp": ("sp",)}
CONDS = {"z", "nz", "c", "nc"}

# Pseudo-ops kept whole instead of expanded (see module docstring).
FAR_CALL = {"farcall", "callfar", "rfarcall"}
FAR_JUMP = {"farjp", "jpfar", "rfarjp"}
INTRINSIC = FAR_CALL | FAR_JUMP | {"predef", "predef_jump", "homecall", "homecall_sf"}

DATA_DIRECTIVES = {"db", "dw", "dl", "ds", "dc", "dba", "dab", "dn", "dbw", "dwb",
                   "bigdw", "dx", "dt", "dd", "incbin", "INCBIN"}

MNEMONICS = {
    "ld", "ldh", "ldi", "ldd", "push", "pop", "add", "adc", "sub", "sbc", "and",
    "xor", "or", "cp", "inc", "dec", "rlca", "rla", "rrca", "rra", "cpl", "scf",
    "ccf", "daa", "rlc", "rl", "rrc", "rr", "sla", "sra", "srl", "swap", "bit",
    "set", "res", "jp", "jr", "call", "ret", "reti", "rst", "di", "ei", "nop",
    "halt", "stop", "ldhl",
}


# --------------------------------------------------------------------------
# .sym / .map
# --------------------------------------------------------------------------

@dataclass
class Section:
    name: str
    region: str          # ROM0, ROMX, WRAM0, ...
    bank: int
    start: int
    end: int
    symbols: list = field(default_factory=list)


@dataclass
class Rom:
    name: str
    sym: dict            # label -> (bank, addr)
    sections: dict       # name -> Section (first placement)
    addr_of: dict        # label -> Section

    def bank(self, label):
        v = self.sym.get(label)
        return None if v is None else v[0]

    def is_romx(self, label):
        v = self.sym.get(label)
        return v is not None and 0x4000 <= v[1] < 0x8000

    def is_home(self, label):
        v = self.sym.get(label)
        return v is not None and v[1] < 0x4000

    def is_rom(self, label):
        v = self.sym.get(label)
        return v is not None and v[1] < 0x8000


def load_rom(name: str) -> Rom:
    sym = {}
    if not (REPO / f"{name}.sym").exists():
        return Rom(name, {}, {}, {})
    for line in open(REPO / f"{name}.sym", encoding="utf-8", errors="ignore"):
        p = line.split(";")[0].split()
        if len(p) == 2 and ":" in p[0]:
            b, a = p[0].split(":")
            sym[p[1]] = (int(b, 16), int(a, 16))
    sections, addr_of = {}, {}
    region, bank, cur = None, None, None
    hdr = re.compile(r"^(\w+) bank #(\d+):")
    sec = re.compile(r'^\s*SECTION: \$([0-9a-f]+)(?:-\$([0-9a-f]+))? \(\$[0-9a-f]+ bytes?\) \["(.*)"\]')
    symre = re.compile(r"^\s*\$([0-9a-f]+) = (\S+)")
    for line in open(REPO / f"{name}.map", encoding="utf-8", errors="ignore"):
        m = hdr.match(line)
        if m:
            region, bank = m.group(1), int(m.group(2))
            continue
        m = sec.match(line)
        if m:
            s = int(m.group(1), 16)
            e = int(m.group(2), 16) if m.group(2) else s
            cur = Section(m.group(3), region, bank, s, e)
            sections.setdefault(cur.name, cur)
            continue
        m = symre.match(line)
        if m and cur is not None:
            cur.symbols.append(m.group(2))
            addr_of[m.group(2)] = cur
    return Rom(name, sym, sections, addr_of)


@lru_cache(None)
def pinned_sections() -> frozenset:
    """Sections whose bank the linker script fixes (layout.link)."""
    out = set()
    if not (REPO / "layout.link").exists():
        return frozenset()
    for line in open(REPO / "layout.link", encoding="utf-8"):
        m = re.match(r'\s*"([^"]+)"', line)
        if m:
            out.add(m.group(1))
    return frozenset(out)


@lru_cache(None)
def in_scope_files() -> frozenset:
    """Files touched since the pret/pokered merge-base (the sweep's scope)."""
    if not (REPO / ".git").exists():
        return frozenset(p.relative_to(REPO).as_posix() for p in REPO.rglob("*.asm"))
    out = subprocess.run(["git", "diff", "--name-only", MERGE_BASE, "HEAD", "--", "*.asm"],
                         cwd=REPO, capture_output=True, text=True, check=True).stdout
    # Uncommitted work counts too.
    out += subprocess.run(["git", "diff", "--name-only", "--", "*.asm"],
                          cwd=REPO, capture_output=True, text=True, check=True).stdout
    out += subprocess.run(["git", "ls-files", "--others", "--exclude-standard", "--", "*.asm"],
                          cwd=REPO, capture_output=True, text=True, check=True).stdout
    return frozenset(p.strip() for p in out.splitlines() if p.strip())


# --------------------------------------------------------------------------
# Source walking
# --------------------------------------------------------------------------

@dataclass
class Item:
    idx: int
    file: str            # repo-relative, forward slashes
    line: int
    kind: str            # label | instr | data | directive
    text: str            # code with comment stripped
    comment: str
    section: str | None
    op: str = ""
    args: list = field(default_factory=list)
    label: str = ""      # full label name for kind == label
    is_global: bool = False
    macro: str = ""      # outermost macro this was expanded from
    load: bool = False   # inside LOAD ... ENDL (executes from RAM)
    obj: str = ""        # top-level object (single-colon labels are local to it)


@dataclass
class Macro:
    name: str
    body: list           # raw lines
    file: str
    line: int


LABEL_RE = re.compile(r"^\s*([A-Za-z_][\w]*(?:\.[\w]+)?|\.[\w]+)(::?)(.*)$")
LOCAL_NOCOLON_RE = re.compile(r"^(\.[\w]+)\s*(.*)$")  # `.loop` at column 0
GLOBAL_NOCOLON_RE = re.compile(r"^([A-Za-z_]\w*)\s*$")  # rare bare global label


def strip_comment(line: str):
    """Split code from ; comment, respecting quoted strings."""
    out, q = [], False
    for i, ch in enumerate(line):
        if ch == '"':
            q = not q
        elif ch == ";" and not q:
            return "".join(out), line[i + 1:].strip()
        out.append(ch)
    return "".join(out), ""


def split_args(s: str):
    """Comma split at depth 0, respecting quotes and parens."""
    args, cur, depth, q = [], [], 0, False
    for ch in s:
        if ch == '"':
            q = not q
        if not q:
            if ch in "([":
                depth += 1
            elif ch in ")]":
                depth -= 1
            elif ch == "," and depth == 0:
                args.append("".join(cur).strip())
                cur = []
                continue
        cur.append(ch)
    if "".join(cur).strip():
        args.append("".join(cur).strip())
    return args


def eval_cond(expr: str, defines: set):
    """IF condition over DEF(X) terms. None = unknown (caller treats as true)."""
    e = expr.strip()
    if not re.fullmatch(r"[\s!()&|]*(?:DEF\s*\(\s*\w+\s*\)[\s!()&|]*)+", e):
        # Pure integer arithmetic (e.g. `_NARG >= 4` after substitution).
        if re.fullmatch(r"[\s\d()<>=!&|+\-*/%$]+", e):
            py = re.sub(r"\$([0-9a-fA-F]+)", lambda m: str(int(m.group(1), 16)), e)
            py = py.replace("&&", " and ").replace("||", " or ")
            py = re.sub(r"!(?!=)", " not ", py).replace("/", "//")
            try:
                return bool(eval(py, {}, {}))
            except Exception:
                return None
        return None
    py = re.sub(r"DEF\s*\(\s*(\w+)\s*\)", lambda m: str(m.group(1) in defines), e)
    py = py.replace("&&", " and ").replace("||", " or ")
    py = re.sub(r"!(?!=)", " not ", py)
    try:
        return bool(eval(py, {}, {}))
    except Exception:
        return None


class Walker:
    """Emit the Items one ROM assembles, in assembly order."""

    def __init__(self, rom_name: str):
        self.defines = set(ROMS[rom_name])
        self.items: list[Item] = []
        self.macros: dict[str, Macro] = {}
        self.section = None
        self.load = False
        self.parent = None
        self.files_seen: set[str] = set()
        self._unique = 0
        self._collect_macros()

    # Macros are defined in the preinclude and scattered files; collect them
    # all up front (names are global in rgbasm once defined).
    def _collect_macros(self):
        if (REPO / ".git").exists():
            files = subprocess.run(["git", "ls-files", "*.asm", "*.inc"], cwd=REPO,
                                   capture_output=True, text=True, check=True).stdout.split("\n")
        else:
            files = [p.relative_to(REPO).as_posix() for p in REPO.rglob("*")
                     if p.suffix in (".asm", ".inc")]
        for f in files:
            if not f or f.startswith("tmp/") or f.startswith("tools/"):
                continue
            p = REPO / f
            if not p.exists():
                continue
            lines = p.read_text(encoding="utf-8", errors="ignore").splitlines()
            i = 0
            while i < len(lines):
                code, _ = strip_comment(lines[i])
                m = re.match(r"^\s*MACRO\??\s+(\w+)", code) or re.match(r"^(\w+):\s*MACRO", code)
                if m:
                    name, body, j = m.group(1), [], i + 1
                    while j < len(lines) and not re.match(r"^\s*ENDM\b", strip_comment(lines[j])[0]):
                        body.append(lines[j])
                        j += 1
                    self.macros.setdefault(name, Macro(name, body, f, i + 1))
                    i = j
                i += 1

    def run(self):
        self.obj = "includes"
        self._file("includes.asm")
        for top in TOP_OBJECTS:
            self.section = None
            self.parent = None
            self.obj = top
            self._file(f"{top}.asm")
        return self.items

    def _emit(self, **kw):
        it = Item(idx=len(self.items), section=self.section, load=self.load,
                  obj=getattr(self, "obj", ""), **kw)
        self.items.append(it)
        return it

    def _file(self, rel: str):
        p = REPO / rel
        if not p.exists():
            return
        self.files_seen.add(rel)
        lines = p.read_text(encoding="utf-8", errors="ignore").splitlines()
        self._lines(lines, rel, [(i + 1) for i in range(len(lines))], macro="", depth=0)

    @staticmethod
    def _join_continuations(lines, linenos):
        out, nums, buf, first = [], [], None, None
        for raw, n in zip(lines, linenos):
            code, comment = strip_comment(raw.rstrip("\r"))
            if code.rstrip().endswith("\\") and not code.rstrip().endswith("\\\\"):
                buf = (buf or "") + code.rstrip()[:-1] + " "
                first = first if first is not None else n
                continue
            if buf is not None:
                out.append(buf + raw.lstrip())
                nums.append(first)
                buf, first = None, None
            else:
                out.append(raw)
                nums.append(n)
        return out, nums

    def _lines(self, lines, rel, linenos, macro, depth, margs=None):
        lines, linenos = self._join_continuations(lines, linenos)
        cond = []  # stack of [active, taken, parent_active]
        skip_macro_def = False
        for raw, n in zip(lines, linenos):
            code, comment = strip_comment(raw)
            s = code.strip()
            if skip_macro_def:
                if re.match(r"^ENDM\b", s):
                    skip_macro_def = False
                continue
            if re.match(r"^MACRO\b", s) or re.match(r"^\w+:\s*MACRO\b", s):
                skip_macro_def = True
                continue
            # Conditional assembly.
            m = re.match(r"^(IF|ELIF|ELSE|ENDC)\b\s*(.*)$", s, re.I)
            if m:
                kw, rest = m.group(1).upper(), m.group(2)
                active_now = all(c[0] for c in cond)
                if kw == "IF":
                    v = eval_cond(self._subst(rest, margs), self.defines)
                    cond.append([v is not False, v is True, active_now])
                elif kw == "ELIF" and cond:
                    c = cond[-1]
                    v = eval_cond(self._subst(rest, margs), self.defines)
                    c[0] = (not c[1]) and v is not False
                    c[1] = c[1] or v is True
                elif kw == "ELSE" and cond:
                    c = cond[-1]
                    c[0] = not c[1]
                elif kw == "ENDC" and cond:
                    cond.pop()
                continue
            if not all(c[0] for c in cond):
                continue
            if margs is not None:
                code = self._subst(code, margs)
                s = code.strip()
            if not s:
                if comment and not macro:
                    self._emit(file=rel, line=n, kind="directive", text="", comment=comment)
                continue
            self._statement(code, s, comment, rel, n, macro, depth)

    def _subst(self, s, margs):
        if not margs:
            return s
        s = s.replace("\\@", f"_u{self._unique}")
        s = s.replace("\\#", ", ".join(margs))
        for i in range(9, 0, -1):
            s = s.replace(f"\\{i}", margs[i - 1] if i <= len(margs) else "")
        s = s.replace("_NARG", str(len(margs)))
        return s

    def _statement(self, code, s, comment, rel, n, macro, depth):
        # Labels (possibly followed by more on the same line).
        m = LABEL_RE.match(code)
        if m and m.group(1).lower() not in MNEMONICS and not s.upper().startswith(("DEF ", "SECTION")):
            name, colons, rest = m.group(1), m.group(2), m.group(3)
            if rest.strip().upper().startswith("MACRO"):
                return
            self._label(name, colons == "::", rel, n, comment, macro)
            if rest.strip():
                self._statement(rest, rest.strip(), "", rel, n, macro, depth)
            return
        if s[:1] == ".":
            m = LOCAL_NOCOLON_RE.match(s)
            if m:
                self._label(m.group(1), False, rel, n, comment, macro)
                if m.group(2).strip():
                    self._statement("\t" + m.group(2), m.group(2).strip(), "", rel, n, macro, depth)
                return
        if code[:1] not in " \t" and GLOBAL_NOCOLON_RE.match(code) and s.lower() not in MNEMONICS \
                and s not in self.macros and s.upper() not in (
                    "ENDC", "ENDR", "ENDL", "ENDU", "NEXTU", "ENDM", "ENDSECTION", "UNION",
                    "RSRESET", "POPO", "PUSHO", "POPS", "PUSHS", "POPC", "PUSHC"):
            self._label(s, False, rel, n, comment, macro)
            return

        parts = s.split(None, 1)
        op_raw = parts[0]
        op = op_raw.lower()
        rest = parts[1] if len(parts) > 1 else ""
        up = op_raw.upper()

        if up == "INCLUDE":
            inc = rest.strip().strip('"')
            if inc.endswith((".asm", ".inc")):
                self._file(inc)
            return
        if up == "SECTION":
            mm = re.match(r'\s*(?:UNION\s+|FRAGMENT\s+)?"([^"]+)"', rest)
            self.section = mm.group(1) if mm else None
            self.parent = None
            self._emit(file=rel, line=n, kind="directive", text=s, comment=comment, op="section",
                       args=[rest], macro=macro)
            return
        if up == "ENDSECTION":
            self.section = None
            return
        if up == "LOAD":
            self.load = True
            return
        if up == "ENDL":
            self.load = False
            return
        if up in ("DEF", "EXPORT", "PURGE", "REDEF", "ASSERT", "STATIC_ASSERT", "WARN", "FAIL",
                  "PRINT", "PRINTLN", "OPT", "PUSHO", "POPO", "PUSHS", "POPS", "CHARMAP", "NEWCHARMAP",
                  "SETCHARMAP", "PUSHC", "POPC", "RSRESET", "RSSET", "SHIFT", "UNION", "NEXTU",
                  "ENDU", "REPT", "FOR", "ENDR", "ALIGN", "BREAK", "ENDM") or " EQU " in f" {s} " \
                or re.match(r"^\w+\s*(=|EQUS|EQU|RB|RW|RL)\b", s):
            return
        if op in DATA_DIRECTIVES or up in DATA_DIRECTIVES:
            self._emit(file=rel, line=n, kind="data", text=s, comment=comment, op=op,
                       args=split_args(rest), macro=macro)
            return
        if op in MNEMONICS:
            args = [a.lower() if a.lower() in PAIRS or a.lower() in REG8 or a.lower() in CONDS
                    or a.lower().startswith("[") and a.lower().rstrip("]").lstrip("[").strip() in
                    ("hl", "hli", "hld", "hl+", "hl-", "bc", "de", "c", "$ff00+c")
                    else a for a in split_args(rest)]
            self._emit(file=rel, line=n, kind="instr", text=s, comment=comment, op=op, args=args,
                       macro=macro)
            return
        name = op_raw.rstrip("?")
        if name in INTRINSIC:
            self._emit(file=rel, line=n, kind="instr", text=s, comment=comment, op=name,
                       args=split_args(rest), macro=macro)
            return
        if name in self.macros and depth < 12:
            mac = self.macros[name]
            margs = split_args(rest)
            self._unique += 1
            self._lines(mac.body, rel, [n] * len(mac.body), macro or name, depth + 1, margs)
            return
        # Unknown statement: keep it visible as an opaque directive.
        self._emit(file=rel, line=n, kind="directive", text=s, comment=comment, op=op,
                   args=split_args(rest), macro=macro)

    def _label(self, name, exported, rel, n, comment, macro):
        if name.startswith("."):
            full = f"{self.parent}{name}" if self.parent else name
            is_global = False
        elif "." in name:
            full = name
            is_global = False
        else:
            full = name
            is_global = True
            self.parent = name
        self._emit(file=rel, line=n, kind="label", text=name, comment=comment, label=full,
                   is_global=is_global, macro=macro)


@lru_cache(None)
def walk(rom_name: str):
    w = Walker(rom_name)
    items = w.run()
    return items, w


# --------------------------------------------------------------------------
# Program model: labels -> item index, section -> bank
# --------------------------------------------------------------------------

class Program:
    def __init__(self, rom_name: str):
        self.rom = load_rom(rom_name)
        self.items, self.walker = walk(rom_name)
        self.label_at = {}
        self.defs = {}   # name -> [idx, ...] (duplicates are object-local labels)
        self._parent = [None] * len(self.items)
        cur = None
        for it in self.items:
            if it.kind == "label":
                self.defs.setdefault(it.label, []).append(it.idx)
            if it.kind == "label" and it.label not in self.label_at:
                self.label_at[it.label] = it.idx
            if it.kind == "label" and it.is_global:
                cur = it.label
            self._parent[it.idx] = cur
        self.scope = in_scope_files()

    def section_bank(self, it: Item):
        if it.load or it.section is None:
            return None
        s = self.rom.sections.get(it.section)
        if s is None or not s.region.startswith("ROM"):
            return None
        return s.bank

    def in_scope(self, it: Item):
        return it.file in self.scope

    def parent_of(self, it: Item):
        return self._parent[it.idx]

    def resolve(self, name: str, at: Item):
        """Resolve a jump/call operand to a label name as the assembler would."""
        if name.startswith("."):
            p = self.parent_of(at)
            return f"{p}{name}" if p else name
        return name

    def def_index(self, name: str, at: Item | None = None):
        """Definition of `name` as the linker would bind it from `at`: an
        object-local (single-colon) duplicate in the same object wins."""
        idxs = self.defs.get(name)
        if not idxs:
            return None
        if at is not None and len(idxs) > 1:
            for i in idxs:
                if self.items[i].obj == at.obj:
                    return i
        return idxs[0]

    def label_loc(self, name: str, at: Item | None = None):
        """(bank, region) where `name` lives: region is HOME, ROMX, RAM or None.
        Prefers the walked definition's section; falls back to the .sym."""
        i = self.def_index(name, at)
        if i is not None:
            it = self.items[i]
            s = self.rom.sections.get(it.section) if it.section and not it.load else None
            if s is not None:
                region = {"ROM0": "HOME", "ROMX": "ROMX", "SRAM": "SRAM"}.get(s.region, "RAM")
                return s.bank, region
        v = self.rom.sym.get(name)
        if v is None:
            return None, None
        a = v[1]
        region = "HOME" if a < 0x4000 else "ROMX" if a < 0x8000 else \
            "SRAM" if 0xA000 <= a < 0xC000 else "RAM"
        return v[0], region

    def label_section(self, name: str, at: Item | None = None):
        i = self.def_index(name, at)
        if i is not None and self.items[i].section:
            return self.items[i].section
        s = self.rom.addr_of.get(name)
        return s.name if s else None


def where(it: Item):
    return f"{it.file}:{it.line}"
