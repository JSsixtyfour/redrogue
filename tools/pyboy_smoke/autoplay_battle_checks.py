"""Battle detectors: table lookups by an invalid id, and battle state a menu changed.

Two crash/corruption classes that nothing else looked for (2026-11-24):

1. Index out of range. A selected move of 0 (nothing chosen yet) or $FF (CANNOT_MOVE)
   reached a `Moves` lookup, which then read bytes outside the table as a move, and its
   name scan ran on through ROM. Every `ld r16, Moves + n` in the ROM is hooked; the
   instruction is found by scanning the ROM for the load, so a new lookup is covered the
   day it is written (test_autoplay_battle_checks compares the count with the source).
   The index is in A for the `ld hl` form (before AddNTimes) and is HL / 6 for the
   `ld de` / `ld bc` form. The other tables a move or species id selects are checked at
   their own routines: GetName, the move effect jump, animations, move sounds,
   GetMonHeader.
2. Aliased RAM. With five or more mons, opening the party menu wrote OAM bytes over the
   enemy's Bide tally, because a UNION edit had slid the two together. Between the battle
   menu opening and the turn being committed, nothing but the player's own choice may
   change: the snapshot taken at DisplayBattleMenu is compared at the next
   DisplayBattleMenu of the same turn and at MainInBattleLoop.selectEnemyMove. Enemy-side
   state is compared always, player-side state only when the player neither switched nor
   used an item.

Read-only: no hook writes to the game.
"""
from __future__ import annotations

import re
from pathlib import Path

from detector_health import observed_check
from source_constants import parse_rgbds_constants

MOVE_LENGTH = 6
TYPE_NAME_LIMIT = {1: "species", 2: "move", 7: "trainer"}  # constants/list_constants.asm
# `ld bc/de/hl, nn`
LOADS = {0x01: "HL6", 0x11: "HL6", 0x21: "A"}

# (first label, label just past the span or a byte count). Enemy side and shared turn
# state: no player menu may change any of it.
ENEMY_SPANS = (
    ("wEnemySubstituteHP", 1), ("wEnemySelectedMove", 1), ("wAICount", 1), ("wEnemyMoveListIndex", 1),
    ("wLastSwitchInEnemyMonHP", 2), ("wTotalPayDayMoney", 3),
    ("wTransformedEnemyMonOriginalDVs", 2), ("wEnemyDisabledMoveNumber", 1),
    ("wEnemyUsedMove", 1), ("wEnemyMonMinimized", 1),
    ("wAITier", "wAISeenPlayerMoveMask"), ("wAISeenPlayerMoveMask", 3), ("wWitchPrevPlayerMove", 1),
    ("wWitchPrevPlayerSlot", 1), ("wAIEnemyEstimateCache", 8), ("wAIPlayerKOMaxDamage", 2),
    ("wEnemyMonUnmodifiedLevel", "wEnemyMonStatMods"), ("wEnemyMonStatMods", 8),
    ("wEnemyStatsToDouble", "wPlayerNumAttacksLeft"),
    ("wEnemyNumAttacksLeft", "wEnemyDisabledMove"), ("wEnemyDisabledMove", 1), ("wEnemyBideAccumulatedDamage", 2),
    ("wEnemyMon", "wEnemyMonBaseStats"), ("wEnemyPartyCount", "wEnemyMonOT"), ("wAITurnPlan", 1),
)
PLAYER_SPANS = (
    ("wPlayerSubstituteHP", 1), ("wBridgeRepeatState", 1), ("wPlayerDisabledMoveNumber", 1),
    ("wPlayerUsedMove", 1), ("wPlayerMonMinimized", 1), ("wPartyFoughtCurrentEnemyFlags", 1),
    ("wPlayerMonUnmodifiedLevel", "wPlayerMonStatMods"), ("wPlayerMonStatMods", 8),
    ("wPlayerStatsToDouble", "wEnemyStatsToDouble"),
    ("wPlayerNumAttacksLeft", "wEnemyNumAttacksLeft"), ("wPlayerBideAccumulatedDamage", 2),
    ("wBattleMon", "wTrainerClass"), ("wPlayerMonNumber", 1), ("wPartyCount", "wPartyMonOT"),
)


def source_move_lookups(root: Path) -> list[tuple[str, str]]:
    """(enclosing global label, line) of every `ld r16, Moves...` in assembled source."""
    found = []
    for folder in ("engine", "home", "custom_functions", "scripts", "data"):
        for path in (root / folder).rglob("*.asm"):
            label = ""
            for line in path.read_text(encoding="utf-8").splitlines():
                code = line.split(";", 1)[0]
                match = re.match(r"([A-Za-z_]\w*)::?", code)
                if match:
                    label = match.group(1)
                elif re.search(r"^\s*ld\s+(hl|de|bc),\s*Moves\b", code):
                    found.append((label, code.strip()))
    return found


def rom_move_lookups(harness, root: Path) -> list[tuple[int, int, str]]:
    """(bank, address, register form) of every instruction loading Moves + 0..5. Another
    bank's table or code can share the address, so a hit counts only inside a routine
    whose source has such a load (GetMonHeader reads BaseStats, at the same address)."""
    routines = {label for label, _line in source_move_lookups(root)}
    _bank, moves = harness.symbols.get("Moves")
    rom = Path(harness.rom_path).read_bytes()
    hits = []
    for low in range(MOVE_LENGTH):
        target = moves + low
        for opcode, form in LOADS.items():
            pattern = bytes((opcode, target & 0xFF, target >> 8))
            at = rom.find(pattern)
            while at >= 0:
                bank = at // 0x4000
                address = at if bank == 0 else 0x4000 + at % 0x4000
                nearest = harness.symbols.nearest(bank, address) or ""
                if re.split(r"[.+]", nearest)[0] in routines:
                    hits.append((bank, address, form))
                at = rom.find(pattern, at + 1)
    return sorted(hits)


# SendOutMon resets these when the player switches.
SWITCH_WRITES = ("wLastSwitchInEnemyMonHP", "wEnemyUsedMove")


class BattleChecks:
    def __init__(self, checks):
        self.checks = checks  # GameChecks: anomaly(), _where(), detector_health
        self.detector_health = checks.detector_health
        self.h = checks.h
        root = Path(checks.root)
        constants = root / "constants"
        self.num_moves = checks.num_moves
        self.species = checks.species
        self.num_effects = parse_rgbds_constants(constants / "move_effect_constants.asm")["DISABLE_EFFECT"]
        moves = parse_rgbds_constants(constants / "move_constants.asm")
        self.num_anims = max(v for k, v in moves.items() if k != "CANNOT_MOVE" and v < 0xFF)
        types = parse_rgbds_constants(constants / "type_constants.asm")
        self.types = {v for k, v in types.items() if k.isupper() and not k.startswith("UNUSED")}
        self.lookups = 0
        self.compares = 0
        self.snapshot: dict[int, int] | None = None
        self.menu_labels: list[str] = []
        self.exposure: dict[str, int] = {}
        self.enemy = self._resolve(ENEMY_SPANS)
        self.player = self._resolve(PLAYER_SPANS)
        written = {self.h.address(name) + i for name in SWITCH_WRITES for i in range(2 if name.endswith("HP") else 1)}
        self.acted_masks = {self.h.address("wEnemyBattleStatus1"): 1 << 5, self.h.address("wEnemyMonStatus"): 7}
        party = self.h.address("wEnemyMon1Status")
        self.acted_masks.update({party + i * 0x2C: 7 for i in range(6)})
        self.enemy_acted = [a for a in self.enemy if a not in written]

        for bank, address, form in rom_move_lookups(self.h, root):
            self.h._register_at((bank, address), lambda _c, b=bank, a=address, f=form: self._on_lookup(b, a, f))
        hook = self.h.register_hook
        hook("GetName", self._on_get_name)
        hook("_JumpMoveEffect.next", self._on_effect)
        hook("PlayAnimation", self._on_animation)
        hook("GetMoveSound", self._on_move_sound)
        hook("GetMonHeader", self._on_mon_header)
        hook("DisplayBattleMenu", self._on_battle_menu)
        hook("MainInBattleLoop", self._on_turn_start)
        hook("MainInBattleLoop.selectEnemyMove", self._on_commit)
        hook("SaveScreenTileAreaToBuffer3", self._on_buffer3)
        hook("TurnRewindRestore", self._on_turn_start)  # it restores last turn's state: no comparison
        hook("SwapMovesInMenu", self._on_turn_start)  # SELECT reorders the moves: the player asked for it
        hook("ExecutePlayerMove", lambda _c: self._count("player_acts"))
        hook("ExecuteEnemyMove", lambda _c: self._count("enemy_acts"))
        hook("GetCurrentMove.selected", self._on_current_move)

    # ------------------------------------------------------------ plumbing

    def _resolve(self, spans) -> list[int]:
        addresses: list[int] = []
        for first, last in spans:
            start = self.h.address(first)
            stop = start + last if isinstance(last, int) else self.h.address(last)
            if not start < stop <= start + 0x200:
                raise ValueError(f"span {first}..{last} is {start:04x}-{stop:04x}")
            addresses += range(start, stop)
        return sorted(set(addresses))

    def _count(self, name: str) -> None:
        self.exposure[name] = self.exposure.get(name, 0) + 1

    def _caller(self) -> list[dict[str, object]]:
        sp = self.h.pyboy.register_file.SP
        return [self.checks._where(self.checks._word(sp + 2 * i)) for i in range(5)]

    def _label(self, address: int) -> str:
        """Nearest WRAM label at or below `address`, all aliases at that byte."""
        symbols = self.h.symbols._by_bank.get(0, ())
        best = max((a for a, _ in symbols if 0xC000 <= a <= address), default=None)
        names = [n for a, n in symbols if a == best]
        return "/".join(names[:3]) + (f"+{address - best}" if address != best else "")

    def reset(self) -> None:
        self.snapshot = None
        self.detector_health = self.checks.detector_health

    def summary(self) -> dict[str, object]:
        return {"move_lookups": self.lookups, "menu_compares": self.compares, "exposure": self.exposure}

    # ------------------------------------------------------------ index checks

    @observed_check
    def _on_lookup(self, bank: int, address: int, form: str) -> None:
        self.lookups += 1
        registers = self.h.pyboy.register_file
        if form == "A":
            index = registers.A
            ok = index < self.num_moves
        else:
            index, rest = divmod(registers.HL, MOVE_LENGTH)
            ok = rest == 0 and index < self.num_moves
        if not ok:
            self.checks.anomaly("move_lookup", f"move id {(index + 1) & 0xFF} at {bank:02X}:{address:04X} "
                                f"{self.h.symbols.nearest(bank, address)}", stack=self._caller(),
                                battle=self._battle_state())

    def _battle_state(self) -> dict[str, object]:
        read = self.h.read8
        return {name: read(name) for name in (
            "wPlayerSelectedMove", "wEnemySelectedMove", "wBattleMonStatus", "wEnemyMonStatus",
            "wPlayerBattleStatus1", "wPlayerBattleStatus2", "wEnemyBattleStatus1", "wEnemyBattleStatus2",
            "wAITurnPlan", "hWhoseTurn")}

    @observed_check
    def _on_get_name(self, _context) -> None:
        kind, index = self.h.read8("wNameListType"), self.h.read8("wNameListIndex")
        name = TYPE_NAME_LIMIT.get(kind)
        bad = (name == "move" and not 1 <= index <= self.num_moves
               or name == "species" and index not in self.species
               or not 1 <= kind <= 7)
        if bad:
            self.checks.anomaly("name_lookup", f"GetName type {kind} index {index}", stack=self._caller())

    @observed_check
    def _on_effect(self, _context) -> None:
        effect = self.h.pyboy.register_file.A
        # .next is also reached by fall-through on the enemy's turn, with A loaded there.
        if not 1 <= effect <= self.num_effects:
            self.checks.anomaly("move_effect", f"effect {effect:#04x} jumped to", stack=self._caller(),
                                battle=self._battle_state())

    @observed_check
    def _on_animation(self, _context) -> None:
        animation = self.h.read8("wAnimationID")
        if not 1 <= animation <= self.num_anims:
            self.checks.anomaly("move_animation", f"animation {animation}", stack=self._caller())

    @observed_check
    def _on_move_sound(self, _context) -> None:
        index = self.h.pyboy.register_file.A
        if index >= self.num_anims:
            self.checks.anomaly("move_sound", f"sound index {index}", stack=self._caller())

    @observed_check
    def _on_mon_header(self, _context) -> None:
        species = self.h.read8("wCurSpecies")
        if species not in self.species:
            self.checks.anomaly("mon_header", f"species ${species:02X}", stack=self._caller())

    @observed_check
    def _on_current_move(self, _context) -> None:
        """A move about to be executed must be one its user can have: its own slot, or
        Struggle. Locked turns repeat a move that may have come from Metronome or Mirror
        Move, and Transform and Mimic write the slots themselves."""
        enemy = self.h.read8("hWhoseTurn")
        move = self.h.pyboy.register_file.A
        side = "Enemy" if enemy else "Player"
        slots = self.h.read_bytes("wEnemyMonMoves" if enemy else "wBattleMonMoves", 4)
        status1 = self.h.read8(f"w{side}BattleStatus1")
        status2 = self.h.read8(f"w{side}BattleStatus2")
        self._count(f"move_{move}")
        locked = status1 & 0b10110011 or status2 & 0b01100000
        if move in slots or move == self.num_moves or locked or move == 0 or move > self.num_moves:
            return  # an invalid id is _on_lookup's finding
        self.checks.anomaly("foreign_move", f"{side.lower()} executes {move}, which is not in {list(slots)}",
                            stack=self._caller(), battle=self._battle_state())

    # ------------------------------------------------------------ menu round trip

    def _take(self) -> None:
        memory = self.h.pyboy.memory
        self.snapshot = {address: memory[address] for address in (*self.enemy, *self.player)}

    @observed_check
    def _on_turn_start(self, _context) -> None:
        self.snapshot = None

    @observed_check
    def _on_battle_menu(self, _context) -> None:
        if self.h.read8("wBattleType") or self.h.read8("wLinkState") == 4:
            self.snapshot = None
            return
        for label in ("wBattleMonType1", "wBattleMonType2", "wEnemyMonType1", "wEnemyMonType2"):
            if self.h.read8(label) not in self.types:
                self.checks.anomaly("battle_type", f"{label} is {self.h.read8(label):#04x}")
        self._compare("menu reopened")
        self._take()

    @observed_check
    def _on_commit(self, _context) -> None:
        self._compare("turn committed")
        self.snapshot = None

    def _compare(self, when: str) -> None:
        before = self.snapshot
        if before is None:
            return
        self.compares += 1
        memory = self.h.pyboy.memory
        acted = self.h.read8("wActionResultOrTookBattleTurn") != 0
        if acted:
            self._count("menu_acted")
        addresses = self.enemy_acted if acted else (*self.enemy, *self.player)
        changed: dict[str, list[str]] = {}
        for address in addresses:
            now = memory[address]
            if acted and address in self.acted_masks:  # a switch ends Wrap, the Poke Flute wakes
                now |= before[address] & self.acted_masks[address]
            if now != before[address]:
                changed.setdefault(self._label(address), []).append(f"{address:04x}:{before[address]:02x}>{now:02x}")
        for label, bytes_ in changed.items():
            self.checks.anomaly("menu_changed_battle", f"{label} ({when}{', acted' if acted else ''})",
                                bytes=bytes_[:8])

    @observed_check
    def _on_buffer3(self, _context) -> None:
        if self.h.read8("hIsInBattle") not in (0, 0xFF) and self.snapshot is not None:
            self.checks.anomaly("buffer3_in_battle", "wTileMapBackup3 covers wMiscBattleData", stack=self._caller())
