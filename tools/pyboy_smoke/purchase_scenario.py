"""Real-input mart contracts on a documented Debug 2 fixture.

Run via run_campaign.py with scenario='purchase', or directly with --output.
No production game bytes are changed. Fixture writes only configure WRAM.
"""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
import sys
import traceback

import autoplay
import autoplay_world as world
from harness import RedRogueHarness
from run_campaign import atomic_json, digest

VERSION = 1
CASES = ("success", "exact_funds", "cancel_quantity", "cancel_confirm", "decline", "insufficient")
PRICE = 200  # Potion, independent fixture expectation: data/items/prices.asm.


def build_parser():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seeds", default="1")
    parser.add_argument("--case", choices=(*CASES, "all"), default="all")
    parser.add_argument("--cgb", action="store_true")
    parser.add_argument("--output", type=Path, default=None)
    parser.add_argument("--replay", type=Path, help="replay a retained case from its initial state and inputs")
    parser.add_argument("--control-overcharge", action="store_true",
                        help="detector validation only: subtract one from the observed money record, never game RAM")
    parser.set_defaults(jobs=1, timeout=120)
    return parser


def snapshot(h):
    return {"money": int("".join(f"{v:02x}" for v in h.read_bytes("wPlayerMoney", 3))),
            "items": h.read_bytes("wRecoveryItemCounts", h.address("wItemCountsEnd") - h.address("wRecoveryItemCounts")),
            "party": h.read_bytes("wPartyDataStart", h.address("wPartyDataEnd") - h.address("wPartyDataStart"))}


def contract(before, after, *, bought, potion_slot, paid_calls, give_calls):
    """Only explicit transaction-owned fields may change; timers are excluded."""
    expected_items = list(before["items"])
    expected_items[potion_slot] += int(bought)
    expected = {"money": before["money"] - PRICE * int(bought),
                "items": expected_items, "party": before["party"],
                "paid_calls": int(bought), "give_calls": int(bought)}
    actual = {**after, "paid_calls": paid_calls, "give_calls": give_calls}
    return [{"check": "mart_transaction", "version": VERSION, "field": field,
             "expected": value, "observed": actual[field],
             "signature": f"mart_transaction/v{VERSION}/{field}",
             "classification": "contract_violation", "severity": "correctness"}
            for field, value in expected.items() if actual[field] != value]


def controlled_observation(state, enabled):
    observed = copy.deepcopy(state)
    if enabled:
        observed["money"] -= 1
    return observed


class Observation:
    def __init__(self, h):
        self.h = h
        self.phase = "greeting"
        self.wait_frame = -100
        self.overworld_frame = -100
        self.visits = self.paid = self.given = 0
        self.insufficient = self.closed = False
        self.events = []
        for label, phase in (("DoBuySellQuitMenu", "main"), ("DisplayListMenuID", "list"),
                             ("DisplayChooseQuantityMenu", "quantity"), ("DisplayTwoOptionMenu", "confirm")):
            h.register_hook(label, lambda _, p=phase: self.set_phase(p))
        h.register_hook("DisplayPokemartDialogue_.buyMenuLoop", self.visit)
        h.register_hook("DisplayPokemartDialogue_.notEnoughMoney", self.not_enough)
        h.register_hook("DisplayPokemartDialogue_.done", self.close)
        h.register_hook("SubtractAmountPaidFromMoney", self.payment)
        h.register_hook("GiveItem", self.grant)
        h.register_hook("JoypadLowSensitivity", lambda _: setattr(self, "wait_frame", h.pyboy.frame_count))
        h.register_hook("JoypadOverworld", lambda _: setattr(self, "overworld_frame", h.pyboy.frame_count))

    def record(self, event):
        self.events.append({"frame": self.h.pyboy.frame_count, "event": event})

    def set_phase(self, phase):
        self.phase = phase
        self.record(phase)

    def visit(self, _):
        self.visits += 1
        self.set_phase("transition")

    def not_enough(self, _):
        self.insufficient = True
        self.set_phase("text")

    def close(self, _):
        self.closed = True
        self.set_phase("text")

    def payment(self, _):
        self.paid += 1
        self.record("payment")

    def grant(self, _):
        self.given += 1
        self.record("grant")


def evidence(h, directory, tag):
    # All trial inputs render; this reads the last rendered frame without ticking.
    h.pyboy.screen.image.save(directory / f"{tag}.png")
    atomic_json(directory / f"{tag}_tilemap.json", {
        "rows": [{"y": y, "tiles": h.read_bytes("wTileMap", 20, y * 20)} for y in range(18)],
        "menu": {name: h.read8(name) for name in
                 ("wListMenuID", "hCurrentMenuItem", "wListScrollOffset", "wMenuExitMethod")},
        "diagnostic": h.diagnostic_state()})


def configure(h, seed, name):
    autoplay.boot(h, seed)
    h.tick(120)
    agent = autoplay.AutoplayAgent(h, seed=seed)
    # Follow the current world's collision grid, including occupied tiles.
    reached = False
    for _ in range(80):
        grid = agent.read_grid()
        clerk = agent.sprites().get(2)  # PC_CLERK1, authored object slot.
        if clerk is None:
            raise RuntimeError("recovery clerk not visible")
        spots = {step: target for step, target in agent.talk_goal(grid, {2: clerk}, "clerk").spots.items()
                 if grid.walkable(*step) and step not in agent.obstacles()}
        if agent.position() in spots:
            facing, _ = spots[agent.position()]
            agent.press(facing, 3, 12)
            reached = True
            break
        path = world.find_path(grid, agent.position(), spots, agent.obstacles())
        if not path:
            raise RuntimeError(f"clerk unreachable by driver at {agent.position()}, spots={spots}, clerk={clerk}")
        agent.walk(path[0])
    if not reached:
        raise RuntimeError("clerk approach not reached")
    constants = autoplay.parse_rgbds_constants(autoplay.ROOT / "constants/item_constants.asm")
    potion = constants["POTION"]
    slot = agent.recovery_table.index(potion)
    funds = PRICE if name == "exact_funds" else PRICE - 1 if name == "insufficient" else 1000
    injections = []

    def inject(label, values, offset=0):
        injections.append({"label": label, "offset": offset,
                           "before": h.read_bytes(label, len(values), offset), "after": list(values)})
        for i, value in enumerate(values):
            h.write8(label, value, offset + i)

    inject("PCClerkText1", [1], 1)
    inject("PCClerkText1Items", [potion, 0xff])
    inject("wWitchPrizesEarned", [0, 0])
    inject("wRecoveryItemCounts", [0], slot)
    digits = f"{funds:06d}"
    inject("wPlayerMoney", [int(digits[i:i + 2], 16) for i in (0, 2, 4)])
    return slot, injections, agent


def act(h, inputs, button=None, hold=2, after=6):
    # Shared drivers can wait without pressing. Retain those idle intervals too.
    if inputs:
        previous = inputs[-1]
        end = previous["frame"] + previous["hold"] + previous["after"]
        if h.pyboy.frame_count > end:
            inputs.append({"frame": end, "button": None,
                           "hold": h.pyboy.frame_count - end, "after": 0})
    inputs.append({"frame": h.pyboy.frame_count, "button": button, "hold": hold, "after": after})
    if button:
        h.pyboy.button_press(button)
    h.tick(hold, render=True)
    if button:
        h.pyboy.button_release(button)
    h.tick(after, render=True)


def run_one(seed, name, directory, *, cgb=False, control=False):
    directory.mkdir(parents=True, exist_ok=False)
    h = RedRogueHarness(autoplay.ROOT, directory, cgb_mode=cgb)
    data = {"schema_version": VERSION, "seed": seed, "scenario": name, "hardware_mode": h.hardware_mode,
            "rom_sha256": h.rom_sha256, "sym_sha256": h.sym_sha256,
            "provenance": "constructed Debug 2 WRAM fixture", "inputs": [],
            "detector_input_control": "observed_money_minus_one" if control else None,
            "execution": "incomplete", "verdict": "incomplete", "findings": []}
    try:
        slot, injections, agent = configure(h, seed, name)
        data.update(potion_slot=slot, injections=injections, navigation_inputs=list(agent.report.inputs),
                    driver="autoplay.AutoplayAgent.shop_step")
        h.tick(1, render=True)
        obs = Observation(h)
        with (directory / "initial.state").open("wb") as state:
            h.save_state(state)
        data["initial_state_sha256"] = digest(directory / "initial.state")
        data["before"] = snapshot(h)
        evidence(h, directory, "before")
        start = h.pyboy.frame_count
        agent.plan = {"kind": "shop", "steps": 0, "done": False}
        # Record and render presses produced by the shared shopping driver.
        agent.press = lambda button, hold=2, after=6: act(h, data["inputs"], button, hold, after)
        act(h, data["inputs"], "a")
        while h.pyboy.frame_count - start < 8000:
            done = obs.visits >= 2 or obs.insufficient
            if obs.closed and obs.overworld_frame > start and h.pyboy.frame_count - obs.overworld_frame <= 2:
                break
            if h.pyboy.frame_count - obs.wait_frame > 2:
                act(h, data["inputs"], hold=1, after=0)
                continue
            agent.plan["done"] = agent.plan["done"] or done
            agent.shop_step(select_purchase=lambda stock: (0, 1, stock[0]),
                            cancel_quantity=name == "cancel_quantity",
                            confirmation="cancel" if name == "cancel_confirm" else "no" if name == "decline" else "yes")
        actual_after = snapshot(h)
        data.update(actual_after=actual_after, after=controlled_observation(actual_after, control),
                    events=obs.events, paid_calls=obs.paid, give_calls=obs.given)
        reached = obs.closed and obs.overworld_frame > start and (obs.insufficient if name == "insufficient" else obs.visits >= 2)
        if not reached:
            data["detail"] = "scenario did not reach its transaction exit and normal overworld input"
        else:
            data["execution"] = "completed"
            data["findings"] = contract(data["before"], data["after"], bought=name in ("success", "exact_funds"),
                                        potion_slot=slot, paid_calls=obs.paid, give_calls=obs.given)
            for finding in data["findings"]:
                finding["evidence_origin"] = "controlled_detector_input" if control else "actual_ROM_fixture"
            data["verdict"] = "contract_violation" if data["findings"] else "no_issue_detected"
        if h.hook_errors:
            data.update(execution="detector_error", verdict="incomplete", detail=h.hook_errors)
        evidence(h, directory, "after")
        with (directory / "final.state").open("wb") as state:
            h.save_state(state)
    except Exception:
        data.update(execution="driver_error", verdict="incomplete", detail=traceback.format_exc())
    finally:
        h.close()
    atomic_json(directory / "case.json", data)
    return data


def replay(path, output):
    data = json.loads(path.read_text())
    h = RedRogueHarness(autoplay.ROOT, output, cgb_mode=data["hardware_mode"] == "CGB")
    try:
        if (h.rom_sha256, h.sym_sha256) != (data["rom_sha256"], data["sym_sha256"]):
            raise ValueError("incompatible ROM/sym for retained state")
        state_path = path.parent / "initial.state"
        if digest(state_path) != data["initial_state_sha256"]:
            raise ValueError("initial state hash mismatch")
        obs = Observation(h)
        with state_path.open("rb") as stream:
            h.load_state(stream)
        before = snapshot(h)
        # PyBoy's host frame counter is not part of its saved machine state.
        frame_offset = h.pyboy.frame_count - data["inputs"][0]["frame"]
        for input_record in data["inputs"]:
            if h.pyboy.frame_count != input_record["frame"] + frame_offset:
                raise ValueError(f"replay frame divergence: recorded={input_record['frame']}, loaded={h.pyboy.frame_count}")
            act(h, [], input_record["button"], input_record["hold"], input_record["after"])
        after = controlled_observation(snapshot(h), bool(data.get("detector_input_control")))
        findings = contract(before, after, bought=data["scenario"] in ("success", "exact_funds"),
                            potion_slot=data["potion_slot"], paid_calls=obs.paid, give_calls=obs.given)
        for finding in findings:
            if any("evidence_origin" in old for old in data["findings"]):
                finding["evidence_origin"] = "controlled_detector_input" if data.get("detector_input_control") else "actual_ROM_fixture"
        events = [{**event, "frame": event["frame"] - frame_offset} for event in obs.events]
        result = {"same_state": before == data["before"] and after == data["after"],
                  "same_events": events == data["events"], "host_frame_offset": frame_offset,
                  "same_findings": findings == data["findings"], "findings": findings}
        atomic_json(output / "replay.json", result)
        return int(not all(result[key] for key in ("same_state", "same_events", "same_findings")))
    finally:
        h.close()


def main(argv=None):
    args = build_parser().parse_args(argv)
    if args.control_overcharge and args.case != "success":
        raise ValueError("the overcharge detector control uses --case success")
    output = (args.output or autoplay.ARTIFACTS).resolve()
    output.mkdir(parents=True, exist_ok=True)
    if args.replay:
        return replay(args.replay, output)
    from run_autoplay import parse_seeds
    rows = []
    for seed in parse_seeds(args.seeds):
        cases = [run_one(seed, name, output / f"purchase_seed{seed}_{name}", cgb=args.cgb, control=args.control_overcharge)
                 for name in (CASES if args.case == "all" else (args.case,))]
        row = {"seed": seed, "outcome": "completed" if all(c["execution"] == "completed" for c in cases) else "unreached",
               "contract_findings": [f for c in cases for f in c["findings"]],
               "cases": [{"scenario": c["scenario"], "execution": c["execution"], "verdict": c["verdict"]} for c in cases]}
        rows.append(row)
        print(json.dumps(row), flush=True)
    atomic_json(output / "autoplay_summary_transaction.json", {"schema_version": VERSION, "runs": rows})
    return int(any(r["outcome"] != "completed" or r["contract_findings"] for r in rows))


if __name__ == "__main__":
    sys.exit(main())
