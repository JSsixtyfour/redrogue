"""Garbled-screen checks for autoplay runs: text and graphics read through a
bad pointer or from the wrong ROM bank.

A wrong text pointer or bank does not crash; it prints whatever bytes are
there. A wrong graphics source loads tiles made of code. These checks look
where the game takes those pointers:

- text_far: the 3-byte target (address, bank) of every TX_FAR must be a label
  in a real bank, and its first byte a valid text command.
- text pointers: TextCommandProcessor's hl and PlaceString's de, when in ROM,
  must not point into code in the bank loaded at the time (a wrong bank
  usually lands in another routine). Neither has to be a label: PlaceString
  gets a pointer into a text after each command, and the Pokedex prints an
  entry's text from just past its name, height and weight (DexEntry+9).
- text commands: the byte NextTextCommand dispatches must be a TX_* command
  (TX_START..TX_FAR); anything else runs off the jump table or into SOUND.
- glyphs: every byte PlaceNextChar writes to the tile map must be a real tile
  (>= $60); control codes the engine does not handle and $00-$48 are what
  garbage looks like. NullChar (the "<NULL>" char's TEXT ID ERROR leftover)
  counts too.
- graphics: CopyVideoData*, FarCopyData* sources in ROM must not lie inside
  code (coverage_inventory's code labels): tiles copied from code are garbled.
- enemy_pic: the enemy's front pic (LoadMonFrontSprite called from
  LoadEnemyFrontSprite or InitWildBattle) must be its own species' pic for its
  form (the form record's, from MON_CATCH_RATE bits 5-6). Found 2026-10-20: a
  trainer's form mon sent out after a faint showed the base species (Erika's
  Toedscruel as a Tentacruel), because EnemySendOut reloaded the header after
  the one-shot form context was spent.

Each finding is a checks.anomaly; record=True instead counts every pointer
seen by kind and verdict, to measure a check before trusting it. Measured
2026-10-20 over 6 runs (Debug 2 and new game, --vary): 570k glyphs, 62k
commands, 35k text pointers, 19k text_far, 62k strings and 72k copies, with no
finding once PlaceString was moved to the code rule. The first nightly's
random-input branches then opened the Pokedex, whose entries print from
DexEntry+9, so text pointers moved to the code rule too.

The code rules need coverage_inventory's code labels, a ~70 s source walk
when the .sym changed. autoplay.play() and the batch runners build them first;
elsewhere (smoke tests) they run only if already cached, or with `code` given.
"""
from __future__ import annotations

import re
from bisect import bisect_right

import coverage_inventory
from source_constants import parse_rgbds_constants

TX_FAR = 0x17
TX_LAST = TX_FAR
FIRST_GLYPH = 0x60  # $60-$FF: font_extra and the font (constants/charmap.asm)
ROM_END = 0x8000
def visible_palette_rows_are_sane(rows: list[tuple[int, ...]]) -> bool:
    """Whether at least one palette used by visible BG tiles has color steps.

    Values are the CGB's 15-bit colors. Grayscale rows pass when they contain
    distinct shades; only fully uniform visible rows are rejected.
    """
    return len({color for row in rows for color in row}) > 1


def uniform_dmg_palette_mapping(value: int) -> bool:
    """Whether rBGP maps every pixel shade to the same palette entry."""
    return len({(value >> shift) & 0x03 for shift in (0, 2, 4, 6)}) == 1


def read_cgb_bg_palette(memory, palette: int) -> tuple[int, ...]:
    """Read one BG palette row as four 15-bit colors, preserving BGPI."""
    if not 0 <= palette < 8:
        raise ValueError(f"BG palette must be 0-7, got {palette}")
    old_index = memory[0xFF68]
    try:
        colors = []
        for color in range(4):
            index = palette * 8 + color * 2
            memory[0xFF68] = index
            low = memory[0xFF69]
            memory[0xFF68] = index + 1
            high = memory[0xFF69]
            colors.append(low | high << 8)
        return tuple(colors)
    finally:
        memory[0xFF68] = old_index


class ScreenChecks:
    def __init__(self, checks, *, record: bool = False, code: list[dict[str, object]] | None = None):
        self.checks = checks
        self.h = checks.h
        self.mem = self.h.pyboy.memory
        self.record = record
        self.seen: dict[str, dict[str, int]] = {}  # record mode: kind -> verdict -> count
        self.calls: dict[str, int] = {}  # pointers checked per kind
        self.code_rule_observations = 0
        self.unchecked_calls = {}
        self.palette_reload = 0
        self.palette_checked: set[tuple[int, int]] = set()
        self.palette_checked_maps: set[int] = set()
        self.palette_skip_reasons: dict[str, int] = {}
        self.palette_counts = {"samples": 0, "passed": 0, "failed": 0, "skipped": 0}
        symbols = self.h.symbols
        self.labels = {(bank, address) for bank, entries in symbols._by_bank.items()
                       for address, _ in entries}
        self.rom_banks = checks.rom_banks
        # Code spans per bank: [code label, next label of any kind).
        self.code_spans: dict[int, list[tuple[int, int]]] = {}
        if code is None:
            code = coverage_inventory.cached_code_labels(self.h.rom_name)
        self.code_checks = code is not None
        code = {(label["bank"], label["address"]) for label in code or ()}
        for bank, entries in symbols._by_bank.items():
            starts = sorted({address for address, _ in entries})
            spans = []
            for i, address in enumerate(starts):
                if (bank, address) in code and address < ROM_END:
                    spans.append((address, starts[i + 1] if i + 1 < len(starts) else ROM_END))
            self.code_spans[bank] = spans
        self.span_starts = {bank: [start for start, _ in spans] for bank, spans in self.code_spans.items()}

        # PlaceNextChar's store: `ld [hli], a` then `call PrintLetterDelay`, just before NextChar.
        _, next_char = symbols.get("NextChar")
        place = next_char - 4
        if self.mem[0, place] not in (0x22, 0xDB) or self.mem[0, place + 1] != 0xCD:  # $DB: hooked already
            raise RuntimeError(f"PlaceNextChar's store is not at ${place:04X}; update autoplay_screen")
        self.h._register_at((0, place), self._on_place_char)
        self.h.register_hook("NullChar", self._on_null_char)
        self.h.register_hook("TextCommandProcessor", self._on_text_processor)
        self.h.register_hook("NextTextCommand.TextCommand", self._on_text_command)
        self.h.register_hook("TextCommand_FAR", self._on_text_far)
        self.h.register_hook("PlaceString", self._on_place_string)
        for label in ("CopyVideoData", "CopyVideoDataDouble", "CopyVideoDataPaced"):
            self.h.register_hook(label, self._on_copy_video)
        for label in ("FarCopyData", "FarCopyData2", "FarCopyDataDouble"):
            self.h.register_hook(label, self._on_far_copy)
        self.front_pics = self._front_pics()
        # Return addresses of the enemy's front-pic loads: the instruction after
        # each `call LoadMonFrontSprite` (3 bytes) in these two routines.
        self.enemy_pic_returns = set()
        for caller in ("LoadEnemyFrontSprite", "InitWildBattle"):
            bank, start, end = symbols.routine_range(caller)
            for address in range(start, end - 2):
                if (self._rom_byte(bank, address) == 0xCD
                        and self._rom_byte(bank, address + 1) | self._rom_byte(bank, address + 2) << 8
                        == symbols.address("LoadMonFrontSprite")):
                    self.enemy_pic_returns.add((bank, address + 3))
        self.h.register_hook("LoadMonFrontSprite", self._on_front_pic)
        self.h.register_hook("JoypadOverworld", self._check_visible_palette)
        self.h.register_hook("LoadMapData", self._on_map_reload)

    def summary(self) -> dict[str, object]:
        """Visible BG palette checks performed during an autoplay run."""
        return {"enabled": self.h.hardware_mode == "CGB", **self.palette_counts,
                "pointer_calls": {kind: count - self.unchecked_calls.get(kind, 0) for kind, count in self.calls.items()},
                "unchecked_calls": dict(self.unchecked_calls), "code_rules_available": self.code_checks,
                "code_rule_observations": self.code_rule_observations,
                "maps_checked": sorted(self.palette_checked_maps),
                "map_loads_checked": len(self.palette_checked),
                "skip_reasons": dict(sorted(self.palette_skip_reasons.items()))}

    def _skip_palette_check(self, reason: str) -> None:
        self.palette_counts["skipped"] += 1
        self.palette_skip_reasons[reason] = self.palette_skip_reasons.get(reason, 0) + 1

    def _on_map_reload(self, _context) -> None:
        self.palette_reload += 1

    def _visible_bg_palette_indices(self, lcdc: int) -> list[int]:
        """Return CGB palette IDs attached to BG tiles in the visible 20x18 area."""
        memory = self.h.pyboy.memory
        tilemap = 0x9C00 if lcdc & 0x08 else 0x9800
        tile_x, tile_y = memory[0xFF43] // 8, memory[0xFF42] // 8
        old_vbk = memory[0xFF4F] & 1
        try:
            memory[0xFF4F] = 1  # tile attributes occupy VRAM bank 1
            attributes = [memory[tilemap + ((tile_y + row) & 31) * 32 + ((tile_x + col) & 31)]
                          for row in range(18) for col in range(20)]
        finally:
            memory[0xFF4F] = old_vbk
        return sorted({attribute & 0x07 for attribute in attributes})

    def _read_bg_palette(self, palette: int) -> tuple[int, ...]:
        return read_cgb_bg_palette(self.h.pyboy.memory, palette)

    def _check_visible_palette(self, _context) -> None:
        """Check screen-used BG palettes at a safe input poll on each map load."""
        if self.h.hardware_mode != "CGB":
            return
        map_id = self.h.read8("hCurMap")
        load = (map_id, self.palette_reload)
        if load in self.palette_checked:
            return
        if (self.h.read8("hIsInBattle") or self.h.read8("hJoyIgnore") & 0xF0
                or self.h.read8("hSimulatedJoypadStatesIndex")):
            self._skip_palette_check("input not at idle overworld poll")
            return
        memory = self.h.pyboy.memory
        lcdc = memory[0xFF40]
        if not lcdc & 0x80 or not lcdc & 0x01:
            self._skip_palette_check("LCD or BG disabled")
            return
        if memory[0xFF41] & 0x03 == 0x03:
            self._skip_palette_check("PPU drawing visible line")
            return
        bgp = memory[0xFF47]
        if uniform_dmg_palette_mapping(bgp):
            self._skip_palette_check("uniform rBGP fade mapping")
            return
        indices = self._visible_bg_palette_indices(lcdc)
        if not indices:
            self._skip_palette_check("no visible BG tiles")
            return
        self.palette_checked.add(load)
        self.palette_checked_maps.add(map_id)
        rows = [self._read_bg_palette(index) for index in indices]
        self.palette_counts["samples"] += 1
        if visible_palette_rows_are_sane(rows):
            self.palette_counts["passed"] += 1
        else:
            self.palette_counts["failed"] += 1
            self._note("palette", "visible BG palettes are uniform",
                       f"map ${map_id:02X} load {self.palette_reload}: palette IDs {indices} "
                       "each contain one repeated color")

    def _front_pics(self) -> dict[tuple[int, int], tuple[int, int]]:
        """(species, form) -> (bank, address) of its front pic, from the base
        stats files (form 0) and the form records."""
        root = self.h.repo_root
        species = parse_rgbds_constants(root / "constants/pokemon_constants.asm")
        pics = {}
        for folder, key in (("base_stats", None), ("forms", "form")):
            for path in (root / "data/pokemon" / folder).glob("*.asm"):
                text = path.read_text(encoding="utf-8")
                pic = re.search(r"dw\s+(\w+PicFront)", text)
                if key:
                    which = re.search(r"form_record\s+(\w+),\s*(\d+)", text)
                    name, form = (which.group(1), int(which.group(2))) if which else (None, 0)
                else:
                    which = re.search(r"db\s+DEX_(\w+)", text)
                    name, form = (which.group(1) if which else None), 0
                if pic and name in species and pic.group(1) in self.h.symbols._symbols:
                    pics[(species[name], form)] = self.h.symbols.get(pic.group(1))
        return pics

    # ---------------------------------------------------------------- helpers

    def _note(self, kind: str, verdict: str, detail: str, **data) -> None:
        self.calls[kind] = self.calls.get(kind, 0) + 1
        if self.record:
            bucket = self.seen.setdefault(kind, {})
            key = verdict if verdict == "ok" else f"{verdict}: {detail}"
            bucket[key] = bucket.get(key, 0) + 1
        elif verdict != "ok":
            self.checks.anomaly(f"screen_{kind}", f"{verdict}: {detail}", **data)

    def _bank_for(self, address: int) -> int:
        return 0 if address < 0x4000 else self.h.read8("hLoadedROMBank")

    def _where(self, bank: int, address: int) -> str:
        if address >= ROM_END:
            return f"${address:04X}"
        return f"{bank:02X}:{address:04X} {self.h.symbols.nearest(bank, address)}"

    def _rom_byte(self, bank: int, address: int) -> int:
        return self.mem[bank, address] if address >= 0x4000 else self.mem[0, address]

    def _in_code(self, bank: int, address: int) -> bool:
        starts = self.span_starts.get(bank, [])
        i = bisect_right(starts, address) - 1
        return i >= 0 and address < self.code_spans[bank][i][1]

    # ----------------------------------------------------------------- checks
    # Each takes plain values, so a test can plant a fault without the game.

    def check_glyph(self, char: int, source: int) -> None:
        if char >= FIRST_GLYPH:
            self._note("glyph", "ok", "")
        else:
            self._note("glyph", "placed a control or non-glyph byte",
                       f"${char:02X} from " + self._where(self._bank_for(source), source))

    def check_text_command(self, command: int, source: int) -> None:
        if command <= TX_LAST:
            self._note("text_command", "ok", "")
        else:
            self._note("text_command", "not a TX_ command",
                       f"${command:02X} at " + self._where(self._bank_for(source), source))

    def check_text_far(self, pointer: int) -> None:
        """`pointer`: the 3 bytes after a TX_FAR (address, then bank)."""
        bank_now = self._bank_for(pointer)
        read = (lambda a: self.mem[a]) if pointer >= ROM_END else (lambda a: self._rom_byte(bank_now, a))
        target = read(pointer) | read(pointer + 1) << 8
        bank = read(pointer + 2)
        site = self._where(bank_now, pointer - 1)
        if bank >= self.rom_banks or not 0x4000 <= target < ROM_END and not (bank == 0 and target < 0x4000):
            self._note("text_far", "bad target", f"{bank:02X}:{target:04X} from {site}")
        elif (bank if target >= 0x4000 else 0, target) not in self.labels:
            self._note("text_far", "target not a label", f"{self._where(bank, target)} from {site}")
        elif (first := self._rom_byte(bank, target)) > TX_LAST and first != 0x50:
            self._note("text_far", "target does not start with a text command",
                       f"${first:02X} at {self._where(bank, target)} from {site}")
        else:
            self._note("text_far", "ok", "")

    def check_source(self, kind: str, bank: int, source: int) -> None:
        """A ROM source (graphics, a copy, a string) must not lie inside code."""
        self.code_rule_observations = getattr(self, 'code_rule_observations', 0) + 1
        if source >= ROM_END:
            self._note(kind, "ok", "")
            return
        if source < 0x4000:
            bank = 0
        if bank >= self.rom_banks:
            self._note(kind, "bad bank", f"{bank:02X}:{source:04X}")
        elif self._in_code(bank, source):
            self._note(kind, "source inside code", self._where(bank, source))
        else:
            self._note(kind, "ok", "")

    # ------------------------------------------------------------------ hooks

    def _de(self) -> int:
        registers = self.h.pyboy.register_file
        return registers.D << 8 | registers.E

    def _on_place_char(self, _context) -> None:
        self.check_glyph(self.h.pyboy.register_file.A, self._de())

    def _on_null_char(self, _context) -> None:
        self._note("glyph", "<NULL> char (TEXT ID ERROR)",
                   self._where(self._bank_for(self._de()), self._de()) + f" hTextID ${self.h.read8('hTextID'):02X}")

    def _on_text_processor(self, _context) -> None:
        address = self.h.pyboy.register_file.HL
        if self.code_checks:
            self.check_source("text_pointer", self._bank_for(address), address)
        else:
            self.unchecked_calls['text_pointer'] = self.unchecked_calls.get('text_pointer', 0) + 1
            self._note("text_pointer", "ok", "")  # counted, unchecked: no code labels cached

    def _on_place_string(self, _context) -> None:
        if self.code_checks:
            self.check_source("string_pointer", self._bank_for(self._de()), self._de())

    def _on_text_command(self, _context) -> None:
        # NextTextCommand's ld a, [hli] has already stepped past the byte.
        self.check_text_command(self.h.pyboy.register_file.A, self.h.pyboy.register_file.HL - 1)

    def _on_text_far(self, _context) -> None:
        sp = self.h.pyboy.register_file.SP
        self.check_text_far(self.mem[sp] | self.mem[sp + 1] << 8)  # .TextCommand's push hl

    def _on_copy_video(self, _context) -> None:
        registers = self.h.pyboy.register_file
        if registers.C and self.code_checks:
            self.check_source("gfx_source", registers.B, self._de())

    def check_enemy_pic(self, species: int, form: int, bank: int, address: int) -> None:
        expected = self.front_pics.get((species, form))
        if expected is None:
            self.unchecked_calls['enemy_pic'] = self.unchecked_calls.get('enemy_pic', 0) + 1
            self._note("enemy_pic", "ok", "")  # a species or form without its own record
        elif expected != (bank, address):
            shown = self.h.symbols.nearest(bank, address)
            want = self.h.symbols.nearest(*expected)
            self._note("enemy_pic", "wrong front pic", f"species ${species:02X} form {form} showed {shown}, not {want}")
        else:
            self._note("enemy_pic", "ok", "")

    def _on_front_pic(self, _context) -> None:
        sp = self.h.pyboy.register_file.SP
        ret = self.mem[sp] | self.mem[sp + 1] << 8
        if (self._bank_for(ret), ret) not in self.enemy_pic_returns:
            return  # the status screen, the Pokedex, the fusion merge: not the enemy
        if self.h.read8("wEnemyBattleStatus3") & 1 << 3:  # TRANSFORMED: shows its target
            return
        form = (self.h.read8("wEnemyMonCatchRate") & 0x60) >> 5  # FORM_MASK, MON_CATCH_RATE bits 5-6
        bank = self.h.read8("wMonHPicBank")
        address = self.h.read8("wMonHFrontSprite") | self.h.read8("wMonHFrontSprite", offset=1) << 8
        self.check_enemy_pic(self.h.read8("wCurSpecies"), form, bank, address)

    def _on_far_copy(self, _context) -> None:
        registers = self.h.pyboy.register_file
        if (registers.B or registers.C) and self.code_checks:
            self.check_source("copy_source", registers.A, registers.HL)
