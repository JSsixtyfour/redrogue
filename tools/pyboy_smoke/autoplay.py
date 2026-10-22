"""Autoplay agent: plays Red Rogue runs through joypad input, for soak testing.

The agent reads game state from RAM through the build's .sym (pokeblue_debug
by default, --rom) and decides every input itself. It writes no game state except the menu-cursor bytes the
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
before the lobby rolls its first doors (at StartNewGame with --new-game), so it
decides the whole run: rerun the same seed to reproduce a report.

    python3 tools/pyboy_smoke/autoplay.py --seed 7 --stages 40
    python3 tools/pyboy_smoke/run_autoplay.py --seeds 1-16   # make autoplay

Options that widen the hunt (--vary, --branches, --coverage, --save-checks,
--rom, --difficulty) are described in tools/pyboy_smoke/README.md, "Options
that widen the hunt", and in each flag's --help.
"""
from __future__ import annotations

import argparse
import json
import os
import random
import sys
import time
import traceback
from collections.abc import Callable
from dataclasses import asdict, dataclass, field, replace
from pathlib import Path

import autoplay_checks
import autoplay_team
import autoplay_world as world
import benchmark_policies
from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"
# The build played (a file stem). play(rom=) sets it for the process, so the
# branch and save-check emulators run the same build. The release builds have
# no Debug 2 menu and play only from NEW GAME (compare_builds.py).
DEBUG_ROM = "pokeblue_debug"
ROMS = (DEBUG_ROM, "pokeblue", "pokered")
ROM = DEBUG_ROM
CGB_MODE = False


def stem(seed: int, *, rom: str | None = None, cgb_mode: bool | None = None) -> str:
    """artifacts/ file stem for a seed, with the build unless it is the debug one."""
    build = ROM if rom is None else rom
    cgb = CGB_MODE if cgb_mode is None else cgb_mode
    return (f"autoplay_seed{seed}" + ("" if build == DEBUG_ROM else f"_{build}")
            + ("_cgb" if cgb else ""))

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
# After the post-Champion finale's briefing, VR's machine warp leads to the
# AI Lair instead (SilphCoVRPatchMachineWarp rewrites it on every VR load).
HUB_ROUTE = {
    "SILPH_CO_DORM": ("SILPH_CO_B1F",),
    "SILPH_CO_1F": ("SILPH_CO_B1F",),
    "SILPH_CO_B1F": ("SILPH_CO_VR",),
    "SILPH_CO_VR": ("OAKS_LAB", "AI_LAIR"),
}

# Healing outside battle (Potions cannot be used in one): HP each restores.
HEAL_AMOUNTS = {"POTION": 20, "SUPER_POTION": 50, "HYPER_POTION": 200,
                "MAX_POTION": 999, "FULL_RESTORE": 999}
REVIVES = ("REVIVE", "MAX_REVIVE")
HEAL_BELOW = 0.5  # heal a mon below this fraction of its max HP
START_MENU_ITEM = 2  # POKEDEX, POKEMON, ITEM, ...
PLAN_STEP_LIMIT = 80  # menu presses before a plan is abandoned
MENU_NAV_LIMIT = 24  # presses for a menu cursor to reach its target
STALEMATE_TURNS = 6  # battle menus in a row with neither side's HP changing
MENU_INPUTS = ("real", "cursor")
# basic: the bot as it was (random rewards and gifts, switches only to dodge a
# KO). strong: takes rewards and gifts on merit (autoplay_team.TeamJudge) and,
# in trainer battles, switches to the best-matched mon when a new enemy mon
# comes out (benchmark_policies.choose_matchup_switch). Compare the two to
# tell "too hard" from "the bot plays badly". merit: the offers alone, to
# measure the two halves apart.
PLAYERS = ("basic", "merit", "strong")
# DIFFICULTY_* names (constants/ram_constants.asm). Autoplay plays HARD unless
# told otherwise: balance is tuned there, and a fresh boot's NORMAL caps the AI
# at tier 2, so THREAT, PLAN and RISKY never ran (the coverage map found them).
DIFFICULTIES = ("VERY_EASY", "EASY", "NORMAL", "HARD", "VERY_HARD")

# Errands (--vary): a short stretch of random menu answers at something the
# agent would never choose itself, after which it backs out with B.
ERRAND_PRESSES = 40  # random answers, then B until the errand ends
ERRAND_GIVE_UP = 120  # presses in all before it is abandoned (a run still has the watchdog)
ERRAND_BUTTONS = (("a", 40), ("down", 20), ("up", 12), ("b", 12), ("left", 8), ("right", 8))
STARTER_SLOTS = (1, 2, 3)
SAVE_CHECK_LOBBIES = 4  # lobby arrivals saved, reloaded and power-cut (save_reload.py)  # Oak's Lab's three starter balls (data/maps/objects/OaksLab.asm)


@dataclass
class Profile:
    """How one seed plays, under --vary: drawn from the seed, recorded in the
    report, so a sweep covers many styles and each run can be replayed."""
    battle_policy: str
    ironman: bool = False
    errands: float = 0.0  # chance of an errand per lobby visit (a lobby NPC) and per stage (the bag)
    battle_items: float = 0.0  # chance per battle turn of choosing ITEM and using what comes up
    starter: int | None = None  # Oak's Lab ball slot, new games
    difficulty: str = "HARD"
    # Key items owned from the start, as [name, tier, active]: written to
    # sKeyItemsBitfield/sKeyItemTiers (SRAM), the state a Credit Exchange
    # purchase leaves. Their WRAM caches (charges, heal levels, the prism) are
    # re-derived by the game itself at the first run boundary
    # (RogueResetRunState), so charge-based items work from run 2 on.
    kit: list[list[object]] = field(default_factory=list)
    credits: int = 0  # Credit Exchange balance (wPlayerCoins), for the hub errands to spend


# The key items a kit draws from: KEY_ITEM_BIT_<NAME>_OWNED in ram_constants.asm,
# less EXP_ALL (an option now, not an item). Tiers are internal 0-2
# (MAX_KEY_ITEM_TIER: TIER 1-3 on screen).
KIT_EXCLUDED = {"EXP_ALL"}
KIT_MAX_TIER = 2
KIT_MAX_ACTIVE = 3  # KEY_ITEM_MAX_ACTIVE
DIFFICULTY_MIX = (("VERY_EASY", 1), ("EASY", 1), ("NORMAL", 2), ("HARD", 3), ("VERY_HARD", 2))


def key_item_bits() -> dict[str, int]:
    """Key item name -> its owned bit (the active bit is the next one)."""
    ram = parse_rgbds_constants(ROOT / "constants/ram_constants.asm")
    return {name[len("KEY_ITEM_BIT_"):-len("_OWNED")]: bit for name, bit in ram.items()
            if name.startswith("KEY_ITEM_BIT_") and name.endswith("_OWNED")}


def draw_profile(seed: int) -> Profile:
    rng = random.Random(f"profile/{seed}")
    profile = Profile(battle_policy=rng.choice(benchmark_policies.POLICIES),
                      ironman=rng.random() < 0.25,
                      errands=rng.choice((0.25, 0.5, 1.0)),
                      battle_items=rng.choice((0.0, 0.05, 0.15)),
                      starter=rng.choice(STARTER_SLOTS))
    names, weights = zip(*DIFFICULTY_MIX)
    profile.difficulty = rng.choices(names, weights)[0]
    items = sorted(name for name in key_item_bits() if name not in KIT_EXCLUDED)
    owned = rng.sample(items, rng.randint(0, len(items)))
    active = set(rng.sample(owned, min(KIT_MAX_ACTIVE, len(owned))))
    profile.kit = [[name, rng.randint(0, KIT_MAX_TIER), name in active] for name in owned]
    profile.credits = rng.choice((0, 0, 150, 999))
    return profile

# Menu routine -> event kind. Each has a .menuLoop local label ahead of its
# HandleMenuInput, lists its offers at 0..wMaxMenuItem-1 and NO THANKS at
# wMaxMenuItem.
CHOICE_MENUS = {"RogueRewardMenu": "reward", "BridgeGiftMenu": "gift"}


@dataclass
class MenuGoal:
    """A menu choice to make with real presses: while `waiting()` (the menu
    is the one polling), press `next_button()` until it answers None (the
    cursor is on the target), then `button`."""
    kind: str
    waiting: Callable[[], bool]
    target: int
    next_button: Callable[[], str | None]
    button: str = "a"
    chaos: tuple[str, ...] = ("up", "down")  # stray presses --menu-chaos may add
    presses: int = 0
    created: int = 0  # frame the goal was set


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
        menu_input: str = "real",
        menu_chaos: float = 0.0,
        snapshot: Callable[[str, dict[str, object]], None] | None = None,
        profile: Profile | None = None,
        player: str = "basic",
        ai_telemetry=None,
    ):
        if profile is not None:
            battle_policy = profile.battle_policy
        if player not in PLAYERS:
            raise ValueError(f"unknown player {player!r}")
        if player in ("merit", "strong"):
            offer_policy = "merit"
        if battle_policy not in benchmark_policies.POLICIES:
            raise ValueError(f"unknown battle policy {battle_policy!r}")
        if menu_input not in MENU_INPUTS:
            raise ValueError(f"unknown menu input {menu_input!r}")
        self.h = harness
        # --ai-telemetry: ai_telemetry.BattleAITelemetry, read-only; one record per trainer battle.
        self.ai_telemetry = ai_telemetry
        self.ai_battles: list[dict[str, object]] = []
        self.ai_blackouts_at_start = 0
        self.mem = harness.pyboy.memory
        self.cgb_wram_wait_frames = 0
        self.rng = random.Random(seed)
        self.battle_policy = battle_policy
        self.door_policy = door_policy
        self.offer_policy = offer_policy
        self.stall_frames = stall_frames
        self.log = log or (lambda message: None)
        self.heartbeat = heartbeat
        # real: menus are answered with presses that move the cursor, as a
        # player does; cursor: the cursor byte is written at the menu's hook
        # (faster, but the menus' own cursor code never runs).
        self.menu_input = menu_input
        self.menu_chaos = menu_chaos
        self.chaos_rng = random.Random(f"chaos/{seed}")  # keeps self.rng's draws unchanged
        self.report = RunReport(seed=seed)
        # Called at the start of a step with a key moment's kind (battle,
        # reward, gift, lobby), before the agent answers it: autoplay_branch.py
        # saves a state there to play random branches from.
        self.snapshot = snapshot
        self.snapshot_pending: str | None = None
        # --vary: a separate stream, so a profile's choices never shift self.rng's.
        self.profile = profile
        self.errand_rng = random.Random(f"errand/{seed}")
        self.errand: dict[str, object] | None = None
        self.errand_target: int | None | bool = False  # this lobby visit's errand NPC; False = not rolled
        self.bag_errand_pending = False
        self.party_menu_repeats = 0  # party menus shown outside battle since the overworld last polled
        self.exchange_visited = False  # this trip through the hub, under --vary
        self.errand_counts: dict[str, int] = {}

        self.rules = benchmark_policies.load_rules(ROOT)
        self.player = player
        self.judge = autoplay_team.TeamJudge(ROOT, harness, self.rules) if offer_policy == "merit" else None
        self.enemy_seen: tuple[int, int] | None = None  # the enemy mon the last matchup switch looked at
        maps = parse_map_constants(ROOT / "constants/map_constants.asm")
        self.map_names = {value: name for name, value in maps.items()}
        self.lobby_map = maps["INDIGO_PLATEAU_LOBBY"]
        self.oaks_lab = maps["OAKS_LAB"]
        self.credit_exchange = maps["CREDIT_EXCHANGE"]
        self.key_swap_text = lobby_text_id("TEXT_PC_KEY_SWAP_ATTENDANT")
        self.silph_b1f = maps["SILPH_CO_B1F"]
        self.hall_of_fame = maps["HALL_OF_FAME"]
        self.champions_room = maps["CHAMPIONS_ROOM"]
        self.dorm = maps["SILPH_CO_DORM"]
        self.reward_room = maps["REWARD_ROOM"]
        self.hub_route = {maps[here]: {maps[there] for there in theres} for here, theres in HUB_ROUTE.items()}
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
        self.menu_goal: MenuGoal | None = None
        self.menu_stats: dict[str, dict[str, int]] = {}  # kind -> choices made, presses, stray presses
        self.menu_frame = -1  # HandleMenuInput last entered
        self.text_wait_frame = -1  # WaitForTextScrollButtonPress last entered
        self.switch_target: int | None = None
        self.stalemate: tuple[tuple[int, int], int] = ((-1, -1), 0)  # (both HPs, turns unchanged)
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
        # The party menu waits in HandleMenuInput_ (its caller is not wanted:
        # HandlePartyMenuInput's own hook marks that menu).
        h.register_hook("HandleMenuInput_",
                        lambda _c: setattr(self, "menu_frame", self.h.pyboy.frame_count))
        h.register_hook("WaitForTextScrollButtonPress",
                        lambda _c: setattr(self, "text_wait_frame", self.h.pyboy.frame_count))
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
        self.last_ui_frame = self.menu_frame = self.h.pyboy.frame_count
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
        if target is None and self.player == "strong":
            target = self.matchup_switch()
        if target is None:
            target = self.break_stalemate()
        self.switched_last_turn = target is not None
        self.switch_target = target
        if self.errand is not None and self.errand["kind"] == "battle":
            self.end_errand("next turn")
        # FIGHT, or PKMN when the policy wants to switch; ITEM for a --vary errand.
        choice = 0 if target is None else 2
        if choice == 0 and self.profile and self.errand_rng.random() < self.profile.battle_items:
            choice = 1
            self.start_errand("battle", opponent=self.last_opponent)
        if self.menu_input == "cursor":
            self.h.write8("wBattleAndStartSavedMenuItem", choice)
        else:
            self.set_menu_goal("battle_menu", ("DisplayBattleMenu",), choice,
                               self._battle_menu_button, chaos=("up", "down", "left", "right"))

    def matchup_switch(self) -> int | None:
        """--player strong: once per enemy mon in a trainer battle, switch to
        a reserve that matches up clearly better (choose_matchup_switch)."""
        if not self.h.read8("wIsTrainerBattle") or self.switched_last_turn:
            return None
        enemy = (self.h.read8("wEnemyMonPartyPos"), self.h.read8("wEnemyMonSpecies"))
        if enemy == self.enemy_seen:
            return None
        self.enemy_seen = enemy
        target = benchmark_policies.choose_matchup_switch(self.rules, benchmark_policies.read_state(self.h))
        if target is not None:
            self.event("matchup_switch", enemy=self.species_names.get(enemy[1]),
                       active=self.species_names.get(self.h.read8("wBattleMonSpecies")), to_slot=target)
        return target

    def break_stalemate(self) -> int | None:
        """A turn after turn where no one's HP moves (two Dittos that only
        know Transform: each Transform restores 5 PP, so neither runs out and
        Struggles) never ends on its own. Switch to another healthy mon, as a
        player would."""
        hps = (self.word("wBattleMonHP"), self.word("wEnemyMonHP"))
        same, turns = self.stalemate
        turns = turns + 1 if hps == same else 0
        self.stalemate = (hps, turns)
        if turns < STALEMATE_TURNS:
            return None
        current = self.h.read8("wPlayerMonNumber")
        alive = [slot for slot, (hp, _) in enumerate(self.party_hp()) if hp and slot != current]
        self.event("stalemate", turns=turns, player=self.species_names.get(self.h.read8("wBattleMonSpecies")),
                   enemy=self.species_names.get(self.h.read8("wEnemyMonSpecies")), switch_to=alive[:1])
        self.stalemate = (hps, 0)
        return alive[0] if alive else None

    def _battle_menu_button(self) -> str | None:
        """Two one-column menus side by side: FIGHT/ITEM (0, 1) and PKMN/RUN
        (2, 3). The column is the menu's cursor X ($9, or $1 in the Safari
        Zone, on the left), the row hCurrentMenuItem."""
        column = int(self.h.read8("wTopMenuItemX") >= 0xD)
        want_column, want_row = divmod(self.menu_goal.target, 2)
        if column != want_column:
            return "right" if want_column else "left"
        return self.line_button(self.h.read8("hCurrentMenuItem"), want_row)

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
        if self.menu_input == "cursor":
            self.h.write8("wPlayerMoveListIndex", slot)
        else:
            # hCurrentMenuItem is the slot + 1 while the menu waits. B backs
            # out to the battle menu, which decides again.
            self.set_menu_goal("move_menu", ("SelectMenuItem",), slot,
                               lambda: self.line_button(self.h.read8("hCurrentMenuItem") - 1,
                                                        self.menu_goal.target),
                               chaos=("up", "down", "b"))

    def menu_context(self, goal: MenuGoal) -> dict[str, object]:
        if goal.kind == "gift":
            return {"gifts": self.h.read_bytes("wGift1", 3)}
        return {}

    @staticmethod
    def line_button(position: int, target: int) -> str | None:
        if position == target:
            return None
        return "down" if position < target else "up"

    def set_menu_goal(self, kind: str, callers: tuple[str, ...] | Callable[[], bool], target: int,
                      next_button: Callable[[], str | None], *, button: str = "a",
                      chaos: tuple[str, ...] = ("up", "down")) -> None:
        """`callers`: the menu's HandleMenuInput call sites, or a predicate
        saying the menu is waiting."""
        waiting = callers if callable(callers) else (
            lambda: self.last_menu_caller.startswith(callers))
        self.menu_goal = MenuGoal(kind, waiting, target, next_button, button, chaos,
                                  created=self.h.pyboy.frame_count)

    def party_menu_goal(self, target: int, button: str) -> None:
        if self.menu_input == "cursor":
            if button == "a":
                self.h.write8("wPartyAndBillsPCSavedMenuItem", target)
            self.party_menu_action = button
            return
        # The party menu waits in HandleMenuInput_, which the menu hook does
        # not see: HandlePartyMenuInput's own hook says it is up.
        self.set_menu_goal("party_menu", lambda: self.party_menu_waiting, target,
                           lambda: None if button == "b" else self.line_button(
                               self.h.read8("hCurrentMenuItem"), self.menu_goal.target),
                           button=button)

    def menu_goal_step(self) -> bool:
        """One press toward the pending menu goal, if its menu is the one
        waiting now. False when it is not (text before the menu, say)."""
        goal = self.menu_goal
        if goal is None or not goal.waiting():
            return False
        stats = self.menu_stats.setdefault(goal.kind, {"choices": 0, "moves": 0, "stray": 0})
        if self.text_wait_frame > self.menu_frame and self.menu_frame < goal.created:
            # Text before this menu has polled at all (the battle menu's goal is
            # set on entry, and a trapping move's "attack continues!" prints
            # before the menu draws): `waiting` only saw last turn's caller.
            self.text_wait_frame = -1
            self.press("a")
            return True
        if self.text_wait_frame > self.menu_frame:
            # The menu's own redraw waits for A/B (a three-line description
            # in a two-line box scrolls with `cont`): directions do nothing
            # until it is answered, and the A only scrolls, so a player has to
            # press twice to choose. Answer it as they would.
            cursor = self.h.read8("hCurrentMenuItem")
            self.checks.anomaly("menu_text_wait", f"{goal.kind}: item {cursor} waits for a button "
                                "while the menu draws it", **self.menu_context(goal))
            self.text_wait_frame = -1
            self.press("a")
            return True
        if self.menu_chaos and self.chaos_rng.random() < self.menu_chaos:
            stats["stray"] += 1
            self.press(self.chaos_rng.choice(goal.chaos))
            return True
        button = goal.next_button()
        if button is not None and goal.presses >= MENU_NAV_LIMIT:
            self.checks.anomaly("menu", f"{goal.kind}: cursor never reached {goal.target} "
                                f"in {MENU_NAV_LIMIT} presses (at {self.h.read8('hCurrentMenuItem')})")
            button = None
        if button is None:
            stats["choices"] += 1
            self.menu_goal = None
            self.party_menu_waiting = False
            self.press(goal.button)
        else:
            stats["moves"] += 1
            goal.presses += 1
            self.press(button)
        return True

    def start_errand(self, kind: str, **data) -> None:
        self.errand = {"kind": kind, "presses": 0, "start": self.h.pyboy.frame_count, **data}
        self.errand_counts[kind] = self.errand_counts.get(kind, 0) + 1
        self.event("errand", phase="start", errand=kind, map=self.map_name(self.h.read8("hCurMap")),
                   **{key: value for key, value in data.items() if key != "opened"})

    def end_errand(self, why: str) -> None:
        errand, self.errand = self.errand, None
        self.event("errand", phase="end", errand=errand["kind"], why=why, presses=errand["presses"],
                   frames=self.h.pyboy.frame_count - errand["start"])

    def errand_step(self) -> None:
        """One random answer, as a player poking at a menu would; past
        ERRAND_PRESSES only B, to back out. A bag errand first walks the START
        menu to ITEM and leaves it with B when it shows again, so it never
        wanders into SAVE or the options (which hold the difficulty)."""
        errand = self.errand
        errand["presses"] += 1
        if errand["presses"] > ERRAND_GIVE_UP:
            self.end_errand("gave up")
            self.press("b")
            return
        if errand["kind"] == "bag" and self.last_menu_caller.startswith("RedisplayStartMenu"):
            if errand["opened"]:
                self.press("b")
            else:
                button = self.line_button(self.h.read8("hCurrentMenuItem"), START_MENU_ITEM)
                if button is None:
                    errand["opened"] = True
                self.press(button or "a")
            return
        if errand["presses"] > ERRAND_PRESSES:
            self.press("b")
            return
        buttons, weights = zip(*ERRAND_BUTTONS)
        self.press(self.errand_rng.choices(buttons, weights)[0])

    def has_body_armor(self) -> bool:
        owner = self.h.read8("wPlayerMonNumber") + 1  # owners are party slot + 1
        records = self.h.read_bytes("wBridgeSelectedEffects", 4)
        return any(records[i] == owner and records[i + 1] == self.body_armor
                   for i in range(0, len(records), 2))

    def _on_party_menu(self, _context) -> None:
        in_battle = self.h.read8("hIsInBattle")
        forced = in_battle and (self.h.read8("wForcePlayerToChooseMon") or not (
            self.h.read8("wBattleMonHP") or self.h.read8("wBattleMonHP", 1)))
        if self.errand is not None and not forced:
            self.party_menu_goal(self.errand_rng.randrange(max(1, self.h.read8("wPartyCount"))), "a")
            return
        if not in_battle:
            # Only reached through an interaction the agent chose: the heal
            # plan's target, else (a gift that teaches a move, a trade offer)
            # the lead. Shown again with no plan (the lead cannot learn a TM
            # an errand opened: "not compatible", and the menu returns) means
            # the lead was refused: back out as a player would.
            if self.plan is None:
                self.party_menu_repeats += 1
                if self.party_menu_repeats > 1:
                    self.party_menu_goal(0, "b")
                    return
            self.party_menu_goal(self.plan["slot"] if self.plan else 0, "a")
            return
        forced = bool(self.h.read8("wForcePlayerToChooseMon"))
        current = self.h.read8("wPlayerMonNumber")
        alive = [slot for slot, (hp, _) in enumerate(self.party_hp()) if hp and slot != current]
        fainted = not (self.h.read8("wBattleMonHP") or self.h.read8("wBattleMonHP", 1))
        if not forced and self.switch_target is not None:
            self.party_menu_goal(self.switch_target, "a")
            self.switch_target = None
        elif alive and (forced or fainted):
            self.party_menu_goal(alive[0], "a")
        else:
            # The optional "switch after a KO" prompt: keep the current mon.
            self.party_menu_goal(current, "b")

    def _on_choice_menu(self, kind: str) -> None:
        self.choice_showings[kind] = self.choice_showings.get(kind, 0) + 1
        self.choice_pending = kind
        if self.choice_showings[kind] == 1:
            self.snapshot_pending = kind

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
        elif self.offer_policy == "merit":
            choice = self.judge.reward_choice() if kind == "reward" else self.judge.gift_choice()
            choice = min(choice, no_thanks)
        elif self.offer_policy == "random":
            choice = self.rng.randrange(no_thanks)
        else:
            choice = 0
        if self.menu_input == "cursor":
            self.h.write8("hCurrentMenuItem", choice)
        else:
            entry = next(name for name, menu_kind in CHOICE_MENUS.items() if menu_kind == kind)
            self.set_menu_goal(kind, (entry,), choice,
                               lambda: self.line_button(self.h.read8("hCurrentMenuItem"),
                                                        self.menu_goal.target))
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

    def game_world_reads_ready(self) -> bool:
        """Whether D000-DFFF currently selects the game's main WRAM bank.

        In CGB mode bank 0 aliases bank 1. The enhanced-color palette buffers
        use banks 2 and 3, which overlap the address range holding map and
        tileset state in bank 1. Agent reads from that range must wait until
        SVBK selects bank 0 or 1.
        """
        if self.h.hardware_mode != "CGB":
            return True
        return self.mem[0xFF70] & 0x07 in (0, 1)

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
                   battle_count=(self.h.read8("wBattleCount")
                                 if self.game_world_reads_ready() else None))
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
                    mode = (self.mode() if self.game_world_reads_ready()
                            else "waiting for main WRAM bank")
                    self.finish("stalled", f"no progress for {self.stall_frames} frames "
                                f"in mode {mode}")
                    break
                self.step()
                if self.h.hook_errors:
                    raise RuntimeError("a hook callback raised:\n" + self.h.hook_errors[0])
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
        if not self.game_world_reads_ready():
            state = {
                "frame": self.h.pyboy.frame_count,
                "map": None,
                "position": None,
                "mode": "waiting for main WRAM bank",
                "last_events": self.report.events[-12:],
            }
            self.heartbeat.write_text(json.dumps(state) + "\n", encoding="utf-8")
            return
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
                   map=self.map_name(self.h.read8("hCurMap")),
                   position=self.position() if self.game_world_reads_ready() else None,
                   last_menu=self.last_menu_caller)

    def note_progress(self) -> None:
        # Game progress only. Moving is not progress, or an agent walking in
        # circles would never trip the watchdog; neither is a map change, or
        # two rooms ping-ponging would not (only a warp not taken before
        # counts).
        if not self.game_world_reads_ready():
            return
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
        if not self.game_world_reads_ready():
            # Let the game finish its CGB palette-buffer work. The outer run
            # loop still performs crash checks and enforces frame/stall limits.
            self.cgb_wram_wait_frames += 1
            self.h.tick(1)
            return
        self.track_battles()
        current_map = self.h.read8("hCurMap")
        if current_map != self.current_map:
            self.on_map_change(current_map)
        if self.snapshot_pending is not None:
            kind, self.snapshot_pending = self.snapshot_pending, None
            if self.snapshot is not None:
                self.snapshot(kind, {"map": self.map_name(current_map), "stages": self.report.stages_cleared,
                                     "opponent": self.last_opponent if kind == "battle" else None})
        mode = self.mode()
        if mode != "busy":
            self.busy_since = None
        if mode == "overworld":
            self.party_menu_repeats = 0
            if self.errand is not None and self.errand["kind"] != "battle" and self.errand["presses"]:
                self.end_errand("back in the overworld")
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
            if self.ai_telemetry is not None:
                self.ai_telemetry.begin_battle(self.last_opponent)
                self.ai_blackouts_at_start = self.report.blackouts
            self.snapshot_pending = "battle"
            self.enemy_seen = None
        elif self.in_battle and not in_battle:
            self.event("battle_end", result=self.h.read8("wBattleResult"))
            if self.ai_telemetry is not None:
                self.record_ai_battle(self.h.read8("wBattleResult"))
            self.checks.on_battle_end()
            if self.errand is not None and self.errand["kind"] == "battle":
                self.end_errand("battle over")
        self.in_battle = in_battle

    def record_ai_battle(self, result: int) -> None:
        # wBattleResult stays 0 on a blackout (that path never writes it), so a
        # blackout during the battle is what marks the player's loss (1).
        if self.report.blackouts > self.ai_blackouts_at_start:
            result = 1
        record = self.ai_telemetry.end_battle(result)
        if record is None:
            return
        record["run_index"] = len(self.report.runs)
        record["battle_index"] = len(self.ai_battles)
        self.ai_battles.append(record)
        if record["flags"]:
            self.log(f"  ai: {record['opponent']} tier {record['tier']} flags {record['flags']} "
                     f"moves {record['moves'][:12]}")

    def on_map_change(self, current_map: int) -> None:
        previous, self.current_map = self.current_map, current_map
        # A heal plan or a menu errand belongs to the map it began on. A
        # cutscene that changes the map under it (the Hall of Fame after a
        # heal, then the title screen) would leave it answering menus that
        # are gone: B at the title, forever.
        if self.plan is not None:
            self.event("plan_dropped", plan=self.plan["kind"], map=self.map_name(current_map))
            self.plan = None
        if self.errand is not None and self.errand["kind"] != "battle":
            self.end_errand("map changed")
        self.party_menu_repeats = 0
        self.blocked_steps.clear()
        self.script_steps.clear()
        self.hidden.clear()
        self.talked.clear()
        if self.arrival_map != current_map:
            self.arrival = None
        self.event("enter_map", map=self.map_name(current_map))
        self.checks.on_map_change()
        if current_map == self.credit_exchange:
            self.exchange_visited = True
            self.errand_target = False
        elif current_map == self.oaks_lab:
            self.exchange_visited = False
        if current_map == self.hall_of_fame and previous == self.champions_room:
            # Only the walk in from the Champion's room is a win: CONTINUE after
            # the credits loads the Hall of Fame save there and passes through
            # again on the way to the Dorm.
            self.end_run("champion", "entered the Hall of Fame")
        elif self.pending_loss and current_map == self.dorm:
            self.end_run("blackout", "the party fainted")
        self.pending_loss = False
        if current_map == self.lobby_map:
            if self.stage_map is not None:
                self.report.stages_cleared += 1
            self.stage_map = None
            self.snapshot_pending = "lobby"
            self.warps_taken.clear()
            self.healed_this_visit = False
            self.shopped_this_visit = False
            self.door_choice = None
            self.errand_target = False
        elif previous in (self.lobby_map, self.reward_room) and current_map != self.reward_room:
            # A stage: from a lobby door, or a new run's first stage, which the
            # reward room after Oak's Lab leads straight into.
            self.stage_map = self.last_stage = current_map
            self.choice_showings.clear()
            if self.profile and self.errand_rng.random() < self.profile.errands:
                self.bag_errand_pending = True

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
        if self.menu_goal_step():
            pass
        elif self.party_menu_waiting and self.menu_input == "cursor":
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
        elif self.errand is not None:
            self.errand_step()
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
        if self.bag_errand_pending and self.errand is None:
            self.bag_errand_pending = False
            self.start_errand("bag", opened=False)
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
        elif kind == "errand":
            self.errand_target = None  # done for this visit
            self.start_errand("npc", target=int(slot))
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
            if self.profile and self.errand_target is False:
                # The key swap attendant stands here only in a checkpoint
                # window (after certain gyms): the one chance to change which
                # 3 owned key items are equipped, so it wins the errand.
                swap = self.key_swap_slot(sprites)
                if swap is not None:
                    self.errand_target = swap
            if self.profile and self.errand_target is False:
                others = sorted(slot for slot in sprites if slot not in (LOBBY_NURSE_SLOT, LOBBY_CLERK_SLOT))
                self.errand_target = (self.errand_rng.choice(others) if others and
                                      self.errand_rng.random() < self.profile.errands else None)
            if self.errand_target in sprites:
                groups.append(self.talk_goal(grid, {self.errand_target: sprites[self.errand_target]}, "errand"))
            return groups + self.door_goals()
        if current == self.credit_exchange and self.profile:
            # --vary's hub detour: one vendor counter (a sign), then back out.
            signs = self.signs()
            if self.errand_target is False:
                self.errand_target = self.errand_rng.randrange(len(signs)) if signs else None
            if self.errand_target is not None and self.errand_target < len(signs):
                return [self.sign_goal(grid, signs[self.errand_target], self.errand_target)] + self.exit_goals()
            return self.exit_goals()
        if current in self.hub_route:
            # Between runs: head for the next run. Talk to everyone if the way
            # on is shut (a checkpoint cutscene wants Prof. Palm first).
            route = [(x, y) for y, x, _, dest in self.h.warp_entries()
                     if dest in self.hub_route[current]]
            if self.profile and self.profile.errands and current == self.silph_b1f \
                    and not self.exchange_visited:
                # --vary: spend credits at the Credit Exchange on the way.
                exchange = [(x, y) for y, x, _, dest in self.h.warp_entries()
                            if dest == self.credit_exchange]
                if exchange:
                    return [self.warp_goal(exchange, "warp_exchange")]
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
        if self.profile and self.profile.starter and current == self.oaks_lab:
            # While all three balls stand, talk only to the profile's starter.
            balls = {slot for slot in STARTER_SLOTS
                     if sprites.get(slot, {}).get("picture") == self.sprite_poke_ball}
            if len(balls) == len(STARTER_SLOTS):
                rest = {slot: sprite for slot, sprite in rest.items()
                        if slot not in balls or slot == self.profile.starter}
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

    def key_swap_slot(self, sprites: dict[int, dict[str, int]]) -> int | None:
        texts = self.h.read_bytes("wMapSpriteData", 2 * SPRITE_SLOTS)
        return next((slot for slot in sprites if texts[2 * (slot - 1) + 1] == self.key_swap_text), None)

    def signs(self) -> list[tuple[int, int]]:
        """This map's bg events (counters, signs) as (x, y) steps."""
        count = self.h.read8("wNumSigns")
        coords = self.h.read_bytes("wSignCoords", 2 * count)
        return [(coords[2 * i + 1], coords[2 * i]) for i in range(count)]

    def sign_goal(self, grid: world.WalkGrid, sign: tuple[int, int], index: int) -> Goal:
        """A bg event is read facing it from the next step: any walkable side."""
        x, y = sign
        sides = {(x, y + 1): "up", (x, y - 1): "down", (x - 1, y): "right", (x + 1, y): "left"}
        return Goal({step: (face, f"errand:{index}") for step, face in sides.items()
                     if grid.walkable(*step)})

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


def lobby_text_id(name: str) -> int:
    """A TEXT_PC_* value: its row in the lobby's text pointer table (from 1)."""
    import re

    source = (ROOT / "scripts/IndigoPlateauLobby.asm").read_text(encoding="utf-8")
    table = source.split("IndigoPlateauLobby_TextPointers:", 1)[1]
    return re.findall(r"^\s*dw_const\s+\w+,\s*(TEXT_\w+)", table, re.M).index(name) + 1


def coverage_hooks() -> dict[str, tuple[int, int]]:
    import coverage_inventory

    return coverage_inventory.plan()[1]


def apply_options(harness: RedRogueHarness, difficulty: str | None, ironman: bool,
                  profile: Profile | None = None) -> None:
    if difficulty is not None:
        harness.set_difficulty(difficulty)
    if ironman:
        bit = parse_rgbds_constants(ROOT / "constants/ram_constants.asm")["BIT_IRONMAN"]
        harness.write8("wOptions3", harness.read8("wOptions3") | 1 << bit)
    if profile is not None:
        grant_kit(harness, profile.kit)
        harness.write8("wPlayerCoins", int(str(profile.credits // 100), 16))  # 2-byte BCD
        harness.write8("wPlayerCoins", int(str(profile.credits % 100), 16), 1)


def grant_kit(harness: RedRogueHarness, kit: list[list[object]]) -> None:
    """Own exactly these key items (and activate the marked ones, at most
    KEY_ITEM_MAX_ACTIVE) at these tiers: item N is bits 2N/2N+1 of
    sKeyItemsBitfield (owned, active) and the same pair of sKeyItemTiers.
    The kit replaces what the boot left (Debug 2 already owns and activates
    three), so the 3-active limit holds."""
    if not kit:
        return
    bits = key_item_bits()
    owned = [0, 0, 0, 0]
    tiers = [0, 0, 0, 0]
    for name, tier, active in kit:
        bit = bits[name]
        owned[bit // 8] |= 1 << bit % 8
        if active:
            owned[(bit + 1) // 8] |= 1 << (bit + 1) % 8
        tiers[bit // 8] = tiers[bit // 8] & ~(3 << bit % 8) | tier << bit % 8
    harness.write_sram_bytes("sKeyItemsBitfield", owned)
    harness.write_sram_bytes("sKeyItemTiers", tiers)


def boot(harness: RedRogueHarness, seed: int, battle_count: int = 1,
         difficulty: str | None = None, ironman: bool = False, profile: Profile | None = None) -> None:
    """Debug 2 boot to the lobby, with the RNG seeded just before the lobby
    rolls its first two doors, so the seed decides the whole run. The
    difficulty is set in the lobby, before any stage builds a party."""
    seeded = {"done": False}

    def seed_once(_context) -> None:
        if not seeded["done"]:
            seeded["done"] = True
            harness.seed_rng([seed >> 24, seed >> 16, seed >> 8, seed])

    harness.register_hook("SelectAndPatchLobbyExit", seed_once)
    harness.boot_to_lobby(battle_count=battle_count)
    harness.unregister_hook("SelectAndPatchLobbyExit", seed_once)
    apply_options(harness, difficulty, ironman, profile)


def boot_new_game(harness: RedRogueHarness, seed: int, difficulty: str | None = None,
                  ironman: bool = False, profile: Profile | None = None) -> None:
    """Power on with no debug menu: the agent itself goes through the title
    screen, NEW GAME, naming and the intro tour. The RNG is seeded when
    StartNewGame runs, so the seed decides the starters and everything after."""
    seeded = {"done": False}

    def seed_once(_context) -> None:
        if not seeded["done"]:
            seeded["done"] = True
            harness.seed_rng([seed >> 24, seed >> 16, seed >> 8, seed])

    harness.register_hook("StartNewGame", seed_once)
    if difficulty is not None or ironman or profile is not None:
        # PrepareOakSpeech re-runs InitOptions (NORMAL) unless the OPTION
        # screen was opened first, so set it at the first overworld frame:
        # after the speech, before Oak's Lab builds any party.
        chosen = {"done": False}

        def choose_difficulty(_context) -> None:
            if not chosen["done"]:
                chosen["done"] = True
                apply_options(harness, difficulty, ironman, profile)

        harness.register_hook("JoypadOverworld", choose_difficulty)


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
    menu_input: str = "real",
    menu_chaos: float = 0.0,
    branches: int = 0,
    snapshots: int = 3,
    branch_frames: int = 3000,
    freeze_frames: int | None = None,
    coverage: bool = False,
    difficulty: str | None = None,
    vary: bool = False,
    save_checks: bool = False,
    rom: str = DEBUG_ROM,
    cgb_mode: bool = False,
    player: str = "basic",
    ai_telemetry: bool = False,
) -> dict[str, object]:
    """Boot (Debug 2 lobby, or a real new game), play and return the report.
    A failure (see FAILURES) also writes a screenshot and state dump under
    artifacts/, and the first anomaly a save state to load and inspect.
    `sram` is the cartridge RAM at power-on (32 KB; zeroes if None), for
    sram_fuzz.py. With `branches`, the run snapshots its key moments and then
    plays that many random-input branches from up to `snapshots` of each kind
    (autoplay_branch.py); the report's "branches" holds what they found. With
    `coverage`, every code label is hooked until it first runs, and the report's
    "coverage" lists the labels that ran (coverage_inventory.py, autoplay_coverage.py)."""
    import autoplay_branch  # it imports this module

    global ROM, CGB_MODE
    if rom != DEBUG_ROM and not new_game:
        raise ValueError(f"{rom} has no Debug 2 menu; play it with new_game")
    ROM = rom
    CGB_MODE = cgb_mode
    # --vary: this seed's own profile (battle policy, ironman, errands, starter).
    profile = draw_profile(seed) if vary else None
    # HARD, the balance baseline, unless asked; --vary mixes difficulties.
    if difficulty is None:
        difficulty = profile.difficulty if profile else "HARD"
    elif profile is not None:
        profile.difficulty = difficulty

    started = time.monotonic()
    reel = autoplay_branch.SnapshotReel() if branches or save_checks else None
    ram_path = None
    if sram is not None:
        ram_path = ARTIFACTS / f"{stem(seed)}_{os.getpid()}.sram"
        ram_path.parent.mkdir(parents=True, exist_ok=True)
        ram_path.write_bytes(sram)
    import coverage_inventory
    # The screen checks' code rules (autoplay_screen.py); a ~70 s walk only after a rebuild.
    # Optional: without it those rules are skipped. /mnt/c reads can fail
    # transiently under load (ENODATA, seen 2026-10-20), which must not end a run.
    try:
        coverage_inventory.code_labels(ROM)
    except OSError:
        pass
    harness = RedRogueHarness(ROOT, ARTIFACTS, ram_path=ram_path, rom=ROM, cgb_mode=cgb_mode)
    if ram_path is not None:
        ram_path.unlink()
    try:
        ironman = bool(profile and profile.ironman)
        if new_game:
            boot_new_game(harness, seed, difficulty, ironman, profile)
        else:
            boot(harness, seed, battle_count, difficulty, ironman, profile)
        telemetry = None
        if ai_telemetry:
            import ai_telemetry as ai_telemetry_module

            telemetry = ai_telemetry_module.BattleAITelemetry(harness, ROOT)
        agent = AutoplayAgent(harness, seed=seed, ai_telemetry=telemetry, battle_policy=battle_policy,
                              door_policy=door_policy, stall_frames=stall_frames, log=log,
                              heartbeat=heartbeat, menu_input=menu_input, menu_chaos=menu_chaos,
                              profile=profile, player=player,
                              snapshot=None if reel is None else lambda kind, info: reel.offer(
                                  kind, harness.pyboy.frame_count, info, harness.save_state))
        # After the agent's and the checks' own hooks, which keep their addresses.
        hits, skipped = harness.track_coverage(coverage_hooks()) if coverage else (set(), [])
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
        data["menus"] = agent.menu_stats
        data["checks"] = agent.checks.summary()
        data["screen_checks"] = agent.checks.screen.summary()
        data["player"] = player
        data["hardware_mode"] = harness.hardware_mode
        data["cgb_wram_wait_frames"] = agent.cgb_wram_wait_frames
        if telemetry is not None:
            data["ai_battles"] = [{**battle, "seed": seed} for battle in agent.ai_battles]
            data["ai_telemetry_errors"] = telemetry.errors[:20]
        if profile is not None:
            data["profile"] = {**asdict(profile), "errands_run": agent.errand_counts}
        if agent.game_world_reads_ready():
            stored = harness.read8("wOptions2") & parse_rgbds_constants(
                ROOT / "constants/ram_constants.asm")["DIFFICULTY_MASK"]
            data["difficulty"] = next((name for name in DIFFICULTIES if parse_rgbds_constants(
                ROOT / "constants/ram_constants.asm")[f"DIFFICULTY_{name}"] == stored), stored)
        else:
            data["difficulty"] = None
        if agent.checks.first_anomaly_state is not None:
            path = ARTIFACTS / f"{stem(seed)}_anomaly.state"
            path.write_bytes(agent.checks.first_anomaly_state)
            data["anomaly_state"] = str(path)
        if report.failed:
            image, state = harness.write_failure_artifacts(stem(seed))
            data["artifacts"] = {"image": str(image), "state": str(state)}
        hits = set(hits)
    finally:
        harness.close()
    if save_checks:
        import save_reload

        lobbies = [s for s in reel.select(SAVE_CHECK_LOBBIES) if s.kind == "lobby"]
        if heartbeat is not None:
            heartbeat.write_text(json.dumps({"frame": None, "mode": "save checks", "map": None,
                                             "position": None}) + "\n", encoding="utf-8")
        data["save_checks"] = save_reload.run_save_checks(seed, lobbies, cgb_mode=cgb_mode)
    if reel is not None and branches:
        options = {} if freeze_frames is None else {"freeze_frames": freeze_frames}
        data["branches"] = autoplay_branch.run_snapshots(
            seed, reel.select(snapshots), branches=branches, frames=branch_frames,
            heartbeat=heartbeat, coverage=coverage, cgb_mode=cgb_mode, **options)
        hits |= set(data["branches"].pop("coverage_hits", ()))
    if coverage:
        data["coverage"] = {"hit": sorted(hits), "skipped": skipped}
    data["wall_seconds"] = round(time.monotonic() - started, 1)
    return data


def build_parser() -> argparse.ArgumentParser:
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
    parser.add_argument("--menu-input", default="real", choices=MENU_INPUTS,
                        help="real: move menu cursors with presses; cursor: write the cursor byte")
    parser.add_argument("--menu-chaos", type=float, default=0.0,
                        help="chance of a stray press at each menu step (0-1)")
    parser.add_argument("--max-frames", type=int, default=1_000_000)
    parser.add_argument("--stall-frames", type=int, default=20_000)
    parser.add_argument("--branches", type=int, default=0,
                        help="random-input branches per snapshot (battle, reward, gift, lobby)")
    parser.add_argument("--snapshots", type=int, default=3, help="snapshots branched per kind")
    parser.add_argument("--branch-frames", type=int, default=3000)
    parser.add_argument("--coverage", action="store_true",
                        help="record which code labels run (autoplay_coverage.py reports them)")
    parser.add_argument("--save-checks", action="store_true",
                        help="save at lobby arrivals, reload on a fresh emulator, compare, and cut "
                             "power mid-save (save_reload.py)")
    parser.add_argument("--vary", action="store_true",
                        help="play this seed's own profile: battle policy, ironman, lobby and bag "
                             "errands, items in battle, starter (Profile, draw_profile)")
    parser.add_argument("--difficulty", choices=DIFFICULTIES, default=None,
                        help="LEVELS setting (default HARD, the balance baseline; --vary mixes them)")
    parser.add_argument("--rom", choices=ROMS, default=DEBUG_ROM,
                        help="build to play; the release builds need --new-game")
    parser.add_argument("--cgb", action="store_true",
                        help="run the emulator in CGB mode (default: DMG)")
    parser.add_argument("--player", choices=PLAYERS, default="basic",
                        help="strong: rewards and gifts on merit, matchup switches (PLAYERS)")
    parser.add_argument("--ai-telemetry", action="store_true",
                        help="record one AI record per trainer battle (ai_telemetry.py); read-only")
    parser.add_argument("--report", type=Path, default=None,
                        help="report path (default artifacts/autoplay_seed<N>[_cgb].json)")
    parser.add_argument("--quiet", action="store_true", help="do not print events as they happen")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    data = play(
        args.seed, runs=args.runs, stages=args.stages, max_frames=args.max_frames,
        new_game=args.new_game,
        stall_frames=args.stall_frames, battle_count=args.battle_count,
        battle_policy=args.battle_policy, door_policy=args.door_policy,
        menu_input=args.menu_input, menu_chaos=args.menu_chaos,
        branches=args.branches, snapshots=args.snapshots, branch_frames=args.branch_frames,
        coverage=args.coverage, difficulty=args.difficulty, vary=args.vary, save_checks=args.save_checks,
        rom=args.rom, cgb_mode=args.cgb, player=args.player, ai_telemetry=args.ai_telemetry,
        log=None if args.quiet else print,
    )
    path = args.report or ARTIFACTS / f"{stem(args.seed)}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")
    print(f"{data['outcome']}: {data['detail']} (stages={data['stages_cleared']} "
          f"won={data['battles_won']} frames={data['frames']}) -> {path}")
    for anomaly in data["anomalies"]:
        print(f"  anomaly at frame {anomaly['frame']} on {anomaly['map']}: "
              f"{anomaly['check']}: {anomaly['detail']}")
    findings = data.get("branches", {}).get("findings", [])
    for finding in findings:
        print(f"  branch {finding['key']} ({finding['at']['map']}): {finding['outcome']} "
              f"{finding['detail']} {len(finding['anomalies'])} anomalies\n    {finding['replay']}")
    return 1 if data["outcome"] in FAILURES or data["anomalies"] or findings else 0


if __name__ == "__main__":
    sys.exit(main())
