"""Just enough SM83 decoding for the coverage map: an instruction's length and
where control can go straight after it.

`first_step(rom, bank, address)` decodes the instruction at a ROM location and
returns its successors as (address, certain) pairs: `certain` when control
always goes there next (a fall-through, an unconditional jr/jp/call/rst),
false for either side of a conditional branch. ret, reti and jp hl have no
static successor.
"""
from __future__ import annotations

from dataclasses import dataclass

TWO_BYTE = {0x06, 0x0E, 0x16, 0x1E, 0x26, 0x2E, 0x36, 0x3E, 0x10, 0x18, 0x20, 0x28, 0x30, 0x38,
            0xC6, 0xCE, 0xD6, 0xDE, 0xE6, 0xEE, 0xF6, 0xFE, 0xE0, 0xF0, 0xE8, 0xF8, 0xCB}
THREE_BYTE = {0x01, 0x11, 0x21, 0x31, 0x08, 0xC2, 0xC3, 0xCA, 0xD2, 0xDA,
              0xC4, 0xCC, 0xCD, 0xD4, 0xDC, 0xEA, 0xFA}
JR_COND = {0x20, 0x28, 0x30, 0x38}
JP_COND = {0xC2, 0xCA, 0xD2, 0xDA}
CALL_COND = {0xC4, 0xCC, 0xD4, 0xDC}
RET_COND = {0xC0, 0xC8, 0xD0, 0xD8}
RST = {0xC7, 0xCF, 0xD7, 0xDF, 0xE7, 0xEF, 0xF7, 0xFF}
NO_SUCCESSOR = {0xC9, 0xD9, 0xE9}  # ret, reti, jp hl


@dataclass
class Step:
    opcode: int
    length: int
    kind: str  # flow, jr, jp, call, rst, branch (conditional), ret
    successors: list[tuple[int, bool]]


def rom_offset(bank: int, address: int) -> int:
    return address if address < 0x4000 else bank * 0x4000 + (address - 0x4000)


def length(opcode: int) -> int:
    return 3 if opcode in THREE_BYTE else 2 if opcode in TWO_BYTE else 1


def first_step(rom: bytes, bank: int, address: int) -> Step:
    at = rom_offset(bank, address)
    opcode = rom[at]
    size = length(opcode)
    after = address + size
    if size == 2:
        relative = rom[at + 1] - 256 if rom[at + 1] >= 128 else rom[at + 1]
    word = rom[at + 1] | rom[at + 2] << 8 if size == 3 else None
    if opcode == 0x18:
        return Step(opcode, size, "jr", [(after + relative, True)])
    if opcode in JR_COND:
        return Step(opcode, size, "branch", [(after + relative, False), (after, False)])
    if opcode == 0xC3:
        return Step(opcode, size, "jp", [(word, True)])
    if opcode in JP_COND:
        return Step(opcode, size, "branch", [(word, False), (after, False)])
    if opcode == 0xCD:
        return Step(opcode, size, "call", [(word, True)])
    if opcode in CALL_COND:
        return Step(opcode, size, "branch", [(word, False), (after, False)])
    if opcode in RET_COND:
        return Step(opcode, size, "branch", [(after, False)])
    if opcode in RST:
        return Step(opcode, size, "rst", [(opcode & 0x38, True)])
    if opcode in NO_SUCCESSOR:
        return Step(opcode, size, "ret", [])
    return Step(opcode, size, "flow", [(after, True)])
