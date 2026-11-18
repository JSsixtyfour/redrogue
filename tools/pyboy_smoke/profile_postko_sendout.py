"""AI_T4_REGRET_PLAN C0 step 1 (2026-11-17): per-routine inclusive profile of one
five-reserve post-KO AISelectSendOut, T1 legacy against T3. A probe, not a smoke test.
Run from WSL: python3 tools/pyboy_smoke/profile_postko_sendout.py

Board and setup copied from tools/pyboy_smoke/probe_postko_latency.py. Timing pattern from
tools/pyboy_smoke/profile_lobby.py: entry hooks plus a hook at the caller's return address,
accepted only when SP matches. Two traps this file handles, both measured:
- A farcalled routine's [SP] is Bankswitch.Return, shared by every farcall and already hooked
  raw by call_routine. Time it to the FAR caller's return instead: [SP+3] is the caller's bank
  (Bankswitch's push af), [SP+4] the caller's return, and SP there is entry SP + 6.
- A routine whose loop jumps back to its own entry label (CopyData's byte loop) fires the entry
  hook once per iteration. Counting those as calls overstated CopyData 10x (48.8% of the pass
  instead of 4.6%). A re-entry with the same name and the same return SP is ignored.
Inclusive cycles overlap between nested routines: do not add rows. "no-VBlank" subtracts any
VBlank that ran inside the routine.
"""
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/pyboy_smoke"))
from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_rgbds_constants, parse_trainer_constants  # noqa: E402

SP = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
MV = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
TR = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
FRAME = 70224

RESERVES = [
    ("SLOWBRO", ["SURF", "PSYCHIC_M", "ICE_BEAM", "BODY_SLAM"]),
    ("MAGMORTAR", ["FLAMETHROWER", "THUNDERBOLT", "BODY_SLAM", "EARTHQUAKE"]),
    ("ELECTRODE", ["THUNDERBOLT", "SWIFT", "TAKE_DOWN", "EXPLOSION"]),
    ("RHYDON", ["EARTHQUAKE", "ROCK_SLIDE", "BODY_SLAM", "HYPER_BEAM"]),
    ("GENGAR", ["THUNDERBOLT", "PSYCHIC_M", "NIGHT_SHADE", "MEGA_DRAIN"]),
]

LABELS = [
    "VBlank",
    "AISelectSendOut", "AIRankPostKOSendOut", "AIPostKOReply",
    "AIRankSendOutCandidates", "AIRankRemainingSendOutCandidates", "AIRankSendOutCandidatesBelow",
    "AIScoreSendOutMon", "AIMonHasDamagingPP", "PreviewTypeMatchup", "AIBuildPlayerThreatTypes",
    "AIBestReserveSurvivesThreat", "_AIScanPlayerMovesForKO", "AIReadMoveIntoPlayerBlock",
    "AIEstimatePlayerMoveDamage", "AIEstimatePlayerDamage", "AIEstimateCritDamage", "AIMoveCritCertain",
    "AIAdjustPlayerDamageForPossibleDelivery", "AIDamageWouldKOEnemy",
    "AIEstimateDamage", "AIEstimateEnemyDamage", "AIScaleDamageForCrit", "AIScaleDamageByAccuracy",
    "AIGetMoveHitChance", "CalcHitChance", "AIMoveIsReliableKO", "AIMoveWouldKO", "AIEnemyCritAlsoKOs",
    "AIEnemyActsFirstWith", "AIAdjustEnemyDamageForReliableDelivery",
    "AIAdjustEnemyDamageForExpectedDelivery", "ApplyBurnAndParalysisPenaltiesToEnemy",
    "CalcCritRate", "GetMonHeader", "Multiply", "Divide", "CopyData", "FarCopyData", "AddNTimes",
    "AIGetTier", "AIClearDecisionCaches", "GetDamageVarsForEnemyAttack", "GetDamageVarsForPlayerAttack",
    "CalculateDamage", "AdjustDamageForMoveType", "ReadMove", "ReadMoveIntoDE",
]


class Timings:
    def __init__(self, h, labels):
        self.h = h
        self.pending = defaultdict(list)
        self.returns = set()
        self.records = []
        self.vblank = 0
        self.enabled = False
        self.hooked = []
        self.top = "AISelectSendOut"
        self.top_start = None
        self.bs_return = h.address("Bankswitch.Return")
        self.copy_callers = defaultdict(lambda: [0, 0, 0])  # calls, bytes, cycles
        self.copy_open = []
        self.entries = defaultdict(int)
        self.raw_copy = defaultdict(int)
        for name in labels:
            if name not in h.symbols._symbols:
                continue
            self.hooked.append(name)
            h.register_hook(name, lambda _, name=name: self.enter(name))

    def enter(self, name):
        h = self.h
        mem = h.pyboy.memory
        sp = h.pyboy.register_file.SP
        addr = mem[sp] | mem[sp + 1] << 8
        if name == self.top:
            self.top_start = (h.cycle_count(), self.vblank)
            return
        if addr == self.bs_return:
            # farcall: [SP] Bankswitch.Return, [SP+2] pushed af (A = caller bank at SP+3),
            # [SP+4] the far caller's return. Time to that return; SP there is entry SP + 6.
            caller_bank = mem[sp + 3]
            addr = mem[sp + 4] | mem[sp + 5] << 8
            bank = 0 if addr < 0x4000 else caller_bank
            ret_sp = sp + 6
        else:
            bank = 0 if addr < 0x4000 else h.read8("hLoadedROMBank")
            ret_sp = sp + 2
        key = bank, addr
        open_ = self.pending[key]
        if open_ and open_[-1][0] == name and open_[-1][1] == ret_sp:
            return  # a loop jumping back to its own entry label, not a new call
        if self.enabled:
            self.entries[name] += 1
            if name == "CopyData":
                rf = h.pyboy.register_file
                self.raw_copy[(bank, addr, rf.B << 8 | rf.C)] += 1
        if name in ("CopyData", "FarCopyData") and self.enabled:
            # attribute to caller: nearest preceding label in the caller's bank, plus bc = length
            lbl = self.symbolize(bank, addr)
            rf = h.pyboy.register_file
            n = rf.B << 8 | rf.C
            c = self.copy_callers[(name, lbl)]
            c[0] += 1; c[1] += n
            self.copy_open.append(((name, lbl), sp + 2, h.cycle_count()))
        self.pending[key].append((name, ret_sp, h.cycle_count(), self.vblank, self.enabled))
        if key not in self.returns:
            self.returns.add(key)
            h._register_at(key, lambda _, key=key: self.leave(key))

    def leave(self, key):
        h = self.h
        stack = self.pending[key]
        while stack and stack[-1][1] == h.pyboy.register_file.SP:
            name, _, start, vb0, enabled = stack.pop()
            elapsed = h.cycle_count() - start
            own = elapsed if name == "VBlank" else elapsed - (self.vblank - vb0)
            if name == "VBlank":
                self.vblank += elapsed
            if enabled and self.enabled:
                self.records.append((name, elapsed, own))
                if name in ("CopyData", "FarCopyData") and self.copy_open:
                    ck, _, _ = self.copy_open.pop()
                    self.copy_callers[ck][2] += elapsed

    def symbolize(self, bank, addr):
        best = None
        for a, lbl in self.h.symbols._by_bank.get(bank, ()):
            if a <= addr:
                best = lbl
            else:
                break
        return best or f"{bank:02x}:{addr:04x}"


def run(tier, count):
    h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
    try:
        mon = lambda s, m: dict(species=SP[s], level=50, moves=[MV[x] for x in m])
        res = [mon(s, m) for s, m in RESERVES[:count]]
        h.inject_fight2_spec([mon("STARMIE", ["SURF", "PSYCHIC_M", "THUNDERBOLT", "ICE_BEAM"])],
                             [mon("RATTATA", ["TACKLE"]), *res],
                             trainer_class=TR["COOLTRAINER_M"], ai_tier=tier)
        h.boot_fight2(seed=1)
        h.write8("wAITurnPlan", 0)
        h.write8("wAISeenPlayerMoveMask", 15)
        h.write8("wEnemyMonHP", 0); h.write8("wEnemyMonHP", 0, offset=1)
        h.write8("wEnemyMon1HP", 0); h.write8("wEnemyMon1HP", 0, offset=1)
        t = Timings(h, LABELS)
        t.enabled = True
        def cap(hh):
            start, vb0 = t.top_start
            inc = hh.cycle_count() - start
            t.records.append((t.top, inc, inc - (t.vblank - vb0)))
            return hh.read8("hWhichPokemon")

        slot = h.call_routine("AISelectSendOut", limit=400000, capture=cap)
        t.enabled = False
        return t, slot, h.pyboy.memory[0xFF4D]
    finally:
        h.close()


def report(t, slot, key1, tier):
    rows = defaultdict(lambda: [0, 0, 0])
    for name, inc, own in t.records:
        r = rows[name]
        r[0] += 1; r[1] += inc; r[2] += own
    top = rows.get("AISelectSendOut", [1, 1, 1])
    total = top[2] or 1
    print(f"\n=== T{tier}, 5 reserves: slot {slot}, key1={key1:#04x}, AISelectSendOut "
          f"{top[1]} cycles incl ({top[1] / FRAME:.2f} 1x-frames), {top[2]} without VBlank")
    print(f"{'routine':42} {'calls':>6} {'incl cyc':>10} {'no-VBlank':>10} {'% top':>6} {'per call':>9}")
    for name, (n, inc, own) in sorted(rows.items(), key=lambda kv: -kv[1][2]):
        print(f"{name:42} {n:6} {inc:10} {own:10} {100 * own / total:6.1f} {own // max(n, 1):9}")
    print(f"\n{'CopyData caller (nearest label)':52} {'calls':>6} {'bytes':>7} {'cycles':>9}")
    for (nm, lbl), (n, b, c) in sorted(t.copy_callers.items(), key=lambda kv: -kv[1][2]):
        print(f"{nm + ' <- ' + lbl:52} {n:6} {b:7} {c:9}")
    print("\nentries vs matched returns (a gap = unmatched returns, inclusive row undercounts):")
    for name, n in sorted(t.entries.items(), key=lambda kv: -kv[1]):
        if n != rows.get(name, [0])[0]:
            print(f"  {name:40} entries {n:5}  matched {rows.get(name, [0])[0]:5}")
    print("\nraw CopyData return address (bank:addr) x length -> calls:")
    for (b, a, n), c in sorted(t.raw_copy.items(), key=lambda kv: -kv[1])[:12]:
        print(f"  {b:02x}:{a:04x} len {n:3} x{c}")
    missing = [l for l in LABELS if l not in t.hooked]
    print("labels not in .sym:", ", ".join(missing) or "none")


if __name__ == "__main__":  # profile_ai_decision.py imports Timings from here
    for tier in (1, 3):
        t, slot, key1 = run(tier, 5)
        report(t, slot, key1, tier)
