"""Bug detectors that ride along on every autoplay run.

The agent only notices a bug that stops play: a freeze, a softlock, a dead
end. These checks look for the quieter ones while it plays:

- data checks: at stable moments (the first overworld input poll after a map change
  or a battle, each turn's battle menu, the end of a run) the party, the item
  pockets, money, the current map and its warps, and in battle both active
  mons and the trainer's party must be valid. A finding is an `anomaly` event;
  the run goes on, and the first one also saves a state to load and inspect.
- crash detection: the debug ROM pads every unused byte with $FF (`rst $38`),
  and `rst $00` is `rst $38` too, so a jump into padding, to NULL or into
  garbage arrives at $0038 (the crash screen). That vector is hooked, and
  between agent steps the CPU must be running ROM with SP inside the stack,
  except inside validated CGB palette/map copy windows.
  Either ends the run as `crashed` with the crash site, its stack and labels.
  The overworld loop must also poll the joypad at one stack depth: a drift is
  a leaked push or a routine that returns past its caller.
- garbled screens (autoplay_screen.py): text and graphics read through a bad
  pointer or from the wrong bank, as `screen_*` anomalies.

An illegal opcode makes PyBoy spin forever inside tick(), out of Python's
reach; run_autoplay.py's per-seed wall-clock timeout covers that (`hung`).
"""
from __future__ import annotations

import io
from detector_health import observed_check, CORE
from pathlib import Path

import autoplay_screen
from source_constants import parse_map_constants, parse_rgbds_constants

PARTY_LENGTH = 6
NUM_MOVES = 4
NAME_LENGTH = 11
TEXT_TERMINATOR = 0x50  # "@"
MAX_LEVEL = 100
MAX_ITEM_COUNT = 99
MAX_WARP_EVENTS = 32
SPECIAL_WARP_MAPS = (0xFD, 0xFE, 0xFF)  # WARP_NO_RETURN, ROGUE_MAP, LAST_MAP
STACK_SIZE = 0xFF  # ram/wram.asm "Stack": ds $100 - 1 below wStack
CRASH_VECTOR = 0x0038
CRASH_STACK_WORDS = 6
MAX_ANOMALIES = 40  # distinct findings kept per report; counts keep going
KEY_ITEM_MAX_TIER = 2  # internal; the Credit Exchange sells TIER 1-3 (credit_mart.asm)
SCREEN_TILE_COUNT = 20 * 18  # constants: SCREEN_WIDTH * SCREEN_HEIGHT

# CGB palette copies borrow SP as a data pointer. Keep these source-derived
# windows narrow; unlike harness.SP_TRICK_ROUTINES, they also validate both
# the live source pointer and the saved normal stack pointer.
CGB_SP_COPY_WINDOWS = (
    ("MakeOverworldBGMapAttributes", "MakeOverworldBGMapAttributes.w2ramCopyLoop2_Y",
     "wTileMap", SCREEN_TILE_COUNT),
    ("GBCBufferFastTransfer", "GBCBufferFastTransfer_BGPVBlank", 0xD500, 128),
    ("GBCBufferFastTransfer_OBP0", "GBCBufferFastTransfer_OBP1", 0xD540, 32),
    ("GBCBufferFastTransfer_OBP1", "CopyGBCFullPalBuffer2to3", 0xD560, 32),
)

# party_struct (macros/ram.asm)
MON_SPECIES, MON_HP, MON_MOVES, MON_PP, MON_LEVEL, MON_MAXHP = 0x00, 0x01, 0x08, 0x1D, 0x21, 0x22
PARTYMON_STRUCT_LENGTH = 0x2C
MOVE_LENGTH, MOVE_PP = 6, 5  # data/moves/moves.asm, constants/battle_constants.asm


class GameChecks:
    def __init__(self, agent, root: Path):
        self.agent = agent
        self.detector_health = {}
        self.h = agent.h
        # The parser leaves `const_value - 1` unresolved: NUM_POKEMON_INDEXES is
        # the last species constant and NUM_ATTACKS is STRUGGLE, the last move.
        species = parse_rgbds_constants(root / "constants/pokemon_constants.asm")
        self.species = {value for value in species.values() if value}
        self.num_moves = parse_rgbds_constants(root / "constants/move_constants.asm")["STRUGGLE"]
        self.num_maps = len(parse_map_constants(root / "constants/map_constants.asm"))
        ram = parse_rgbds_constants(root / "constants/ram_constants.asm")
        self.pockets = [  # (count label, items in the table, saved slots)
            ("wRecoveryItemCounts", ram["NUM_RECOVERY_ITEMS"], ram["RECOVERY_ITEM_SLOTS"]),
            ("wStatItemCounts", ram["NUM_STAT_ITEMS"], ram["STAT_ITEM_SLOTS"]),
            ("wValuableItemCounts", ram["NUM_VALUABLE_ITEMS"], ram["VALUABLE_ITEM_SLOTS"]),
        ]
        bank, address = self.h.symbols.get("Moves")
        self.base_pp = [0] + [self.h.pyboy.memory[bank, address + i * MOVE_LENGTH + MOVE_PP]
                              for i in range(self.num_moves)]
        self.rom_banks = 2 << self.h.pyboy.memory[0x148]  # cartridge header ROM size
        self.key_item_bits = {name[len("KEY_ITEM_BIT_"):-len("_OWNED")]: bit for name, bit in ram.items()
                              if name.startswith("KEY_ITEM_BIT_") and name.endswith("_OWNED")}
        self.key_item_max_active = ram["KEY_ITEM_MAX_ACTIVE"]
        self.stack_top = self.h.address("wStack")
        self.sp_trick_ranges = [self.h.symbols.routine_range(name)
                                for name in self.h.SP_TRICK_ROUTINES if name in self.h.symbols._symbols]
        self.sp_copy_windows = []
        if self.h.hardware_mode == "CGB":
            for start_label, end_label, source, size in CGB_SP_COPY_WINDOWS:
                if start_label not in self.h.symbols._symbols or end_label not in self.h.symbols._symbols:
                    continue
                start_bank, start = self.h.symbols.get(start_label)
                end_bank, end = self.h.symbols.get(end_label)
                if start_bank != end_bank:
                    continue
                source_start = self.h.address(source) if isinstance(source, str) else source
                self.sp_copy_windows.append((start_bank, start, end, source_start, source_start + size))

        self.anomalies: list[dict[str, object]] = []
        self.counts: dict[str, int] = {}
        self._seen: set[tuple[str, str]] = set()
        self.first_anomaly_state: bytes | None = None
        self.crash: dict[str, object] | None = None
        self.overworld_sp: dict[int, int] = {}
        self.lowest_sp = self.stack_top
        self.stack_armed = False  # power-on runs part of Init before SP moves into the stack
        self.world_pending = True
        self.battle_party_checked = False

        self.h.pyboy.hook_register(0, CRASH_VECTOR, self._on_crash_vector, None)
        self.h.register_hook("JoypadOverworld", self._on_overworld_poll)
        self.h.register_hook("DisplayBattleMenu", self._on_battle_menu)
        self.screen = autoplay_screen.ScreenChecks(self)  # garbled text and graphics

    def reset(self) -> None:
        """Forget findings, for a new branch from a loaded state
        (autoplay_branch.py). The overworld SP baseline and the lowest SP
        carry over: every branch must poll at the same depth as the others."""
        self.anomalies = []
        self.detector_health = {}
        self.counts = {}
        self._seen = set()
        self.first_anomaly_state = None
        self.crash = None
        self.world_pending = True
        self.battle_party_checked = False

    # -------------------------------------------------------------- reporting

    def anomaly(self, check: str, detail: str, **data) -> None:
        self.counts[check] = self.counts.get(check, 0) + 1
        if (check, detail) in self._seen or len(self.anomalies) >= MAX_ANOMALIES:
            return
        self._seen.add((check, detail))
        entry = {"frame": self.h.pyboy.frame_count, "check": check, "detail": detail,
                 "map": self.agent.map_name(self.h.read8("hCurMap")), **data}
        self.anomalies.append(entry)
        self.agent.event("anomaly", **{k: v for k, v in entry.items() if k != "frame"})
        if self.first_anomaly_state is None:
            state = io.BytesIO()
            self.h.save_state(state)
            self.first_anomaly_state = state.getvalue()

    def summary(self) -> dict[str, object]:
        return {
            "anomaly_counts": self.counts,
            "detector_health": {name: {"enabled": True,
                "status": "error" if self.detector_health.get(name, {}).get("errors") else
                          "observed" if self.detector_health.get(name, {}).get("returned") else "unreached",
                **self.detector_health.get(name, {"attempted": 0, "returned": 0, "errors": 0})}
                for name in CORE},
            "crash": self.crash,
            "crash_vector_hook": {'enabled': True, 'available': True, 'status': 'armed'},
            "overworld_sp": {f"${sp:04X}": n for sp, n in sorted(self.overworld_sp.items())},
            "lowest_sp_seen": f"${self.lowest_sp:04X}",
            "stack_bytes_free_at_lowest": self.lowest_sp - (self.stack_top - STACK_SIZE),
        }

    # ----------------------------------------------------------------- crashes

    def _where(self, address: int) -> dict[str, object]:
        if address < 0x4000:
            bank = 0
        elif address < 0x8000:
            bank = self.h.read8("hLoadedROMBank")
        else:
            return {"address": f"${address:04X}", "label": None}
        return {"address": f"{bank:02X}:{address:04X}", "label": self.h.symbols.nearest(bank, address)}

    def _on_crash_vector(self, _context) -> None:
        if self.crash is not None:
            return
        memory = self.h.pyboy.memory
        sp = self.h.pyboy.register_file.SP
        words = [memory[sp + 2 * i] | memory[sp + 2 * i + 1] << 8 for i in range(CRASH_STACK_WORDS + 1)]
        # The rst that brought us here pushed the address after itself.
        self.crash = {
            "kind": "rst $38",
            "detail": "jumped into $FF padding, NULL or garbage",
            "from": self._where((words[0] - 1) & 0xFFFF),
            "sp": f"${sp:04X}",
            "stack": [self._where(word) for word in words[1:]],
        }

    def _in_sp_trick(self, pc: int, sp: int) -> bool:
        bank = 0 if pc < 0x4000 else self.h.read8("hLoadedROMBank")
        if any(bank == r_bank and start <= pc < end for r_bank, start, end in self.sp_trick_ranges):
            return True
        if self.h.hardware_mode != "CGB":
            return False
        # These routines save their actual stack in hSPTemp before pointing SP
        # at a tile or palette buffer. Reject a bad saved pointer or a live SP
        # that leaves the exact data source window.
        saved_sp = self.h.read8("hSPTemp") << 8 | self.h.read8("hSPTemp", 1)
        if not self.stack_top - STACK_SIZE <= saved_sp <= self.stack_top:
            return False
        return any(bank == r_bank and start <= pc < end
                   and source_start <= sp <= source_end
                   and (sp - source_start) % 2 == 0
                   for r_bank, start, end, source_start, source_end in self.sp_copy_windows)

    @observed_check
    def after_step(self) -> None:
        """Between agent steps: the CPU must be in ROM (or HRAM's OAM DMA
        routine) with SP inside the stack, bar the known map/palette copies
        that borrow SP to pop data."""
        if self.crash is not None:
            return
        registers = self.h.pyboy.register_file
        pc, sp = registers.PC, registers.SP
        if 0x8000 <= pc < 0xFF80:
            self.crash = {"kind": "pc_in_ram", "detail": f"executing ${pc:04X}, outside ROM",
                          "sp": f"${sp:04X}", "stack": [self._where(self._word(sp + 2 * i))
                                                        for i in range(CRASH_STACK_WORDS)]}
            return
        if self.stack_top - STACK_SIZE <= sp <= self.stack_top:
            self.stack_armed = True
            self.lowest_sp = min(self.lowest_sp, sp)
        elif self.stack_armed and not self._in_sp_trick(pc, sp):
            self.crash = {"kind": "stack_out_of_range", "detail": f"SP ${sp:04X} outside the stack",
                          "pc": self._where(pc)}
            return
        # 0 is a real value: CopyVideoData selects bank 0 for ROM0 sources.
        bank = self.h.read8("hLoadedROMBank")
        if self.stack_armed and bank >= self.rom_banks:
            self.anomaly("rom_bank", f"hLoadedROMBank is ${bank:02X}, past the ROM's {self.rom_banks} banks",
                         pc=self._where(pc))

    def _word(self, address: int) -> int:
        memory = self.h.pyboy.memory
        return memory[address & 0xFFFF] | memory[(address + 1) & 0xFFFF] << 8

    @observed_check
    def _on_overworld_poll(self, _context) -> None:
        sp = self.h.pyboy.register_file.SP
        if self.overworld_sp and sp not in self.overworld_sp:
            usual = max(self.overworld_sp, key=self.overworld_sp.get)
            self.anomaly("overworld_stack_depth", f"SP ${sp:04X}, usually ${usual:04X}",
                         stack=[self._where(self._word(sp + 2 * i)) for i in range(CRASH_STACK_WORDS)])
        self.overworld_sp[sp] = self.overworld_sp.get(sp, 0) + 1
        # The data checks run here, at the poll itself, not at an agent step
        # that merely follows one: the map script runs right after the poll,
        # and a step can land mid-routine. Measured 2026-10-20: seed 11's
        # cemetery theft was checked halfway through _RemovePokemon's struct
        # shift (species list compacted, structs not yet), a false anomaly.
        if self.world_pending:
            self.world_pending = False
            self.check_world()

    # ------------------------------------------------------------- data checks

    def on_map_change(self) -> None:
        self.world_pending = True

    def on_battle_end(self) -> None:
        self.world_pending = True
        self.battle_party_checked = False

    @observed_check
    def check_world(self) -> None:
        self.check_party()
        self.check_items()
        self.check_map()

    def _mon_problems(self, base: int, *, check_pp: bool) -> list[str]:
        memory = self.h.pyboy.memory
        problems = []
        species = memory[base + MON_SPECIES]
        if species not in self.species:
            problems.append(f"species ${species:02X}")
        level = memory[base + MON_LEVEL]
        if not 1 <= level <= MAX_LEVEL:
            problems.append(f"level {level}")
        hp = memory[base + MON_HP] << 8 | memory[base + MON_HP + 1]
        max_hp = memory[base + MON_MAXHP] << 8 | memory[base + MON_MAXHP + 1]
        if max_hp == 0 or hp > max_hp:
            problems.append(f"HP {hp}/{max_hp}")
        moves = [memory[base + MON_MOVES + i] for i in range(NUM_MOVES)]
        if moves[0] == 0:
            problems.append("no moves")
        if any(move > self.num_moves for move in moves):
            problems.append(f"move ids {moves}")
        if any(moves[i] == 0 and moves[i + 1] for i in range(NUM_MOVES - 1)):
            problems.append(f"gap in moves {moves}")
        known = [move for move in moves if move]
        if len(set(known)) != len(known):
            problems.append(f"duplicate moves {moves}")
        if check_pp:
            for slot, move in enumerate(moves):
                pp = memory[base + MON_PP + slot]
                current, ups = pp & 0x3F, pp >> 6
                if move == 0 or move > self.num_moves:
                    if pp:
                        problems.append(f"PP {pp:#04x} in empty slot {slot + 1}")
                    continue
                base_pp = self.base_pp[move]
                if current > min(base_pp + ups * (base_pp // 5), 61):
                    problems.append(f"slot {slot + 1} PP {current} over max for move {move}")
        return problems

    def _check_party_list(self, check: str, count_label: str, species_label: str, mon_label: str,
                          *, minimum: int, check_pp: bool) -> None:
        count = self.h.read8(count_label)
        if not minimum <= count <= PARTY_LENGTH:
            self.anomaly(check, f"party count {count}")
            return
        listed = self.h.read_bytes(species_label, count + 1)
        if listed[count] != 0xFF:
            self.anomaly(check, f"species list not terminated after {count}: {list(listed)}")
        base = self.h.address(mon_label)
        for slot in range(count):
            mon = base + slot * PARTYMON_STRUCT_LENGTH
            if listed[slot] != self.h.pyboy.memory[mon + MON_SPECIES]:
                self.anomaly(check, f"slot {slot + 1} listed as ${listed[slot]:02X} "
                             f"but holds ${self.h.pyboy.memory[mon + MON_SPECIES]:02X}")
            for problem in self._mon_problems(mon, check_pp=check_pp):
                self.anomaly(check, f"slot {slot + 1} "
                             f"({self.agent.species_names.get(listed[slot], listed[slot])}): {problem}")

    @observed_check
    def check_party(self) -> None:
        self._check_party_list("party", "wPartyCount", "wPartySpecies", "wPartyMon1",
                               minimum=0, check_pp=True)
        count = min(self.h.read8("wPartyCount"), PARTY_LENGTH)
        nicks = self.h.read_bytes("wPartyMonNicks", PARTY_LENGTH * NAME_LENGTH)
        for slot in range(count):
            if TEXT_TERMINATOR not in nicks[slot * NAME_LENGTH:(slot + 1) * NAME_LENGTH]:
                self.anomaly("party", f"slot {slot + 1} nickname not terminated")

    @observed_check
    def check_items(self) -> None:
        for label, used, slots in self.pockets:
            counts = self.h.read_bytes(label, slots)
            for index, count in enumerate(counts):
                if index >= used and count:
                    self.anomaly("items", f"{label}+{index} is {count}, past the {used} items in its table")
                elif count > MAX_ITEM_COUNT:
                    self.anomaly("items", f"{label}+{index} holds {count}")
        self.check_key_items()
        money = self.h.read_bytes("wPlayerMoney", 3)
        if any(byte >> 4 > 9 or byte & 0xF > 9 for byte in money):
            self.anomaly("money", f"not BCD: {bytes(money).hex()}")

    @observed_check
    def check_key_items(self) -> None:
        """sKeyItemsBitfield (SRAM): item N owns bits 2N (owned) and 2N+1
        (active); at most KEY_ITEM_MAX_ACTIVE active, each of them owned, and
        no tier in sKeyItemTiers above the vendors' cap."""
        field = int.from_bytes(bytes(self.h.read_sram_bytes("sKeyItemsBitfield", 4)), "little")
        tiers = int.from_bytes(bytes(self.h.read_sram_bytes("sKeyItemTiers", 4)), "little")
        active = [name for name, bit in self.key_item_bits.items() if field >> (bit + 1) & 1]
        if len(active) > self.key_item_max_active:
            self.anomaly("key_items", f"{len(active)} key items active, at most {self.key_item_max_active}: {active}")
        for name in active:
            if not field >> self.key_item_bits[name] & 1:
                self.anomaly("key_items", f"{name} active but not owned")
        for name, bit in self.key_item_bits.items():
            if tiers >> bit & 3 > KEY_ITEM_MAX_TIER:
                self.anomaly("key_items", f"{name} at tier {tiers >> bit & 3}")

    @observed_check
    def check_map(self) -> None:
        current = self.h.read8("hCurMap")
        if current >= self.num_maps:
            self.anomaly("map", f"hCurMap ${current:02X}")
            return
        last = self.h.read8("wLastMap")
        if last >= self.num_maps:
            self.anomaly("map", f"wLastMap ${last:02X}")
        warps = self.h.read8("wNumberOfWarps")
        if warps > MAX_WARP_EVENTS:
            self.anomaly("warps", f"{warps} warps")
            return
        # A warp off the map is not checked: maps park warps they disable
        # there (CeruleanTrashedHouse's wall hole, Route 9's fourth warp, the
        # facility's unused pads at Y $FF), and one can never trigger.
        for index, (_y, _x, _warp_id, dest) in enumerate(self.h.warp_entries()[:warps]):
            if dest >= self.num_maps and dest not in SPECIAL_WARP_MAPS:
                self.anomaly("warps", f"warp {index} leads to map ${dest:02X}")

    @observed_check
    def _on_battle_menu(self, _context) -> None:
        for label, side in (("wBattleMonMoves", "player"), ("wEnemyMonMoves", "enemy")):
            moves = self.h.read_bytes(label, NUM_MOVES)
            if moves[0] == 0:
                self.anomaly("battle", f"{side}'s active mon has no moves")
            elif any(move > self.num_moves for move in moves):
                self.anomaly("battle", f"{side}'s active mon has move ids {list(moves)}")
        for prefix, side in (("wBattleMon", "player"), ("wEnemyMon", "enemy")):
            hp = self.h.read8(f"{prefix}HP") << 8 | self.h.read8(f"{prefix}HP", 1)
            max_hp = self.h.read8(f"{prefix}MaxHP") << 8 | self.h.read8(f"{prefix}MaxHP", 1)
            if hp > max_hp:
                self.anomaly("battle", f"{side}'s active mon HP {hp}/{max_hp}")
        # The trainer's party, once per battle. Outside battle these bytes are
        # the item pockets' list buffers, and a wild battle uses one slot.
        if not self.battle_party_checked and self.h.read8("wIsTrainerBattle"):
            self.battle_party_checked = True
            self._check_party_list("enemy_party", "wEnemyPartyCount", "wEnemyPartySpecies",
                                   "wEnemyMon1", minimum=1, check_pp=False)
