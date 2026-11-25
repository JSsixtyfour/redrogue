"""Bill's PC fuzzer: random input on unusual rosters, with every mon tagged.

The autoplay "pc" errand plays one tidy script (deposit, withdraw, two swaps, STATS) on
whatever roster a run has. This plays random input (RELEASE and CHANGE BOX included) on
party sizes 1-6 and box sizes 0 / 1 / 2 / 10 / 19 / 20, where the edge code lives: the last
party mon, a full box, a full party, an empty slot, the last occupied slot.

Every mon gets its own OT id, nickname and OT name. At each grid input poll
(BillsPC_.inputLoop): counts in range, species lists matching the structs and terminated,
no tag twice, no tag missing unless RELEASE took that very mon, each nickname and OT name
still on its own mon, and its species, moves, DVs, exp and catch-rate flags unchanged.
Other boxes are read from SRAM, so a box change cannot hide a loss. autoplay_checks
(crash, stack, garbled screen, party data) and the branch freeze watch are armed too.

    python3 tools/pyboy_smoke/bills_pc_fuzz.py --seeds 1-200 --jobs 6
    ... --cgb
"""
from __future__ import annotations

import argparse
import io
import json
import os
import random
import sys
import time
import traceback
from collections import Counter

import autoplay
import autoplay_branch
import run_autoplay
from harness import RedRogueHarness

ROOT, ARTIFACTS = autoplay.ROOT, autoplay.ARTIFACTS
PARTY_STRUCT, BOX_STRUCT, NAME = 0x2C, 0x21, 11
PARTY_MAX, BOX_MAX = 6, 20
OTID = 0x0C
BUTTONS = (("a", 38), ("b", 8), ("up", 10), ("down", 20), ("left", 8), ("right", 14), ("start", 2))
TAG_BASE = 0x5000
FIXED = (0x00, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0E, 0x0F, 0x10, 0x1B, 0x1C)  # species, types, flags, moves, exp, DVs


class StopAtMenu(Exception):
    pass


def name_bytes(letter: int, tag: int) -> list[int]:
    return [letter, 0xF6 + tag // 10, 0xF6 + tag % 10, 0x50] + [0x50] * (NAME - 4)


def main_menu_state(cgb: bool) -> tuple[RedRogueHarness, bytes]:
    """A harness parked at a Bridge room PC's main menu, the state before BILL's PC is entered."""
    h = RedRogueHarness(ROOT, ARTIFACTS, cgb_mode=cgb)
    autoplay.boot(h, 1)
    agent = autoplay.AutoplayAgent(h, seed=1, errands=frozenset({"pc"}))
    seen = {"menu": False}
    h.register_hook("PCMainMenu", lambda _c: seen.update(menu=True))
    for _ in range(60000):
        agent.step()
        if seen["menu"] and agent.last_wait_caller.startswith("HandleMenuInput") \
                and agent.last_menu_caller.startswith("PCMainMenu"):
            break
    else:
        raise RuntimeError("the PC main menu was never reached")
    state = io.BytesIO()
    h.save_state(state)
    h.close()
    h = RedRogueHarness(ROOT, ARTIFACTS, cgb_mode=cgb)
    return h, state.getvalue()


class PCDriver(autoplay_branch.BranchDriver):
    def __init__(self, h, seed: int):
        super().__init__(h)
        self.rng = random.Random(f"bills_pc/{seed}")
        self.exposure: Counter = Counter()
        self.released: set[int] = set()
        self.releasing = False
        self.home: dict[int, tuple] = {}
        self.rebase = False
        # Back in the lobby, random input can reach the move tutor, a TM or a trade: the next
        # visit starts from whatever the roster is then (seeds 77 and 310, 2026-11-24).
        h.register_hook("JoypadOverworld", lambda _c: setattr(self, "rebase", True))
        for label in ("DepositBillsPCSelectedPartyMon", "WithdrawBillsPCSelectedBoxMon", "ExecuteBillsPCSwap",
                      "StatusScreen", "ChangeBox", "BillsPC_"):
            if label in h.symbols._symbols:
                h.register_hook(label, lambda _c, name=label: self.exposure.update([name]))
        h.register_hook("ReleaseBillsPCSelectedBoxMon", lambda _c: setattr(self, "releasing", True))
        h.register_hook("RemovePokemon", self._on_remove)
        h.register_hook("BillsPC_.inputLoop", self._on_poll)
        self.polls = 0

    # ---------------------------------------------------------------- fixture
    def build(self, party: int, box: int) -> None:
        h, rng = self.h, self.rng
        seed_mons = [h.read_bytes("wPartyMons", PARTY_STRUCT * PARTY_MAX)[i * PARTY_STRUCT:(i + 1) * PARTY_STRUCT]
                     for i in range(h.read8("wPartyCount"))]
        species = [m[0] for m in seed_mons]

        def put(label, values, offset=0):
            base = h.address(label) + offset
            for i, value in enumerate(values):
                h.pyboy.memory[base + i] = value

        for tag in range(party + box):
            mon = list(seed_mons[rng.randrange(len(seed_mons))])
            mon[OTID:OTID + 2] = [(TAG_BASE + tag) >> 8, (TAG_BASE + tag) & 0xFF]
            if tag < party:
                put("wPartyMons", mon, tag * PARTY_STRUCT)
                put("wPartySpecies", [mon[0]], tag)
                put("wPartyMonNicks", name_bytes(0x93, tag), tag * NAME)
                put("wPartyMonOT", name_bytes(0x8E, tag), tag * NAME)
            else:
                slot = tag - party
                box_mon = mon[:BOX_STRUCT]
                box_mon[3] = mon[0x21]  # the box level
                put("wBoxMons", box_mon, slot * BOX_STRUCT)
                put("wBoxSpecies", [mon[0]], slot)
                put("wBoxMonNicks", name_bytes(0x93, tag), slot * NAME)
                put("wBoxMonOT", name_bytes(0x8E, tag), slot * NAME)
        h.write8("wPartyCount", party)
        put("wPartySpecies", [0xFF], party)
        h.write8("wBoxCount", box)
        put("wBoxSpecies", [0xFF], box)
        self.home = {tag: core for tag, core, *_ in self.roster()[0]}
        assert len(self.home) == party + box and species

    # ----------------------------------------------------------------- checks
    def roster(self):
        """[(tag, fixed bytes, where, nick, ot)], problems."""
        h = self.h
        mons, problems = [], []
        for where, count_label, limit, species_label, mons_label, size, nicks, ots in (
                ("party", "wPartyCount", PARTY_MAX, "wPartySpecies", "wPartyMons", PARTY_STRUCT, "wPartyMonNicks", "wPartyMonOT"),
                ("box", "wBoxCount", BOX_MAX, "wBoxSpecies", "wBoxMons", BOX_STRUCT, "wBoxMonNicks", "wBoxMonOT")):
            count = h.read8(count_label)
            if count > limit or where == "party" and not count:
                problems.append(f"{where} count {count}")
                continue
            listed = h.read_bytes(species_label, count + 1)
            if listed[count] != 0xFF:
                problems.append(f"{where} species list not terminated after {count}")
            for slot in range(count):
                mon = h.read_bytes(mons_label, size * (slot + 1))[slot * size:]
                nick = h.read_bytes(nicks, NAME * (slot + 1))[slot * NAME:]
                ot = h.read_bytes(ots, NAME * (slot + 1))[slot * NAME:]
                if listed[slot] != mon[0]:
                    problems.append(f"{where} slot {slot + 1} listed ${listed[slot]:02X} holds ${mon[0]:02X}")
                tag = (mon[OTID] << 8 | mon[OTID + 1]) - TAG_BASE
                mons.append((tag, tuple(mon[i] for i in FIXED), f"{where} {slot + 1}", nick, ot))
        return mons, problems

    def _on_remove(self, _context) -> None:
        if self.releasing:
            self.releasing = False
            slot = self.h.read8("hWhichPokemon")
            mon = self.h.read_bytes("wBoxMons", BOX_STRUCT * (slot + 1))[slot * BOX_STRUCT:]
            self.released.add((mon[OTID] << 8 | mon[OTID + 1]) - TAG_BASE)
            self.exposure["released"] += 1

    def _on_poll(self, _context) -> None:
        if not self.home:
            return
        self.polls += 1
        self.releasing = False
        if self.h.read8("wCurrentBoxNum") & 0x7F != self.box_number:
            self.exposure["other box shown"] += 1
            return  # the tags are in SRAM until this box comes back
        mons, problems = self.roster()
        if self.rebase:
            self.rebase = False
            self.exposure["visits after the lobby"] += 1
            self.home = {tag: core for tag, core, *_ in mons}
            self.released = set()
            self.left_box = False
            return
        tags = Counter(tag for tag, *_ in mons)
        problems += [f"mon {t} appears {n} times" for t, n in tags.items() if n > 1]
        if not self.left_box:
            missing = set(self.home) - set(tags) - self.released
            problems += [f"mon {t} is gone" for t in sorted(missing)]
            problems += [f"released mon {t} is still there" for t in sorted(self.released & set(tags))]
        for tag, core, where, nick, ot in mons:
            if tag not in self.home:
                problems.append(f"{where} holds unknown OT id {tag + TAG_BASE:04x}")
                continue
            if core != self.home[tag]:
                problems.append(f"{where}: mon {tag} changed {self.home[tag]} -> {core}")
            if not 0 <= tag < 100:
                continue  # traded or caught outside: not one of the tagged names
            if list(nick[:4]) != name_bytes(0x93, tag)[:4]:
                problems.append(f"{where}: mon {tag} wears nickname {list(nick[:4])}")
            if list(ot[:4]) != name_bytes(0x8E, tag)[:4]:
                problems.append(f"{where}: mon {tag} wears OT {list(ot[:4])}")
        for problem in problems:
            self.checks.anomaly("bills_pc", problem)

    def run_seed(self, state: bytes, seed: int, frames: int) -> dict[str, object]:
        h = self.h
        h.load_state(io.BytesIO(state))
        party = self.rng.choice((1, 1, 2, 3, 5, 6, 6))
        box = self.rng.choice((0, 1, 2, 10, 19, 20, 20))
        self.box_number = h.read8("wCurrentBoxNum") & 0x7F
        self.left_box = False
        self.build(party, box)
        h.register_hook("ChangeBox", lambda _c: setattr(self, "left_box", True)) \
            if "ChangeBox" in h.symbols._symbols else None
        prepared = io.BytesIO()
        h.save_state(prepared)
        result = self.run(prepared.getvalue(), f"bills_pc/{seed}", frames, buttons=BUTTONS)
        result.update(seed=seed, party=party, box=box, polls=self.polls, exposure=dict(self.exposure),
                      start_state=prepared.getvalue())
        return result


_BASE: dict[bool, bytes] = {}


def play(seed: int, *, cgb: bool, frames: int) -> dict[str, object]:
    cache = ARTIFACTS / f"bills_pc_base{'_cgb' if cgb else ''}.state"
    h = RedRogueHarness(ROOT, ARTIFACTS, cgb_mode=cgb)
    try:
        driver = PCDriver(h, seed)
        result = driver.run_seed(cache.read_bytes(), seed, frames)
        start_state = result.pop("start_state")
        if result["anomalies"] or result["outcome"] != "ok":
            path = ARTIFACTS / f"bills_pc_{'cgb_' if cgb else ''}{seed}.start.state"
            path.write_bytes(start_state)
            result["state"] = str(path)
        return result
    except Exception:
        return {"seed": seed, "outcome": "error", "detail": traceback.format_exc(limit=4), "anomalies": [],
                "exposure": {}, "polls": 0, "frames": 0, "party": 0, "box": 0}
    finally:
        h.close()


def _worker(seed, options, results) -> None:
    results.put((seed, play(seed, cgb=options["cgb_mode"], frames=options["frames"])))


def _hung(seed, timeout, _options) -> dict[str, object]:
    return {"seed": seed, "outcome": "hung", "detail": f"no result within {timeout:.0f}s", "anomalies": [],
            "exposure": {}, "polls": 0, "frames": 0, "party": 0, "box": 0}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Random Bill's PC input on unusual, tagged rosters.")
    parser.add_argument("--seeds", default="random:60")
    parser.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) - 1))
    parser.add_argument("--frames", type=int, default=9000)
    parser.add_argument("--timeout", type=float, default=150)
    parser.add_argument("--cgb", action="store_true")
    args = parser.parse_args(argv)
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    h, state = main_menu_state(args.cgb)
    h.close()
    (ARTIFACTS / f"bills_pc_base{'_cgb' if args.cgb else ''}.state").write_bytes(state)
    findings: dict[str, list[int]] = {}
    exposure, outcomes, polls, started = Counter(), Counter(), 0, time.monotonic()
    rows = []
    for row in run_autoplay.run_all(run_autoplay.parse_seeds(args.seeds),
                                    {"cgb_mode": args.cgb, "frames": args.frames}, args.jobs, args.timeout,
                                    worker=_worker, timeout_row=_hung):
        outcomes[row["outcome"]] += 1
        polls += row["polls"]
        exposure.update(row["exposure"])
        found = [f"{a['check']}: {a['detail']}" for a in row["anomalies"]]
        if row["outcome"] != "ok":
            found.append(f"{row['outcome']}: {row['detail'].strip().splitlines()[-1] if row['detail'] else ''}")
        for item in found:
            findings.setdefault(item, []).append(row["seed"])
        if found:
            rows.append(row)
            print(f"seed {row['seed']} (party {row['party']}, box {row['box']}): {'; '.join(found)[:400]}", flush=True)
    (ARTIFACTS / f"bills_pc_fuzz{'_cgb' if args.cgb else ''}.json").write_text(json.dumps(
        {"outcomes": dict(outcomes), "polls": polls, "findings": findings, "exposure": dict(exposure),
         "rows": rows}, indent=1, default=str) + "\n", encoding="utf-8")
    print(f"{sum(outcomes.values())} seeds {dict(outcomes)}, {polls} grid checks, {time.monotonic() - started:.0f}s")
    print("exposure:", dict(sorted(exposure.items())))
    for item, seeds in sorted(findings.items(), key=lambda kv: -len(kv[1])):
        print(f"  {len(seeds)}x {item[:220]}  seeds {seeds[:6]}")
    if not polls:
        print("the grid was never polled: nothing was tested")
        return 2
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
