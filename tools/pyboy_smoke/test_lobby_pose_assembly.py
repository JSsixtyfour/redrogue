"""Actual-assembly tests for the isolated lobby pose transaction.

The fixture includes ``engine/overworld/lobby_pose.asm`` directly.  It gives
the one game symbol used by that source a fixed synthetic WRAM address and
drives both public entries through a tiny ROM mailbox.  Nothing in the game
RAM declarations or renderer is included here.
"""

from __future__ import annotations

import io
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


try:
    from pyboy import PyBoy
except ImportError:  # pragma: no cover - the smoke environment supplies PyBoy
    PyBoy = None  # type: ignore[assignment,misc]


REPO_ROOT = Path(__file__).resolve().parents[2]


class _LobbyPoseRom:
    """Build and run the current lobby pose source in a tiny ROM."""

    # Mailbox and fixed synthetic WRAM buffers.
    COMMAND = 0xC000
    COMPLETE = 0xC001
    RESULT_CARRY = 0xC002
    RESULT_A = 0xC003
    RESULT_B = 0xC004
    RESULT_C = 0xC005
    RESULT_D = 0xC006
    RESULT_E = 0xC007
    RESULT_H = 0xC008
    RESULT_L = 0xC009
    RESULT_LY = 0xC00A
    ARG0 = 0xC00B
    ARG1 = 0xC00C
    TARGET = 0xC00D
    READY = 0xC00E

    # wShadowOAM is deliberately the fixed address requested by the API.
    SHADOW_OAM = 0xC100
    STAGING = 0xC200
    OAM_SOURCE = 0xC300

    RESOLVE = 1
    COMMIT = 2
    COMMIT_AT_LINE = 3

    _FIXTURE = r'''
INCLUDE "includes.asm"

; This is the only game symbol referenced by the isolated source.
DEF wShadowOAM EQU $C100

DEF MAIL_COMMAND EQU $C000
DEF MAIL_COMPLETE EQU $C001
DEF MAIL_RESULT_CARRY EQU $C002
DEF MAIL_RESULT_A EQU $C003
DEF MAIL_RESULT_B EQU $C004
DEF MAIL_RESULT_C EQU $C005
DEF MAIL_RESULT_D EQU $C006
DEF MAIL_RESULT_E EQU $C007
DEF MAIL_RESULT_H EQU $C008
DEF MAIL_RESULT_L EQU $C009
DEF MAIL_RESULT_LY EQU $C00A
DEF MAIL_ARG0 EQU $C00B
DEF MAIL_ARG1 EQU $C00C
DEF MAIL_TARGET EQU $C00D
DEF MAIL_READY EQU $C00E
DEF POSE_STAGING EQU $C200
DEF POSE_OAM_SOURCE EQU $C300
DEF wLobbyPoseStagingTiles EQU POSE_STAGING
DEF wLobbyPoseStagingOAM EQU POSE_OAM_SOURCE

SECTION "Lobby pose test entry", ROM0[$100]
    nop
    jp LobbyPoseTestMain

; The source itself is kept in the test ROM's only banked section.  There are
; no bank-switch helpers or game callers hidden behind the fixture.
INCLUDE "engine/overworld/lobby_pose.asm"

SECTION "Lobby pose test dispatcher", ROMX
LobbyPoseTestMain::
    di
    ld sp, $DFFF
    xor a
    ld [MAIL_COMMAND], a
    ld [MAIL_COMPLETE], a
    ld a, $5A
    ld [MAIL_READY], a
.wait
    ld a, [MAIL_COMMAND]
    and a
    jr z, .wait
    ld b, a
    xor a
    ld [MAIL_COMMAND], a
    ld a, b
    cp 1
    jp z, .resolve
    cp 2
    jp z, .commit
    cp 3
    jp z, .commit_at_line
    ld a, $EE
    scf
    jp .report
.resolve
    ld a, [MAIL_ARG0]
    ld d, a
    ld a, [MAIL_ARG1]
    ld e, a
    ld bc, $A1B2
    ld hl, $C3D4
    call LobbyPoseResolve
    jp .report
.commit
    ld hl, POSE_STAGING
    ld de, POSE_OAM_SOURCE
    ld a, [MAIL_ARG0]
    ld b, a
    ld a, [MAIL_ARG1]
    ld c, a
    call LobbyPoseCommit
    jp .report
.commit_at_line
.line_wait
    ldh a, [rLY]
    ld d, a
    ld a, [MAIL_TARGET]
    cp d
    jr nz, .line_wait
    ld hl, POSE_STAGING
    ld de, POSE_OAM_SOURCE
    ld a, [MAIL_ARG0]
    ld b, a
    ld a, [MAIL_ARG1]
    ld c, a
    call LobbyPoseCommit
    jp .report
.report
    jr nc, .carry_clear
    ld a, 1
    jr .store_carry
.carry_clear
    xor a
.store_carry
    ld [MAIL_RESULT_CARRY], a
    ld a, b
    ld [MAIL_RESULT_B], a
    ld a, c
    ld [MAIL_RESULT_C], a
    ld a, d
    ld [MAIL_RESULT_D], a
    ld a, e
    ld [MAIL_RESULT_E], a
    ld a, h
    ld [MAIL_RESULT_H], a
    ld a, l
    ld [MAIL_RESULT_L], a
    ldh a, [rLY]
    ld [MAIL_RESULT_LY], a
    ld a, 0
    ld [MAIL_RESULT_A], a
    ld a, 1
    ld [MAIL_COMPLETE], a
    jp .wait
'''

    def __init__(self, temp_dir: Path):
        if PyBoy is None:
            raise unittest.SkipTest("PyBoy is unavailable")
        for tool in ("rgbasm", "rgblink", "rgbfix"):
            if shutil.which(tool) is None:
                raise unittest.SkipTest(f"{tool} is unavailable")

        self.source = temp_dir / "lobby_pose_fixture.asm"
        self.object = temp_dir / "lobby_pose_fixture.o"
        self.rom_path = temp_dir / "lobby_pose_fixture.gb"
        self.source.write_text(self._FIXTURE, encoding="utf-8")
        self._run(("rgbasm", "-Weverything", "-I", str(REPO_ROOT),
                   "-o", str(self.object), str(self.source)))
        self._run(("rgblink", "-o", str(self.rom_path), str(self.object)))
        self._run(("rgbfix", "-v", "-p", "0", str(self.rom_path)))
        self.pyboy = PyBoy(
            io.BytesIO(self.rom_path.read_bytes()),
            window="null",
            sound_emulated=False,
            cgb=False,
            log_level="CRITICAL",
        )
        self.pyboy.set_emulation_speed(0)
        self._wait_for_boot()

    @staticmethod
    def _run(command: tuple[str, ...]) -> None:
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(
                f"command failed ({result.returncode}): {' '.join(command)}\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )

    def close(self) -> None:
        self.pyboy.stop(save=False)

    def _wait_for_boot(self) -> None:
        for _ in range(120):
            self.pyboy.tick(render=False)
            if self.read8(self.READY) == 0x5A:
                return
        raise AssertionError("lobby pose fixture did not reach its mailbox loop")

    def read8(self, address: int) -> int:
        return self.pyboy.memory[address]

    def write8(self, address: int, value: int) -> None:
        self.pyboy.memory[address] = value & 0xFF

    def read_block(self, address: int, size: int) -> bytes:
        return bytes(self.read8(address + i) for i in range(size))

    def write_block(self, address: int, data: bytes) -> None:
        for offset, value in enumerate(data):
            self.write8(address + offset, value)

    def command(self, command: int, arg0: int = 0, arg1: int = 0,
                target: int = 0) -> dict[str, int | bool]:
        self.write8(self.COMPLETE, 0)
        self.write8(self.ARG0, arg0)
        self.write8(self.ARG1, arg1)
        self.write8(self.TARGET, target)
        self.write8(self.COMMAND, command)
        for _ in range(240):
            self.pyboy.tick(render=False)
            if self.read8(self.COMPLETE):
                return {
                    "carry": bool(self.read8(self.RESULT_CARRY)),
                    "a": self.read8(self.RESULT_A),
                    "b": self.read8(self.RESULT_B),
                    "c": self.read8(self.RESULT_C),
                    "d": self.read8(self.RESULT_D),
                    "e": self.read8(self.RESULT_E),
                    "h": self.read8(self.RESULT_H),
                    "l": self.read8(self.RESULT_L),
                    "ly": self.read8(self.RESULT_LY),
                }
        raise AssertionError(f"lobby pose fixture timed out on command {command}")

    def resolve(self, actor: int, image: int) -> dict[str, int | bool]:
        return self.command(self.RESOLVE, actor, image)

    def commit(self, base: int, offset: int, *, target: int | None = None
               ) -> dict[str, int | bool]:
        if target is None:
            return self.command(self.COMMIT, base, offset)
        return self.command(self.COMMIT_AT_LINE, base, offset, target)


class LobbyPoseAssemblyTest(unittest.TestCase):
    """Exercise the public ABI through assembled code and real PyBoy memory."""

    fixture: _LobbyPoseRom | None = None
    temp_dir: tempfile.TemporaryDirectory[str] | None = None

    ACTORS = {
        0: (0x00, "walker"),
        1: (0x24, "stationary"),
        2: (0x30, "stationary"),
        3: (0x30, "stationary"),
        4: (0x3C, "stationary"),
        5: (0x48, "stationary"),
        6: (0x54, "stationary"),
        7: (0x60, "stationary"),
        8: (0x6C, "cached"),
        9: (0x18, "walker"),
        10: (0x70, "cached"),
        11: (0x74, "cached"),
        15: (0x0C, "walker"),
    }

    @classmethod
    def setUpClass(cls) -> None:
        cls.temp_dir = tempfile.TemporaryDirectory(prefix="redrogue-lobby-pose-")
        try:
            cls.fixture = _LobbyPoseRom(Path(cls.temp_dir.name))
        except Exception:
            cls.temp_dir.cleanup()
            cls.temp_dir = None
            raise

    @classmethod
    def tearDownClass(cls) -> None:
        if cls.fixture is not None:
            cls.fixture.close()
        if cls.temp_dir is not None:
            cls.temp_dir.cleanup()

    def setUp(self) -> None:
        assert self.fixture is not None
        f = self.fixture
        f.write8(0xFF40, 0x00)  # LCD off gives deterministic immediate commits.
        f.write8(0xFF4F, 0x00)  # CGB VRAM bank zero is part of the ABI.
        # Keep every output's neighboring bytes distinctive.  The source's
        # contract intentionally does not claim pointer-range validation.
        for address in range(0x8000, 0x9000):
            f.write8(address, 0xD1)
        for address in range(f.SHADOW_OAM, f.SHADOW_OAM + 0xA0):
            f.write8(address, 0xD2)
        for address in range(0xFE00, 0xFEA0):
            f.write8(address, 0xD3)
        f.write_block(f.STAGING, bytes((0x40 + i) & 0xFF for i in range(64)))
        f.write_block(f.OAM_SOURCE, bytes((0x90 + i) & 0xFF for i in range(16)))

    @classmethod
    def _resolve_expected(cls, actor: int, image: int) -> tuple[int, int, int, int]:
        base, actor_kind = cls.ACTORS[actor]
        direction = image & 0x0C
        frame = image & 0x03
        xflip = 0
        if direction == 0x0C:
            source = 8
            xflip = 0x20
        else:
            source = direction
        if actor_kind == "walker" and frame & 1:
            source |= 0x80
            if frame == 3 and direction in (0, 4):
                xflip ^= 0x20
        physical = base if actor_kind == "cached" else base + source
        return physical, source, xflip, int(actor_kind == "cached")

    def _assert_resolve(self, actor: int, image: int) -> None:
        assert self.fixture is not None
        result = self.fixture.resolve(actor, image)
        expected_d, expected_e, expected_c, expected_b = self._resolve_expected(
            actor, image
        )
        self.assertFalse(result["carry"])
        self.assertEqual(result["d"], expected_d)
        self.assertEqual(result["e"], expected_e)
        self.assertEqual(result["c"], expected_c)
        self.assertEqual(result["b"], expected_b)
        self.assertEqual((result["h"], result["l"]), (0xC3, 0xD4))

    def test_all_low_nibble_poses_for_full_walkers_match_legacy_facings(self) -> None:
        for actor in (0, 9, 15):
            for low_nibble in range(16):
                with self.subTest(actor=actor, image=low_nibble):
                    self._assert_resolve(actor, low_nibble)

    def test_all_stationary_roster_indices_ignore_animation_frame(self) -> None:
        for actor in (*range(1, 9), 10, 11):
            for image in range(16):
                with self.subTest(actor=actor, image=image):
                    self._assert_resolve(actor, image)

    def test_normal_image_high_nibble_is_ignored_and_nurse_legacy_writes_map(self) -> None:
        assert self.fixture is not None
        for actor in self.ACTORS:
            for low_nibble in (0, 1, 4, 7, 8, 0xB, 0xC, 0xF):
                for high_nibble in (0x10, 0x20, 0xA0):
                    with self.subTest(actor=actor, image=high_nibble | low_nibble):
                        self._assert_resolve(actor, high_nibble | low_nibble)
        # The legacy nurse image IDs $18 and $14 must select left and up
        # standing tiles in the new physical nurse block.
        for image, physical, source in ((0x18, 0x2C, 8), (0x14, 0x28, 4)):
            with self.subTest(nurse_image=image):
                result = self.fixture.resolve(1, image)
                self.assertFalse(result["carry"])
                self.assertEqual((result["d"], result["e"]), (physical, source))

    def test_independent_clerks_keep_the_same_pose_policy_without_shared_state(self) -> None:
        assert self.fixture is not None
        for first_image, second_image in ((0, 0x0C), (4, 8), (0x0B, 0x03)):
            first = self.fixture.resolve(2, first_image)
            second = self.fixture.resolve(3, second_image)
            self.assertFalse(first["carry"])
            self.assertFalse(second["carry"])
            expected_first = self._resolve_expected(2, first_image)
            expected_second = self._resolve_expected(3, second_image)
            self.assertEqual((first["d"], first["e"], first["b"], first["c"]),
                             (expected_first[0], expected_first[1],
                              expected_first[3], expected_first[2]))
            self.assertEqual((second["d"], second["e"], second["b"], second["c"]),
                             (expected_second[0], expected_second[1],
                              expected_second[3], expected_second[2]))
            # Both clerk objects occupy the same full sheet, but each resolves
            # its own current facing and neither relies on a shared cache key.
            self.assertEqual(first["d"] - first["e"], 0x30)
            self.assertEqual(second["d"] - second["e"], 0x30)

    def test_invalid_actor_or_hidden_image_rejects_atomically_and_preserves_registers(self) -> None:
        assert self.fixture is not None
        for actor, image in ((12, 0), (13, 4), (14, 8), (16, 0), (255, 12),
                             (0, 0xFF), (15, 0xFF)):
            with self.subTest(actor=actor, image=image):
                result = self.fixture.resolve(actor, image)
                self.assertTrue(result["carry"])
                self.assertEqual(
                    (result["b"], result["c"], result["d"], result["e"],
                     result["h"], result["l"]),
                    (0xA1, 0xB2, actor, image, 0xC3, 0xD4),
                )

    def test_commit_preserves_registers_and_writes_only_requested_pose_and_oam(self) -> None:
        assert self.fixture is not None
        f = self.fixture
        for base in (0x6C, 0x70, 0x74):
            self.setUp()
            result = f.commit(base, 0x20)
            self.assertFalse(result["carry"])
            self.assertEqual((result["b"], result["c"]), (base, 0x20))
            self.assertEqual((result["d"], result["e"]), (0xC3, 0x00))
            self.assertEqual((result["h"], result["l"]), (0xC2, 0x00))
            self.assertEqual(f.read_block(0x8000 + base * 16, 64),
                             bytes((0x40 + i) & 0xFF for i in range(64)))
            self.assertEqual(f.read_block(f.SHADOW_OAM + 0x20, 16),
                             bytes((0x90 + i) & 0xFF for i in range(16)))
            self.assertEqual(f.read_block(0xFE20, 16),
                             bytes((0x90 + i) & 0xFF for i in range(16)))
            # The neighboring cache tile is reserved for healing overlays and
            # the upper half remains reserved for walking/font data.
            self.assertEqual(f.read8(0x8000 + 0x7C * 16), 0xD1)
            self.assertEqual(f.read8(0x8000 + 0x80 * 16), 0xD1)
            self.assertEqual(f.read8(f.SHADOW_OAM + 0x1F), 0xD2)
            self.assertEqual(f.read8(f.SHADOW_OAM + 0x30), 0xD2)
            self.assertEqual(f.read8(0xFE1F), 0xD3)
            self.assertEqual(f.read8(0xFE30), 0xD3)

    def test_actual_cached_sprite_bytes_fit_each_four_tile_cache(self) -> None:
        assert self.fixture is not None
        f = self.fixture
        assets = (("channeler.2bpp", 0x6C), ("super_nerd.2bpp", 0x70),
                  ("gameboy_kid.2bpp", 0x74))
        for name, base in assets:
            path = REPO_ROOT / "gfx" / "sprites" / name
            self.assertTrue(path.exists(), path)
            data = path.read_bytes()
            self.assertGreaterEqual(len(data), 64)
            for direction, source_tile in (("down", 0), ("up", 4),
                                           ("left", 8), ("right", 8)):
                with self.subTest(asset=name, direction=direction):
                    self.setUp()
                    staged = data[source_tile * 16:source_tile * 16 + 64]
                    self.assertEqual(len(staged), 64)
                    f.write_block(f.STAGING, staged)
                    result = f.commit(base, 0)
                    self.assertFalse(result["carry"], name)
                    self.assertEqual(f.read_block(0x8000 + base * 16, 64), staged)
                    self._assert_reserved_sprite_bytes_untouched(f)

            # A turn to the left and back to down must restore the exact
            # source bytes, while the font/healing ranges remain untouched.
            self.setUp()
            down = data[:64]
            left = data[8 * 16:8 * 16 + 64]
            f.write_block(f.STAGING, left)
            self.assertFalse(f.commit(base, 0)["carry"])
            f.write_block(f.STAGING, down)
            self.assertFalse(f.commit(base, 0)["carry"])
            self.assertEqual(f.read_block(0x8000 + base * 16, 64), down)
            self._assert_reserved_sprite_bytes_untouched(f)

    def _assert_reserved_sprite_bytes_untouched(self, f: _LobbyPoseRom) -> None:
        # 0x7c..0x7e is the healing overlay scratch and 0x80 onward is the
        # walking/font half.  The four-tile cache transfer must touch neither.
        self.assertEqual(f.read_block(0x8000 + 0x7C * 16, 3 * 16),
                         bytes([0xD1] * (3 * 16)))
        self.assertEqual(f.read_block(0x8000 + 0x80 * 16, 0x80 * 16),
                         bytes([0xD1] * (0x80 * 16)))

    def test_invalid_cache_base_or_oam_offset_rejects_before_any_write(self) -> None:
        assert self.fixture is not None
        f = self.fixture
        for base, offset in ((0x00, 0), (0x6D, 0), (0x78, 0), (0x6C, 1),
                             (0x6C, 0x0F), (0x6C, 0xA0), (0x6C, 0x91)):
            with self.subTest(base=base, offset=offset):
                self.setUp()
                before_vram = f.read_block(0x8000, 0x1000)
                before_shadow = f.read_block(f.SHADOW_OAM, 0xA0)
                before_oam = f.read_block(0xFE00, 0xA0)
                result = f.commit(base, offset)
                self.assertTrue(result["carry"])
                self.assertEqual((result["b"], result["c"]), (base, offset))
                self.assertEqual((result["d"], result["e"]), (0xC3, 0x00))
                self.assertEqual((result["h"], result["l"]), (0xC2, 0x00))
                self.assertEqual(f.read_block(0x8000, 0x1000), before_vram)
                self.assertEqual(f.read_block(f.SHADOW_OAM, 0xA0), before_shadow)
                self.assertEqual(f.read_block(0xFE00, 0xA0), before_oam)

    def test_lcd_on_defers_every_line_except_first_vblank_line(self) -> None:
        assert self.fixture is not None
        f = self.fixture
        f.write8(0xFF40, 0x80)
        for line in (0, 100, 143, 145, 153):
            with self.subTest(line=line):
                self.setUp()
                f.write8(0xFF40, 0x80)
                before_vram = f.read_block(0x8000, 0x1000)
                before_shadow = f.read_block(f.SHADOW_OAM, 0xA0)
                before_oam = f.read_block(0xFE00, 0xA0)
                result = f.commit(0x6C, 0, target=line)
                self.assertTrue(result["carry"])
                self.assertEqual(f.read_block(0x8000, 0x1000), before_vram)
                self.assertEqual(f.read_block(f.SHADOW_OAM, 0xA0), before_shadow)
                self.assertEqual(f.read_block(0xFE00, 0xA0), before_oam)

    def test_overlay_writes_and_turn_restore_preserve_actual_pose_bytes(self) -> None:
        assert self.fixture is not None
        f = self.fixture
        for actor, name, base in ((8, "channeler", 0x6C),
                                  (10, "super_nerd", 0x70),
                                  (11, "gameboy_kid", 0x74)):
            with self.subTest(actor=actor):
                self.setUp()
                sheet = (REPO_ROOT / "gfx/sprites" / f"{name}.2bpp").read_bytes()
                # Deliberately simulated overlays, not calls to game text/healing.
                font = bytes((i * 7) & 0xFF for i in range(0x800))
                healing = bytes([0xE7] * 48)
                f.write_block(0x8800, font)
                f.write_block(0x87C0, healing)
                for image in (0, 4, 8, 12, 0):
                    pose = f.resolve(actor, image)
                    offset = int(pose["e"]) * 16
                    staged = sheet[offset:offset + 64]
                    # Existing mirrored OAM positions plus retained palette/grass.
                    flip = int(pose["c"])
                    quad = bytes(value for i in range(4) for value in (
                        48 + (i // 2) * 8,
                        40 + ((i % 2) ^ bool(flip)) * 8,
                        base + i,
                        0x10 | flip | (0x80 if i >= 2 else 0),
                    ))
                    f.write_block(f.STAGING, staged)
                    f.write_block(f.OAM_SOURCE, quad)
                    self.assertFalse(f.commit(base, 0x30)["carry"])
                    self.assertEqual(f.read_block(0x8000 + base * 16, 64), staged)
                    self.assertEqual(f.read_block(f.SHADOW_OAM + 0x30, 16), quad)
                    self.assertEqual(f.read_block(0xFE30, 16), quad)
                    self.assertEqual(f.read_block(0x8800, 0x800), font)
                    self.assertEqual(f.read_block(0x87C0, 48), healing)

    def test_successful_lcd_on_commit_at_line_144_finishes_before_late_vblank(self) -> None:
        assert self.fixture is not None
        f = self.fixture
        self.setUp()
        f.write8(0xFF40, 0x80)
        result = f.commit(0x74, 0x90, target=144)
        self.assertFalse(result["carry"])
        self.assertGreaterEqual(result["ly"], 144)
        self.assertLessEqual(result["ly"], 150)
        self.assertEqual(f.read_block(0x8000 + 0x74 * 16, 64),
                         bytes((0x40 + i) & 0xFF for i in range(64)))
        self.assertEqual(f.read_block(f.SHADOW_OAM + 0x90, 16),
                         bytes((0x90 + i) & 0xFF for i in range(16)))
        self.assertEqual(f.read_block(0xFE90, 16),
                         bytes((0x90 + i) & 0xFF for i in range(16)))


if __name__ == "__main__":
    unittest.main(verbosity=2)
