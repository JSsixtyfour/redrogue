"""Hunt for reads of save RAM the game never wrote.

Init clears all of WRAM and HRAM (the ROM links in DMG mode, so WRAM0 is the
whole 8 KB), so the one memory the game can read without writing it first is
the cartridge's save RAM: 32 KB in four banks, holding whatever a new, used or
flash cartridge had on it. This plays the same seed with SRAM all zeroes, then
all $FF, then random bytes. Every run must play identically, event for event
and relative frame for relative frame after the documented seeded startup
boundary. A divergence is a suspected initialization sensitivity, not proof
of an uninitialized read.

The title menu's save check is kept out of the fills on purpose: a '@' in
sPlayerName counts as a save (CheckForPlayerNameInSRAM), the checksum then
fails and the game says the file data is destroyed before NEW GAME. That is
an intentional startup path. Random headers can still require discard consent;
these disposable images explicitly select YES through the existing shared boot
driver. Raw startup events are retained separately from post-consent traces.

With --bisect, a diverging fill is narrowed down by replaying with only part of
it applied, until the SRAM bytes that change play are found, then named from
the .sym file.

    python3 tools/pyboy_smoke/sram_fuzz.py --seeds 1-4 --new-game
    python3 tools/pyboy_smoke/sram_fuzz.py --seeds 3 --fills 6 --bisect

Exits non-zero when any fill diverges. Results go to
artifacts/sram_fuzz_summary.json.
"""
from __future__ import annotations

import argparse
import json
import random
import sys
from pathlib import Path
import time
import traceback

import autoplay
from harness import SymbolTable
from run_autoplay import parse_seeds

SRAM_BANK_SIZE = 0x2000
SRAM_SIZE = 4 * SRAM_BANK_SIZE
SRAM_START = 0xA000
MAX_BISECT_RUNS = 64
BISECT_MARGIN_FRAMES = 600  # replay this far past the first divergence


TEXT_TERMINATOR = 0x50  # "@"
NAME_LENGTH = 11


def _player_name_offset() -> int:
    bank, address = SymbolTable(autoplay.ROOT / "pokeblue_debug.sym").get("sPlayerName")
    return bank * SRAM_BANK_SIZE + address - SRAM_START


def fill_bytes(name: str, seed: int) -> bytes:
    if name == "zero":
        return bytes(SRAM_SIZE)
    if name == "ff":
        return b"\xff" * SRAM_SIZE
    rng = random.Random(f"{seed}/{name}")
    sram = bytearray(rng.randrange(256) for _ in range(SRAM_SIZE))
    start = _player_name_offset()
    for offset in range(start, start + NAME_LENGTH):  # no save for the title menu to find
        if sram[offset] == TEXT_TERMINATOR:
            sram[offset] += 1
    return bytes(sram)


def trace(data: dict[str, object]) -> list[tuple]:
    """Everything that must match between two runs: each event with its frame,
    then the outcome."""
    boundary = (data.get("startup") or {}).get("comparison_frame")
    if boundary is None:
        raise ValueError("post-consent comparison boundary was not reached")
    events = [(event["frame"] - boundary, event["kind"],
               json.dumps({k: v for k, v in event.items() if k not in ("frame", "kind")}, sort_keys=True))
              for event in data["events"] if event["frame"] >= boundary]
    return events + [("end", data["outcome"], data["detail"])]


def first_divergence(a: list[tuple], b: list[tuple]) -> int | None:
    for index, (left, right) in enumerate(zip(a, b)):
        if left != right:
            return index
    return None if len(a) == len(b) else min(len(a), len(b))


def play_trace(seed: int, sram: bytes, options: dict[str, object]) -> list[tuple]:
    data = autoplay.play(seed, sram=sram, **options)
    return trace(data)


def sram_label(symbols: SymbolTable, offset: int) -> str:
    """The SRAM label at or before a byte, by bank. SymbolTable.nearest would
    also consider ROM labels of the same bank number."""
    bank, address = divmod(offset, SRAM_BANK_SIZE)
    address += SRAM_START
    best = None
    for symbol_address, label in symbols._by_bank.get(bank, ()):
        if SRAM_START <= symbol_address <= address:
            best = (symbol_address, label)
    where = f"{bank:02X}:{address:04X}"
    if best is None:
        return where
    symbol_address, label = best
    return f"{where} {label}" + (f"+${address - symbol_address:x}" if address != symbol_address else "")


class Bisector:
    """Finds the smallest SRAM ranges of a diverging fill that change play on
    their own (or, when only a combination does, the range holding it)."""

    def __init__(self, seed: int, fill: bytes, options: dict[str, object], frame_limit: int):
        self.seed = seed
        self.fill = fill
        self.options = options | {"max_frames": frame_limit}
        self.baseline = play_trace(seed, fill_bytes("zero", seed), self.options)
        self.runs = 0

    def diverges(self, start: int, end: int) -> bool:
        if self.runs >= MAX_BISECT_RUNS:
            raise RuntimeError(f"gave up after {MAX_BISECT_RUNS} replays")
        self.runs += 1
        sram = bytearray(SRAM_SIZE)
        sram[start:end] = self.fill[start:end]
        return first_divergence(self.baseline, play_trace(self.seed, bytes(sram), self.options)) is not None

    def narrow(self, start: int, end: int) -> list[tuple[int, int]]:
        if end - start <= 1 or not any(self.fill[start:end]):
            return [(start, end)]
        middle = (start + end) // 2
        left, right = self.diverges(start, middle), self.diverges(middle, end)
        if not left and not right:
            return [(start, end)]  # needs bytes from both halves together
        return (self.narrow(start, middle) if left else []) + (self.narrow(middle, end) if right else [])


def run_fill(seed: int, name: str, options: dict[str, object]) -> tuple[int, str, list[tuple]]:
    return seed, name, play_trace(seed, fill_bytes(name, seed), options)


def fill_worker(task_id, options, results):
    from run_campaign import atomic_json, digest
    task = options["tasks"][task_id]
    directory = Path(task["directory"])
    autoplay.ARTIFACTS = directory
    record = {**task, "execution": "running", "equivalent": None}
    atomic_json(directory / "record.json", record)
    try:
        if digest(directory / "input.sram") != task["input_sha256"]:
            raise ValueError("input SRAM changed before fill execution")
        rom = options["play"].get("rom", autoplay.DEBUG_ROM)
        record["build_identity"] = {ext: digest(autoplay.ROOT / f"{rom}.{ext}") for ext in ("gbc", "sym")}
        data = autoplay.play(task["seed"], sram=(directory / "input.sram").read_bytes(), **options["play"])
        atomic_json(directory / "report.json", data)
        record["anomalies"] = data.get("anomalies", [])
        record["outcome"] = data["outcome"]
        record["execution"] = "completed" if data["outcome"] in ("completed", "blackout", "champion") else "incomplete"
        if record["execution"] == "completed":
            atomic_json(directory / "trace.json", trace(data))
    except BaseException:
        record.update(execution="error", detail=traceback.format_exc(limit=5))
    atomic_json(directory / "record.json", record)
    results.put((task_id, record))


def fill_timeout(task_id, timeout, options):
    from run_campaign import atomic_json
    task = options["tasks"][task_id]
    record = {**task, "execution": "budget_exhausted", "equivalent": None,
              "detail": f"fill exceeded {timeout}s"}
    atomic_json(Path(task["directory"]) / "record.json", record)
    return record


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Find reads of uninitialised save RAM.")
    parser.add_argument("--seeds", default="1-4")
    parser.add_argument("--fills", type=int, default=3, help="random fills per seed, besides zero and $FF")
    parser.add_argument("--new-game", action="store_true",
                        help="power on and start a NEW GAME (the default boots the Debug 2 lobby)")
    parser.add_argument("--runs", type=int, default=1)
    parser.add_argument("--stages", type=int, default=6)
    parser.add_argument("--max-frames", type=int, default=400_000)
    parser.add_argument("--bisect", action="store_true", help="narrow each divergence down to SRAM bytes")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--rom", choices=("pokered", "pokeblue", "pokeblue_debug"), default="pokeblue_debug")
    parser.add_argument("--cgb", action="store_true")
    parser.add_argument("--timeout", type=float, default=120, help="wall-clock seconds per isolated fill")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.rom != "pokeblue_debug" and not args.new_game:
        parser.error("release ROMs require --new-game")
    if args.timeout <= 0 or args.jobs < 1 or args.fills < 0:
        parser.error("timeout/jobs must be positive and fills nonnegative")

    options = {"new_game": args.new_game, "runs": args.runs, "stages": args.stages,
               "max_frames": args.max_frames, "discard_test_sram": True,
               "rom": args.rom, "cgb_mode": args.cgb}
    seeds = parse_seeds(args.seeds)
    fills = ["zero", "zero", "ff"] + [f"random{k}" for k in range(1, args.fills + 1)]
    import coverage_inventory
    coverage_inventory.code_labels()  # once, before the workers (autoplay_screen.py)
    from run_autoplay import run_all
    from run_campaign import atomic_json, digest
    attempt = autoplay.ARTIFACTS / f"sram_attempt-{time.time_ns()}"
    tasks = []
    for seed in seeds:
        for index, name in enumerate(fills):
            directory = attempt / f"seed-{seed}" / f"{index:02d}-{name}"
            directory.mkdir(parents=True)
            (directory / "input.sram").write_bytes(fill_bytes(name, seed))
            task = {"seed": seed, "fill": name, "repetition": index, "directory": str(directory.resolve()),
                    "input_sha256": digest(directory / "input.sram")}
            atomic_json(directory / "record.json", {**task, "execution": "scheduled", "equivalent": None})
            tasks.append(task)
    records = []
    path = autoplay.ARTIFACTS / "sram_fuzz_summary.json"
    summary = {"options": options, "fills": fills[2:], "seeds": seeds, "divergences": [],
               "expected_fills": tasks, "records": records, "comparison": "post-consent seeded boundary; relative frames"}
    atomic_json(path, summary)
    traces: dict[tuple[int, str], list[list[tuple]]] = {}
    for record in run_all(list(range(len(tasks))), {"tasks": tasks, "play": options}, max(1, args.jobs), args.timeout,
                          worker=fill_worker, timeout_row=fill_timeout):
        records.append(record)
        if record["execution"] == "completed":
            result = json.loads((Path(record["directory"]) / "trace.json").read_text())
            traces.setdefault((record["seed"], record["fill"]), []).append(result)
        atomic_json(path, summary)

    if any(record["execution"] != "completed" for record in records):
        print(f"incomplete SRAM fills; preserved {len(records)} individual results -> {path}")
        return 2

    symbols = SymbolTable(autoplay.ROOT / "pokeblue_debug.sym")
    findings = []
    for seed in seeds:
        baseline, again = traces[(seed, "zero")]
        if first_divergence(baseline, again) is not None:
            print(f"seed {seed}: two all-zero runs differ, so the runs are not deterministic; stopping")
            summary["comparison_error"] = "repeated zero baseline differs"
            atomic_json(path, summary)
            return 2
        if baseline[-1][1] in autoplay.FAILURES:
            # Identical failures would prove nothing; run autoplay.py on the seed.
            print(f"seed {seed}: the all-zero run itself ended {baseline[-1][1]}: {baseline[-1][2]}; stopping")
            summary["comparison_error"] = "zero baseline failed"
            atomic_json(path, summary)
            return 2
        for name in fills[2:]:
            index = first_divergence(baseline, traces[(seed, name)][0])
            if index is None:
                print(f"ok   seed {seed:>3} {name:<8} plays identically")
                continue
            ours = traces[(seed, name)][0]
            expected = baseline[index] if index < len(baseline) else None
            got = ours[index] if index < len(ours) else None
            finding = {"seed": seed, "fill": name, "event_index": index,
                       "zero_sram": expected, "this_fill": got}
            print(f"DIFF seed {seed:>3} {name:<8} event {index}: zero SRAM {expected}\n"
                  f"{'':23}this fill {got}")
            if args.bisect:
                frames = [event[0] for event in (expected, got) if event and isinstance(event[0], int)]
                # Trace frames are relative to the seed boundary; the emulator
                # max_frames limit is measured from power-on.
                startup_frames = [json.loads((Path(record["directory"]) / "report.json").read_text())
                                  ["startup"]["comparison_frame"] for record in records
                                  if record["seed"] == seed and record["fill"] in ("zero", name)]
                limit = min(args.max_frames, max(startup_frames) + min(frames) + BISECT_MARGIN_FRAMES) if frames else args.max_frames
                bisector = Bisector(seed, fill_bytes(name, seed), options, limit)
                try:
                    ranges = bisector.narrow(0, SRAM_SIZE) if bisector.diverges(0, SRAM_SIZE) else []
                    finding["sram"] = [{"bytes": [sram_label(symbols, start), sram_label(symbols, end - 1)],
                                        "length": end - start} for start, end in ranges]
                    for start, end in ranges:
                        span = sram_label(symbols, start) + (
                            f" .. {sram_label(symbols, end - 1)}" if end - start > 1 else "")
                        print(f"       changes play: {span} ({end - start} byte(s))")
                    if not ranges:
                        print("       the divergence did not reproduce within its frame window")
                except RuntimeError as error:
                    finding["sram_error"] = str(error)
                    print(f"       bisect: {error}")
                finding["bisect_runs"] = bisector.runs
            findings.append(finding)

    summary["divergences"] = findings
    for record in records:
        record["equivalent"] = not record.get("anomalies") and not any(
            f["seed"] == record["seed"] and f["fill"] == record["fill"] for f in findings)
        atomic_json(Path(record["directory"]) / "record.json", record)
    atomic_json(path, summary)
    print(f"\n{len(seeds)} seed(s) x {len(fills) - 2} fill(s): {len(findings)} divergence(s) -> {path}")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
