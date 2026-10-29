"""Hunt for reads of save RAM the game never wrote.

Init clears all of WRAM and HRAM (the ROM links in DMG mode, so WRAM0 is the
whole 8 KB), so the one memory the game can read without writing it first is
the cartridge's save RAM: 32 KB in four banks, holding whatever a new, used or
flash cartridge had on it. This plays the same seed with SRAM all zeroes, then
all $FF, then random bytes. It compares events and relative frames after the
documented seeded startup boundary. Different startup paths are reported as
confounded comparisons and are not bisected as evidence of uninitialized reads.
Even equal paths can differ in CPU/PPU phase; a divergence remains a suspect.

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
MATCHED_MODE = "matched_startup_controls_v1"


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


def comparison_kind(baseline, candidate):
    if not baseline.get("startup_path") or not candidate.get("startup_path"):
        return "unverified_startup"
    return "different_startup_paths" if baseline["startup_path"] != candidate["startup_path"] else "same_startup_path"


def header_range(rom):
    symbols = SymbolTable(autoplay.ROOT / f"{rom}.sym")
    bank, address = symbols.get("sSaveHeader")
    end_bank, end = symbols.get("sSaveHeaderEnd")
    if bank != end_bank or end - address != 8:
        raise ValueError("matched header policy requires the reviewed eight-byte save header")
    return {"label": "sSaveHeader", "offset": bank * SRAM_BANK_SIZE + address - SRAM_START, "length": 8}


def matched_header_image(candidate, copied_range):
    offset, length = copied_range["offset"], copied_range["length"]
    if (copied_range.get("label") != "sSaveHeader" or type(offset) is not int or type(length) is not int or len(candidate) != SRAM_SIZE
            or length != 8 or not 0 <= offset <= SRAM_SIZE - length):
        raise ValueError("invalid matched-control input/range")
    control = bytearray(SRAM_SIZE)
    control[offset:offset + length] = candidate[offset:offset + length]
    return bytes(control)


def matched_tasks(attempt, seeds, fills, rom):
    """Two raw zero baselines, then two candidates and two controls per fill."""
    from run_campaign import atomic_json, digest
    tasks, pairs = [], []
    copied_range = header_range(rom)

    def add(seed, name, role, repetition, image, target=None):
        directory = attempt / f"seed-{seed}" / f"{name}-{repetition}"
        directory.mkdir(parents=True)
        (directory / "input.sram").write_bytes(image)
        task = {"seed": seed, "fill": name, "role": role, "repetition": repetition,
                "directory": str(directory.resolve()), "input_sha256": digest(directory / "input.sram")}
        if target:
            task.update(target_fill=target, copied_range=copied_range)
        atomic_json(directory / "record.json", {**task, "execution": "scheduled", "equivalent": None})
        tasks.append(task)

    for seed in seeds:
        for repetition in range(2):
            add(seed, "zero", "baseline", repetition, fill_bytes("zero", seed))
        for name in fills:
            image = fill_bytes(name, seed)
            control_name = f"control_{name}"
            pairs.append({"seed": seed, "fill": name, "control_fill": control_name, "copied_range": copied_range})
            for repetition in range(2):
                add(seed, name, "candidate", repetition, image)
                add(seed, control_name, "matched_control", repetition,
                    matched_header_image(image, copied_range), target=name)
    return tasks, pairs


def load_fill_evidence(record):
    from run_campaign import digest
    directory = Path(record["directory"])
    for name, field in (("input.sram", "input_sha256"), ("report.json", "report_sha256"), ("trace.json", "trace_sha256")):
        if digest(directory / name) != record[field]:
            raise ValueError(f"missing or changed {name}")
    data = json.loads((directory / "trace.json").read_text())
    if (not isinstance(data, list) or not data or not isinstance(data[-1], list) or len(data[-1]) != 3
            or data[-1][0] != "end" or data[-1][1] not in ("completed", "blackout", "champion")
            or not isinstance(data[-1][2], str) or any(
                not isinstance(row, list) or len(row) != 3 or type(row[0]) is not int or row[0] < 0
                or not isinstance(row[1], str) or not isinstance(row[2], str) for row in data[:-1])):
        raise ValueError("invalid trace schema")
    report = json.loads((directory / "report.json").read_text())
    if (not isinstance(report, dict) or type(report["seed"]) is not int or report["seed"] != record["seed"]
            or not isinstance(report["anomalies"], list) or report["outcome"] != record["outcome"]
            or report["hardware_mode"] != record["hardware_mode"] or report["build_identity"] != record["build_identity"]
            or report["anomalies"] != record["anomalies"]
            or [event["kind"] for event in report["startup"]["events"]] != record["startup_path"]
            or any(report["startup"].get(key) != value for key, value in record["comparison_boundary"].items())
            or json.loads(json.dumps(trace(report))) != data):
        raise ValueError("report, trace and worker metadata do not agree")
    return (directory / "input.sram").read_bytes(), data


def boundary_key(record):
    boundary = record["comparison_boundary"]
    state = boundary["comparison_state"]
    if (not record["startup_path"] or "initialization_entered" not in record["startup_path"]
            or "gameplay_ready" not in record["startup_path"] or
            any(type(boundary[key]) is not int or boundary[key] < 0
                for key in ("comparison_frame", "comparison_cycle", "comparison_ly")) or
            boundary["comparison_ly"] > 153 or
            boundary["rng_boundary"] not in ("OakSpeech", "SelectAndPatchLobbyExit") or
            not isinstance(state, dict) or "key1" not in state or len(state["rng"]) != 12 or len(state["joy"]) != 3 or
            any(type(value) is not int or not 0 <= value <= 255 for value in state["rng"] + state["joy"])):
        raise ValueError("startup boundary evidence unavailable or malformed")
    build = record["build_identity"]
    if set(build) != {"gbc", "sym"} or any(not isinstance(value, str) or len(value) != 64 or
            any(char not in "0123456789abcdef" for char in value) for value in build.values()):
        raise ValueError("invalid build identity")
    mode = record["hardware_mode"]
    if mode not in ("DMG", "CGB") or (mode == "DMG" and state["key1"] is not None) or (
            mode == "CGB" and (type(state["key1"]) is not int or not 0 <= state["key1"] <= 255)):
        raise ValueError("hardware/speed evidence unavailable")
    return json.dumps({"path": record["startup_path"], "boundary": boundary, "build": build, "mode": mode}, sort_keys=True)


def evaluate_matched_pair(pair, records):
    """Fail closed on missing, unstable, incomparable or changed evidence."""
    result = {**pair, "status": "incomplete", "evidence": []}
    names = (pair["fill"], pair["control_fill"])
    selected = [row for row in records if row["seed"] == pair["seed"] and row["fill"] in names]
    result["evidence"] = [row["directory"] for row in selected]
    if len(selected) != 4 or any(row["execution"] != "completed" for row in selected):
        result["detail"] = "requires two completed candidate and two completed control runs"
        return result
    try:
        groups = []
        inputs = []
        for name, role in zip(names, ("candidate", "matched_control")):
            group = sorted([row for row in selected if row["fill"] == name], key=lambda row: row["repetition"])
            if [row["repetition"] for row in group] != [0, 1] or any(row["role"] != role for row in group):
                raise ValueError("invalid pair roles/repetitions")
            loaded = [load_fill_evidence(row) for row in group]
            if loaded[0][0] != loaded[1][0]:
                raise ValueError("repeated input SRAM differs")
            inputs.append(loaded[0][0])
            groups.append([trace for _, trace in loaded])
        controls = [row for row in selected if row["role"] == "matched_control"]
        if any(row["target_fill"] != pair["fill"] or row["copied_range"] != pair["copied_range"] for row in controls):
            raise ValueError("matched-control provenance differs")
        if inputs[1] != matched_header_image(inputs[0], controls[0]["copied_range"]):
            raise ValueError("control is not zero SRAM with the declared matching header")
        keys = [boundary_key(row) for row in selected]
        if any(key != keys[0] for key in keys):
            result.update(status="confounded", detail="startup path, phase, seed context or build differs")
            return result
        if any(row.get("anomalies") for row in selected):
            result.update(status="incomplete", detail="game/detector findings prevent clean equivalence")
            return result
        if any(first_divergence(group[0], group[1]) is not None for group in groups):
            result.update(status="unstable", detail="identical repeated inputs do not reproduce")
            return result
        index = first_divergence(groups[1][0], groups[0][0])
        result.update(status="equivalent" if index is None else "divergent", event_index=index,
                      control_event=groups[1][0][index] if index is not None and index < len(groups[1][0]) else None,
                      candidate_event=groups[0][0][index] if index is not None and index < len(groups[0][0]) else None)
    except (OSError, ValueError, KeyError, TypeError, IndexError) as error:
        result.update(status="invalid_evidence", detail=str(error))
    return result


def finish_matched(summary, path, bisect=False):
    """Keep raw startup coverage separate from verified matched equivalence."""
    from run_campaign import atomic_json
    records = summary["records"]
    errors = []
    identity = lambda row: (row["seed"], row["fill"], row["repetition"])
    if (len(records) != len(summary["expected_fills"]) or
            len({identity(row) for row in records}) != len(records) or
            {identity(row) for row in records} != {identity(row) for row in summary["expected_fills"]}):
        errors.append("missing, duplicated or unexpected worker records")
    if any(row["execution"] != "completed" for row in records):
        errors.append("incomplete worker execution")
    if len({json.dumps(row.get("build_identity"), sort_keys=True) for row in records}) != 1:
        errors.append("build identity changed between fills")
    baselines = {}
    for seed in summary["seeds"]:
        group = sorted([row for row in records if row["seed"] == seed and row["fill"] == "zero"],
                       key=lambda row: row["repetition"])
        try:
            if len(group) != 2 or any(row["execution"] != "completed" or row.get("anomalies") for row in group):
                raise ValueError("requires two healthy zero baselines")
            loaded = [load_fill_evidence(row) for row in group]
            if (any(image != bytes(SRAM_SIZE) for image, _ in loaded) or
                    boundary_key(group[0]) != boundary_key(group[1]) or loaded[0][1] != loaded[1][1]):
                raise ValueError("zero baselines are not reproducible")
            baselines[seed] = (group[0], loaded[0][1])
        except (OSError, ValueError, KeyError, TypeError, IndexError) as error:
            errors.append(f"seed {seed} baseline: {error}")
    results = [evaluate_matched_pair(pair, records) for pair in summary["expected_comparisons"]]
    raw = []
    for pair in summary["expected_comparisons"]:
        if pair["seed"] not in baselines:
            continue
        reference, baseline = baselines[pair["seed"]]
        candidate = next((row for row in records if row["seed"] == pair["seed"] and row["fill"] == pair["fill"]
                          and row["repetition"] == 0), None)
        try:
            if candidate is None or candidate["execution"] != "completed":
                raise ValueError("candidate not completed")
            _, trace_data = load_fill_evidence(candidate)
            raw.append({"seed": pair["seed"], "fill": pair["fill"], "event_index": first_divergence(baseline, trace_data),
                        "comparison_kind": comparison_kind(reference, candidate), "initialization_evidence": False})
        except (OSError, ValueError, KeyError, TypeError, IndexError) as error:
            raw.append({"seed": pair["seed"], "fill": pair["fill"], "detail": str(error),
                        "initialization_evidence": False})
    summary.update(initialization_comparisons=results, startup_comparisons=raw, comparison_errors=errors,
                   divergences=[row for row in results if row["status"] == "divergent"])
    if bisect:
        for result in results:
            if result["status"] != "equivalent":
                result["bisect_skipped"] = "legacy bisection does not preserve matched startup controls"
    for row in records:
        result = next((result for result in results if result["seed"] == row["seed"] and
                       row["fill"] in (result["fill"], result["control_fill"])), None)
        row["equivalent"] = (result["status"] == "equivalent" if result and result["status"] in ("equivalent", "divergent")
                             else True if row["fill"] == "zero" and row["seed"] in baselines else None)
        atomic_json(Path(row["directory"]) / "record.json", row)
    atomic_json(path, summary)
    for result in results:
        print(f"matched seed {result['seed']} {result['fill']}: {result['status']}", flush=True)
    incomplete = errors or any(row["status"] not in ("equivalent", "divergent") for row in results)
    return 2 if incomplete else 1 if summary["divergences"] else 0


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
        if data["build_identity"] != record["build_identity"]:
            raise ValueError("loaded ROM/sym identity differs from pre-launch build")
        atomic_json(directory / "report.json", data)
        record["report_sha256"] = digest(directory / "report.json")
        startup = data.get("startup") or {}
        record["startup_path"] = [event["kind"] for event in startup.get("events", [])]
        record["comparison_boundary"] = {key: startup.get(key) for key in
                                          ("rng_boundary", "comparison_frame", "comparison_cycle", "comparison_ly", "comparison_state")}
        record["anomalies"] = data.get("anomalies", [])
        record["outcome"] = data["outcome"]
        record["hardware_mode"] = data["hardware_mode"]
        record["execution"] = "completed" if data["outcome"] in ("completed", "blackout", "champion") else "incomplete"
        if record["execution"] == "completed":
            atomic_json(directory / "trace.json", trace(data))
            record["trace_sha256"] = digest(directory / "trace.json")
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
    parser.add_argument("--matched-controls", action="store_true",
                        help="opt in to repeated candidates and zero controls with matching save headers")
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
    if not seeds or len(seeds) != len(set(seeds)):
        parser.error("seeds must be nonempty and unique")
    fills = ["zero", "zero", "ff"] + [f"random{k}" for k in range(1, args.fills + 1)]
    import coverage_inventory
    coverage_inventory.code_labels(args.rom)  # warm the actual build once before forking
    from run_autoplay import run_all
    from run_campaign import atomic_json, digest
    attempt = autoplay.ARTIFACTS / f"sram_attempt-{time.time_ns()}"
    tasks = []
    pairs = []
    if args.matched_controls:
        tasks, pairs = matched_tasks(attempt, seeds, fills[2:], args.rom)
    else:
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
    if args.matched_controls:
        summary.update(schema_version=2, comparison_mode=MATCHED_MODE, expected_comparisons=pairs,
                       initialization_comparisons=[], startup_comparisons=[])
    atomic_json(path, summary)
    traces: dict[tuple[int, str], list[list[tuple]]] = {}
    for record in run_all(list(range(len(tasks))), {"tasks": tasks, "play": options}, max(1, args.jobs), args.timeout,
                          worker=fill_worker, timeout_row=fill_timeout):
        records.append(record)
        if record["execution"] == "completed":
            try:
                result = json.loads((Path(record["directory"]) / "trace.json").read_text())
                traces.setdefault((record["seed"], record["fill"]), []).append(result)
            except (OSError, ValueError) as error:
                record.update(execution="error", detail=f"invalid retained trace: {error}")
                atomic_json(Path(record["directory"]) / "record.json", record)
        atomic_json(path, summary)

    if args.matched_controls:
        return finish_matched(summary, path, args.bisect)
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
            reference = next(r for r in records if r["seed"] == seed and r["repetition"] == 0)
            candidate = next(r for r in records if r["seed"] == seed and r["fill"] == name)
            finding["comparison_kind"] = comparison_kind(reference, candidate)
            semantics = lambda events: [event[1:] if isinstance(event[0], int) else event for event in events]
            finding["semantic_event_index"] = first_divergence(semantics(baseline), semantics(ours))
            print(f"DIFF seed {seed:>3} {name:<8} event {index}: zero SRAM {expected}\n"
                  f"{'':23}this fill {got}")
            if args.bisect and finding["comparison_kind"] != "same_startup_path":
                finding["bisect_skipped"] = "startup paths differ or are unverified; matched controls required"
            if args.bisect and finding["comparison_kind"] == "same_startup_path":
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
