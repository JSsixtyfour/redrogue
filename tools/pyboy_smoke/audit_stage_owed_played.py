"""Played run: a villain the player had no room to collect from stays reachable after reloads.

On every wild area type, with a pair and with a single villain, and through real input:

  1. The villain steals the party mon holding a Growth Ray, on arrival, at map load.
  2. The party and the current box are filled (staged: catching 21 mons is not the point).
  3. The agent walks to the hideout and wins the real battle. The hand-over finds no room,
     so the event must stop at OWED with the record and the gift intact.
  4. Reload one: leave the floor by a real warp to a neighbouring room, and come back.
  5. Reload two: START > SAVE > YES, a fresh emulator on that cartridge RAM, CONTINUE.
  6. Walk back and talk. Still no room: still OWED, and nothing lost.
  7. One box slot is emptied (staged). Talk again: the mon comes home to the box, SETTLED,
     with its struct, nickname, and gift.

A blocked path, a parked villain or a lost record fails the run. Staged writes are the party
and box contents and the theft's slot roll; everything else is the game's own code.

    python3 tools/pyboy_smoke/audit_stage_owed_played.py [--seeds 3] [--jobs 6] [--map cave] [--thief psychic]
"""
from __future__ import annotations

import argparse
import json
import multiprocessing
import sys
from pathlib import Path

import autoplay
import autoplay_world as world
import save_reload
from audit_stage_hideout_partner import stage_const
from harness import RedRogueHarness
from source_constants import parse_map_constants
from witch_autoplay import EVENTS

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"

MON = 44
BOX_MON = 33
NAME = 11
MONS_PER_BOX = 20
PARTY_LENGTH = 6
BOX_BASE = 7
OWNER_STOLEN = 249  # BRIDGE_SELECTED_OWNER_STOLEN; test_stolen_bridge_gift pins the same value
GROWTH_RAY = 3
VICTIM_SLOT = 1
PHASE_SHIFT = stage_const("STAGE_EVENT_PHASE_SHIFT")
PHASE_MASK = stage_const("STAGE_EVENT_PHASE_MASK")
HIDING = stage_const("STAGE_EVENT_PHASE_HIDING")
SETTLED = stage_const("STAGE_EVENT_PHASE_SETTLED")
OWED = stage_const("STAGE_EVENT_PHASE_OWED")
NO_ROOM = stage_const("STAGE_GIVEBACK_NO_ROOM")
TO_BOX = stage_const("STAGE_GIVEBACK_TO_BOX")
THIEVES = {"psychic": stage_const("STAGE_EVENT_PSYCHIC"), "jessie": stage_const("STAGE_EVENT_JESSIE_JAMES")}
STAGES = {"cave": ("PROCEDURAL_CAVE_1", "Procedural Cave"), "forest": ("PROCEDURAL_FOREST", "Procedural Forest"),
          "facility": ("PROCEDURAL_FACILITY", "Procedural Facility"),
          "cemetery": ("PROCEDURAL_CEMETERY_1", "Procedural Cemetery 1")}
BUDGET = 400_000
WALK_BUDGET = 60_000


class Failed(Exception):
    pass


class Play:
    def __init__(self, stage, thief, seed):
        self.maps = parse_map_constants(ROOT / "constants/map_constants.asm")
        self.stage, self.thief, self.seed = stage, thief, seed
        self.h = RedRogueHarness(ROOT, ARTIFACTS)
        self.agent = None
        self.row = {"stage": stage, "thief": thief, "seed": seed, "steps": []}

    def note(self, text, **data):
        self.row["steps"].append({"frame": self.h.pyboy.frame_count, "did": text, **data})

    def require(self, condition, text):
        if not condition:
            raise Failed(text)

    def phase(self):
        return (self.h.read8("wStageEvent") & PHASE_MASK) >> PHASE_SHIFT

    def records(self):
        return self.h.read_bytes("wBridgeSelectedEffects", 4)

    def gift_owner(self):
        records = self.records()
        for index in (0, 2):
            if records[index + 1] == GROWTH_RAY:
                return records[index]
        return 0

    def stolen_kind(self):
        return self.h.read_sram_bytes("sStolenKind", 1, bank=1)[0]

    # ---------------------------------------------------------------- the staged parts

    def choose_victim(self):
        """The slot roll, replayed at its consumer so the gifted mon is the one taken."""
        h = self.h
        bank, start = h.symbols.get("StageEventStealMon")
        _, callee = h.symbols.get("Rangerandom")
        pattern = bytes([0xCD, callee & 0xFF, callee >> 8])
        code = bytes(h.pyboy.memory[bank, start + i] for i in range(120))
        offset = code.find(pattern)
        if offset < 0:
            raise Failed("no Rangerandom call in StageEventStealMon")

        def roll(_context):
            h.pyboy.register_file.A = VICTIM_SLOT

        h._register_at((bank, start + offset + 3), roll)

    def fill_party_and_box(self):
        h = self.h
        memory = h.pyboy.memory
        count = h.read8("wPartyCount")
        first = h.address("wPartyMons")
        nicks, ot = h.address("wPartyMonNicks"), h.address("wPartyMonOT")
        species = h.address("wPartySpecies")
        for slot in range(count, PARTY_LENGTH):
            memory[first + slot * MON:first + (slot + 1) * MON] = list(memory[first:first + MON])
            memory[nicks + slot * NAME:nicks + (slot + 1) * NAME] = list(memory[nicks:nicks + NAME])
            memory[ot + slot * NAME:ot + (slot + 1) * NAME] = list(memory[ot:ot + NAME])
            memory[species + slot] = memory[species]
        memory[species + PARTY_LENGTH] = 0xFF
        h.write8("wPartyCount", PARTY_LENGTH)
        box = h.address("wBoxSpecies")
        for slot in range(MONS_PER_BOX):
            memory[box + slot] = memory[species]
        memory[box + MONS_PER_BOX] = 0xFF
        h.write8("wBoxCount", MONS_PER_BOX)
        self.note("staged: party and box full")

    def empty_one_box_slot(self):
        h = self.h
        h.pyboy.memory[h.address("wBoxSpecies") + MONS_PER_BOX - 1] = 0xFF
        h.write8("wBoxCount", MONS_PER_BOX - 1)
        self.note("staged: one box slot emptied")

    # ---------------------------------------------------------------- driving

    def until(self, condition, budget, what):
        """Let the agent play on its own until the condition holds."""
        h, end = self.h, self.h.pyboy.frame_count + budget
        while h.pyboy.frame_count < end:
            if self.agent.game_world_reads_ready() and condition():
                return
            self.agent.step()
            if self.agent.checks.crash:
                raise Failed(f"crash while waiting for {what}: {self.agent.checks.crash}")
            if h.hook_errors:
                raise Failed(f"hook error while waiting for {what}: {h.hook_errors[:2]}")
        raise Failed(f"never happened in {budget} frames: {what}")

    def settle(self, budget=8000):
        self.until(lambda: self.agent.mode() == "overworld", budget, "an idle overworld frame")

    def walk_to(self, spots, budget, what):
        """A shortest walk over the game's own grid. Wild battles and text are the agent's."""
        h, agent = self.h, self.agent
        end = h.pyboy.frame_count + budget
        while h.pyboy.frame_count < end:
            if not agent.game_world_reads_ready() or agent.mode() != "overworld":
                agent.step()
                continue
            here = agent.position()
            if here in spots:
                return here
            grid = agent.read_grid()
            path = world.find_path(grid, here, spots, agent.obstacles(), enter_impassable_goals=False)
            if not path:
                raise Failed(f"no path to {what} from {here} on {agent.map_name(h.read8('hCurMap'))}")
            agent.walk(path[0])
        raise Failed(f"walk ran out of frames: {what}")

    def hideout_step(self):
        h = self.h
        return (h.read_sram_bytes("sStageEventHideoutX", 1, bank=0)[0] * 2,
                h.read_sram_bytes("sStageEventHideoutY", 1, bank=0)[0] * 2)

    def villain_slot(self):
        """Whichever sprite stands on the hideout. It being on the map is half the point."""
        where = self.hideout_step()
        data2 = self.h.address("wSpriteStateData2")
        memory = self.h.pyboy.memory
        # Highest first: a taken pokeball keeps its coordinates, and balls have the low slots.
        for slot in range(14, 0, -1):
            if (memory[data2 + slot * 16 + 5] - 4, memory[data2 + slot * 16 + 4] - 4) == where:
                return slot
        raise Failed(f"no sprite stands on the hideout {where}: the villain was parked or moved")

    def talk_to_villain(self):
        """Walk up, face, press A, and read the hand-over the talk caused."""
        agent, h = self.agent, self.h
        self.settle()
        grid = agent.read_grid()
        slot = self.villain_slot()
        where = self.hideout_step()
        spots = {step: face for step, face in
                 world.adjacent_facing(where, agent.counter_tiles(), grid).items()}
        spots = {step: face for step, face in spots.items() if step not in agent.obstacles()}
        self.require(spots, f"nowhere to stand beside the villain at {where}")
        before = self.give_back["count"]
        talks = self.after_line["count"]
        # The last step can start a wild battle that eats the presses. Only the villain's
        # own after-battle routine running proves the talk happened.
        for _ in range(6):
            at = self.walk_to(spots, WALK_BUDGET, "the villain")
            self.settle(12000)
            if agent.position() != at:
                continue
            agent.press(spots[at], 3, 6)
            agent.press("a", 2, 8)
            self.settle(12000)
            if self.after_line["count"] > talks:
                return {"slot": slot, "at": at, "hand_overs": self.give_back["count"] - before,
                        "result": h.read8("wStageEventScratch"), "phase": self.phase()}
        raise Failed(f"six talks to the villain at {where} from {at} never reached its after-battle routine")

    def hop_to_neighbour_and_back(self):
        """Reload one: a real warp to another room of the same stage, and back through it."""
        agent, h = self.agent, self.h
        self.settle()
        home = h.read8("hCurMap")
        rooms = {self.maps[name] for name in self.maps if name.startswith("PROCEDURAL_")} - {home}
        pads = {(x, y) for y, x, _, dest in h.warp_entries() if dest in rooms}
        if not pads:
            self.note("no neighbouring room from this map; reload one skipped")
            return False
        grid = agent.read_grid()
        spots = {pad: None for pad in pads}
        here = agent.position()
        path = world.find_path(grid, here, spots, agent.obstacles() - pads, enter_impassable_goals=True)
        self.require(path or here in pads, f"no path to a neighbouring room from {here}")
        end = h.pyboy.frame_count + WALK_BUDGET
        while h.read8("hCurMap") == home:
            self.require(h.pyboy.frame_count < end, "never reached the neighbouring room")
            if not agent.game_world_reads_ready() or agent.mode() != "overworld":
                agent.step()
                continue
            here = agent.position()
            if here in pads:
                agent.enter_warp(None)
                continue
            path = world.find_path(agent.read_grid(), here, spots, agent.obstacles() - pads,
                                   enter_impassable_goals=True)
            self.require(path, f"lost the path to a neighbouring room at {here}")
            agent.walk(path[0], into_warp=len(path) == 1)
        away = h.read8("hCurMap")
        self.note("left the floor", to=agent.map_name(away))
        self.settle()
        end = h.pyboy.frame_count + WALK_BUDGET
        while h.read8("hCurMap") != home:
            self.require(h.pyboy.frame_count < end, "never came back from the neighbouring room")
            if not agent.game_world_reads_ready() or agent.mode() != "overworld":
                agent.step()
                continue
            back = {(x, y) for y, x, _, dest in h.warp_entries() if dest == home}
            self.require(back, f"no way back from {agent.map_name(away)}")
            here = agent.position()
            if here in back:
                agent.enter_warp(None)
                continue
            path = world.find_path(agent.read_grid(), here, {pad: None for pad in back},
                                   agent.obstacles() - back, enter_impassable_goals=True)
            self.require(path, f"no path back from {here}")
            agent.walk(path[0], into_warp=len(path) == 1)
        self.settle()
        self.note("back on the floor")
        return True

    def save_and_continue(self):
        """Reload two: the menu's own save, then a fresh emulator on only that cartridge RAM."""
        agent, h = self.agent, self.h
        self.settle()
        saved = h.hook_flag("SaveGameData")
        row = 4 if h.event_is_set(EVENTS["EVENT_GOT_POKEDEX"]) else 3
        agent.set_menu_goal("start_save", ("RedisplayStartMenu",), row,
                            lambda: agent.line_button(h.read8("hCurrentMenuItem"), agent.menu_goal.target))
        agent.press("start", 3, 8)
        self.until(lambda: saved["count"] and agent.mode() == "overworld", 4000, "the menu save")
        sram = save_reload.sram_image(h)
        before = {"event": h.read8("wStageEvent"), "records": self.records(), "party": h.read8("wPartyCount"),
                  "box": h.read8("wBoxCount"), "map": h.read8("hCurMap")}
        h.close()
        boot = save_reload.Reboot(sram)
        boot.load()
        self.h = boot.h
        self.require(boot.status == 2 and boot.overworld, f"CONTINUE failed, status {boot.status}")
        self.agent = autoplay.AutoplayAgent(self.h, seed=self.seed, player="strong")
        self.give_back = self.h.hook_flag("StageEventGiveBack")
        self.after_line = self.h.hook_flag("StageEventPrintAfterLine")
        self.settle()
        after = {"event": self.h.read8("wStageEvent"), "records": self.records(), "party": self.h.read8("wPartyCount"),
                 "box": self.h.read8("wBoxCount"), "map": self.h.read8("hCurMap")}
        self.require(before == after, f"the save did not carry the state: {before} -> {after}")
        self.note("saved and continued", state=after)

    # ---------------------------------------------------------------- the run

    def run(self):
        h = self.h
        autoplay.boot(h, self.seed, 73, "VERY_EASY")
        h.write8("hWhichPokemon", VICTIM_SLOT)
        h.pyboy.register_file.E = GROWTH_RAY
        h.call_routine("BridgeGrantSelectedEffect")
        memory = h.pyboy.memory
        base = h.address("wPartyMons") + VICTIM_SLOT * MON
        self.victim = {"box": list(memory[base:base + BOX_MON]),
                       "max_hp": memory[base + 34] << 8 | memory[base + 35],
                       "nick": list(memory[h.address("wPartyMonNicks") + VICTIM_SLOT * NAME:
                                           h.address("wPartyMonNicks") + (VICTIM_SLOT + 1) * NAME])}
        self.require(self.gift_owner() == VICTIM_SLOT + 1, f"grant failed: {self.records()}")
        self.choose_victim()
        h.write8("wStageEvent", THIEVES[self.thief])
        name, description = STAGES[self.stage]
        h.preload_and_enter_wild_area(self.maps[name], description)
        self.agent = autoplay.AutoplayAgent(h, seed=self.seed, player="strong")
        self.give_back = h.hook_flag("StageEventGiveBack")
        self.after_line = h.hook_flag("StageEventPrintAfterLine")

        self.until(lambda: self.phase() == HIDING and self.agent.mode() == "overworld", 12000, "the theft")
        self.require(self.stolen_kind() == 1, "the villain did not take a mon")
        self.require(self.gift_owner() == OWNER_STOLEN, f"theft lost the gift: {self.records()}")
        self.note("robbed", records=self.records(), party=h.read8("wPartyCount"))
        self.fill_party_and_box()

        villain = {}

        def fought():
            if self.phase() == OWED:
                return True
            if self.thief == "psychic" and "stats" not in villain and h.read8("hIsInBattle") == 2:
                count = h.read8("wEnemyPartyCount")
                enemy = h.address("wEnemyMons") + (count - 1) * MON
                if count and memory[enemy] == self.victim["box"][0]:
                    villain["stats"] = {"hp": memory[enemy + 1] << 8 | memory[enemy + 2],
                                        "max_hp": memory[enemy + 34] << 8 | memory[enemy + 35]}
            self.require(self.phase() == HIDING, f"phase left HIDING for {self.phase()} without OWED")
            return False

        self.until(fought, BUDGET, "the villain's defeat at no room")
        self.settle()
        self.require(h.read8("wStageEventScratch") == NO_ROOM, "hand-over did not report no room")
        self.require(self.stolen_kind() == 1, "the record was lost at OWED")
        self.require(self.gift_owner() == OWNER_STOLEN, f"OWED lost the gift: {self.records()}")
        if self.thief == "psychic":
            self.require("stats" in villain, "the Psychic's team never held the stolen mon")
            self.require(villain["stats"]["hp"] <= villain["stats"]["max_hp"], f"villain's copy: {villain['stats']}")
            self.require(villain["stats"]["max_hp"] == self.victim["max_hp"], f"villain's copy: {villain['stats']}")
            self.row["villain"] = villain["stats"]
        self.note("won with no room: OWED", map=self.agent.map_name(h.read8("hCurMap")), hideout=self.hideout_step())

        self.row["floor_reload"] = self.hop_to_neighbour_and_back()
        self.require(self.phase() == OWED and self.stolen_kind() == 1, "the floor reload ended the debt")

        self.save_and_continue()
        h = self.h
        memory = h.pyboy.memory
        self.require(self.phase() == OWED and self.stolen_kind() == 1, "the reload ended the debt")

        first = self.talk_to_villain()
        self.note("talked with no room", **first)
        self.require(first["hand_overs"] == 1 and first["result"] == NO_ROOM and first["phase"] == OWED,
                     f"retry with no room: {first}")
        self.require(self.stolen_kind() == 1 and self.gift_owner() == OWNER_STOLEN, "the retry lost the mon or gift")

        self.empty_one_box_slot()
        second = self.talk_to_villain()
        self.note("talked with room", **second)
        self.require(second["hand_overs"] == 1 and second["result"] == TO_BOX and second["phase"] == SETTLED,
                     f"retry with room: {second}")
        self.require(self.stolen_kind() == 0, "the record outlived the hand-over")
        self.require(h.read8("wBoxCount") == MONS_PER_BOX, "the box did not grow")

        last = MONS_PER_BOX - 1
        slot = h.address("wBoxMons") + last * BOX_MON
        struct = list(memory[slot:slot + BOX_MON])
        nick = list(memory[h.address("wBoxMonNicks") + last * NAME:h.address("wBoxMonNicks") + MONS_PER_BOX * NAME])
        struct[3] = self.victim["box"][3]  # byte 3 is recomputed from experience on this path
        self.require(struct == self.victim["box"], "the returned struct differs")
        self.require(nick == self.victim["nick"], "the returned nickname differs")
        box = h.read8("wCurrentBoxNum") & 0x7F
        want = BOX_BASE + box * MONS_PER_BOX + last
        self.require(self.gift_owner() == want, f"gift at {self.gift_owner()}, expected box owner {want}")

        third = self.talk_to_villain_if_standing()
        self.note("after settling", **third)
        self.row["ok"] = True
        self.row["anomalies"] = self.agent.checks.anomalies[:6]
        self.row["frames"] = h.pyboy.frame_count

    def talk_to_villain_if_standing(self):
        """A settled villain says an idle line: no third hand-over, no second mon."""
        try:
            result = self.talk_to_villain()
        except Failed as gone:
            return {"gone": str(gone)}
        self.require(result["hand_overs"] == 0, f"a settled villain handed over again: {result}")
        self.require(self.h.read8("wBoxCount") == MONS_PER_BOX, "a settled villain gave a second mon")
        return result


def play(job):
    stage, thief, seed = job
    runner = Play(stage, thief, seed)
    try:
        runner.run()
    except Exception as error:
        runner.row["ok"] = False
        runner.row["failure"] = f"{type(error).__name__}: {error}"[:500]
        if runner.agent is not None:
            memory = runner.h.pyboy.memory
            data1, data2 = runner.h.address("wSpriteStateData1"), runner.h.address("wSpriteStateData2")
            runner.row["sprites"] = [[slot, memory[data1 + slot * 16], memory[data1 + slot * 16 + 2],
                                      memory[data2 + slot * 16 + 5] - 4, memory[data2 + slot * 16 + 4] - 4]
                                     for slot in range(1, 15) if memory[data1 + slot * 16]]
            runner.row["hidden"] = {slot: flag for slot, flag in runner.agent.hidden.items() if flag}
            runner.row["hideout"] = runner.hideout_step()
            runner.row["position"] = runner.agent.position()
            runner.row["map"] = runner.agent.map_name(runner.h.read8("hCurMap"))
        try:
            runner.h.write_failure_artifacts(f"owed_played_{stage}_{thief}_{seed}")
        except Exception:
            pass
    finally:
        try:
            runner.h.close()
        except Exception:
            pass
    return runner.row


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seeds", type=int, default=2)
    parser.add_argument("--first-seed", type=int, default=1)
    parser.add_argument("--jobs", type=int, default=6)
    parser.add_argument("--map", choices=sorted(STAGES), action="append")
    parser.add_argument("--thief", choices=sorted(THIEVES), action="append")
    args = parser.parse_args(argv)
    jobs = [(stage, thief, seed) for stage in (args.map or sorted(STAGES)) for thief in (args.thief or sorted(THIEVES))
            for seed in range(args.first_seed, args.first_seed + args.seeds)]
    with multiprocessing.Pool(args.jobs) as pool:
        rows = pool.map(play, jobs, chunksize=1)
    for row in rows:
        print(json.dumps(row, default=str), flush=True)
    failed = [row for row in rows if not row.get("ok")]
    print(f"{len(rows) - len(failed)} of {len(rows)} played runs passed", flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
