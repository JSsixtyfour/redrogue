"""Witch bargain lifecycle runner: real dialogue, doors, battles, settlement.

Plan: WITCH_AUTOPLAY_SOL_PLAN_2026-11-04.md. Handoff: WITCH_AUTOPLAY_HANDOFF_2026-11-04.md.
Run it from the frozen tree (witch_freeze.sh), never the live one:

    T=~/witch_frozen/<snapshot>
    python3 $T/tools/pyboy_smoke/witch_autoplay.py fixtures --evidence E
    python3 $T/tools/pyboy_smoke/witch_autoplay.py run --evidence E --rom pokered --case C03
    python3 $T/tools/pyboy_smoke/witch_autoplay.py list

What a run is allowed to touch (see the Intervention log in each result):
- setup: context before the offer (wBattleCount, badges, party, earned bits used as
  a precondition). Always logged. Never the accepted bit, and never earned bits
  after the offer: those must change only through the game's own code.
- steer: the appearance branch and the challenge/prize draws. The real Rangerandom
  still runs, so the RNG advances as in play; only its answer is replaced, at the
  instruction after the call. Then the hooks are gone, because the pre-offer state
  is saved and each branch loads it in a fresh emulator.
- Everything after the pre-offer state is button presses, plus any draw a case
  replays at its consumer, which it must log with Run.log_intervention.

A case passes only when the event was observed, its delta verified and the player
regained control. A KO, a skipped effect or a timeout is not_reached, not a pass.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import random
import re
import sys
import threading
import time
import traceback
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

import autoplay
from autoplay import AutoplayAgent, ROOT, lobby_text_id
from harness import RedRogueHarness
from source_constants import parse_rgbds_constants

ROMS = ("pokeblue_debug", "pokeblue", "pokered")
ROUNDS = parse_rgbds_constants(ROOT / "constants/round_constants.asm")
RAM = parse_rgbds_constants(ROOT / "constants/ram_constants.asm", ROUNDS)
EVENTS = parse_rgbds_constants(ROOT / "constants/event_constants.asm")
SPECIES = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
MOVES = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
ACCEPTED = 1 << RAM["BIT_WITCH_ACCEPTED"]
GYM_NEXT = 1 << RAM["BIT_ROGUE_GYM_NEXT"]
PARTY_STRUCT = 0x2C
MON_MOVES, MON_PP = 8, 0x1D

CHARS: dict[int, str] = {}
for _char, _value in re.findall(r'charmap "(.)",\s*\$([0-9a-fA-F]{2})',
                                (ROOT / "constants/charmap.asm").read_text(encoding="utf-8")):
    CHARS.setdefault(int(_value, 16), _char)
CHARS[0x7F] = " "
NAME_LENGTH = 11
FIXTURE_NAME = [next(k for k, v in CHARS.items() if v == c) for c in "TEST"] + [0x50]


class NotReached(Exception):
    """The event under test never happened: uncovered, not passed."""


class DriverFault(Exception):
    """The runner itself could not do its job."""


def screen_rows(h: RedRogueHarness) -> list[str]:
    tiles = h.read_bytes("wTileMap", 20 * 18)
    return ["".join(CHARS.get(t, "?") for t in tiles[y * 20:(y + 1) * 20]) for y in range(18)]


def textbox(h: RedRogueHarness) -> str:
    """The dialogue box's two lines, as the player reads them."""
    rows = screen_rows(h)
    return " ".join(rows[y][1:19].replace("?", " ").strip() for y in (14, 16)).strip()


def bcd(values: list[int]) -> int:
    return int("".join(f"{v:02x}" for v in values))


# ------------------------------------------------------------------- the agent

class WitchAgent(AutoplayAgent):
    """The autoplay agent, which also walks to the witch and answers her with
    real presses. Everything else (battles, rewards, doors) is its normal play."""

    def __init__(self, harness, *, answers=("yes", "yes"), talk=True, door=None,
                 shop=False, heal_at_nurse=True, move_policy=None, **options):
        options.setdefault("door_policy", "first")
        options.setdefault("offer_policy", "last")
        options.setdefault("battle_policy", "best_power")
        super().__init__(harness, **options)
        self.move_policy = move_policy  # callable(agent) -> move slot, or None for the policy's
        self.answers = list(answers)
        self.witch_pending = talk
        self.witch_talking = False
        self.witch_talk_frame = -1
        self.witch_done = False
        self.forced_door = door
        self.shop = shop
        self.heal_at_nurse = heal_at_nurse
        self.transcript: list[str] = []
        self.witch_text = lobby_text_id("TEXT_PC_WITCH")
        harness.register_hook("YesNoChoice", self._on_yes_no)
        harness.register_hook("WaitForTextScrollButtonPress", self._capture_text)
        harness.register_hook("HandleMenuInput", self._capture_text)

    def _on_move_menu(self, context) -> None:
        super()._on_move_menu(context)
        slot = self.move_policy(self) if self.move_policy else None
        if slot is not None and self.menu_goal is not None and self.menu_goal.kind == "move_menu":
            self.menu_goal.target = slot

    def _capture_text(self, _context) -> None:
        line = textbox(self.h)
        if line and (not self.transcript or self.transcript[-1] != line):
            self.transcript.append(line)

    def _on_yes_no(self, _context) -> None:
        if not self.witch_talking or not self.answers:
            return
        answer = self.answers.pop(0)
        target = 0 if answer == "yes" else 1
        self.event("witch_answer", answer=answer)
        self.set_menu_goal("witch_yes_no", ("DisplayTwoOptionMenu",), target,
                           lambda: self.line_button(self.h.read8("hCurrentMenuItem"),
                                                    self.menu_goal.target))

    def witch_slot(self, sprites) -> int | None:
        texts = self.h.read_bytes("wMapSpriteData", 2 * autoplay.SPRITE_SLOTS)
        return next((slot for slot in sprites if texts[2 * (slot - 1) + 1] == self.witch_text), None)

    def choose_heal(self):
        # Challenge 15 refuses medicine outside battle, so the base agent's heal plan
        # would retry forever. A player reads the refusal and stops. Cases that test
        # the refusal drive the menu themselves.
        h = self.h
        if (h.read8("wRogueFlagsBitfield") & ACCEPTED
                and h.read8("wWitchChallenge") == RAM["CHALLENGE_NO_HEALING"]):
            return None
        return super().choose_heal()

    def goal_groups(self, grid):
        groups = super().goal_groups(grid)
        if self.witch_pending and self.h.read8("hCurMap") == self.lobby_map:
            sprites = self.sprites()
            slot = self.witch_slot(sprites)
            if slot is not None:
                groups.insert(0, self.talk_goal(grid, {slot: sprites[slot]}, "witch"))
        return groups

    def arrive(self, face, label) -> None:
        if label.startswith("witch:"):
            self.witch_pending = False
            self.witch_talking = True
            self.witch_talk_frame = self.h.pyboy.frame_count
            self.event("witch_talk", slot=label)
        super().arrive(face, label)

    def door_goals(self):
        if self.forced_door is not None:
            self.door_choice = self.forced_door
        return super().door_goals()

    def on_map_change(self, current_map: int) -> None:
        super().on_map_change(current_map)
        if current_map == self.lobby_map:
            self.shopped_this_visit = not self.shop
            self.healed_this_visit = not self.heal_at_nurse

    def step(self) -> None:
        if (self.witch_talking and self.last_overworld_frame > self.witch_talk_frame + 4
                and self.mode() == "overworld"):
            self.witch_talking = False
            self.witch_done = True
            self.event("witch_end", accepted=bool(self.h.read8("wRogueFlagsBitfield") & ACCEPTED))
        super().step()


# ------------------------------------------------------------------- the context

@dataclass
class Mon:
    species: str = "TAUROS"
    level: int = 100
    moves: tuple[str, ...] = ()
    pp: tuple[int, ...] = ()


@dataclass
class Context:
    """The legal state an offer is made in. Every field applied is logged as setup."""
    battle_count: int | None = None
    gym_next: bool | None = None
    badges: int | None = None
    earned: tuple[int, int] | None = None  # precondition only, never the outcome
    party: tuple[Mon, ...] = (Mon(), Mon("ALAKAZAM"))
    money: int | None = None
    pokes: dict[str, int] = field(default_factory=dict)
    arrays: dict[str, tuple[int, ...]] = field(default_factory=dict)  # consecutive bytes from the label
    events: tuple[str, ...] = ()  # event flags set before the lobby entry


@dataclass
class Case:
    id: str
    title: str
    challenge: int
    prize: int
    run: Callable[["Run"], None]
    context: Context = field(default_factory=Context)
    max_frames: int = 400_000
    agent_options: dict[str, object] = field(default_factory=dict)  # WitchAgent keywords
    gate_rejects: bool = False  # the steered challenge must be refused: any other offer is the setup
    gate_hides: bool = False  # the witch must be absent: no offer at all is the setup


@dataclass
class Check:
    name: str
    expected: object
    observed: object
    ok: bool


class Run:
    """One branch of one case on one ROM: state, helpers, and the evidence."""

    def __init__(self, case: Case, rom: str, branch: str, evidence: Path):
        self.case, self.rom, self.branch, self.evidence = case, rom, branch, evidence
        self.h: RedRogueHarness = None
        self.agent: WitchAgent = None
        self.checks: list[Check] = []
        self.interventions: list[dict[str, object]] = []
        self.notes: list[str] = []
        self.old_transcript: list[str] = []  # dialogue from before a Continue
        # Anomalies the case itself causes, by message prefix (see hold_enemy in witch_cases.py).
        # They are counted in the result as ignored_anomalies, never dropped silently.
        self.expected_anomaly_prefixes: list[str] = []

    # ---- evidence
    def unexplained_anomalies(self) -> list[dict[str, object]]:
        return [a for a in self.agent.checks.anomalies
                if not any(str(a.get("detail", "")).startswith(p) for p in self.expected_anomaly_prefixes)]

    def check(self, name: str, expected, observed) -> bool:
        ok = expected == observed
        self.checks.append(Check(name, expected, observed, ok))
        return ok

    def require(self, name: str, ok: bool, detail: object = None) -> None:
        self.checks.append(Check(name, True, detail if detail is not None else ok, bool(ok)))

    def must_reach(self, what: str, reached: bool) -> None:
        if not reached:
            raise NotReached(what)

    def log_intervention(self, kind: str, **data) -> None:
        self.interventions.append({"kind": kind, "frame": self.h.pyboy.frame_count, **data})

    # ---- reads
    @property
    def earned(self) -> list[int]:
        return self.h.read_bytes("wWitchPrizesEarned", 2)

    @property
    def accepted(self) -> bool:
        return bool(self.h.read8("wRogueFlagsBitfield") & ACCEPTED)

    @property
    def money(self) -> int:
        return bcd(self.h.read_bytes("wPlayerMoney", 3))

    def party_snapshot(self) -> dict[str, object]:
        count = self.h.read8("wPartyCount")
        return {"count": count, "species": self.h.read_bytes("wPartySpecies", count),
                "hp": [self.h.read8("wPartyMon1HP", i * PARTY_STRUCT) << 8
                       | self.h.read8("wPartyMon1HP", i * PARTY_STRUCT + 1) for i in range(count)],
                "status": [self.h.read8("wPartyMon1Status", i * PARTY_STRUCT) for i in range(count)]}

    # ---- the lifecycle verbs a case composes
    def talk(self, answers=None) -> None:
        """Walk to the witch and answer her. Default: this branch's answers."""
        agent = self.agent
        if answers is not None:
            agent.answers = list(answers)
        limit = self.h.pyboy.frame_count + 6000
        while not agent.witch_done:
            agent.step()
            self.raise_on_hook_error()
            if self.h.pyboy.frame_count > limit:
                raise DriverFault(f"witch dialogue did not finish: {agent.event_tail()}")

    def play_zone(self, stages: int = 1) -> None:
        """Normal autoplay until `stages` more zones are cleared and the lobby is
        playable again. Raises NotReached on a blackout or timeout."""
        agent = self.agent
        goal = agent.report.stages_cleared + stages
        agent.run(stages=goal, max_frames=self.case.max_frames)
        self.raise_on_hook_error()
        self.must_reach(f"zone cleared (outcome {agent.report.outcome}: {agent.report.detail})",
                        agent.report.stages_cleared >= goal and not agent.report.blackouts)
        self.wait_playable()

    def wait_playable(self, limit: int = 3000) -> None:
        """Until the overworld polls input with no script holding the pad: the
        visit's setup, settlement included, has then run."""
        agent = self.agent
        end = self.h.pyboy.frame_count + limit
        while self.h.pyboy.frame_count < end:
            agent.step()
            if agent.mode() == "overworld" and agent.h.read8("hCurMap") == agent.current_map:
                return
        raise NotReached("player control never returned")

    def control_check(self, label: str = "control") -> None:
        """A meaningful input and its verified result: the player walks a step."""
        self.wait_playable()
        agent = self.agent
        grid = agent.read_grid()
        here = agent.position()
        blocked = agent.obstacles()
        for direction, step in grid.moves(*here):
            if step not in blocked:
                agent.walk(direction)
                moved = agent.position()
                self.require(f"{label}: input moved the player", moved != here,
                             {"from": here, "to": moved, "pressed": direction})
                return
        raise DriverFault(f"no free step from {here}")

    def raise_on_hook_error(self) -> None:
        if self.h.hook_errors:
            raise DriverFault(self.h.hook_errors[0])

    def hook_count(self, label: str) -> dict[str, int]:
        return self.h.hook_flag(label)

    def transcript_has(self, text: str) -> bool:
        return any(text in line for line in self.agent.transcript + self.old_transcript)

    def hook_after_call(self, routine: str, callee: str, callback, *, nth: int = 0, span: int = 200) -> None:
        """Hook the instruction after the nth `call callee` in routine: the seam for
        replaying one draw at its consumer. The real callee still runs, so the RNG
        advances as in play. Set registers.A in the callback, and log it."""
        h = self.h
        bank, start = h.symbols.get(routine)
        callee_bank, callee_address = h.symbols.get(callee)
        if callee_bank not in (0, bank):
            raise DriverFault(f"{callee} (bank {callee_bank:02x}) is not callable from {routine} ({bank:02x})")
        pattern = bytes([0xCD, callee_address & 0xFF, callee_address >> 8])
        code = bytes(h.pyboy.memory[bank, start + i] for i in range(span))
        offset = -1
        for _ in range(nth + 1):
            offset = code.find(pattern, offset + 1)
            if offset < 0:
                raise DriverFault(f"call {nth} to {callee} not found in {routine}")
        h._register_at((bank, start + offset + len(pattern)), callback)

    def witch_state(self) -> dict[str, object]:
        """What a save must carry for a bargain to survive it."""
        h = self.h
        return {"challenge": h.read8("wWitchChallenge"), "prize": h.read8("wWitchPrize"),
                "accepted": self.accepted, "earned": self.earned,
                "boosts": h.read8("wEarnedStatBoosts"), "party_limit": h.read8("wPartyLimit"),
                "turn_limit": h.read8("wBattleTurnLimit"), "party": self.party_snapshot()}

    def save_and_continue(self) -> tuple[dict[str, object], dict[str, object]]:
        """A real in-game save through START > SAVE > YES, then a fresh emulator
        on that cartridge RAM, through the title and CONTINUE. Returns the bargain
        state before and after. The emulator is replaced, so hooks must be
        registered again afterwards, and agent report counters restart."""
        import save_reload
        agent, h = self.agent, self.h
        self.wait_playable()
        saved = h.hook_flag("SaveGameData")
        row = 4 if h.event_is_set(EVENTS["EVENT_GOT_POKEDEX"]) else 3
        agent.set_menu_goal("start_save", ("RedisplayStartMenu",), row,
                            lambda: agent.line_button(h.read8("hCurrentMenuItem"), agent.menu_goal.target))
        agent.press("start", 3, 8)
        end = h.pyboy.frame_count + 3000
        while h.pyboy.frame_count < end:
            agent.step()
            if saved["count"] and agent.mode() == "overworld":
                break
        self.must_reach("SaveGameData ran through the menu", bool(saved["count"]))
        before = self.witch_state()
        sram = save_reload.sram_image(h)
        self.old_transcript += agent.transcript
        options = agent.rebuild_options
        h.close()
        autoplay.ROM = self.rom
        boot = save_reload.Reboot(sram)
        boot.load()
        self.h = boot.h
        self.must_reach(f"CONTINUE loaded the save (status {boot.status})", boot.status == 2 and boot.overworld)
        self.agent = WitchAgent(self.h, talk=False, answers=(), **options)
        self.wait_playable()
        return before, self.witch_state()


# ------------------------------------------------------------------- fixtures

def harness(rom: str, evidence: Path) -> RedRogueHarness:
    return RedRogueHarness(ROOT, evidence / "harness_artifacts", rom=rom)


def rom_tag(rom: str) -> str:
    return hashlib.sha256((ROOT / f"{rom}.gbc").read_bytes()).hexdigest()[:8]


def fixture_path(evidence: Path, rom: str) -> Path:
    return evidence / "fixtures" / f"{rom}_{rom_tag(rom)}.state"


def make_fixture(rom: str, evidence: Path, seed: int = 1, limit: int = 400_000) -> dict[str, object]:
    """A lobby at an input poll, reached the way the build reaches it. Debug: the
    Debug 2 menu. Release: power on, NEW GAME, the agent plays to the first lobby.
    Campaign contexts branch from this one state."""
    path = fixture_path(evidence, rom)
    path.parent.mkdir(parents=True, exist_ok=True)
    h = harness(rom, evidence)
    try:
        if rom == autoplay.DEBUG_ROM:
            autoplay.boot(h, seed, 1, "HARD")
        else:
            autoplay.boot_new_game(h, seed, "HARD")
        agent = AutoplayAgent(h, seed=seed, door_policy="first", offer_policy="first",
                              stall_frames=20_000)
        start = h.pyboy.frame_count
        while True:
            agent.step()
            if h.pyboy.frame_count - start > limit:
                raise DriverFault(f"{rom} never reached the lobby in {limit} frames")
            if (agent.game_world_reads_ready() and h.read8("hCurMap") == agent.lobby_map
                    and agent.mode() == "overworld"):
                break
        state = io.BytesIO()
        h.save_state(state)
        path.write_bytes(state.getvalue())
        return {"rom": rom, "sha": rom_tag(rom), "seed": seed, "path": str(path),
                "frames": h.pyboy.frame_count - start, "battle_count": h.read8("wBattleCount"),
                "party": h.read_bytes("wPartySpecies", h.read8("wPartyCount"))}
    finally:
        h.close()


def set_party(run: Run, mons: tuple[Mon, ...]) -> None:
    h = run.h
    h.write8("wPartyCount", 0)
    h.write8("wPartySpecies", 0xFF)
    for index, mon in enumerate(mons):
        h.park_before_hijack()
        h.write8("wCurPartySpecies", SPECIES[mon.species])
        h.write8("wCurEnemyLevel", mon.level)
        h.write8("wMonDataLocation", 0x10)
        h.write8("wSpawnForm", 0)
        h.write8("wSpawnDVSlot", 0)
        h.call_routine("_AddPartyMon", limit=60000)
        # _AddPartyMon leaves the names to its callers; a party larger than the
        # fixture's prints uninitialised bytes otherwise (TEXT ID ERROR).
        for label in ("wPartyMonNicks", "wPartyMonOT"):
            for i, byte in enumerate(FIXTURE_NAME):
                h.write8(label, byte, offset=index * NAME_LENGTH + i)
        base = index * PARTY_STRUCT
        if mon.moves:
            for slot in range(4):
                move = MOVES[mon.moves[slot]] if slot < len(mon.moves) else 0
                h.write8("wPartyMon1", move, offset=base + MON_MOVES + slot)
        if mon.pp:
            for slot in range(4):
                h.write8("wPartyMon1", mon.pp[slot] if slot < len(mon.pp) else 0,
                         offset=base + MON_PP + slot)
    run.log_intervention("setup", party=[(m.species, m.level, m.moves, m.pp) for m in mons])


def steer_offer(h: RedRogueHarness, challenge: int, prize: int) -> dict[str, list[int]]:
    """Replace the appearance branch and the two draws. Real Rangerandom still runs.
    A draw the game's gates reject would loop, so past five it stops steering: the
    caller then sees a different challenge, which is what an exclusion test wants."""
    draws: dict[str, list[int]] = {"challenge": [], "prize": []}
    for key, label, value in (("challenge", "PCWitchSetup.rollChallenge", challenge),
                              ("prize", "PCWitchSetup.rollPrize", prize)):
        bank, address = h.symbols.get(label)
        code = [h.pyboy.memory[bank, address + i] for i in (0, 2)]
        if code != [0x0E, 0xCD]:
            raise DriverFault(f"{label} is no longer ld c,N / call: {code}")

        def replace_draw(_context, key=key, value=value) -> None:
            real = h.pyboy.register_file.A
            draws[key].append(real)
            if value and len(draws[key]) <= 5:
                h.pyboy.register_file.A = value - 1
        h._register_at((bank, address + 5), replace_draw)

    def show_anyway(_context) -> None:
        h.pyboy.register_file.PC = h.address("RollLobbyNPCAppearance.show")
    h.register_hook("RollLobbyNPCAppearance.hide", show_anyway)
    return draws


def prepare_offer(run: Run, base: bytes, attempt: int) -> bool:
    """Apply the context, re-run the lobby's own entry setup, return whether the
    witch now offers this case's challenge. Clearing EVENT_ENTER_ROOM is what every
    warp does; it re-enters the same code at the same boundary without the walk."""
    case, h = run.case, run.h
    h.load_state(io.BytesIO(base))
    h.tick(2)
    context = case.context
    run.interventions.clear()
    if context.party:
        set_party(run, context.party)
    writes: dict[str, int] = dict(context.pokes)
    if context.battle_count is not None:
        writes["wBattleCount"] = context.battle_count
    if context.badges is not None:
        writes["wObtainedBadges"] = context.badges
    for label, value in writes.items():
        h.write8(label, value)
    for label, values in context.arrays.items():
        for offset, value in enumerate(values):
            h.write8(label, value, offset=offset)
    for name in context.events:
        h.set_event(EVENTS[name])
    if context.gym_next is not None:
        flags = h.read8("wRogueFlagsBitfield") & ~GYM_NEXT & 0xFF
        h.write8("wRogueFlagsBitfield", flags | (GYM_NEXT if context.gym_next else 0))
    if context.earned is not None:
        h.write8("wWitchPrizesEarned", context.earned[0])
        h.write8("wWitchPrizesEarned", context.earned[1], offset=1)
    if context.money is not None:
        digits = f"{context.money:06d}"
        for i in range(3):
            h.write8("wPlayerMoney", int(digits[2 * i:2 * i + 2], 16), offset=i)
    run.log_intervention("setup", writes=writes, arrays=context.arrays, gym_next=context.gym_next,
                         earned=context.earned, money=context.money)
    h.seed_rng([attempt, 0x57, 0x49, 0x54])
    run.log_intervention("seed", seed=[attempt, 0x57, 0x49, 0x54])
    event = EVENTS["EVENT_ENTER_ROOM"]
    address = h.address("wEventFlags") + event // 8
    h.pyboy.memory[address] &= ~(1 << (event % 8)) & 0xFF
    setup = h.hook_flag("PCWitchSetup")
    polls = h.hook_flag("JoypadOverworld")
    h.wait_until(lambda: setup["count"] > 0, "lobby setup", 1200)
    polls["count"] = 0
    h.wait_until(lambda: polls["count"] > 2, "lobby input poll", 1200)
    if case.gate_hides:
        return h.read8("wWitchChallenge") == 0
    if case.gate_rejects:
        return h.read8("wWitchChallenge") not in (0, case.challenge)
    return (h.read8("wWitchChallenge") == case.challenge
            and (not case.prize or h.read8("wWitchPrize") == case.prize))


def build_preoffer(case: Case, rom: str, evidence: Path) -> tuple[bytes, list[dict[str, object]]]:
    """The state both branches fork from. Fresh emulator, so steering hooks die here."""
    base = fixture_path(evidence, rom).read_bytes()
    run = Run(case, rom, "setup", evidence)
    run.h = harness(rom, evidence)
    try:
        draws = steer_offer(run.h, case.challenge, case.prize)
        for attempt in range(1, 9):
            draws["challenge"].clear()
            draws["prize"].clear()
            if prepare_offer(run, base, attempt):
                state = io.BytesIO()
                run.h.save_state(state)
                run.log_intervention("steer", challenge=case.challenge, prize=case.prize, attempt=attempt,
                                     challenge_draws=len(draws["challenge"]))
                return state.getvalue(), list(run.interventions)
        raise NotReached(f"witch never offered challenge {case.challenge} / prize {case.prize} "
                         f"(a gate rejected it, or a gift-room door hid her, 8 seeds)")
    finally:
        run.h.close()


# ------------------------------------------------------------------- execution

ANSWERS = {"accept": ("yes", "yes"), "decline": ("yes", "no"), "refuse_intro": ("no",)}


def start_hang_watchdog(run: Run, out: Path, preoffer: bytes, on_hang, seconds: float = 45) -> None:
    """tick() stops returning when the CPU hits an illegal opcode. Nothing in the main
    thread can notice, so record where it stopped and report a failed branch. Hook
    wedges freeze too: the report names the opcode so the two can be told apart."""
    beat = {"time": time.monotonic()}
    original = run.h.tick

    def tick(*args, **kwargs):
        beat["time"] = time.monotonic()
        return original(*args, **kwargs)

    run.h.tick = tick

    def watch() -> None:
        while True:
            time.sleep(3)
            if time.monotonic() - beat["time"] < seconds:
                continue
            h = run.h
            registers = h.pyboy.register_file
            pc, sp = registers.PC, registers.SP
            bank = h.read8("hLoadedROMBank")
            opcode = h.pyboy.memory[0 if pc < 0x4000 else bank, pc]
            hooked = (0 if pc < 0x4000 else bank, pc) in h._hook_callbacks
            illegal = opcode in (0xD3, 0xDB, 0xDD, 0xE3, 0xE4, 0xEB, 0xEC, 0xED, 0xF4, 0xFC, 0xFD)
            detail = (f"emulator stopped at {bank:02x}:{pc:04x} "
                      f"({h.symbols.nearest(0 if pc < 0x4000 else bank, pc)}) opcode {opcode:02x}"
                      f"{' ILLEGAL' if illegal else ''}{' HOOKED (wedge?)' if hooked else ''}, sp={sp:04x}, "
                      f"map {h.read8('hCurMap'):02x}, wCurMapScript {h.read8('wCurMapScript')}")
            stack = [h.pyboy.memory[sp + i] | h.pyboy.memory[sp + i + 1] << 8 for i in range(0, 16, 2)]
            result = {"case": run.case.id, "title": run.case.title, "rom": run.rom, "rom_sha8": rom_tag(run.rom),
                      "branch": run.branch, "status": "driver_fault" if hooked else "gameplay_fail",
                      "detail": detail, "stack": [f"{word:04x}" for word in stack],
                      "checks": [c.__dict__ for c in run.checks], "notes": run.notes,
                      "interventions": run.interventions,
                      "transcript": run.agent.transcript if run.agent else [],
                      "anomalies": run.agent.checks.anomalies[:12] if run.agent else [],
                      "frames": h.pyboy.frame_count, "wall_seconds": seconds, "hang": True,
                      "stages": run.agent.report.stages_cleared if run.agent else 0,
                      "battles_won": run.agent.report.battles_won if run.agent else 0,
                      "replay": f"witch_autoplay.py run --evidence {run.evidence} --rom {run.rom} "
                                f"--case {run.case.id} --branch {run.branch}"}
            out.mkdir(parents=True, exist_ok=True)
            write_failure_bundle(run, out, preoffer, result)
            (out / "result.json").write_text(json.dumps(result, indent=1, default=str) + "\n", encoding="utf-8")
            if on_hang:
                on_hang(result)
            os._exit(0)

    threading.Thread(target=watch, daemon=True).start()


def run_branch(case: Case, rom: str, branch: str, evidence: Path, preoffer: bytes,
               interventions: list[dict[str, object]], seed: int = 1, on_hang=None) -> dict[str, object]:
    run = Run(case, rom, branch, evidence)
    run.interventions = list(interventions)
    run.h = harness(rom, evidence)
    started = time.monotonic()
    status, detail = "pass", ""
    out = evidence / "results" / rom / case.id / branch
    start_hang_watchdog(run, out, preoffer, on_hang)
    try:
        run.h.load_state(io.BytesIO(preoffer))
        options = {"seed": seed, "stall_frames": 30_000, **case.agent_options}
        run.agent = WitchAgent(run.h, answers=ANSWERS.get(branch, ("yes", "yes")), **options)
        run.agent.rebuild_options = options
        case.run(run)
        if not run.checks:
            raise DriverFault("the case verified nothing")
        if not all(c.ok for c in run.checks):
            status = "gameplay_fail"
        anomalies = run.unexplained_anomalies()
        if anomalies:
            status = status if status != "pass" else "anomaly"
    except NotReached as error:
        status, detail = "not_reached", str(error)
    except DriverFault as error:
        status, detail = "driver_fault", str(error)
    except Exception:
        status, detail = "driver_fault", traceback.format_exc()
    result = {
        "case": case.id, "title": case.title, "rom": rom, "rom_sha8": rom_tag(rom), "branch": branch,
        "status": status, "detail": detail,
        "checks": [c.__dict__ for c in run.checks], "notes": run.notes,
        "interventions": run.interventions,
        "transcript": run.agent.transcript if run.agent else [],
        "anomalies": run.unexplained_anomalies()[:12] if run.agent else [],
        "ignored_anomalies": (len(run.agent.checks.anomalies) - len(run.unexplained_anomalies())) if run.agent else 0,
        "frames": run.agent.report.frames if run.agent else 0,
        "wall_seconds": round(time.monotonic() - started, 1),
        "stages": run.agent.report.stages_cleared if run.agent else 0,
        "battles_won": run.agent.report.battles_won if run.agent else 0,
        "replay": f"witch_autoplay.py run --evidence {evidence} --rom {rom} --case {case.id} --branch {branch}",
    }
    out.mkdir(parents=True, exist_ok=True)
    if status != "pass":
        write_failure_bundle(run, out, preoffer, result)
    (out / "result.json").write_text(json.dumps(result, indent=1, default=str) + "\n", encoding="utf-8")
    run.h.close()
    return result


def write_failure_bundle(run: Run, out: Path, preoffer: bytes, result: dict[str, object]) -> None:
    """Last good state, input trace, frame, and every tilemap cell with its coordinates."""
    h = run.h
    (out / "last_good_preoffer.state").write_bytes(preoffer)
    try:
        h.pyboy.screen.image.save(out / "screen.png")
        rows = screen_rows(h)
        tiles = h.read_bytes("wTileMap", 360)
        (out / "tilemap.txt").write_text(
            "\n".join(f"y={y:02d} {rows[y]}  " + " ".join(f"{tiles[y * 20 + x]:02x}" for x in range(20))
                      for y in range(18)) + "\n", encoding="utf-8")
        if run.agent:
            result["last_mode"] = run.agent.mode()
            result["map"] = run.agent.map_name(h.read8("hCurMap"))
            result["position"] = run.agent.position()
            (out / "inputs.json").write_text(json.dumps(run.agent.report.inputs[-200:]) + "\n", encoding="utf-8")
            (out / "events.json").write_text(json.dumps(run.agent.report.events[-200:], default=str) + "\n",
                                             encoding="utf-8")
    except Exception as error:  # a bundle must never hide the result that asked for it
        result["bundle_error"] = str(error)


def run_case(case: Case, rom: str, evidence: Path, branch: str, on_hang=None) -> list[dict[str, object]]:
    try:
        preoffer, interventions = build_preoffer(case, rom, evidence)
    except (NotReached, DriverFault) as error:
        status = "not_reached" if isinstance(error, NotReached) else "driver_fault"
        return [{"case": case.id, "rom": rom, "branch": branch, "status": status, "detail": str(error)}]
    return [run_branch(case, rom, branch, evidence, preoffer, interventions, on_hang=on_hang)]


def _worker(index: int, options: dict[str, object], results) -> None:
    import witch_cases
    case_id, rom, branch = options["jobs_list"][index]
    case = witch_cases.CASES[case_id]

    def on_hang(result: dict[str, object]) -> None:
        # os._exit skips the queue's feeder thread, so flush it first.
        results.put((index, {"rows": [result]}))
        results.close()
        results.join_thread()

    try:
        rows = run_case(case, rom, Path(options["evidence"]), branch, on_hang)
    except BaseException:
        rows = [{"case": case_id, "rom": rom, "branch": branch, "status": "driver_fault",
                 "detail": traceback.format_exc()}]
    results.put((index, {"rows": rows}))


# ------------------------------------------------------------------- campaign

class CampaignAgent(WitchAgent):
    """Unforced play: whenever she is genuinely there, talk and answer by a seeded
    coin. No steering, no fixture. Natural frequencies are recorded, and they never
    stand in for explicit coverage."""

    def __init__(self, harness, *, seed: int, accept_rate: float = 0.75, **options):
        super().__init__(harness, seed=seed, talk=True, answers=(), **options)
        self.witch_rng = random.Random(f"witch/{seed}")
        self.accept_rate = accept_rate
        self.offers: list[dict[str, object]] = []
        self.settlements: list[dict[str, object]] = []
        harness.register_hook("WitchSettlePendingPrize", self._on_settle)

    def _on_settle(self, _context) -> None:
        h = self.h
        self.settlements.append({"frame": h.pyboy.frame_count, "accepted": bool(h.read8("wRogueFlagsBitfield") & ACCEPTED),
                                 "challenge": h.read8("wWitchChallenge"), "prize": h.read8("wWitchPrize"),
                                 "earned": h.read_bytes("wWitchPrizesEarned", 2),
                                 "count": h.read8("wBattleCount"), "depth": h.read8("wEndlessDepth")})

    def on_map_change(self, current_map: int) -> None:
        super().on_map_change(current_map)
        if current_map == self.lobby_map:
            self.witch_pending, self.witch_done, self.witch_talking = True, False, False

    def arrive(self, face, label) -> None:
        if label.startswith("witch:"):
            answer = "yes" if self.witch_rng.random() < self.accept_rate else "no"
            self.answers = ["yes", answer]
            self.offers.append({"frame": self.h.pyboy.frame_count, "answer": answer,
                                "challenge": self.h.read8("wWitchChallenge"), "prize": self.h.read8("wWitchPrize"),
                                "count": self.h.read8("wBattleCount"), "badges": self.h.read8("wObtainedBadges"),
                                "depth": self.h.read8("wEndlessDepth"),
                                "doors": [self.h.read8("wLobbyDoor1StageMap"), self.h.read8("wLobbyDoor2StageMap")]})
        super().arrive(face, label)


def play_endless(h, agent: "CampaignAgent", stages: int, max_frames: int) -> dict[str, object]:
    """After the Hall of Fame: accept the Endless offer, then play `stages` more zones
    with the same unforced witch coin. Returns what Endless added."""
    continues = h.hook_flag("EndlessContinue")

    def accept(_context) -> None:
        agent.answers, agent.witch_talking = ["yes"], True
        agent.witch_talk_frame = h.pyboy.frame_count

    h.register_hook("EndlessOffer", accept)
    end = h.pyboy.frame_count + 60000
    while not continues["count"] and h.pyboy.frame_count < end:
        agent.step()
        if h.hook_errors:
            raise RuntimeError("a hook callback raised:\n" + h.hook_errors[0])
    if not continues["count"]:
        return {"continued": False, "stages": 0, "detail": "the Endless offer never continued",
                "map": agent.map_name(h.read8("hCurMap")), "mode": agent.mode(),
                "last_menu": agent.last_menu_caller, "events": [str(e)[:160] for e in agent.report.events[-6:]]}
    offers_before, settled_before = len(agent.offers), len(agent.settlements)
    stages_before = agent.report.stages_cleared
    agent.run(runs=2, stages=stages_before + stages, max_frames=max_frames)
    return {"continued": True, "stages": agent.report.stages_cleared - stages_before,
            "depth": h.read8("wEndlessDepth"), "offers": len(agent.offers) - offers_before,
            "settled": sum(1 for s in agent.settlements[settled_before:] if s["accepted"]),
            "outcome": agent.report.outcome, "detail": agent.report.detail}


def run_campaign_seed(seed: int, options: dict[str, object]) -> dict[str, object]:
    rom = options["rom"]
    autoplay.ROM = rom
    evidence = Path(options["evidence"])
    h = harness(rom, evidence)
    started = time.monotonic()
    try:
        if rom == autoplay.DEBUG_ROM:
            autoplay.boot(h, seed, 1, options["difficulty"])
        else:
            autoplay.boot_new_game(h, seed, options["difficulty"])
        if options["endless_stages"]:
            # Endless is offered only to a player who has beaten the AI once; the event
            # outlives every run reset, so a returning player's save has it already.
            h.set_event(EVENTS["EVENT_AI_DEFEATED"])
        chooser = {"player": "strong"} if options["strong"] else {"offer_policy": "random"}
        agent = CampaignAgent(h, seed=seed, stall_frames=options["stall_frames"], battle_policy="type_switcher",
                              **chooser)
        error = None
        endless = {"continued": False, "stages": 0}
        try:
            agent.run(runs=1, stages=options["stages"], max_frames=options["max_frames"])
            if options["endless_stages"] and agent.report.outcome == "champion":
                endless = play_endless(h, agent, options["endless_stages"], options["max_frames"])
        except Exception:
            error = traceback.format_exc()
        report = agent.report
        row = {"rom": rom, "rom_sha8": rom_tag(rom), "seed": seed, "outcome": report.outcome, "detail": report.detail,
               "stages": report.stages_cleared, "battles_won": report.battles_won, "frames": report.frames,
               "wall_seconds": round(time.monotonic() - started, 1), "offers": agent.offers,
               "settlements": [s for s in agent.settlements if s["accepted"]], "endless": endless,
               "anomalies": agent.checks.anomalies[:30], "error": error,
               "replay": f"witch_autoplay.py campaign --evidence {evidence} --rom {rom} --seeds {seed} "
                         f"--stages {options['stages']} --max-frames {options['max_frames']} "
                         f"--stall-frames {options['stall_frames']} --difficulty {options['difficulty']}"}
        if report.failed or error or agent.checks.anomalies:
            image, state = h.write_failure_artifacts(f"witch_campaign_{rom}_{seed}")
            row["artifacts"] = {"image": str(image), "state": str(state)}
            row["inputs_tail"] = report.inputs[-200:]
        return row
    finally:
        h.close()


def _campaign_worker(seed: int, options: dict[str, object], results) -> None:
    try:
        row = run_campaign_seed(seed, options)
    except BaseException:
        row = {"rom": options["rom"], "seed": seed, "outcome": "error", "detail": traceback.format_exc()}
    results.put((seed, row))


def run_campaign(args) -> int:
    import coverage_inventory
    import run_autoplay
    failed = 0
    for rom in args.rom or list(ROMS):
        coverage_inventory.code_labels(rom)
        options = {"rom": rom, "evidence": str(args.evidence), "stages": args.stages, "max_frames": args.max_frames,
                   "stall_frames": args.stall_frames, "strong": args.strong, "difficulty": args.difficulty,
                   "endless_stages": args.endless_stages}
        out = args.evidence / "campaign" / rom
        out.mkdir(parents=True, exist_ok=True)

        def timed_out(seed, timeout, _options, rom=rom):
            return {"rom": rom, "seed": seed, "outcome": "hung", "detail": f"killed after {timeout}s"}

        for row in run_autoplay.run_all(run_autoplay.parse_seeds(args.seeds), options, max(1, args.jobs),
                                        args.timeout, worker=_campaign_worker, timeout_row=timed_out):
            (out / f"seed_{row['seed']}.json").write_text(json.dumps(row, indent=1, default=str) + "\n", encoding="utf-8")
            bad = row["outcome"] in autoplay.FAILURES or row.get("anomalies") or row.get("error")
            failed += bool(bad)
            print(f"{'FAIL' if bad else 'ok  '} {rom:15} seed {row['seed']:>3} {row['outcome']:<11} "
                  f"stages={row.get('stages')} won={row.get('battles_won')} frames={row.get('frames')} "
                  f"offers={len(row.get('offers', []))} accepted_settled={len(row.get('settlements', []))} "
                  f"endless={row.get('endless', {}).get('stages', 0)}/{row.get('endless', {}).get('offers', 0)}/"
                  f"{row.get('endless', {}).get('settled', 0)} "
                  f"anomalies={len(row.get('anomalies', []))} {row.get('detail', '')[:90]}", flush=True)
    return 1 if failed else 0


def write_manifest(evidence: Path) -> dict[str, object]:
    """Rebuild the per-ROM report from every result on disk."""
    rows = [json.loads(p.read_text(encoding="utf-8")) for p in sorted((evidence / "results").rglob("result.json"))]
    table: dict[str, dict[str, dict[str, str]]] = {}
    for row in rows:
        table.setdefault(row["rom"], {}).setdefault(row["case"], {})[row["branch"]] = row["status"]
    manifest = {"snapshot": evidence.name, "rom_hashes": {r: rom_tag(r) for r in ROMS},
                "testcode": (ROOT / "TESTCODE_HASH").read_text().strip() if (ROOT / "TESTCODE_HASH").is_file() else "live",
                "table": table}
    (evidence / "manifest.json").write_text(json.dumps(manifest, indent=1) + "\n", encoding="utf-8")
    return manifest


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("command", choices=("fixtures", "run", "campaign", "list", "report"))
    parser.add_argument("--seeds", default="1-8", help="campaign: e.g. 1-8 or 3,9")
    parser.add_argument("--stages", type=int, default=1000, help="campaign: stop after this many stages")
    parser.add_argument("--max-frames", type=int, default=1_000_000)
    parser.add_argument("--stall-frames", type=int, default=20_000)
    parser.add_argument("--strong", action="store_true",
                        help="campaign: rewards on merit and matchup switches; release seeds need it to survive")
    parser.add_argument("--difficulty", default="HARD", choices=("VERY_EASY", "EASY", "NORMAL", "HARD", "VERY_HARD"),
                        help="campaign: the LEVELS setting")
    parser.add_argument("--endless-stages", type=int, default=0,
                        help="campaign: after a Hall of Fame win, accept Endless and play this many more stages")
    parser.add_argument("--evidence", type=Path)
    parser.add_argument("--rom", action="append", choices=ROMS)
    parser.add_argument("--case", action="append")
    parser.add_argument("--branch", action="append")
    parser.add_argument("--jobs", type=int, default=os.cpu_count() or 1)
    parser.add_argument("--timeout", type=float, default=1800)
    parser.add_argument("--seed", type=int, default=1, help="fixtures: the new-game seed")
    args = parser.parse_args(argv)
    import witch_cases
    if args.command == "list":
        for case in witch_cases.CASES.values():
            print(f"{case.id:8} {case.title}")
        return 0
    if args.evidence is None:
        parser.error("--evidence is required")
    args.evidence.mkdir(parents=True, exist_ok=True)
    roms = args.rom or list(ROMS)
    if args.command == "report":
        print(json.dumps(write_manifest(args.evidence), indent=1))
        return 0
    if args.command == "campaign":
        return run_campaign(args)
    if args.command == "fixtures":
        import coverage_inventory
        code = 0
        for rom in roms:
            coverage_inventory.code_labels(rom)
            try:
                print(json.dumps(make_fixture(rom, args.evidence, args.seed)), flush=True)
            except Exception as error:
                print(f"{rom}: FIXTURE FAILED {error}", flush=True)
                code = 1
        return code
    ids = args.case or list(witch_cases.MATRIX)
    # One process per branch, so a hang in one cannot cost the other its result.
    jobs_list = [(case_id, rom, branch) for rom in roms for case_id in ids
                 for branch in (args.branch or ["accept", "decline"])]
    missing = [r for r in roms if not fixture_path(args.evidence, r).is_file()]
    if missing:
        parser.error(f"no fixture for {missing}: run the fixtures command first")
    import run_autoplay

    def timed_out(index, timeout, _options):
        case_id, rom, branch = jobs_list[index]
        return {"rows": [{"case": case_id, "rom": rom, "branch": branch, "status": "driver_fault",
                          "detail": f"killed after {timeout}s without a hang report"}]}

    options = {"jobs_list": jobs_list, "evidence": str(args.evidence)}
    failed = 0
    for row in run_autoplay.run_all(list(range(len(jobs_list))), options, max(1, args.jobs), args.timeout,
                                    worker=_worker, timeout_row=timed_out):
        for result in row["rows"]:
            bad = [c["name"] for c in result.get("checks", []) if not c["ok"]]
            print(f"{result['status']:13} {result['rom']:15} {result['case']:8} {result['branch']:8} "
                  f"{result.get('frames', 0):>8}f {result.get('wall_seconds', 0):>6}s "
                  f"{result.get('detail', '')[:120]} {bad if bad else ''}", flush=True)
            failed += result["status"] != "pass"
    write_manifest(args.evidence)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
