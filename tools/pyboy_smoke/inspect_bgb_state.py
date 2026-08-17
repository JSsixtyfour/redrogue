from __future__ import annotations

from pathlib import Path
import struct
import sys


def read_chunks(path: Path) -> dict[str, bytes]:
    data = path.read_bytes()
    if not data.startswith(b"BGB1.0\0"):
        raise ValueError(f"{path} is not a BGB 1.x save state")

    chunks: dict[str, bytes] = {}
    offset = 11
    while offset < len(data):
        end = data.find(b"\0", offset)
        if end < 0 or end + 5 > len(data):
            break
        name = data[offset:end].decode("ascii")
        size = struct.unpack_from("<I", data, end + 1)[0]
        start = end + 5
        stop = start + size
        if stop > len(data):
            raise ValueError(f"truncated BGB chunk {name!r}")
        chunks[name] = data[start:stop]
        offset = stop
    return chunks


def word(value: bytes) -> int:
    return int.from_bytes(value, "little")


def read_symbols(path: Path) -> dict[int, list[tuple[int, str]]]:
    banks: dict[int, list[tuple[int, str]]] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if len(line) < 8 or line[2] != ":":
            continue
        location, _, name = line.partition(" ")
        try:
            bank_text, address_text = location.split(":")
            bank = int(bank_text, 16)
            address = int(address_text, 16)
        except ValueError:
            continue
        banks.setdefault(bank, []).append((address, name))
    for symbols in banks.values():
        symbols.sort()
    return banks


def nearest_symbol(
    symbols: dict[int, list[tuple[int, str]]], bank: int, address: int
) -> str:
    candidates = [entry for entry in symbols.get(bank, []) if entry[0] <= address]
    if not candidates:
        return "?"
    symbol_address, name = candidates[-1]
    return f"{name}+${address - symbol_address:x}"


def main() -> None:
    path = Path(sys.argv[1])
    chunks = read_chunks(path)
    symbols = read_symbols(Path(sys.argv[2])) if len(sys.argv) > 2 else None
    for name in ("AF", "BC", "DE", "HL", "PC", "SP", "IME", "rombank"):
        if name in chunks:
            print(f"{name}={word(chunks[name]):0{len(chunks[name]) * 2}x}")

    sp = word(chunks["SP"])
    wram = chunks["WRAM"]
    if 0xC000 <= sp < 0xE000 and len(wram) >= 0x2000:
        offset = sp - 0xC000
        stack = wram[offset : min(offset + 32, len(wram))]
        print(f"stack@{sp:04x}={stack.hex(' ')}")
        if symbols is not None:
            for stack_offset in range(0, len(stack) - 1, 2):
                address = word(stack[stack_offset : stack_offset + 2])
                bank = 0 if address < 0x4000 else -1
                if bank == 0:
                    location = nearest_symbol(symbols, bank, address)
                    print(f"  sp+{stack_offset:02x}: {address:04x} {location}")

    hram = chunks.get("HRAM")
    if hram is not None:
        print(f"HRAM={hram.hex(' ')}")
        for name, address in (
            ("hJoyPressed", 0xFFB3),
            ("hJoyHeld", 0xFFB4),
            ("hJoy5", 0xFFB5),
            ("hJoy6", 0xFFB6),
            ("hJoy7", 0xFFB7),
            ("hLoadedROMBank", 0xFFB8),
            ("hFrameCounter", 0xFFD5),
            ("hJoyIgnore", 0xFFF7),
            ("hSimulatedJoypadStatesIndex", 0xFFF9),
        ):
            offset = address - 0xFF80
            if offset < len(hram):
                print(f"{name}={hram[offset]:02x}")


if __name__ == "__main__":
    main()
