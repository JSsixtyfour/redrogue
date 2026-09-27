"""Interprocedural register/stack dataflow over the walked program.

Each register holds a SET of abstract values (union at control-flow merges):
    "E<r>"   the value register <r> held when the routine was entered, so a
             `push de / pop hl` makes h, l hold "Ed", "Ee" and a read through
             hl is credited to the caller's d, e
    "D"      defined inside the routine (or by a callee)
    "G<idx>" garbage manufactured by a bank-crossing boundary at item <idx>
             (farcall entry/exit, predef, homecall) - see lib's docstring

Per entry label we compute a Summary:
    reads     registers read while still holding the entry value
    clobbers  registers whose value at some exit is not the entry value
    opaque    control left through something we cannot see (jp hl, unknown
              call target, macro we didn't expand). Callers then assume
              every register is clobbered and nothing is read.

Push/pop move value SETS through a modelled stack, so `push bc ... pop bc`
correctly restores "E<r>" and garbage pushed then popped is still garbage.

Summaries are solved to a fixpoint over the whole call graph (recursion and
mutual tail calls included). Findings are collected on the final pass only.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

from lib import FAR_CALL, FAR_JUMP, PAIRS, REG8, Item, Program

ALL = frozenset(REG8)
ENTRY = {r: frozenset({"E" + r}) for r in REG8}

# Hardware state carried like registers. "Hin" = whatever the caller had.
#   sram: open / closed        (rRAMG)
#   ramb: 0 / nz               (rRAMB, the SRAM bank)
#   svbk: 1 / x                (rSVBK, the WRAM bank)
#   ime : on / off             (di / ei)
HW = ("sram", "ramb", "svbk", "ime")
HIN = frozenset({"Hin"})
SRAM_ENABLE_CONSTS = {"ramg_sram_enable", "sram_enable", "$0a", "10", "$a"}


def entry_origins(vals):
    return [v[1:] for v in vals if v.startswith("E")]
D = frozenset({"D"})
MEMREG = {"[hl]": ("h", "l"), "[hli]": ("h", "l"), "[hld]": ("h", "l"), "[hl+]": ("h", "l"),
          "[hl-]": ("h", "l"), "[bc]": ("b", "c"), "[de]": ("d", "e"), "[c]": ("c",),
          "[$ff00+c]": ("c",)}
HL_INCDEC = {"[hli]", "[hld]", "[hl+]", "[hl-]"}
FLAG_TEST_OPS = {"cp", "bit"}  # instructions whose only purpose is setting flags


def regs_of(arg: str):
    a = arg.lower()
    if a in PAIRS:
        return PAIRS[a]
    if a in REG8:
        return (a,)
    return ()


def is_g(vals):
    return any(v.startswith("G") for v in vals)


def g_sites(vals):
    return sorted(int(v[1:]) for v in vals if v.startswith("G"))


@dataclass
class Summary:
    reads: frozenset = frozenset()
    clobbers: frozenset = frozenset()
    opaque: bool = False
    hw: tuple = ()          # ((var, values at exit), ...) for HW vars a callee changes

    def key(self):
        return (self.reads, self.clobbers, self.opaque, self.hw)


OPAQUE = Summary(frozenset(), ALL, True)


@dataclass
class State:
    regs: dict
    stack: tuple            # tuple of (pairname, (vals...)) ; ("?", None) = unknown slot
    flags_pending: int = -1  # idx of a cp/bit whose flags nothing has read yet
    flags_lost: int = -1     # idx of that cp/bit if a pop af then overwrote f
    push_af_at: int = -1
    zgarbage: int = -1       # idx of `and a`/`or a` that tested a garbage a
    sp_lost: bool = False    # sp was reassigned (ld sp / add sp): stack no longer modelled

    def copy(self):
        return State(dict(self.regs), self.stack, self.flags_pending, self.flags_lost,
                     self.push_af_at, self.zgarbage, self.sp_lost)

    def key(self):
        return (tuple(sorted((k, v) for k, v in self.regs.items())), self.stack,
                self.flags_pending, self.flags_lost, self.zgarbage, self.sp_lost)


def merge(a: State, b: State):
    """Union merge. Returns (state, depth_conflict)."""
    regs = {r: a.regs[r] | b.regs[r] for r in a.regs}
    conflict = len(a.stack) != len(b.stack)
    if conflict:
        stack = a.stack if len(a.stack) <= len(b.stack) else b.stack
    else:
        stack = tuple(
            (x[0], tuple(p | q for p, q in zip(x[1], y[1])))
            if x[0] == y[0] and x[1] is not None and y[1] is not None else ("?", None)
            for x, y in zip(a.stack, b.stack))
    return State(regs, stack, max(a.flags_pending, b.flags_pending),
                 max(a.flags_lost, b.flags_lost), max(a.push_af_at, b.push_af_at),
                 max(a.zgarbage, b.zgarbage), a.sp_lost or b.sp_lost),         conflict and not (a.sp_lost or b.sp_lost)


@dataclass
class Finding:
    rule: str
    item: Item
    entry: str
    msg: str
    extra: dict = field(default_factory=dict)


class Flow:
    def __init__(self, prog: Program):
        self.p = prog
        self.items = prog.items
        self.summaries: dict[str, Summary] = {}
        self.collect = False
        self.findings: list[Finding] = []
        self._seen_findings = set()
        # Tail-calling one of these ends the activity (e.g. TextScriptEnd ends a
        # text_asm handler's text), so that exit is not a return to the caller.
        self.term: set[str] = set()
        self.called = set()  # labels entered by call/far-call/predef: stack = just the return
        for it in self.items:
            if it.kind == "instr" and it.args and (it.op == "call" or it.op in FAR_CALL
                                                   or it.op in FAR_JUMP
                                                   or it.op in ("predef", "predef_jump",
                                                                "homecall", "homecall_sf")):
                t = it.args[-1] if it.op == "call" else it.args[0]
                self.called.add(prog.resolve(t, it))
        self.why = {}   # (entry, reg) -> idx of the item that first reads the entry value
        self._zval = {}  # idx of an `and a`/`or a` -> the a it tested
        # next code/data/label item after each index, for fall-through
        self._next = [None] * len(self.items)
        nxt = None
        for i in range(len(self.items) - 1, -1, -1):
            self._next[i] = nxt
            it = self.items[i]
            if it.kind in ("instr", "data", "label") or (it.kind == "directive" and it.op):
                nxt = i

    # ------------------------------------------------------------------
    def entry_parent(self, label):
        return label.split(".")[0]

    def summary(self, label) -> Summary:
        if label not in self.p.label_at:
            return OPAQUE
        return self.summaries.get(label, Summary())

    def solve(self, labels, max_rounds=40):
        """Two phases, because entry reads SHRINK as callee clobbers grow:
        1. clobbers/opaque (monotone growing) to a fixpoint, reads ignored;
        2. with those frozen, reads (monotone growing) to a fixpoint."""
        labels = [l for l in labels if l in self.p.label_at]
        rounds = 0
        for phase in (1, 2):
            for _ in range(max_rounds):
                rounds += 1
                changed = 0
                for l in labels:
                    s = self.analyze(l)
                    old = self.summaries.get(l, Summary())
                    if phase == 1:
                        ohw, shw = dict(old.hw), dict(s.hw)
                        hw = tuple((v, ohw.get(v, frozenset()) | shw.get(v, frozenset()))
                                   for v in HW if v in ohw or v in shw)
                        new = Summary(frozenset(), s.clobbers | old.clobbers, s.opaque or old.opaque, hw)
                    else:
                        new = Summary(s.reads | old.reads, old.clobbers, old.opaque, old.hw)
                    if new.key() != old.key() or l not in self.summaries:
                        self.summaries[l] = new
                        changed += 1
                if not changed:
                    break
        return rounds

    def run_findings(self, labels):
        # silent pass so `why` reflects the converged summaries before any
        # finding quotes it
        self.why = {}
        self._zval = {}
        for l in labels:
            if l in self.p.label_at:
                self.analyze(l)
        self.collect = True
        self.findings = []
        self._seen_findings = set()
        for l in labels:
            if l in self.p.label_at:
                self.analyze(l)
        self.collect = False
        return self.findings

    def _find(self, rule, it, entry, msg, **extra):
        if not self.collect:
            return
        k = (rule, it.idx, msg)
        if k in self._seen_findings:
            return
        self._seen_findings.add(k)
        self.findings.append(Finding(rule, it, entry, msg, extra))

    # ------------------------------------------------------------------
    def analyze(self, entry: str) -> Summary:
        start = self.p.label_at[entry]
        parent = self.entry_parent(entry)
        init = State({**ENTRY, **{v: HIN for v in HW}}, ())
        # a routine only ever jumped to is a continuation: whatever its jumper
        # left pushed is its to pop, so its stack discipline is not checkable
        # in isolation and pops past the bottom are not findings there
        self._stack_checked = entry in self.called
        reads, clob = set(), set()
        hwx = {v: frozenset() for v in HW}
        self.last_exits = set()
        opaque = False
        states: dict[int, State] = {}
        work = [(start, init)]
        steps = 0
        while work:
            i, st = work.pop()
            steps += 1
            if steps > 20000:
                opaque = True
                break
            if i in states:
                m, conflict = merge(states[i], st)
                if conflict and self._stack_checked:
                    self._find("A1", self.items[i], entry,
                               f"stack depth differs on paths merging here "
                               f"({len(states[i].stack)} vs {len(st.stack)})")
                if m.key() == states[i].key():
                    continue
                states[i] = m
                st = m
            else:
                states[i] = st
            for succ, s2, exit_ in self.step(i, st.copy(), entry, parent, reads):
                if exit_ is not None:
                    kind, xs = exit_
                    self.last_exits.add(kind)
                    if kind == "opaque":
                        opaque = True
                    elif kind == "term":
                        pass  # left through a routine that ends the whole activity
                    else:
                        for r in REG8:
                            if xs.regs[r] != ENTRY[r]:
                                clob.add(r)
                        for v in HW:
                            hwx[v] = hwx[v] | xs.regs[v]
                        self._hw_exit_check(self.items[i], entry, xs)
                    continue
                work.append((succ, s2))
        hw = tuple((v, hwx[v]) for v in HW if hwx[v] and hwx[v] != HIN)
        return Summary(frozenset(reads), frozenset(clob), opaque, hw)

    def _hw_exit_check(self, it, entry, xs):
        if not (self.collect and self._stack_checked):
            return
        if "open" in xs.regs["sram"]:
            self._find("A2", it, entry, "can return with SRAM still enabled (rRAMG)")
        if any(v.startswith("b") and v != "b0" and not v.endswith("*") for v in xs.regs["ramb"]):
            self._find("A2", it, entry, "can return with the SRAM bank (rRAMB) left non-zero")
        if "x" in xs.regs["svbk"]:
            self._find("A2", it, entry, "can return with a WRAM bank other than 1 mapped (rSVBK)")
        if "off" in xs.regs["ime"]:
            self._find("A2", it, entry, "can return with interrupts disabled (di without ei)")

    # ------------------------------------------------------------------
    def read(self, st, regs, it, entry, reads, why=""):
        for r in regs:
            v = st.regs[r]
            for o in entry_origins(v):
                reads.add(o)
                self.why.setdefault((entry, o), it.idx)
            if is_g(v):
                self._find("B5", it, entry,
                           f"reads `{r}` holding garbage from the bank-crossing boundary at "
                           + ", ".join(f"{self.items[g].file}:{self.items[g].line}" for g in g_sites(v))
                           + (f" ({why})" if why else ""), reg=r, sites=g_sites(v))

    def why_chain(self, target, r, depth=6):
        """Human trail of where `target` consumes its entry value of r."""
        out, cur = [], target
        for _ in range(depth):
            idx = self.why.get((cur, r))
            if idx is None:
                break
            it = self.items[idx]
            out.append(f"{it.file}:{it.line} `{it.text}`")
            nxt = None
            if it.kind == "instr" and it.op in ("call", "jp", "jr") and it.args:
                nxt = self.p.resolve(it.args[-1], it)
            elif it.kind == "label":
                nxt = it.label
            if not nxt or nxt == cur or (nxt, r) not in self.why:
                break
            cur = nxt
        return " -> ".join(out) or "?"

    def write(self, st, regs, val=D):
        for r in regs:
            st.regs[r] = val

    def apply_call(self, st, target, it, entry, reads, garbage_in=()):
        """Plain call semantics against target's summary."""
        s = self.summary(target)
        st.zgarbage = -1
        if s.opaque:
            for r in REG8:
                st.regs[r] = D
            return s
        for r in s.reads:
            v = st.regs[r]
            for o in entry_origins(v):
                reads.add(o)
                self.why.setdefault((entry, o), it.idx)
            if is_g(v):
                if r in garbage_in:
                    self._find("B4", it, entry,
                               f"`{target}` reads `{r}` on entry ({self.why_chain(target, r)}), "
                               f"but `{it.op}` has already destroyed it",
                               reg=r, target=target)
                else:
                    self._find("B5", it, entry,
                               f"passes garbage `{r}` (from bank-crossing boundary at "
                               + ", ".join(f"{self.items[g].file}:{self.items[g].line}" for g in g_sites(v))
                               + f") into `{target}`, which reads it", reg=r, target=target)
        for r in s.clobbers:
            st.regs[r] = D
        for v, ex in s.hw:
            # values a callee leaves behind are marked `*` (inherited), so the
            # exit check blames the routine that introduced a state, not
            # every caller above it
            st.regs[v] = frozenset(x if x.endswith("*") or x == "?" else x + "*"
                                   for x in ex - HIN) | \
                (st.regs[v] if "Hin" in ex else frozenset())
        return s

    def resolve_target(self, name, it):
        return self.p.resolve(name, it)

    def local_to(self, label, parent):
        return self.entry_parent(label) == parent and label in self.p.label_at

    # ------------------------------------------------------------------
    def step(self, i, st: State, entry, parent, reads):
        """Yield (successor_idx, state, exit) for item i."""
        it = self.items[i]
        nxt = self._next[i]

        def fall(s):
            if nxt is None:
                return [(None, s, ("opaque", s))]
            n = self.items[nxt]
            if n.kind == "label" and n.is_global and n.label != entry and not s.stack:
                # fall-through into another routine == tail call to it. With
                # values still pushed it is a continuation that will pop them,
                # so it is followed inline instead (PlaceString -> PlaceNextChar).
                s2 = s.copy()
                self.apply_call(s2, n.label, it, entry, reads)
                return [(None, s2, (self._tail_kind(n.label), s2))]
            if n.kind == "data":
                self._find("C1", it, entry, "execution falls through into data")
                return [(None, s, ("opaque", s))]
            if n.kind == "directive" and n.op == "section":
                self._find("C1", it, entry, "execution falls off the end of the SECTION")
                return [(None, s, ("opaque", s))]
            return [(nxt, s, None)]

        if it.kind == "label":
            if it.is_global and it.label != entry and it.idx != self.p.label_at[entry] \
                    and not st.stack:
                s2 = st.copy()
                self.apply_call(s2, it.label, it, entry, reads)
                return [(None, s2, (self._tail_kind(it.label), s2))]
            return fall(st)
        if it.kind == "data":
            return [(None, st, ("opaque", st))]
        if it.kind == "directive":
            if it.op and it.op != "section" and it.text:
                # an unexpanded statement inside code: can't model it
                return [(None, st, ("opaque", st))]
            return fall(st)

        op, args = it.op, it.args
        a0 = args[0] if args else ""
        a1 = args[1] if len(args) > 1 else ""

        # ---------------- bank-crossing pseudo-ops ----------------
        if op in FAR_CALL or op in FAR_JUMP:
            tgt = args[0] if args else ""
            g = frozenset({f"G{i}"})
            for r in ("a", "b", "c", "h", "l"):
                st.regs[r] = g
            self.apply_call(st, tgt, it, entry, reads, garbage_in=("a", "b", "c", "h", "l"))
            for r in ("a", "b", "c"):
                st.regs[r] = g
            if op in FAR_JUMP:
                return [(None, st, ("ret", st))]
            st.flags_pending = -1
            return fall(st)
        if op in ("predef", "predef_jump"):
            tgt = args[0] if args else ""
            g = frozenset({f"G{i}"})
            for r in ("a", "d", "e", "h", "l"):
                st.regs[r] = g
            self.apply_call(st, tgt, it, entry, reads, garbage_in=("a", "d", "e", "h", "l"))
            st.regs["a"] = g
            st.regs["f"] = g
            if op == "predef_jump":
                return [(None, st, ("ret", st))]
            return fall(st)
        if op in ("homecall", "homecall_sf"):
            tgt = args[0] if args else ""
            g = frozenset({f"G{i}"})
            st.regs["a"] = g
            self.apply_call(st, tgt, it, entry, reads, garbage_in=("a",))
            st.regs["a"] = g
            if op == "homecall":
                st.regs["f"] = g
            else:
                st.regs["b"] = g
                st.regs["c"] = g
            return fall(st)

        # ---------------- control flow ----------------
        cond = a0 if a0 in ("z", "nz", "c", "nc") and (
            len(args) == 2 or (op == "ret" and len(args) == 1)) else None
        tgt = a1 if cond else a0
        if op in ("jr", "jp", "call", "ret") and cond:
            self.read(st, ("f",), it, entry, reads, "condition")
            self._flag_check(st, it, entry)
            st.flags_pending = -1  # the test has been consumed
            if cond in ("z", "nz") and st.zgarbage >= 0:
                src = self.items[st.zgarbage]
                zv = self._zval.get(st.zgarbage, frozenset())
                for o in entry_origins(zv):
                    reads.add(o)
                    self.why.setdefault((entry, o), st.zgarbage)
                if is_g(zv):
                    self._find("B5", it, entry,
                               f"branches on Z from `{src.text}` at {src.file}:{src.line}, which "
                               "tested an `a` a bank-crossing boundary had already destroyed")
        if op in ("jp", "jr"):
            if tgt in ("hl", "[hl]"):
                self.read(st, ("h", "l"), it, entry, reads)
                return [(None, st, ("opaque", st))]
            lab = self.resolve_target(tgt, it)
            out = []
            here = self.p.parent_of(it)
            ret_to = self.pushed_return(st)
            if ret_to is not None and not (lab == here or ("." in lab and self.entry_parent(lab) == here)):
                # `ld de, .back / push de / jp Routine`: a hand-rolled call
                s2 = st.copy()
                s2.stack = s2.stack[:-1]
                self.apply_call(s2, lab, it, entry, reads)
                out.append((self.p.label_at[ret_to], s2, None))
                if cond:
                    out += fall(st)
                return out
            inline = lab in self.p.label_at and (
                lab == entry or lab == here
                or ("." in lab and self.entry_parent(lab) == here)
                or bool(st.stack))  # continuation that will pop what we pushed
            if inline:
                out.append((self.p.label_at[lab], st.copy(), None))
            else:
                s2 = st.copy()
                self.apply_call(s2, lab, it, entry, reads)
                out.append((None, s2, (self._tail_kind(lab), s2)))
            if cond:
                out += fall(st)
            return out
        if op == "call":
            lab = self.resolve_target(tgt, it)
            s2 = st.copy()
            self.apply_call(s2, lab, it, entry, reads)
            s2.flags_pending = -1
            out = fall(s2)
            if cond:
                out += fall(st)
            return out
        if op in ("ret", "reti"):
            ret_to = self.pushed_return(st)
            if ret_to is not None:
                # `ld de, Label / push de / ret`: a jump to Label
                s2 = st.copy()
                s2.stack = s2.stack[:-1]
                out = [(self.p.label_at[ret_to], s2, None)]
                return out + (fall(st) if cond else [])
            prev = self.items[i - 1] if i else None
            if st.stack and prev is not None and prev.kind == "instr" and prev.op == "push":
                # `push de / ret` of a computed address: an indirect jump
                out = [(None, st, ("opaque", st))]
                return out + (fall(st) if cond else [])
            if st.stack and not st.sp_lost:
                self._find("A1", it, entry,
                           f"`{op}` with {len(st.stack)} value(s) still pushed: returns into a "
                           "pushed value, not the caller")
            out = [(None, st, ("ret", st))]
            if cond:
                out += fall(st)
            return out
        if op == "rst":
            v = a0.lower()
            if v in ("$38", "38h", "56"):
                return [(None, st, ("opaque", st))]
            for r in REG8:
                st.regs[r] = D
            return [(None, st, ("opaque", st))] if v in ("$08", "$18", "rst_farcall", "rst_farjump") \
                else fall(st)

        # ---------------- stack ----------------
        if op == "push":
            pr = a0.lower()
            regs = PAIRS.get(pr, ())
            for r in regs:
                if r in ("sp",):
                    continue
                if "E" in st.regs[r]:
                    pass  # pushing the entry value is not a use of it
            st.stack = st.stack + ((pr, tuple(st.regs[r] for r in regs)),)
            if pr == "af":
                st.push_af_at = i
            return fall(st)
        if op == "pop":
            pr = a0.lower()
            regs = PAIRS.get(pr, ())
            if not st.stack:
                if self._stack_checked and not st.sp_lost:
                    self._find("A1", it, entry,
                               f"`pop {pr}` with nothing pushed in this routine: pops the caller's "
                               "return address (deliberate only for inline-argument tricks)")
                for r in regs:
                    st.regs[r] = D
                if st.sp_lost or not self._stack_checked:
                    return fall(st)
                return [(None, st, ("opaque", st))]
            slot = st.stack[-1]
            st.stack = st.stack[:-1]
            if slot[1] is None or len(slot[1]) != len(regs):
                for r in regs:
                    st.regs[r] = D
            else:
                for r, v in zip(regs, slot[1]):
                    st.regs[r] = v
            if pr == "af" and st.flags_pending >= 0:
                st.flags_lost = st.flags_pending
                st.flags_pending = -1
            return fall(st)

        # ---------------- hardware state ----------------
        if op == "di":
            st.regs["ime"] = frozenset({"off"})
        elif op == "ei":
            st.regs["ime"] = frozenset({"on"})
        if op in ("ld", "ldh") and a1.lower().replace(" ", "") == "a":
            dst = a0.lower().replace(" ", "")
            konst = {v[2:].lower() for v in st.regs["a"] if v.startswith("K:")}
            konst_raw = {v[2:] for v in st.regs["a"] if v.startswith("K:")}
            only_k = bool(konst) and all(v.startswith("K:") for v in st.regs["a"])
            saved = {v[3:] for v in st.regs["a"] if v.startswith("SV:")}
            only_saved = bool(saved) and all(v.startswith("SV:") for v in st.regs["a"])
            if dst in ("[rramg]", "[$0000]"):
                if only_k:
                    st.regs["sram"] = frozenset("open" if k in SRAM_ENABLE_CONSTS else "closed"
                                                for k in konst)
                else:
                    st.regs["sram"] = frozenset({"?"})
            elif dst in ("[rramb]", "[$4000]"):
                if only_k:
                    st.regs["ramb"] = frozenset(self.sram_bank_of(k) for k in konst_raw)
                else:
                    st.regs["ramb"] = frozenset({"?"})
            elif dst == "[rsvbk]":
                if only_saved:
                    st.regs["svbk"] = frozenset(saved)   # restoring what was read earlier
                elif only_k:
                    st.regs["svbk"] = frozenset("1" if k in ("1", "$1", "$01") else "x"
                                                for k in konst)
                else:
                    st.regs["svbk"] = frozenset({"?"})
        sram_refs = []
        for x in (a0, a1):
            xl = x.strip()
            if xl.startswith("[") and xl.endswith("]"):
                sram_refs.append(xl[1:-1].strip())
        if op == "ld" and a0.lower() in ("hl", "de", "bc"):
            sram_refs.append(a1.strip())
        for ref in sram_refs:
            sbank, region = self.p.label_loc(ref, it)
            if region != "SRAM" or not self._stack_checked:
                continue
            banks = st.regs["ramb"]
            wrong = sorted(v.rstrip("*") for v in banks
                           if v.startswith("b") and v.rstrip("*") != f"b{sbank}")
            if wrong:
                self._find("A2", it, entry,
                           f"reaches SRAM `{ref}` (bank {sbank}) on a path where SRAM bank "
                           + "/".join(w[1:] for w in wrong) + " is mapped")
        for x in (a0, a1):
            xl = x.strip()
            if xl.startswith("[") and xl.endswith("]"):
                region = self.p.label_loc(xl[1:-1].strip(), it)[1]
                if region == "SRAM" and self._stack_checked and (
                        "closed" in st.regs["sram"] or "closed*" in st.regs["sram"]):
                    self._find("A2", it, entry,
                               f"touches SRAM `{xl}` on a path where SRAM was disabled "
                               "(by this routine or a callee)")

        # ---------------- data movement / ALU ----------------
        rd, wr = self.effects(op, args)
        rd = {r for r in rd if r in REG8}
        wr = {r for r in wr if r in REG8}
        z_idiom = op in ("and", "or") and [x.lower() for x in args] == ["a"]             and (is_g(st.regs["a"]) or bool(entry_origins(st.regs["a"])))
        if z_idiom:
            # `and a` / `or a` on a garbage a is the carry-clear idiom; it only
            # matters if a z/nz branch later consumes the Z it computed.
            a_before = st.regs["a"]
            rd = rd - {"a"}
        if rd:
            self.read(st, rd, it, entry, reads)
        if "f" in rd:
            self._flag_check(st, it, entry)
            st.flags_pending = -1
        for r in wr:
            st.regs[r] = D
        if op in ("xor", "sub") and [x.lower() for x in args] == ["a"]:
            st.regs["a"] = frozenset({"K:0"})
        elif op in ("ld", "ldh") and a0.lower() == "a" and a1.lower().replace(" ", "") == "[rsvbk]":
            st.regs["a"] = frozenset("SV:" + v for v in st.regs["svbk"])
        elif op == "ld" and a0.lower() == "a" and a1 and not a1.strip().startswith("[")                 and a1.lower().strip() not in REG8:
            st.regs["a"] = frozenset({"K:" + a1.replace(" ", "")})
        if op == "ld" and a0.lower() in ("bc", "de", "hl") and a1:
            lab = self.p.resolve(a1.strip(), it)
            if lab in self.p.label_at and self.items[lab_idx := self.p.label_at[lab]].kind == "label":
                nx = self._next[lab_idx]
                while nx is not None and self.items[nx].kind == "label":
                    nx = self._next[nx]
                if nx is not None and self.items[nx].kind == "instr":
                    for r in PAIRS[a0.lower()]:
                        st.regs[r] = frozenset({"L:" + lab})
        if "f" in wr:
            st.flags_lost = -1
            st.flags_pending = i if op in FLAG_TEST_OPS else -1
            st.zgarbage = -1
        if z_idiom:
            st.regs["a"] = a_before
            st.zgarbage = i
            self._zval[i] = self._zval.get(i, frozenset()) | a_before
        if op in ("ld", "add", "inc", "dec") and a0.lower() == "sp":
            st.sp_lost = True
            st.stack = ()
        return fall(st)

    def sram_bank_of(self, k):
        """Value written to rRAMB -> "b<N>" or "?"."""
        kl = k.lower()
        m = re.fullmatch(r'bank\((.+)\)', k, re.I)
        if m:
            arg = m.group(1).strip()
            if arg.startswith('"'):
                sec = self.p.rom.sections.get(arg.strip('"'))
                return f"b{sec.bank}" if sec else "?"
            b = self.p.label_loc(arg)[0]
            return f"b{b}" if b is not None else "?"
        try:
            return f"b{int(kl[1:], 16) if kl.startswith('$') else int(kl)}"
        except ValueError:
            return "?"

    def _tail_kind(self, label):
        return "term" if label in self.term else "ret"

    def pushed_return(self, st):
        """Label on top of the stack if it was pushed from `ld rr, <code label>`."""
        if not st.stack or st.stack[-1][1] is None:
            return None
        vals = st.stack[-1][1]
        labs = {v[2:] for vs in vals for v in vs if v.startswith("L:")}
        if len(labs) == 1 and all(all(v.startswith("L:") for v in vs) for vs in vals):
            lab = labs.pop()
            return lab if lab in self.p.label_at else None
        return None

    def _flag_check(self, st, it, entry):
        if st.flags_lost >= 0:
            src = self.items[st.flags_lost]
            self._find("B8", it, entry,
                       f"branches on flags restored by `pop af`, discarding the "
                       f"`{src.text}` at {src.file}:{src.line} that looks meant for it")
            st.flags_lost = -1

    # ------------------------------------------------------------------
    @staticmethod
    def effects(op, args):
        """(reads, writes) register sets for a non-control instruction."""
        rd, wr = set(), set()

        def operand_reads(x):
            xl = x.lower().replace(" ", "")
            if xl in MEMREG:
                return set(MEMREG[xl])
            return set(regs_of(xl))

        def memwrites(x):
            xl = x.lower().replace(" ", "")
            return {"h", "l"} if xl in HL_INCDEC else set()

        a0 = args[0] if args else ""
        a1 = args[1] if len(args) > 1 else ""
        if op in ("ld", "ldh", "ldi", "ldd"):
            d0 = a0.lower().replace(" ", "")
            if op == "ld" and d0 == "hl" and a1.lower().replace(" ", "").startswith("sp"):
                return {"sp"} - {"sp"}, {"h", "l", "f"}
            if d0.startswith("["):
                rd |= operand_reads(a0) | operand_reads(a1)
                wr |= memwrites(a0)
                rd |= memwrites(a0)
            else:
                wr |= set(regs_of(d0))
                rd |= operand_reads(a1)
                wr |= memwrites(a1)
                rd |= memwrites(a1)
            if op in ("ldi", "ldd"):
                rd |= {"h", "l"}
                wr |= {"h", "l"}
            return rd, wr
        if op in ("add", "adc", "sub", "sbc", "and", "xor", "or", "cp"):
            if len(args) == 2 and a0.lower() in ("hl", "sp"):
                if a0.lower() == "sp":
                    return set(), {"f"}
                rd |= {"h", "l"} | set(regs_of(a1))
                wr |= {"h", "l", "f"}
                return rd, wr
            src = a1 if len(args) == 2 else a0
            srcl = src.lower().replace(" ", "")
            if op in ("xor", "sub") and srcl == "a":
                return set(), {"a", "f"}  # xor a / sub a: constant 0
            rd |= {"a"} | operand_reads(src)
            if op in ("adc", "sbc"):
                rd.add("f")
            wr |= {"f"} if op == "cp" else {"a", "f"}
            wr |= memwrites(src)
            return rd, wr
        if op in ("inc", "dec"):
            x = a0.lower().replace(" ", "")
            if x in ("bc", "de", "hl"):
                return set(PAIRS[x]), set(PAIRS[x])
            if x == "sp":
                return set(), set()
            if x.startswith("["):
                return operand_reads(x), {"f"}
            return {x}, {x, "f"}
        if op in ("rlca", "rrca"):
            return {"a"}, {"a", "f"}
        if op in ("rla", "rra"):
            return {"a", "f"}, {"a", "f"}
        if op == "cpl":
            return {"a"}, {"a"}
        if op == "daa":
            return {"a", "f"}, {"a", "f"}
        if op == "scf":
            return set(), {"f"}
        if op == "ccf":
            return {"f"}, {"f"}
        if op in ("rlc", "rrc", "sla", "sra", "srl", "swap", "rl", "rr"):
            x = a0.lower().replace(" ", "")
            r = operand_reads(x)
            w = set() if x.startswith("[") else {x}
            if op in ("rl", "rr"):
                r.add("f")
            return r | w, w | {"f"}
        if op == "bit":
            return operand_reads(a1), {"f"}
        if op in ("set", "res"):
            x = a1.lower().replace(" ", "")
            r = operand_reads(x)
            return r, set() if x.startswith("[") else {x}
        return set(), set()  # nop, di, ei, halt, stop


def code_entries(prog: Program):
    """Routine entry points: global labels that start code, plus every label
    reached by a call / far-call / predef / homecall, or by a jump from a
    different routine."""
    labels = set()
    items = prog.items
    for it in items:
        if it.kind == "label" and it.is_global:
            n = it.idx + 1
            while n < len(items) and items[n].kind in ("label", "directive") and                     not (items[n].kind == "directive" and items[n].op):
                n += 1
            if n < len(items) and items[n].kind == "instr":
                labels.add(it.label)
        elif it.kind == "instr" and it.args and (
                it.op in ("call", "jp", "jr") or it.op in FAR_CALL | FAR_JUMP
                or it.op in ("predef", "predef_jump", "homecall", "homecall_sf")):
            t = it.args[-1] if it.op in ("call", "jp", "jr") else it.args[0]
            t = prog.resolve(t, it)
            if t not in prog.label_at:
                continue
            if it.op in ("jp", "jr") and "." in t and t.split(".")[0] == prog.parent_of(it):
                continue
            labels.add(t)
    return sorted(labels)
