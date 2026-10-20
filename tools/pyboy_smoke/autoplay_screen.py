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

from bisect import bisect_right

import coverage_inventory

TX_FAR = 0x17
TX_LAST = TX_FAR
FIRST_GLYPH = 0x60  # $60-$FF: font_extra and the font (constants/charmap.asm)
ROM_END = 0x8000


class ScreenChecks:
    def __init__(self, checks, *, record: bool = False, code: list[dict[str, object]] | None = None):
        self.checks = checks
        self.h = checks.h
        self.mem = self.h.pyboy.memory
        self.record = record
        self.seen: dict[str, dict[str, int]] = {}  # record mode: kind -> verdict -> count
        self.calls: dict[str, int] = {}  # pointers checked per kind
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

    def _on_far_copy(self, _context) -> None:
        registers = self.h.pyboy.register_file
        if (registers.B or registers.C) and self.code_checks:
            self.check_source("copy_source", registers.A, registers.HL)
