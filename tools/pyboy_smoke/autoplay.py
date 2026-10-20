"""Autoplay agent: plays Red Rogue runs through joypad input, for soak testing.

The agent reads game state from RAM through pokeblue_debug.sym and decides
every input itself. It writes no game state except the menu-cursor bytes the
AI benchmark already steers (battle menu, move menu, party menu, the reward and
gift pickers): those choose WHICH option the next A press confirms, the same
as moving the cursor there first.

Each `step()` looks at the current mode and does one thing:

- overworld: walk one step of a BFS path (autoplay_world.py) toward the first
             reachable goal group: heal at the lobby nurse, enter a lobby door,
             fight the map's unbeaten trainers, talk once to leaders, bosses
             and gift givers, then leave through the room's forward exit;
- battle / dialogue: answer the game while it polls for a button. Moves and
             switches come from a benchmark_policies policy at the menu hooks;
- busy:      the game is animating or driving the d-pad itself: wait.

A run ends `completed` (the requested number of stages), `champion` (the Hall
of Fame), `blackout` (the party fainted: a legitimate loss), or as a failure:
`stalled` (no game progress for --stall-frames, a softlock suspect),
`crashed` (autoplay_checks caught a crash), `frame_limit`, or `error`.
Failures write a screenshot and state dump. autoplay_checks also reports
invalid game data it finds along the way as `anomaly` events.

Runs are deterministic for a given ROM and seed. The seed is applied just
before the lobby rolls its first doors, so it decides the whole run: rerun the
same seed to reproduce a report.

    python3 tools/pyboy_smoke/autoplay.py --seed 7 --stages 40
    python3 tools/pyboy_smoke/run_autoplay.py --seeds 1-16   # make autoplay
"""
from __future__ import annotations

import argparse
import json
import os
import random
import sys
import time
import traceback
from dataclasses import dataclass, field, replace
from pathlib import Path

import autoplay_checks
import autoplay_world as world
import benchmark_policies
from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"

# crashed: autoplay_checks caught a crash; hung: the emulator stopped returning
# (run_autoplay.py's per-seed timeout, an illegal opcode).
FAILURES = ("stalled", "frame_limit", "error", "crashed", "hung")
HEARTBEAT_STEPS = 1000

PARTYMON_STRUCT_LENGTH = 0x2C
MON_HP, MON_MAXHP = 0x01, 0x22  # party_struct offsets
SPRITE_SLOTS = 16
FOLLOWER_SLOT = 15  # the Pokemon follower walks behind the player and never blocks
TRAINER_HEADER_LENGTH = 12  # the `trainer` macro
WARP_NO_RETURN = 0xFD
ROGUE_MAP = 0xFE
LAST_MAP = 0xFF
LOBBY_NURSE_SLOT = 1  # first object_event in IndigoPlateauLobby
LOBBY_CLERK_SLOT = 2  # the clerk selling recovery items
STOCK_HEALS = 4  # buy HP-healing items up to this many
PRICED_ITEM_LIST_MENU = 3  # PRICEDITEMLISTMENU, the mart's buy list
NUDGE_FRAMES = 300  # with nothing polling for this long, press A anyway
EXPLORE_AFTER_FRAMES = 3000  # without progress this long, talk to everyone first
INPUT_LOG_LENGTH = 200

# Between runs the game leaves the player in the Silph Co hub (the dorm after a
# loss or the Hall of Fame). The next run starts through VR's warp to Oak's Lab.
HUB_ROUTE = {
    "SILPH_CO_DORM": "SILPH_CO_B1F",
    "SILPH_CO_1F": "SILPH_CO_B1F",
    "SILPH_CO_B1F": "SILPH_CO_VR",
    "SILPH_CO_VR": "OAKS_LAB",
}

# Healing outside battle (Potions cannot be used in one): HP each restores.
HEAL_AMOUNTS = {"POTION": 20, "SUPER_POTION": 50, "HYPER_POTION": 200,
                "MAX_POTION": 999, "FULL_RESTORE": 999}
REVIVES = ("REVIVE", "MAX_REVIVE")
HEAL_BELOW = 0.5  # heal a mon below this fraction of its max HP
START_MENU_ITEM = 2  # POKEDEX, POKEMON, ITEM, ...
PLAN_STEP_LIMIT = 80  # menu presses before a plan is abandoned

# Menu routine -> event kind. Each has a .menuLoop local label ahead of its
# HandleMenuInput, lists its offers at 0..wMaxMenuItem-1 and NO THANKS at
# wMaxMenuItem.
CHOICE_MENUS = {"RogueRewardMenu": "reward", "BridgeGiftMenu": "gift"}


@dataclass
class Goal:
    """Steps to reach, each with the direction to face on arrival and a label
    ("trainer:3", "warp_exit", ...). Warp goals may sit on impassable tiles."""
    spots: dict[tuple[int, int], tuple[str | None, str]]
    warp: bool = False


@dataclass
class RunReport:
    seed: int
    outcome: str = "running"
    detail: str = ""
    frames: int = 0
    steps: int = 0
    stages_cleared: int = 0
    battles_won: int = 0
    blackouts: int = 0
    runs: list[dict[str, object]] = field(default_factory=list)  # one per finished run
    events: list[dict[str, object]] = field(default_factory=list)
    inputs: list[tuple[int, str, int]] = field(default_factory=list)  # (frame, button, held)

    @property
    def failed(self) -> bool:
        return self.outcome in FAILURES

    def to_json(self) -> dict[str, object]:
        return {
            "seed": self.seed,
            "outcome": self.outcome,
            "detail": self.detail,
            "frames": self.frames,
            "steps": self.steps,
            "stages_cleared": self.stages_cleared,
            "battles_won": self.battles_won,
            "blackouts": self.blackouts,
            "runs": self.runs,
            "events": self.events,
            "last_inputs": self.inputs[-INPUT_LOG_LENGTH:],
        }


class AutoplayAgent:
    def __init__(
        self,
        harness: RedRogueHarness,
        *,
        seed: int,
        battle_policy: str = "type_switcher",
        door_policy: str = "random",
        offer_policy: str = "random",
        stall_frames: int = 20_000,
        log=None,
        heartbeat: Path | None = None,
    ):
        if battle_policy not in benchmark_policies.POLICIES:
            raise ValueError(f"unknown battle policy {battle_policy!r}")
        self.h = harness
        self.mem = harness.pyboy.memory
        self.rng = random.Random(seed)
        self.battle_policy = battle_policy
        self.door_policy = door_policy
        self.offer_policy = offer_policy
        self.stall_frames = stall_frames
        self.log = log or (lambda message: None)
        self.heartbeat = heartbeat
        self.report = RunReport(seed=seed)

        self.rules = benchmark_policies.load_rules(ROOT)
        maps = parse_map_constants(ROOT / "constants/map_constants.asm")
        self.map_names = {value: name for name, value in maps.items()}
        self.lobby_map = maps["INDIGO_PLATEAU_LOBBY"]
        self.hall_of_fame = maps["HALL_OF_FAME"]
        self.dorm = maps["SILPH_CO_DORM"]
        self.reward_room = maps["REWARD_ROOM"]
        self.hub_route = {maps[here]: maps[there] for here, there in HUB_ROUTE.items()}
        sprites = parse_rgbds_constants(ROOT / "constants/sprite_constants.asm")
        self.sprite_nurse = sprites["SPRITE_NURSE"]
        self.sprite_poke_ball = sprites["SPRITE_POKE_BALL"]
        self.sprite_clerk = sprites["SPRITE_CLERK"]
        self.trainer_names = {value: name for name, value in parse_trainer_constants(
            ROOT / "constants/trainer_constants.asm").items()}
        self.species_names = {value: name for name, value in parse_rgbds_constants(
            ROOT / "constants/pokemon_constants.asm").items()}
        self.opp_id_offset = parse_rgbds_constants(
            ROOT / "constants/trainer_constants.asm")["OPP_ID_OFFSET"]
        items = parse_rgbds_constants(ROOT / "constants/item_constants.asm")
        self.heal_amounts = {items[name]: amount for name, amount in HEAL_AMOUNTS.items()}
        self.revives = {items[name] for name in REVIVES}
        bank, address = self.h.symbols.get("RecoveryItemTable")
        self.recovery_table = self._terminated(bank, address)  # wRecoveryItemCounts order
        self.body_armor = parse_rgbds_constants(
            ROOT / "constants/pokemon_data_constants.asm")["BRIDGE_SELECTED_EFFECT_BODY_ARMOR"]
        self.body_armor_allowed = {self.rules.effect(name) for name in
                                   ("SPECIAL_DAMAGE_EFFECT", "SUPER_FANG_EFFECT", "BIDE_EFFECT")}
        self.pair_collisions = self._read_pair_collisions()
        self.ledges = self._read_ledges()
        self.bridge_rooms = self._read_bridge_rooms()

        # Written by hooks.
        self.last_overworld_frame = -1  # JoypadOverworld polled
        self.last_ui_frame = -1  # the text engine or a menu started
        self.last_wait_frame = -1  # JoypadLowSensitivity polled: a button is wanted
        self.last_menu_caller = ""
        self.naming_screen = False
        self.naming_letters = 0
        self.quantity_waiting = False
        self.party_menu_waiting = False
        self.party_menu_action = "b"
        self.switch_target: int | None = None
        self.switched_last_turn = False
        self.choice_showings: dict[str, int] = {}
        self.choice_pending: str | None = None
        self.hidden: dict[int, bool] = {}  # sprite slot -> IsObjectHidden's answer
        self.trainer_headers: tuple[int, int] | None = None  # (map, address)
        self.arrow_table: tuple[int, ...] | None = None  # (map, bank, address, x0, y0)
        self._arrows: tuple[tuple | None, dict] = (None, {})
        self.warping = False
        self.arrival: tuple[int, int] | None = None  # warp-in step on this map
        self.arrival_map: int | None = None

        # Agent state.
        self.last_press_frame = -1
        self.busy_since: int | None = None
        self.current_map: int | None = None
        self.stage_map: int | None = None  # set from entering a stage until the lobby
        self.last_stage: int | None = None
        self.warps_taken: set[tuple[int, int, int]] = set()  # (map, x, y) since the lobby
        self.talked: set[int] = set()  # talk-once sprite slots, this visit
        self.blocked_steps: dict[tuple[int, int], int] = {}  # failed step attempts
        self.script_steps: dict[tuple[int, int], int] = {}  # steps that set off a script
        self.door_choice: int | None = None
        self.healed_this_visit = False
        self.shopped_this_visit = False
        self.in_battle = 0
        self.pending_loss = False  # a blackout, until it sends the player to the dorm
        self.last_opponent: str | None = None
        self.run_start = {"frame": 0, "stages": 0, "battles_won": 0}
        self.plan: dict[str, object] | None = None  # a menu errand in progress
        self.last_no_path = None
        self.last_progress_frame = 0
        self.progress_marker: tuple = ()
        self._install_hooks()
        self.checks = autoplay_checks.GameChecks(self, ROOT)

    # ------------------------------------------------------------------ hooks

    def _install_hooks(self) -> None:
        h = self.h
        h.register_hook("JoypadOverworld", self._on_overworld)
        h.register_hook("JoypadLowSensitivity", self._on_wait)
        h.register_hook("TextCommandProcessor", self._on_text)
        h.register_hook("HandleMenuInput", self._on_menu)
        h.register_hook("DisplayNamingScreen", self._on_naming_screen)
        h.register_hook("DisplayNamingScreen.submitNickname",
                        lambda _c: setattr(self, "naming_screen", False))
        h.register_hook("DisplayBattleMenu", self._on_battle_menu)
        h.register_hook("MoveSelectionMenu", self._on_move_menu)
        h.register_hook("PartyMenuInit", self._on_party_menu)
        h.register_hook("DisplayChooseQuantityMenu", lambda _c: setattr(self, "quantity_waiting", True))
        h.register_hook("HandlePartyMenuInput", lambda _c: setattr(self, "party_menu_waiting", True))
        for entry, kind in CHOICE_MENUS.items():
            h.register_hook(entry, lambda _c, kind=kind: self._on_choice_menu(kind))
            h.register_hook(f"{entry}.menuLoop", self._on_choice_menu_loop)
        h.register_hook("TrainerBattleVictory", self._on_victory)
        h.register_hook("HandlePlayerBlackOut", self._on_blackout)
        h.register_hook("IsObjectHidden.hidden", self._on_hidden)
        h.register_hook("ExecuteCurMapScriptInTable", self._on_map_script)
        h.register_hook("DecodeArrowMovementRLE", self._on_arrow_table)
        h.register_hook("WarpFound2", self._on_warp)
        self._hook_after_call("EnterMap", "LoadMapData", self._on_enter_map)

    def _hook_after_call(self, routine: str, callee: str, callback) -> None:
        """Hook the instruction after `call callee` inside routine, a point
        with no label of its own, found by scanning routine's code."""
        bank, start = self.h.symbols.get(routine)
        callee_bank, callee_address = self.h.symbols.get(callee)
        if callee_bank:
            raise ValueError(f"{callee} is not in ROM0, so `call` cannot reach it")
        call = bytes([0xCD, callee_address & 0xFF, callee_address >> 8])
        code = bytes(self._rom(bank, start + i) for i in range(64))
        offset = code.find(call)
        if offset < 0:
            raise ValueError(f"no `call {callee}` in the first 64 bytes of {routine}")
        address = start + offset + len(call)
        self.h.pyboy.hook_register(bank, address, callback, None)
        self.h._registered_hooks.append((bank, address))  # so close() deregisters it

    def _on_overworld(self, _context) -> None:
        self.last_overworld_frame = self.h.pyboy.frame_count

    def _on_wait(self, _context) -> None:
        self.last_wait_frame = self.h.pyboy.frame_count

    def _on_text(self, _context) -> None:
        self.last_ui_frame = self.h.pyboy.frame_count

    def _on_menu(self, _context) -> None:
        self.last_ui_frame = self.h.pyboy.frame_count
        sp = self.h.pyboy.register_file.SP
        ret = self.mem[sp] | self.mem[sp + 1] << 8
        bank = 0 if ret < 0x4000 else self.h.read8("hLoadedROMBank")
        self.last_menu_caller = self.h.symbols.nearest(bank, ret) or f"{bank:02x}:{ret:04x}"

    def _on_naming_screen(self, _context) -> None:
        self.naming_screen = True
        self.naming_letters = 0

    def _on_battle_menu(self, _context) -> None:
        target = None
        if self.battle_policy in benchmark_policies.SWITCHING_POLICIES:
            target = benchmark_policies.choose_switch(
                self.rules, benchmark_policies.read_state(self.h),
                self.battle_policy, self.switched_last_turn)
        self.switched_last_turn = target is not None
        self.switch_target = target
        # FIGHT, or PKMN when the policy wants to switch.
        self.h.write8("wBattleAndStartSavedMenuItem", 0 if target is None else 2)

    def _on_move_menu(self, _context) -> None:
        # Open the move menu with the cursor on the policy's move, as
        # run_ai_benchmark.py does.
        state = benchmark_policies.read_state(self.h)
        # The policies only rule out moves without PP. A move the game refuses
        # bounces back to this menu, which would choose it again: so a refused
        # move is given no PP here. Refused are a Disabled move, and under Body
        # Armor (a bridge gift) every move without base power but the fixed-
        # damage ones (BridgeBodyArmorBlocksSelectedMove).
        pp = list(state.player.pp)
        disabled = (self.h.read8("wPlayerDisabledMove") >> 4) - 1  # high nibble: slot + 1
        if 0 <= disabled < 4:
            pp[disabled] = 0
        if self.has_body_armor():
            for slot, move in enumerate(state.player.moves):
                rule = self.rules.moves.get(move)
                if rule and not rule.power and rule.effect not in self.body_armor_allowed:
                    pp[slot] = 0
        if pp != list(state.player.pp):
            state.player = replace(state.player, pp=tuple(pp))
        if self.battle_policy == "first_slot":
            legal = benchmark_policies.legal_slots(state.player)
            slot = legal[0] if legal else 0
        else:
            policy = "type_aware" if self.battle_policy == "best_power" else self.battle_policy
            slot = benchmark_policies.choose_slot(self.rules, state, policy)
        self.h.write8("wPlayerMoveListIndex", slot)

    def has_body_armor(self) -> bool:
        owner = self.h.read8("wPlayerMonNumber") + 1  # owners are party slot + 1
        records = self.h.read_bytes("wBridgeSelectedEffects", 4)
        return any(records[i] == owner and records[i + 1] == self.body_armor
                   for i in range(0, len(records), 2))

    def _on_party_menu(self, _context) -> None:
        if not self.h.read8("hIsInBattle"):
            # Only reached through an interaction the agent chose: the heal
            # plan's target, else (a gift that teaches a move, a trade offer)
            # the lead.
            target = self.plan["slot"] if self.plan else 0
            self.h.write8("wPartyAndBillsPCSavedMenuItem", target)
            self.party_menu_action = "a"
            return
        forced = bool(self.h.read8("wForcePlayerToChooseMon"))
        current = self.h.read8("wPlayerMonNumber")
        alive = [slot for slot, (hp, _) in enumerate(self.party_hp()) if hp and slot != current]
        fainted = not (self.h.read8("wBattleMonHP") or self.h.read8("wBattleMonHP", 1))
        if not forced and self.switch_target is not None:
            self.h.write8("wPartyAndBillsPCSavedMenuItem", self.switch_target)
            self.switch_target = None
            self.party_menu_action = "a"
        elif alive and (forced or fainted):
            self.h.write8("wPartyAndBillsPCSavedMenuItem", alive[0])
            self.party_menu_action = "a"
        else:
            # The optional "switch after a KO" prompt: keep the current mon.
            self.party_menu_action = "b"

    def _on_choice_menu(self, kind: str) -> None:
        self.choice_showings[kind] = self.choice_showings.get(kind, 0) + 1
        self.choice_pending = kind

    def _on_choice_menu_loop(self, _context) -> None:
        """Place the cursor once per showing, before HandleMenuInput draws it.

        The menus reopen when an offer cannot be taken (party and box full, a
        declined trade), so take an offer on the first showing and NO THANKS
        after that."""
        kind, self.choice_pending = self.choice_pending, None
        if kind is None:
            return
        no_thanks = self.h.read8("wMaxMenuItem")
        showing = self.choice_showings[kind]
        if showing > 1 or no_thanks == 0:
            choice = no_thanks
        elif self.offer_policy == "random":
            choice = self.rng.randrange(no_thanks)
        else:
            choice = 0
        self.h.write8("hCurrentMenuItem", choice)
        self.event(kind, choice=choice, offers=no_thanks, showing=showing)

    def _on_victory(self, _context) -> None:
        self.report.battles_won += 1
        self.event("battle_won", opponent=self.last_opponent)

    def _on_blackout(self, _context) -> None:
        # Not necessarily the end of the run: losing to the rival in Oak's Lab
        # goes through here too and play goes on. The run is lost when the
        # blackout sends the player to the dorm (on_map_change).
        self.report.blackouts += 1
        self.pending_loss = True
        self.event("blackout", map=self.map_name(self.h.read8("hCurMap")))

    def _on_hidden(self, _context) -> None:
        # IsObjectHidden's own answer for the sprite it just checked: rogue
        # stage maps special-case several slots, so it is not reimplemented.
        slot = self.h.read8("hCurrentSpriteOffset") >> 4
        self.hidden[slot] = bool(self.h.pyboy.register_file.A)

    def _on_map_script(self, _context) -> None:
        # Map scripts with trainers pass their whole header table in hl.
        # wTrainerHeaderPtr is no substitute: TalkToTrainer repoints it at the
        # one header being fought, so reading it later starts mid-table.
        self.trainer_headers = (self.h.read8("hCurMap"), self.h.pyboy.register_file.HL)

    def _on_arrow_table(self, _context) -> None:
        # Map scripts pass their arrow-tile table in hl every frame, with the
        # player's step in b (y) and c (x). Keep the first per map: the routine
        # recurses through the table's entries. The facility's spinner pieces
        # pass the step relative to the piece, so remember that offset too.
        current = self.h.read8("hCurMap")
        if self.arrow_table is None or self.arrow_table[0] != current:
            registers = self.h.pyboy.register_file
            x, y = self.position()
            self.arrow_table = (current, self.h.read8("hLoadedROMBank"), registers.HL,
                                (x - registers.C) & 0xFF, (y - registers.B) & 0xFF)

    def _on_warp(self, _context) -> None:
        # Still on the old map, standing on the warp being taken.
        self.warping = True
        self.warps_taken.add((self.h.read8("hCurMap"), *self.position()))

    def _on_enter_map(self, _context) -> None:
        # Right after LoadMapData: the warp-in step, before a scripted walk-in
        # moves the player (the E4 rooms walk the player well away from their
        # entrance). EnterMap also reloads the map after each battle; only a
        # warp counts.
        if self.warping:
            self.warping = False
            self.arrival = self.position()
            self.arrival_map = self.h.read8("hCurMap")

    # ------------------------------------------------------------- reporting

    def event(self, kind: str, **data) -> None:
        entry = {"frame": self.h.pyboy.frame_count, "kind": kind, **data}
        self.report.events.append(entry)
        self.log(json.dumps(entry))

    def map_name(self, map_id: int) -> str:
        return self.map_names.get(map_id, f"${map_id:02x}")

    # ------------------------------------------------------------------ reads

    def _rom(self, bank: int, address: int) -> int:
        return self.mem[bank, address] if address >= 0x4000 else self.mem[address]

    def _terminated(self, bank: int, address: int) -> list[int]:
        """Bytes up to a $FF terminator."""
        values = []
        while (value := self._rom(bank, address)) != 0xFF:
            values.append(value)
            address += 1
        return values

    def _read_pair_collisions(self) -> list[tuple[int, int, int]]:
        raw = self._terminated(*self.h.symbols.get("TilePairCollisionsLand"))
        return [tuple(raw[i:i + 3]) for i in range(0, len(raw) - 2, 3)]

    def _read_ledges(self) -> list[world.Ledge]:
        raw = self._terminated(*self.h.symbols.get("LedgeTiles"))
        return [world.Ledge(raw[i], raw[i + 1], raw[i + 2]) for i in range(0, len(raw) - 3, 4)]

    def _read_bridge_rooms(self) -> set[int]:
        bank, address = self.h.symbols.get("BridgeRoomMaps")
        count = parse_rgbds_constants(
            ROOT / "custom_functions/bridge_selection.asm")["NUM_BRIDGE_ROOMS"]
        return {self.mem[bank, address + i] for i in range(count)}

    def word(self, label: str) -> int:
        return self.h.read8(label) | self.h.read8(label, 1) << 8

    def position(self) -> tuple[int, int]:
        return self.h.read8("wXCoord"), self.h.read8("wYCoord")

    def map_size(self) -> tuple[int, int]:
        """In steps."""
        return self.h.read8("wCurMapWidth") * 2, self.h.read8("wCurMapHeight") * 2

    def party_hp(self) -> list[tuple[int, int]]:
        base = self.h.address("wPartyMons")
        result = []
        for slot in range(self.h.read8("wPartyCount")):
            mon = base + slot * PARTYMON_STRUCT_LENGTH
            hp = self.mem[mon + MON_HP] << 8 | self.mem[mon + MON_HP + 1]
            max_hp = self.mem[mon + MON_MAXHP] << 8 | self.mem[mon + MON_MAXHP + 1]
            result.append((hp, max_hp))
        return result

    def read_grid(self) -> world.WalkGrid:
        width, height = self.h.read8("wCurMapWidth"), self.h.read8("wCurMapHeight")
        bank = self.h.read8("wTilesetBank")
        blocks = self.word("wTilesetBlocksPtr")
        overworld = self.h.read_bytes("wOverworldMap", (width + 6) * (height + 6))
        blockset = [self._rom(bank, blocks + i) for i in range((max(overworld) + 1) * 16)]
        return world.grid_from_blocks(
            width, height, overworld, blockset,
            self._terminated(0, self.word("wTilesetCollisionPtr")),
            tileset=self.h.read8("wCurMapTileset"),
            pair_collisions=self.pair_collisions,
            ledges=self.ledges,
            teleports=self.arrow_tiles() | self.warp_pads(),
        )

    def arrow_tiles(self) -> dict[tuple[int, int], tuple[int, int]]:
        """{arrow step: where its forced movement ends}: Viridian Gym, Rocket
        Hideout, and the facility's spinner pieces (tables relative to the piece)."""
        if self.arrow_table is None or self.arrow_table[0] != self.h.read8("hCurMap"):
            return {}
        if self._arrows[0] == self.arrow_table:
            return self._arrows[1]
        _, bank, address, x0, y0 = self.arrow_table
        result = {}
        # Entries: y, x, movement pointer. Movements: (PAD_* bit, count) pairs.
        while self._rom(bank, address) != 0xFF and len(result) < 64:
            y = (self._rom(bank, address) + y0) & 0xFF
            x = (self._rom(bank, address + 1) + x0) & 0xFF
            movement = self._rom(bank, address + 2) | self._rom(bank, address + 3) << 8
            moves = []
            while self._rom(bank, movement) != 0xFF and len(moves) < 16:
                moves.append((self._rom(bank, movement), self._rom(bank, movement + 1)))
                movement += 2
            result[(x, y)] = world.arrow_destination((x, y), moves)
            address += 4
        self._arrows = (self.arrow_table, result)
        return result

    def warp_pads(self) -> dict[tuple[int, int], tuple[int, int]]:
        """Warps into the current map itself (Saffron Gym, facility pads):
        stepping on one lands on the warp its warp ID names."""
        current = self.h.read8("hCurMap")
        warps = self.h.warp_entries()
        return {
            (x, y): (warps[warp_id][1], warps[warp_id][0])
            for y, x, warp_id, dest in warps
            if dest == current and warp_id < len(warps)
        }

    def sprites(self) -> dict[int, dict[str, int]]:
        """Visible map sprites by slot, the player and follower excluded."""
        data1 = self.h.address("wSpriteStateData1")
        data2 = self.h.address("wSpriteStateData2")
        width, height = self.map_size()
        result = {}
        for slot in range(1, SPRITE_SLOTS):
            picture = self.mem[data1 + slot * 16]
            if slot == FOLLOWER_SLOT or not picture or self.hidden.get(slot, False):
                continue
            y = self.mem[data2 + slot * 16 + 4] - 4
            x = self.mem[data2 + slot * 16 + 5] - 4
            if 0 <= x < width and 0 <= y < height:
                result[slot] = {"x": x, "y": y, "picture": picture}
        return result

    def trainer_header_slots(self) -> dict[int, bool]:
        """{sprite slot: beaten} from this map's trainer header table."""
        if self.trainer_headers is None or self.trainer_headers[0] != self.h.read8("hCurMap"):
            return {}
        pointer = self.trainer_headers[1]
        if not 0x4000 <= pointer < 0x8000:
            return {}
        table_bank, table = self.h.symbols.get("MapHeaderBanks")
        bank = self.mem[table_bank, table + self.h.read8("hCurMap")]
        result = {}
        for _ in range(SPRITE_SLOTS):
            slot = self.mem[bank, pointer]  # the header's flag bit is its sprite slot
            if slot == 0xFF:
                break
            flags = self.mem[bank, pointer + 2] | self.mem[bank, pointer + 3] << 8
            result[slot] = bool(self.mem[flags + slot // 8] >> (slot % 8) & 1)
            pointer += TRAINER_HEADER_LENGTH
        return result

    def unbeaten_trainers(self) -> list[int]:
        return [slot for slot, beaten in self.trainer_header_slots().items() if not beaten]

    def special_trainers(self) -> list[int]:
        """Visible sprites with a trainer class and party but no trainer
        header: gym leaders and stage bosses, fought by talking to them."""
        headers = self.trainer_header_slots()
        result = []
        for slot in self.sprites():
            trainer_class, party = self.h.read_bytes("wMapSpriteExtraData", 2, 2 * (slot - 1))
            if trainer_class >= self.opp_id_offset and party and slot not in headers:
                result.append(slot)
        return result

    def counter_tiles(self) -> set[int]:
        return {tile for tile in self.h.read_bytes("wTilesetTalkingOverTiles", 3) if tile != 0xFF}

    # ------------------------------------------------------------------ input

    def press(self, button: str, hold: int = 2, after: int = 6) -> None:
        self.last_press_frame = self.h.pyboy.frame_count
        self.report.inputs.append((self.h.pyboy.frame_count, button, hold))
        self.h.pyboy.button_press(button)
        self.h.tick(hold)
        self.h.pyboy.button_release(button)
        self.h.tick(after)

    def walk(self, direction: str, *, into_warp: bool = False) -> bool:
        """Take one step. Returns whether the player moved (or left the map).

        into_warp keeps the direction held until the step lands: a door warp
        fires only while the direction is still held as the step completes
        (see RedRogueHarness.enter_stage_door1). It releases as soon as the
        step lands, though: holding on starts the next step, which walks
        straight across an edge warp (a doormat that needs DOWN)."""
        before = self.position()
        start_map = self.h.read8("hCurMap")
        frame = self.h.pyboy.frame_count
        self.h.pyboy.button_press(direction)
        moved = False
        dx, dy = world.DIRECTIONS[direction]
        target = (before[0] + dx, before[1] + dy)
        for _ in range(64):
            self.h.tick()
            if self.h.read8("hCurMap") != start_map or self.h.read8("hIsInBattle"):
                moved = True
                break
            if self.last_ui_frame >= frame:
                # A script started (a trainer's sight line, a "don't go away"
                # tile), set off by the step the player stands on: it runs on
                # the frame after a step lands, so usually interrupts the NEXT
                # walk. Twice on one step this visit and the step is avoided:
                # Oak's Lab turns the player back on its doorway row.
                moved = True
                standing = self.position()
                self.script_steps[standing] = self.script_steps.get(standing, 0) + 1
                break
            if self.position() != before:
                moved = True
                if not into_warp or not self.h.read8("wWalkCounter"):
                    break
            elif self.h.pyboy.frame_count - frame >= 40:
                break
        self.h.pyboy.button_release(direction)
        self.report.inputs.append((frame, direction, self.h.pyboy.frame_count - frame))
        for _ in range(40):
            if not self.h.read8("wWalkCounter"):
                break
            self.h.tick()
        if not moved:
            self.blocked_steps[target] = self.blocked_steps.get(target, 0) + 1
        return moved

    # ------------------------------------------------------------------- loop

    def run(self, *, runs: int = 1, stages: int = 1000, max_frames: int) -> RunReport:
        """Play until `runs` runs have ended (won at the Hall of Fame or lost
        to a blackout; between runs the agent walks the Silph Co hub into the
        next), or `stages` stages are cleared, whichever is first."""
        start_frame = self.h.pyboy.frame_count
        self.last_progress_frame = start_frame
        self.run_start["frame"] = start_frame
        self.event("start", map=self.map_name(self.h.read8("hCurMap")),
                   battle_count=self.h.read8("wBattleCount"))
        try:
            while True:
                if len(self.report.runs) >= runs:
                    outcomes = [run["outcome"] for run in self.report.runs]
                    if runs == 1:
                        self.finish(outcomes[0], self.report.runs[0]["detail"])
                    else:
                        self.finish("completed", f"played {runs} runs: " + ", ".join(
                            f"{outcomes.count(o)} {o}" for o in sorted(set(outcomes))))
                    break
                if self.report.stages_cleared >= stages:
                    self.finish("completed", f"cleared {stages} stage(s)")
                    break
                if self.h.pyboy.frame_count - start_frame > max_frames:
                    self.finish("frame_limit", f"no result within {max_frames} frames")
                    break
                if self.h.pyboy.frame_count - self.last_progress_frame > self.stall_frames:
                    self.finish("stalled", f"no progress for {self.stall_frames} frames "
                                f"in mode {self.mode()}")
                    break
                self.step()
                self.checks.after_step()
                if self.checks.crash is not None:
                    crash = self.checks.crash
                    where = crash.get("from") or crash.get("pc") or {}
                    self.finish("crashed", f"{crash['kind']}: {crash['detail']}"
                                + (f" at {where.get('label') or where.get('address')}" if where else ""))
                    break
                self.note_progress()
                if self.heartbeat is not None and self.report.steps % HEARTBEAT_STEPS == 0:
                    self.write_heartbeat()
        except Exception as error:  # an agent bug or a game crash: keep the report
            self.finish("error", f"{type(error).__name__}: {error}")
            raise
        finally:
            self.report.frames = self.h.pyboy.frame_count - start_frame
        return self.report

    def write_heartbeat(self) -> None:
        """Where the run is, for run_autoplay.py to report if the emulator
        hangs (the worker can then no longer report anything itself)."""
        self.heartbeat.write_text(json.dumps({
            "frame": self.h.pyboy.frame_count,
            "map": self.map_name(self.h.read8("hCurMap")),
            "position": self.position(),
            "mode": self.mode(),
            "last_events": self.report.events[-12:],
        }) + "\n", encoding="utf-8")

    def end_run(self, outcome: str, detail: str) -> None:
        start = self.run_start
        record = {
            "outcome": outcome,
            "detail": detail,
            "stages_cleared": self.report.stages_cleared - start["stages"],
            "battles_won": self.report.battles_won - start["battles_won"],
            "frames": self.h.pyboy.frame_count - start["frame"],
            "last_stage": self.map_name(self.last_stage) if self.last_stage is not None else None,
        }
        if outcome == "blackout":
            record["lost_to"] = self.last_opponent
        self.report.runs.append(record)
        self.event("run_end", **record)
        self.run_start = {"frame": self.h.pyboy.frame_count, "stages": self.report.stages_cleared,
                          "battles_won": self.report.battles_won}

    def finish(self, outcome: str, detail: str) -> None:
        self.report.outcome = outcome
        self.report.detail = detail
        self.event("finish", outcome=outcome, detail=detail,
                   map=self.map_name(self.h.read8("hCurMap")), position=self.position(),
                   last_menu=self.last_menu_caller)

    def note_progress(self) -> None:
        # Game progress only. Moving is not progress, or an agent walking in
        # circles would never trip the watchdog; neither is a map change, or
        # two rooms ping-ponging would not (only a warp not taken before
        # counts).
        marker = (
            self.report.stages_cleared, len(self.warps_taken), self.report.battles_won,
            len(self.unbeaten_trainers()), len(self.talked), sum(self.choice_showings.values()),
            self.healed_this_visit, self.report.blackouts, self.h.read8("wBattleCount"),
            self.h.read8("wPartyCount"), len(self.report.runs),
            self.h.read8("hIsInBattle"), self.h.read8("wEnemyMonHP"), self.h.read8("wEnemyMonHP", 1),
        )
        if marker != self.progress_marker:
            self.progress_marker = marker
            self.last_progress_frame = self.h.pyboy.frame_count

    def mode(self) -> str:
        """battle, overworld (waiting for a step), dialogue (text or a menu is
        up), or busy (a step animating, a scripted scene, a fade: wait).

        The overworld loop stops polling the joypad both while a text box is
        open and while a step animates, so a quiet JoypadOverworld alone does
        not mean dialogue: dialogue is the text engine or a menu having started
        since the overworld last polled."""
        if self.h.read8("hIsInBattle"):
            return "battle"
        if self.naming_screen or self.last_ui_frame > self.last_overworld_frame:
            return "dialogue"
        if self.h.read8("hSimulatedJoypadStatesIndex") or self.h.read8("hJoyIgnore") & 0xF0:
            return "busy"  # arrow tiles, scripted walks: the game has the d-pad
        if self.last_overworld_frame >= 0 and self.h.pyboy.frame_count - self.last_overworld_frame <= 2:
            return "overworld"
        return "busy"

    def step(self) -> None:
        self.report.steps += 1
        self.track_battles()
        current_map = self.h.read8("hCurMap")
        if current_map != self.current_map:
            self.on_map_change(current_map)
        mode = self.mode()
        if mode != "busy":
            self.busy_since = None
        if mode == "overworld":
            self.checks.before_overworld_step()
            self.overworld_step()
        elif mode == "busy":
            self.busy_step()
        else:
            self.ui_step()

    def track_battles(self) -> None:
        in_battle = self.h.read8("hIsInBattle")
        if in_battle and not self.in_battle:
            if self.h.read8("wIsTrainerBattle"):
                opponent = self.h.read8("wCurOpponent")
                self.last_opponent = self.trainer_names.get(opponent, str(opponent))
            else:
                species = self.h.read8("wEnemyMonSpecies2")
                self.last_opponent = "wild " + self.species_names.get(species, str(species))
            self.event("battle_start", opponent=self.last_opponent)
        elif self.in_battle and not in_battle:
            self.event("battle_end", result=self.h.read8("wBattleResult"))
            self.checks.on_battle_end()
        self.in_battle = in_battle

    def on_map_change(self, current_map: int) -> None:
        previous, self.current_map = self.current_map, current_map
        self.blocked_steps.clear()
        self.script_steps.clear()
        self.hidden.clear()
        self.talked.clear()
        if self.arrival_map != current_map:
            self.arrival = None
        self.event("enter_map", map=self.map_name(current_map))
        self.checks.on_map_change()
        if current_map == self.hall_of_fame:
            self.end_run("champion", "entered the Hall of Fame")
        elif self.pending_loss and current_map == self.dorm:
            self.end_run("blackout", "the party fainted")
        self.pending_loss = False
        if current_map == self.lobby_map:
            if self.stage_map is not None:
                self.report.stages_cleared += 1
            self.stage_map = None
            self.warps_taken.clear()
            self.healed_this_visit = False
            self.shopped_this_visit = False
            self.door_choice = None
        elif previous in (self.lobby_map, self.reward_room) and current_map != self.reward_room:
            # A stage: from a lobby door, or a new run's first stage, which the
            # reward room after Oak's Lab leads straight into.
            self.stage_map = self.last_stage = current_map
            self.choice_showings.clear()

    # --------------------------------------------------- dialogue and battle

    def ui_step(self) -> None:
        """Answer the game only while it polls for a button.

        Text boxes, menus and the naming screen all wait in
        JoypadLowSensitivity. Pressing at any other moment is not just wasted:
        the A that closes a text box can land on the first overworld frame
        after it and talk to the same NPC again, forever."""
        now = self.h.pyboy.frame_count
        if now - self.last_wait_frame > 2:
            if now - max(self.last_wait_frame, self.last_press_frame) > NUDGE_FRAMES:
                self.press("a")  # a wait outside the usual poll: nudge it
            else:
                self.h.tick(2)
            return
        if self.party_menu_waiting:
            self.party_menu_waiting = False
            self.press(self.party_menu_action)
        elif self.plan is not None:
            self.plan_step()
        elif self.naming_screen:
            # One letter (A types the one under the cursor, "A"), then START
            # to submit: the player and rival names refuse to be empty.
            if self.naming_letters < 1:
                self.naming_letters += 1
                self.press("a")
            else:
                self.press("start", 4, 8)
        else:
            self.press("a")

    def busy_step(self) -> None:
        now = self.h.pyboy.frame_count
        if self.busy_since is None:
            self.busy_since = now
        if now - self.last_wait_frame <= 2 or now - self.busy_since > NUDGE_FRAMES:
            # Polling outside the text engine (a Pokedex page), or nothing at
            # all for a long while: answer or nudge with A.
            self.busy_since = now
            self.press("a")
            return
        self.h.tick(2)

    # ---------------------------------------------------------------- healing

    def recovery_counts(self) -> dict[int, int]:
        counts = self.h.read_bytes("wRecoveryItemCounts", len(self.recovery_table))
        return {item: count for item, count in zip(self.recovery_table, counts) if count}

    def no_heal_maps(self) -> set[int]:
        # The lobby nurse heals for free, and between runs the bag is moot.
        return {self.lobby_map, *self.hub_route}

    def choose_heal(self) -> dict[str, object] | None:
        """The item and party slot to heal between fights, or None. Revive a
        fainted mon first; else heal the living mon lowest on HP, if it is
        under HEAL_BELOW, with the smallest item that covers what it lacks."""
        owned = self.recovery_counts()
        party = self.party_hp()
        revives = [item for item in owned if item in self.revives]
        fainted = [slot for slot, (hp, max_hp) in enumerate(party) if max_hp and not hp]
        if revives and fainted:
            return self.new_plan(revives[0], fainted[0], owned)
        heals = sorted((self.heal_amounts[item], item) for item in owned if item in self.heal_amounts)
        hurt = [(hp / max_hp, slot) for slot, (hp, max_hp) in enumerate(party)
                if hp and max_hp and hp < max_hp * HEAL_BELOW]
        if not heals or not hurt:
            return None
        _, slot = min(hurt)
        missing = party[slot][1] - party[slot][0]
        item = next((item for amount, item in heals if amount >= missing), heals[-1][1])
        return self.new_plan(item, slot, owned)

    def new_plan(self, item: int, slot: int, owned: dict[int, int]) -> dict[str, object]:
        return {"kind": "heal", "item": item, "slot": slot, "count": owned[item], "steps": 0, "done": False,
                "index": sorted(owned, key=self.recovery_table.index).index(item)}

    def plan_step(self) -> None:
        if self.plan["kind"] == "shop":
            self.shop_step()
        else:
            self.heal_step()

    def heal_step(self) -> None:
        """One press of the heal errand: START, ITEM, the Recovery pocket,
        the item, USE, the target (set at PartyMenuInit), then back out."""
        plan = self.plan
        plan["steps"] += 1
        used = self.recovery_counts().get(plan["item"], 0) < plan["count"]
        if (used or plan["steps"] > PLAN_STEP_LIMIT) and not plan["done"]:
            plan["done"] = True
            if not used:
                self.event("heal_abandoned", item=plan["item"], menu=self.last_menu_caller)
        caller = self.last_menu_caller
        cursor = self.h.read8("hCurrentMenuItem")
        if plan["done"]:
            button = "b" if caller.startswith(("RedisplayStartMenu", "DisplayListMenuID")) else "a"
        elif caller.startswith("RedisplayStartMenu"):
            button = "a" if cursor == START_MENU_ITEM else ("down" if cursor < START_MENU_ITEM else "up")
        elif caller.startswith("DisplayListMenuID"):
            pocket = self.h.read8("wBagPocketsFlags") & 0x07
            position = cursor + self.h.read8("wListScrollOffset")
            if pocket:
                button = "left"  # back toward pocket 0, Recovery
            elif position != plan["index"]:
                button = "down" if position < plan["index"] else "up"
            else:
                button = "a"
        else:
            button = "a"  # USE, the item's text
        self.press(button)

    # --------------------------------------------------------------- shopping

    def money(self) -> int:
        return int("".join(f"{byte:02x}" for byte in self.h.read_bytes("wPlayerMoney", 3)))

    def price(self, item: int) -> int:
        bank, table = self.h.symbols.get("ItemPrices")
        return int("".join(f"{self.mem[bank, table + (item - 1) * 3 + i]:02x}" for i in range(3)))

    def choose_purchase(self, stock: list[int]) -> tuple[int, int, int] | None:
        """(list index, quantity, item) to buy next, or None. Keeps
        STOCK_HEALS HP-healing items with the cheapest one in today's stock
        (it is randomized), else a Revive when there is none."""
        owned = self.recovery_counts()
        money = self.money()
        heals = sum(count for item, count in owned.items() if item in self.heal_amounts)
        options = []
        if heals < STOCK_HEALS:
            options = [(self.price(item), index, item, STOCK_HEALS - heals)
                       for index, item in enumerate(stock) if item in self.heal_amounts]
        if not options and not any(item in self.revives for item in owned):
            options = [(self.price(item), index, item, 1)
                       for index, item in enumerate(stock) if item in self.revives]
        options = [option for option in options if 0 < option[0] <= money]
        if not options:
            return None
        price, index, item, wanted = min(options)
        return index, min(wanted, money // price), item

    def shop_step(self) -> None:
        """One press at the lobby clerk: BUY, then each purchase (item,
        quantity with UP, YES) until choose_purchase is satisfied, then out."""
        plan = self.plan
        plan["steps"] += 1
        if plan["steps"] > PLAN_STEP_LIMIT:
            plan["done"] = True
        caller = self.last_menu_caller
        cursor = self.h.read8("hCurrentMenuItem")
        if plan.get("selected"):
            # A purchase in progress: its quantity menu, then OK? YES. The
            # quantity menu can miss an A right after UP, so it is answered
            # until the YES/NO prompt shows.
            if caller.startswith("DisplayTwoOptionMenu"):
                button = "a"
                plan["selected"] = self.quantity_waiting = False
            elif self.quantity_waiting:
                button = "up" if self.h.read8("wItemQuantity") < plan["quantity"] else "a"
            else:
                self.h.tick(2)  # the next of its menus is still opening
                return
        elif caller.startswith("DoBuySellQuitMenu"):
            button = "b" if plan["done"] else ("a" if cursor == 0 else "up")  # BUY is first
        elif caller.startswith("DisplayListMenuID") and self.h.read8("wListMenuID") == PRICED_ITEM_LIST_MENU:
            pointer = self.word("wListPointer")
            stock = [self.mem[pointer + 1 + i] for i in range(self.mem[pointer])]
            purchase = None if plan["done"] else self.choose_purchase(stock)
            if purchase is None:
                plan["done"] = True
                button = "b"
            else:
                index, plan["quantity"], item = purchase
                position = cursor + self.h.read8("wListScrollOffset")
                if position != index:
                    button = "down" if position < index else "up"
                else:
                    button = "a"
                    plan["selected"] = True
                    self.event("buy", item=item, quantity=plan["quantity"], money=self.money())
        else:
            button = "a"  # the clerk's lines, OK? YES
        self.press(button)

    # -------------------------------------------------------------- overworld

    def overworld_step(self) -> None:
        """Walk one step toward the first goal group with a reachable spot.

        Groups come in priority order (goal_groups). A group none of whose
        spots can be reached right now (a leader behind Cinnabar's gates, an
        NPC boxed in by furniture) is skipped for this step, not forever, so
        it is retried as gates open and NPCs move."""
        if self.arrival is None:
            self.arrival = self.position()
        if self.plan is not None and (self.plan["done"] or self.plan["kind"] == "shop"):
            self.plan = None  # its menus have closed
        if self.plan is None and self.h.read8("hCurMap") not in self.no_heal_maps():
            self.plan = self.choose_heal()
            if self.plan is not None:
                self.event("heal", item=self.plan["item"], slot=self.plan["slot"])
        if self.plan is not None:
            self.press("start", 3, 8)
            return
        grid = self.read_grid()
        here = self.position()
        occupied = {(sprite["x"], sprite["y"]) for sprite in self.sprites().values()}
        blocked = self.obstacles()
        groups = self.goal_groups(grid)
        for goal in groups:
            spots = {step: target for step, target in goal.spots.items()
                     if step not in occupied and (goal.warp or grid.walkable(*step))}
            if here in spots:
                self.arrive(*spots[here])
                return
            path = world.find_path(grid, here, spots, blocked, enter_impassable_goals=goal.warp)
            if path:
                self.walk(path[0], into_warp=goal.warp and len(path) == 1)
                return
        labels = ",".join(sorted({target[1] for goal in groups for target in goal.spots.values()}))
        if self.last_no_path != (labels, here):
            self.last_no_path = (labels, here)
            self.event("no_path", goals=labels, position=here)
        self.blocked_steps.clear()
        self.script_steps.clear()
        self.h.tick(30)

    def obstacles(self) -> set[tuple[int, int]]:
        blocked = {(sprite["x"], sprite["y"]) for sprite in self.sprites().values()}
        current = self.h.read8("hCurMap")
        for warp_y, warp_x, _, dest in self.h.warp_entries():
            if dest != current:  # warp pads are path edges (warp_pads)
                blocked.add((warp_x, warp_y))
        # Steps the player failed to enter twice: a moving NPC, or terrain the
        # grid gets wrong. Cleared on each map change and when no path is left.
        blocked.update(step for step, count in self.blocked_steps.items() if count >= 2)
        blocked.update(step for step, count in self.script_steps.items() if count >= 2)
        return blocked

    def arrive(self, face: str | None, label: str) -> None:
        if label.startswith("warp"):
            self.enter_warp(face)
            return
        if face is not None:
            self.press(face, 3, 6)  # turn toward the target (it blocks the step)
        kind, _, slot = label.partition(":")
        if kind == "nurse":
            self.healed_this_visit = True
        elif kind == "clerk":
            self.shopped_this_visit = True
            self.plan = {"kind": "shop", "steps": 0, "done": False}
        elif kind == "special":
            self.talked.add(int(slot))
        self.press("a", 2, 8)

    def enter_warp(self, face: str | None) -> None:
        """The player stands on the goal warp. An edge warp fires by walking
        off the map, so first hold toward the edge; a door warp fires only on
        the step onto it, so then step off and back on."""
        start_map = self.h.read8("hCurMap")
        if face is not None:
            self.walk(face, into_warp=True)
            if self.h.read8("hCurMap") != start_map or self.mode() in ("battle", "dialogue"):
                return
        grid = self.read_grid()
        blocked = self.obstacles()
        x, y = self.position()
        back = {"up": "down", "down": "up", "left": "right", "right": "left"}
        for direction, step in grid.moves(x, y):
            if step in blocked or abs(step[0] - x) + abs(step[1] - y) != 1:
                continue
            if self.walk(direction):
                self.walk(back[direction], into_warp=True)
                return
        self.event("warp_stuck", position=(x, y))
        self.h.tick(30)

    def goal_groups(self, grid: world.WalkGrid) -> list[Goal]:
        """Goal groups for the current room, highest priority first."""
        sprites = self.sprites()
        current = self.h.read8("hCurMap")
        groups = []
        if current == self.lobby_map:
            nurse = sprites.get(LOBBY_NURSE_SLOT)
            if (
                nurse and nurse["picture"] == self.sprite_nurse
                and not self.healed_this_visit
                and any(hp < max_hp for hp, max_hp in self.party_hp())
            ):
                groups.append(self.talk_goal(grid, {LOBBY_NURSE_SLOT: nurse}, "nurse"))
            clerk = sprites.get(LOBBY_CLERK_SLOT)
            if clerk and clerk["picture"] == self.sprite_clerk and not self.shopped_this_visit:
                groups.append(self.talk_goal(grid, {LOBBY_CLERK_SLOT: clerk}, "clerk"))
            return groups + self.door_goals()
        if current in self.hub_route:
            # Between runs: head for the next run. Talk to everyone if the way
            # on is shut (a checkpoint cutscene wants Prof. Palm first).
            route = [(x, y) for y, x, _, dest in self.h.warp_entries()
                     if dest == self.hub_route[current]]
            rest = {slot: sprite for slot, sprite in sprites.items() if slot not in self.talked}
            explore = [self.talk_goal(grid, rest, "special")] if rest else []
            ahead = [self.warp_goal(route, "warp_hub")] if route else []
            if self.h.pyboy.frame_count - self.last_progress_frame > EXPLORE_AFTER_FRAMES:
                return explore + ahead
            return ahead + explore
        # Trainers from the map's header table: fought until their flag sets.
        trainers = {slot: sprites[slot] for slot in self.unbeaten_trainers() if slot in sprites}
        if trainers:
            groups.append(self.talk_goal(grid, trainers, "trainer"))
        # Talk once per visit: leaders and bosses (trainer sprites without a
        # header, fought by talking), and in gift rooms every NPC (the giver
        # is one of them). Talking again would only repeat their line.
        once = {slot: sprites[slot] for slot in self.special_trainers() if slot not in self.talked}
        if current in self.bridge_rooms:
            once |= {slot: sprite for slot, sprite in sprites.items()
                     if slot not in self.talked and sprite["picture"] != self.sprite_poke_ball}
        if once:
            groups.append(self.talk_goal(grid, once, "special"))
        # Talk to everyone once: after the exits, for rooms whose exit cannot be
        # reached (Mr. Fuji walks the player out of Pokemon Tower 7F, whose exit
        # warp is walled off), and before them once progress stalls, for rooms
        # whose script refuses the exit until something is done (Oak's Lab
        # turns the player back until a starter is chosen).
        rest = {slot: sprite for slot, sprite in sprites.items() if slot not in self.talked}
        explore = [self.talk_goal(grid, rest, "special")] if rest else []
        if self.h.pyboy.frame_count - self.last_progress_frame > EXPLORE_AFTER_FRAMES:
            return groups + explore + self.exit_goals()
        return groups + self.exit_goals() + explore

    def talk_goal(self, grid: world.WalkGrid, targets: dict[int, dict[str, int]], kind: str) -> Goal:
        spots = {}
        counters = self.counter_tiles()
        for slot, target in targets.items():
            for step, face in world.adjacent_facing((target["x"], target["y"]), counters, grid).items():
                spots.setdefault(step, (face, f"{kind}:{slot}"))
        return Goal(spots)

    def warp_goal(self, steps, label: str) -> Goal:
        return Goal({step: (self.edge_face(step), label) for step in steps}, warp=True)

    def door_goals(self) -> list[Goal]:
        """The lobby's two stage doors are its ROGUE_MAP warps at the top.
        Entering through one sets wLastMap to the lobby, which the wild areas'
        LAST_MAP exits rely on. (The bottom warps are only where the player
        arrives; they are WARP_NO_RETURN and lead nowhere.)"""
        doors = [(x, y) for y, x, _, dest in self.h.warp_entries() if dest == ROGUE_MAP]
        if not doors:
            return []
        if self.door_choice is None:
            self.door_choice = self.rng.randrange(len(doors)) if self.door_policy == "random" else 0
            label = "wLobbyDoor1StageMap" if self.door_choice == 0 else "wLobbyDoor2StageMap"
            self.event("door", door=self.door_choice + 1, stage=self.map_name(self.h.read8(label)))
        door = doors[min(self.door_choice, len(doors) - 1)]
        if self.blocked_steps.get(door, 0) >= 3 and len(doors) > 1:
            # Some visits draw only one open door; the other is wall.
            self.door_choice = 1 - self.door_choice
            self.event("door_closed", switched_to=self.door_choice + 1)
            door = doors[self.door_choice]
        return [self.warp_goal([door], f"warp_door{self.door_choice + 1}")]

    def exit_goals(self) -> list[Goal]:
        """Ways out of the room, best first. Exits are runtime-patched (wild
        areas use LAST_MAP, a cleared gym can lead to REWARD_ROOM, bridges back
        to the lobby), so rank by destination: the lobby, then LAST_MAP (a wild
        area's exit), then ROGUE_MAP (the reward room's doors), then side doors
        not taken yet this stage (a cave subroom, the next Elite Four room, the
        SS Anne's cabins), and last the way back: the door the player came in
        by, or one already taken. WARP_NO_RETURN is never an exit."""
        current = self.h.read8("hCurMap")
        width, height = self.map_size()
        warps = [((x, y), dest) for y, x, _, dest in self.h.warp_entries()
                 if x < width and y < height and dest not in (WARP_NO_RETURN, current)]
        forward = [(step, dest) for step, dest in warps if not self.near_arrival(step)]
        groups = []
        for wanted in (self.lobby_map, LAST_MAP, ROGUE_MAP):
            exits = [step for step, dest in forward if dest == wanted]
            if exits:
                groups.append(self.warp_goal(exits, "warp_exit"))
        side = [step for step, dest in forward
                if dest not in (self.lobby_map, LAST_MAP, ROGUE_MAP) and not self.taken(step)]
        if side:
            groups.append(self.warp_goal(side, "warp_side"))
        back = [step for step, _ in warps if step not in side]
        if back:
            groups.append(self.warp_goal(back, "warp_back"))
        return groups

    def taken(self, step: tuple[int, int]) -> bool:
        """Whether this warp, or its twin in a two-tile doorway, was taken."""
        current = self.h.read8("hCurMap")
        return any(
            taken_map == current and abs(x - step[0]) + abs(y - step[1]) <= 1
            for taken_map, x, y in self.warps_taken
        )

    def near_arrival(self, step: tuple[int, int]) -> bool:
        if self.arrival is None:
            return False
        return abs(step[0] - self.arrival[0]) + abs(step[1] - self.arrival[1]) <= 1

    def edge_face(self, step: tuple[int, int]) -> str | None:
        """Direction off the map edge for an edge warp, which fires only by
        walking off the map; None for a door-style warp."""
        x, y = step
        width, height = self.map_size()
        if y == 0:
            return "up"
        if y == height - 1:
            return "down"
        if x == 0:
            return "left"
        if x == width - 1:
            return "right"
        return None


def boot(harness: RedRogueHarness, seed: int, battle_count: int = 1) -> None:
    """Debug 2 boot to the lobby, with the RNG seeded just before the lobby
    rolls its first two doors, so the seed decides the whole run."""
    seeded = {"done": False}

    def seed_once(_context) -> None:
        if not seeded["done"]:
            seeded["done"] = True
            harness.seed_rng([seed >> 24, seed >> 16, seed >> 8, seed])

    harness.register_hook("SelectAndPatchLobbyExit", seed_once)
    harness.boot_to_lobby(battle_count=battle_count)
    harness.unregister_hook("SelectAndPatchLobbyExit", seed_once)


def boot_new_game(harness: RedRogueHarness, seed: int) -> None:
    """Power on with no debug menu: the agent itself goes through the title
    screen, NEW GAME, naming and the intro tour. The RNG is seeded when
    StartNewGame runs, so the seed decides the starters and everything after."""
    seeded = {"done": False}

    def seed_once(_context) -> None:
        if not seeded["done"]:
            seeded["done"] = True
            harness.seed_rng([seed >> 24, seed >> 16, seed >> 8, seed])

    harness.register_hook("StartNewGame", seed_once)


def play(
    seed: int,
    *,
    runs: int = 1,
    stages: int = 1000,
    max_frames: int,
    new_game: bool = False,
    stall_frames: int = 20_000,
    battle_count: int = 1,
    battle_policy: str = "type_switcher",
    door_policy: str = "random",
    log=None,
    sram: bytes | None = None,
    heartbeat: Path | None = None,
) -> dict[str, object]:
    """Boot (Debug 2 lobby, or a real new game), play and return the report.
    A failure (see FAILURES) also writes a screenshot and state dump under
    artifacts/, and the first anomaly a save state to load and inspect.
    `sram` is the cartridge RAM at power-on (32 KB; zeroes if None), for
    sram_fuzz.py."""
    started = time.monotonic()
    ram_path = None
    if sram is not None:
        ram_path = ARTIFACTS / f"autoplay_seed{seed}_{os.getpid()}.sram"
        ram_path.parent.mkdir(parents=True, exist_ok=True)
        ram_path.write_bytes(sram)
    harness = RedRogueHarness(ROOT, ARTIFACTS, ram_path=ram_path)
    if ram_path is not None:
        ram_path.unlink()
    try:
        if new_game:
            boot_new_game(harness, seed)
        else:
            boot(harness, seed, battle_count)
        agent = AutoplayAgent(harness, seed=seed, battle_policy=battle_policy,
                              door_policy=door_policy, stall_frames=stall_frames, log=log,
                              heartbeat=heartbeat)
        error = None
        try:
            agent.run(runs=runs, stages=stages, max_frames=max_frames)
        except Exception:  # run() already recorded outcome "error"
            error = traceback.format_exc()
        report = agent.report
        data = report.to_json()
        if error:
            data["traceback"] = error
        data["anomalies"] = agent.checks.anomalies
        data["checks"] = agent.checks.summary()
        if agent.checks.first_anomaly_state is not None:
            path = ARTIFACTS / f"autoplay_seed{seed}_anomaly.state"
            path.write_bytes(agent.checks.first_anomaly_state)
            data["anomaly_state"] = str(path)
        if report.failed:
            image, state = harness.write_failure_artifacts(f"autoplay_seed{seed}")
            data["artifacts"] = {"image": str(image), "state": str(state)}
    finally:
        harness.close()
    data["wall_seconds"] = round(time.monotonic() - started, 1)
    return data


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Play Red Rogue runs with the autoplay agent.")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--runs", type=int, default=1,
                        help="stop after this many runs end (Hall of Fame or blackout)")
    parser.add_argument("--stages", type=int, default=1000, help="or after this many stages")
    parser.add_argument("--new-game", action="store_true",
                        help="start from power-on and NEW GAME instead of the Debug 2 lobby")
    parser.add_argument("--battle-count", type=int, default=1, help="Debug 2 starting battle count")
    parser.add_argument("--battle-policy", default="type_switcher", choices=benchmark_policies.POLICIES)
    parser.add_argument("--door-policy", default="random", choices=("random", "first"))
    parser.add_argument("--max-frames", type=int, default=1_000_000)
    parser.add_argument("--stall-frames", type=int, default=20_000)
    parser.add_argument("--report", type=Path, default=None,
                        help="report path (default artifacts/autoplay_seed<N>.json)")
    parser.add_argument("--quiet", action="store_true", help="do not print events as they happen")
    args = parser.parse_args(argv)

    data = play(
        args.seed, runs=args.runs, stages=args.stages, max_frames=args.max_frames,
        new_game=args.new_game,
        stall_frames=args.stall_frames, battle_count=args.battle_count,
        battle_policy=args.battle_policy, door_policy=args.door_policy,
        log=None if args.quiet else print,
    )
    path = args.report or ARTIFACTS / f"autoplay_seed{args.seed}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")
    print(f"{data['outcome']}: {data['detail']} (stages={data['stages_cleared']} "
          f"won={data['battles_won']} frames={data['frames']}) -> {path}")
    for anomaly in data["anomalies"]:
        print(f"  anomaly at frame {anomaly['frame']} on {anomaly['map']}: "
              f"{anomaly['check']}: {anomaly['detail']}")
    return 1 if data["outcome"] in FAILURES or data["anomalies"] else 0


if __name__ == "__main__":
    sys.exit(main())
