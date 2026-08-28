"""Actual-assembly tests for the non-included overworld follower core.

The fixture deliberately does not include the game's RAM declarations or link
the game ROM.  It includes the current source file directly, gives its named
RAM symbols fixed synthetic addresses, and drives the public entries through a
small ROM mailbox under PyBoy.
"""

from __future__ import annotations

import io
import re
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


class _FollowerRom:
    """Build and run the actual follower source in a tiny two-bank ROM."""

    # Mailbox and synthetic WRAM addresses used by the generated fixture.
    COMMAND = 0xC000
    COMPLETE = 0xC001
    RESULT_A = 0xC002
    RESULT_CARRY = 0xC003
    ARG0 = 0xC004
    ARG1 = 0xC005
    READY = 0xC006
    STATE1 = 0xC100
    STATE2 = 0xC200
    COMMAND_SIZE = 0xC300
    COMMAND_BUFFER = 0xC301
    LEDGE_LATCH = 0xC311
    PLAYER_DIRECTION = 0xC312
    MOVEMENT_FLAGS = 0xC313
    OPTIONS2 = 0xC314
    PLAYER_Y = 0xC315
    PLAYER_X = 0xC316
    GRASS_TILE = 0xC317
    PLAYER_FACING = 0xC318
    FONT_LOADED = 0xC319
    WALK_COUNTER = 0xC31A
    RANDOM_VALUE = 0xC31B
    TILE_MAP = 0xC400

    # Mailbox commands.
    CLEAR = 1
    APPEND = 2
    DEQUEUE = 3
    QUEUE_PLAYER = 4
    QUEUE_ENCODED = 5
    UPDATE = 6
    PLACE = 7
    VISIBILITY = 8
    UPDATE_IMAGE = 9
    REFRESH_QUEUE = 10
    SCHEDULE = 11
    FACE_PLAYER = 12

    # State-data offsets imported from constants/map_object_constants.asm.
    S1_PICTURE = 0
    S1_STATUS = 1
    S1_IMAGE = 2
    S1_YVECTOR = 3
    S1_YPIXELS = 4
    S1_XVECTOR = 5
    S1_XPIXELS = 6
    S1_INTRA = 7
    S1_ANIM = 8
    S1_FACING = 9
    S2_COUNTER = 0
    S2_MAP_Y = 4
    S2_MAP_X = 5
    S2_MOVEMENT_BYTE = 6
    S2_GRASS_PRIORITY = 7
    S2_PHASE = 10
    S2_IMAGE_BASE = 14

    # Source constants from follower.asm and constants/sprite_constants.asm.
    COMMAND_EMPTY = 0xFF
    STATUS_READY = 1
    STATUS_WAITING = 2
    STATUS_WALKING = 3
    STATUS_TWO_STEP = 4
    STATUS_FAST = 5
    STATUS_HOP = 6
    STATUS_IDLE_WALK = 7
    STATUS_IDLE_TOGGLE = 8
    STATUS_IDLE_TURN = 9
    FACE_BIT = 7
    PLACE_OVERLAP = 0
    PLACE_RIGHT = 1
    PLACE_BEHIND = 2
    PLACE_OVERLAP_DOWN = 3
    PLACE_BELOW = 4
    PLACE_ABOVE = 5
    PLACE_LEFT = 6
    PLACE_AHEAD = 7
    FACING_DOWN = 0
    FACING_UP = 4
    FACING_LEFT = 8
    FACING_RIGHT = 12
    LEDGE_BIT = 6
    FPS_BIT = 7
    MAP_TILESET_SIZE = 0x60
    OAM_PRIO = 0x80

    _FIXTURE = r'''
INCLUDE "includes.asm"

; The follower source is intentionally not linked into the game yet. These
; fixed addresses are test-only stand-ins for the symbols it references.
DEF MAP_TILESET_SIZE EQU $60
DEF wSprite15StateData1 EQU $C100
DEF wSprite15StateData2 EQU $C200
DEF wFollowerCommandBufferSize EQU $C300
DEF wFollowerCommandBuffer EQU $C301
DEF wFollowerLedgeLatch EQU $C311
DEF wPlayerDirection EQU $C312
DEF wMovementFlags EQU $C313
DEF wOptions2 EQU $C314
DEF wYCoord EQU $C315
DEF wXCoord EQU $C316
DEF wGrassTile EQU $C317
DEF wSpritePlayerStateData1FacingDirection EQU $C318
DEF wFontLoaded EQU $C319
DEF wWalkCounter EQU $C31A
DEF hRandomAdd EQU $FF80
DEF wTileMap EQU $C400

DEF MAIL_COMMAND EQU $C000
DEF MAIL_COMPLETE EQU $C001
DEF MAIL_RESULT_A EQU $C002
DEF MAIL_RESULT_CARRY EQU $C003
DEF MAIL_ARG0 EQU $C004
DEF MAIL_ARG1 EQU $C005
DEF MAIL_READY EQU $C006

SECTION "Follower test entry", ROM0[$100]
    nop
    jp FollowerTestMain

SECTION "Follower test home helper", ROM0[$150]
; HOME fill helper, matching home/tilemap.asm. Random is controlled below.
FillMemory::
    push de
    ld d, a
.loop
    ld a, d
    ld [hli], a
    dec bc
    ld a, b
    or c
    jr nz, .loop
    pop de
    ret

; Deterministic RNG input for branch/animation traces. This tests the core's
; use of Random and hRandomAdd, not the game's RNG distribution or timing.
Random::
    ld a, [$C31B]
    ldh [hRandomAdd], a
    ret

; Put the follower core and its dispatcher in the same ROMX bank. The test
; entry above jumps directly to this bank, so no banked helper is hidden by a
; test stub or an accidental far call.
INCLUDE "engine/overworld/follower.asm"

SECTION "Follower test dispatcher", ROMX
FollowerTestMain::
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
    jr z, .clear
    cp 2
    jr z, .append
    cp 3
    jr z, .dequeue
    cp 4
    jr z, .queue_player
    cp 5
    jr z, .queue_encoded
    cp 6
    jr z, .update
    cp 7
    jr z, .place
    cp 8
    jr z, .visibility
    cp 9
    jr z, .update_image
    cp 10
    jr z, .refresh_queue
    cp 11
    jr z, .schedule
    cp 12
    jr z, .face_player
    ld a, $EE
    and a
    jr .report
.clear
    call FollowerClearState
    jr .report
.append
    ld a, [MAIL_ARG0]
    call FollowerAppendCommand
    jr .report
.dequeue
    call FollowerDequeueCommand
    jr .report
.queue_player
    call FollowerQueuePlayerStep
    jr .report
.queue_encoded
    ld a, [MAIL_ARG0]
    ld e, a
    ld a, $A5             ; prove the banked entry consumes E, not A
    call FollowerQueueEncodedStep
    jr .report
.update
    call FollowerUpdate
    jr .report
.place
    ld a, [MAIL_ARG0]
    ld d, a
    ld a, [MAIL_ARG1]
    ld e, a
    call FollowerPlaceAtPlayer
    jr .report
.visibility
    call FollowerCheckVisibility
    jr .report
.update_image
    call FollowerUpdateImage
    jr .report
.refresh_queue
    call FollowerRefreshQueue
    jr .report
.schedule
    ld a, [MAIL_ARG0]
    ld d, a
    ld a, [MAIL_ARG1]
    ld e, a
    call FollowerScheduleSpawn
    jr .report
.face_player
    call FollowerFacePlayer
.report
    ld [MAIL_RESULT_A], a
    ld a, 0
    jr nc, .store_carry
    inc a
.store_carry
    ld [MAIL_RESULT_CARRY], a
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

        self.source = temp_dir / "follower_fixture.asm"
        self.object = temp_dir / "follower_fixture.o"
        self.rom_path = temp_dir / "follower_fixture.gb"
        # This constant lives in movement.asm, not includes.asm. Take the
        # actual definition so this isolated fixture cannot silently drift.
        movement_source = (REPO_ROOT / "engine/overworld/movement.asm").read_text()
        tile_limit = re.search(r"(?m)^DEF MAP_TILESET_SIZE EQU .+$", movement_source)
        assert tile_limit is not None, "movement tile-limit definition moved"
        fixture_source = self._FIXTURE.replace("DEF MAP_TILESET_SIZE EQU $60", tile_limit[0])
        self.source.write_text(fixture_source, encoding="utf-8")
        self._run(("rgbasm", "-Weverything", "-I", str(REPO_ROOT), "-o", str(self.object), str(self.source)))
        self._run(("rgblink", "-o", str(self.rom_path), str(self.object)))
        self._run(("rgbfix", "-v", "-p", "0", str(self.rom_path)))
        self.pyboy = PyBoy(
            io.BytesIO(self.rom_path.read_bytes()),
            window="null",
            sound_emulated=False,
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
            if self.pyboy.memory[self.READY] == 0x5A:
                return
        raise AssertionError("follower fixture did not reach its mailbox loop")

    def read8(self, address: int) -> int:
        return self.pyboy.memory[address]

    def write8(self, address: int, value: int) -> None:
        self.pyboy.memory[address] = value & 0xFF

    def read_state1(self, offset: int) -> int:
        return self.read8(self.STATE1 + offset)

    def write_state1(self, offset: int, value: int) -> None:
        self.write8(self.STATE1 + offset, value)

    def read_state2(self, offset: int) -> int:
        return self.read8(self.STATE2 + offset)

    def write_state2(self, offset: int, value: int) -> None:
        self.write8(self.STATE2 + offset, value)

    def command(self, command: int, arg0: int = 0, arg1: int = 0) -> tuple[int, bool]:
        self.write8(self.COMPLETE, 0)
        self.write8(self.ARG0, arg0)
        self.write8(self.ARG1, arg1)
        self.write8(self.COMMAND, command)
        for _ in range(120):
            self.pyboy.tick(render=False)
            if self.read8(self.COMPLETE):
                return self.read8(self.RESULT_A), bool(self.read8(self.RESULT_CARRY))
        raise AssertionError(f"follower fixture timed out on command {command}")

    def clear(self) -> None:
        self.command(self.CLEAR)

    def append(self, value: int) -> tuple[int, bool]:
        return self.command(self.APPEND, value)

    def dequeue(self) -> tuple[int, bool]:
        return self.command(self.DEQUEUE)

    def queue_player(self) -> tuple[int, bool]:
        return self.command(self.QUEUE_PLAYER)

    def queue_encoded(self, value: int) -> tuple[int, bool]:
        return self.command(self.QUEUE_ENCODED, value)

    def update(self) -> tuple[int, bool]:
        return self.command(self.UPDATE)

    def place(self, picture: int, mode: int) -> tuple[int, bool]:
        return self.command(self.PLACE, picture, mode)

    def visibility(self) -> tuple[int, bool]:
        return self.command(self.VISIBILITY)

    def update_image(self) -> tuple[int, bool]:
        return self.command(self.UPDATE_IMAGE)

    def face_player(self) -> tuple[int, bool]:
        return self.command(self.FACE_PLAYER)


class FollowerCoreAssemblyTest(unittest.TestCase):
    """Exercise core behavior through an assembled fixture, not Python copies."""

    fixture: _FollowerRom | None = None
    temp_dir: tempfile.TemporaryDirectory[str] | None = None

    @classmethod
    def setUpClass(cls) -> None:
        cls.temp_dir = tempfile.TemporaryDirectory(prefix="redrogue-follower-")
        try:
            cls.fixture = _FollowerRom(Path(cls.temp_dir.name))
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
        self.fixture.clear()
        self.fixture.write8(self.fixture.PLAYER_Y, 20)
        self.fixture.write8(self.fixture.PLAYER_X, 30)
        self.fixture.write8(self.fixture.PLAYER_FACING, self.fixture.FACING_DOWN)
        self.fixture.write8(self.fixture.OPTIONS2, 0)
        self.fixture.write8(self.fixture.MOVEMENT_FLAGS, 0)
        self.fixture.write8(self.fixture.PLAYER_DIRECTION, 0)
        self.fixture.write8(self.fixture.FONT_LOADED, 0)
        self.fixture.write8(self.fixture.WALK_COUNTER, 0)
        self.fixture.write8(self.fixture.RANDOM_VALUE, 0)
        self.fixture.write8(self.fixture.GRASS_TILE, 0x33)
        for offset in range(18 * 20):
            self.fixture.write8(self.fixture.TILE_MAP + offset, 0)

    def _interaction_fixture(self):
        self.setUp()
        f = self.fixture
        assert f is not None
        f.place(1, f.PLACE_ABOVE)
        f.update_image()
        f.append(4)
        f.append(1)
        f.write8(f.LEDGE_LATCH, 1)
        return f

    def _interaction_snapshot(self, f):
        return (
            [f.read_state1(i) for i in range(16)],
            [f.read_state2(i) for i in range(16)],
            [f.read8(f.COMMAND_SIZE + i) for i in range(18)],
        )

    def test_face_player_directions_idle_cleanup_and_queue_preservation(self) -> None:
        for fps in (0, 1 << 7):
            for facing in (0, 4, 8, 12):
                for status in (1, 2, 6, 7, 8, 9):
                    with self.subTest(fps=fps, facing=facing, status=status):
                        f = self._interaction_fixture()
                        f.write8(f.OPTIONS2, fps)
                        f.write8(f.PLAYER_FACING, facing)
                        y, x = f.read_state1(f.S1_YPIXELS), f.read_state1(f.S1_XPIXELS)
                        f.write_state1(f.S1_STATUS, status)
                        f.write_state1(f.S1_INTRA, 3)
                        f.write_state1(f.S1_ANIM, 2)
                        f.write_state2(f.S2_COUNTER, 9)
                        f.write_state2(f.S2_PHASE, 1)
                        if status == 6:
                            f.write_state1(f.S1_YVECTOR, 0xFC)
                            f.write_state1(f.S1_XVECTOR, 2)
                            f.write_state1(f.S1_YPIXELS, y - 4)
                            f.write_state1(f.S1_XPIXELS, x + 2)
                        before = self._interaction_snapshot(f)
                        self.assertFalse(f.face_player()[1])
                        self.assertEqual(f.read_state1(f.S1_FACING), facing ^ 4)
                        self.assertEqual(f.read_state1(f.S1_STATUS), 1)
                        self.assertEqual((f.read_state1(f.S1_YPIXELS), f.read_state1(f.S1_XPIXELS)), (y, x))
                        for offset in (f.S1_YVECTOR, f.S1_XVECTOR, f.S1_INTRA, f.S1_ANIM):
                            self.assertEqual(f.read_state1(offset), 0)
                        self.assertEqual(f.read_state2(f.S2_COUNTER), 0)
                        self.assertEqual(f.read_state2(f.S2_PHASE), 0)
                        after = self._interaction_snapshot(f)
                        self.assertEqual(after[2], before[2])
                        self.assertEqual(after[1][4:6], before[1][4:6])

    def test_face_player_rejects_unready_or_hidden_without_state_reset(self) -> None:
        cases = [("status", value) for value in (0, 3, 4, 5, 10, 127)]
        cases += [("picture", 0), ("base", 0), ("image", 255), ("walk", 8)]
        for field, value in cases:
            with self.subTest(field=field, value=value):
                f = self._interaction_fixture()
                if field == "status":
                    f.write_state1(f.S1_STATUS, value)
                elif field == "picture":
                    f.write_state1(f.S1_PICTURE, value)
                elif field == "base":
                    f.write_state2(f.S2_IMAGE_BASE, value)
                elif field == "image":
                    f.write_state1(f.S1_IMAGE, value)
                else:
                    f.write8(f.WALK_COUNTER, value)
                before = self._interaction_snapshot(f)
                self.assertTrue(f.face_player()[1])
                self.assertEqual(self._interaction_snapshot(f), before)

    def test_face_player_spatial_rejection_preserves_queue(self) -> None:
        for overlap in (False, True):
            with self.subTest(overlap=overlap):
                f = self._interaction_fixture()
                f.write_state2(f.S2_MAP_Y, 24 if overlap else 0)
                f.write_state2(f.S2_MAP_X, 34)
                before = self._interaction_snapshot(f)
                self.assertTrue(f.face_player()[1])
                after = self._interaction_snapshot(f)
                self.assertEqual(after[2], before[2])
                self.assertEqual(after[1], before[1])
                self.assertEqual(after[0][:2] + after[0][3:], before[0][:2] + before[0][3:])
                self.assertEqual(f.read_state1(f.S1_IMAGE), 255)

    def test_face_request_precedes_font_dispatch_and_preserves_pending_steps(self) -> None:
        for font in (0, 1):
            for status in (0, 1, 3, 4, 5):
                with self.subTest(font=font, status=status):
                    f = self._interaction_fixture()
                    f.write8(f.FONT_LOADED, font)
                    f.write8(f.PLAYER_FACING, 8)
                    f.write_state1(f.S1_STATUS, status | 0x80)
                    before = self._interaction_snapshot(f)
                    self.assertEqual(f.update()[1], status != 1)
                    after = self._interaction_snapshot(f)
                    self.assertEqual(f.read_state1(f.S1_STATUS), status)
                    self.assertEqual(after[2], before[2])
                    if status == 1:
                        self.assertEqual(f.read_state1(f.S1_FACING), 12)
                    else:
                        self.assertEqual(after[0][:1] + after[0][2:], before[0][:1] + before[0][2:])
                        self.assertEqual(after[1], before[1])
        f.clear()
        self.assertEqual(f.read_state1(f.S1_PICTURE), 0)
        self.assertEqual(f.read8(f.COMMAND_SIZE), 255)
        self.assertEqual(f.read8(f.LEDGE_LATCH), 0)

    def test_clear_resets_state_queue_and_ledge_latch(self) -> None:
        assert self.fixture is not None
        for offset in range(16):
            self.fixture.write_state1(offset, 0xA1)
            self.fixture.write_state2(offset, 0xA2)
        self.fixture.write8(self.fixture.COMMAND_SIZE, 0x0F)
        for offset in range(16):
            self.fixture.write8(self.fixture.COMMAND_BUFFER + offset, 0xB0 + offset)
        self.fixture.write8(self.fixture.LEDGE_LATCH, 1)

        self.fixture.clear()

        self.assertEqual(
            [self.fixture.read_state1(i) for i in range(16)],
            [0, 0, self.fixture.COMMAND_EMPTY] + [0] * 13,
        )
        self.assertEqual([self.fixture.read_state2(i) for i in range(16)], [0] * 16)
        self.assertEqual(self.fixture.read8(self.fixture.COMMAND_SIZE), self.fixture.COMMAND_EMPTY)
        self.assertEqual(
            [self.fixture.read8(self.fixture.COMMAND_BUFFER + i) for i in range(16)],
            [0] * 16,
        )
        self.assertEqual(self.fixture.read8(self.fixture.LEDGE_LATCH), 0)

    def test_queue_lag_full_and_invalid_commands(self) -> None:
        assert self.fixture is not None
        self.assertFalse(self.fixture.append(4)[1])
        self.assertEqual(self.fixture.read8(self.fixture.COMMAND_SIZE), 0)
        self.assertEqual(self.fixture.read8(self.fixture.COMMAND_BUFFER), 4)
        for invalid in (0, 9, 0xFF):
            self.assertEqual(self.fixture.append(invalid)[1], True)
            self.assertEqual(self.fixture.read8(self.fixture.COMMAND_SIZE), 0)

        self.fixture.clear()
        self.assertFalse(self.fixture.append(1)[1])
        self.assertEqual(self.fixture.dequeue()[1], True, "one queued command is the lag sentinel")
        self.assertEqual(self.fixture.read8(self.fixture.COMMAND_SIZE), 0)
        self.assertFalse(self.fixture.append(2)[1])
        self.assertEqual(self.fixture.dequeue(), (1, False))
        self.assertEqual(self.fixture.read8(self.fixture.COMMAND_SIZE), 0)
        self.assertEqual(self.fixture.read8(self.fixture.COMMAND_BUFFER), 2)

        self.fixture.clear()
        for index in range(16):
            self.assertFalse(self.fixture.append((index % 8) + 1)[1])
        self.assertEqual(self.fixture.read8(self.fixture.COMMAND_SIZE), 15)
        self.assertTrue(self.fixture.append(1)[1])
        self.assertEqual(self.fixture.read8(self.fixture.COMMAND_SIZE), 15)

    def test_encoded_entry_uses_e_and_player_ledge_latch(self) -> None:
        assert self.fixture is not None
        self.assertFalse(self.fixture.queue_encoded(7)[1])
        self.assertEqual(self.fixture.read8(self.fixture.COMMAND_BUFFER), 7)

        self.fixture.clear()
        self.fixture.write8(self.fixture.PLAYER_DIRECTION, 1 << 2)  # down
        self.fixture.write8(self.fixture.MOVEMENT_FLAGS, 1 << self.fixture.LEDGE_BIT)
        self.assertFalse(self.fixture.queue_player()[1])
        self.assertEqual(self.fixture.read8(self.fixture.COMMAND_BUFFER), 5)
        self.assertEqual(self.fixture.read8(self.fixture.LEDGE_LATCH), 1)
        self.assertTrue(self.fixture.queue_player()[1])
        self.assertEqual(self.fixture.read8(self.fixture.COMMAND_SIZE), 0)
        self.assertEqual(self.fixture.read8(self.fixture.LEDGE_LATCH), 0)
        self.assertFalse(self.fixture.queue_player()[1])
        self.assertEqual(self.fixture.read8(self.fixture.COMMAND_SIZE), 1)
        self.assertEqual(self.fixture.read8(self.fixture.COMMAND_BUFFER + 1), 5)

    def _prepare_movement(self, *, options2: int = 0) -> None:
        assert self.fixture is not None
        self.fixture.write8(self.fixture.OPTIONS2, options2)
        self.fixture.write_state1(self.fixture.S1_PICTURE, 0x42)
        self.fixture.write_state1(self.fixture.S1_STATUS, self.fixture.STATUS_READY)
        self.fixture.write_state1(self.fixture.S1_YPIXELS, 0)
        self.fixture.write_state1(self.fixture.S1_XPIXELS, 64)
        self.fixture.write_state2(self.fixture.S2_MAP_Y, 4)
        self.fixture.write_state2(self.fixture.S2_MAP_X, 8)
        self.fixture.write_state2(self.fixture.S2_IMAGE_BASE, 0)

    def _run_direction(self, command: int, *, options2: int = 0, ledge: bool = False) -> tuple[int, int]:
        assert self.fixture is not None
        self._prepare_movement(options2=options2)
        self.fixture.queue_encoded(command)
        self.fixture.queue_encoded(command)
        calls = 16 if options2 & (1 << self.fixture.FPS_BIT) else 8
        if ledge and not options2 & (1 << self.fixture.FPS_BIT):
            calls = 8
        if ledge and options2 & (1 << self.fixture.FPS_BIT):
            calls = 16
        for _ in range(calls):
            self.fixture.update()
        return (
            self.fixture.read_state1(self.fixture.S1_YPIXELS),
            self.fixture.read_state1(self.fixture.S1_XPIXELS),
        )

    def test_all_directions_normal_and_ledge_timing(self) -> None:
        assert self.fixture is not None
        expected = {
            1: (16, 64, 1, self.fixture.FACING_DOWN),
            2: (0xF0, 64, 0xFF, self.fixture.FACING_UP),
            3: (0, 48, 0xFF, self.fixture.FACING_LEFT),
            4: (0, 80, 1, self.fixture.FACING_RIGHT),
        }
        for command, (expected_y, expected_x, expected_map_delta, facing) in expected.items():
            with self.subTest(command=command):
                self.fixture.clear()
                self.setUp()
                ypixels, xpixels = self._run_direction(command)
                self.assertEqual((ypixels, xpixels), (expected_y, expected_x))
                self.assertEqual(self.fixture.read_state1(self.fixture.S1_STATUS), self.fixture.STATUS_READY)
                if command in (1, 2):
                    expected_map = (4 + expected_map_delta) & 0xFF
                    self.assertEqual(self.fixture.read_state2(self.fixture.S2_MAP_Y), expected_map)
                else:
                    expected_map = (8 + expected_map_delta) & 0xFF
                    self.assertEqual(self.fixture.read_state2(self.fixture.S2_MAP_X), expected_map)

        self.fixture.clear()
        self.setUp()
        self._prepare_movement()
        self.fixture.queue_encoded(5)
        self.fixture.queue_encoded(5)
        for _ in range(8):
            self.fixture.update()
        self.assertEqual(self.fixture.read_state1(self.fixture.S1_YPIXELS), 32)
        self.assertEqual(self.fixture.read_state2(self.fixture.S2_MAP_Y), 6)
        self.assertEqual(self.fixture.read_state1(self.fixture.S1_STATUS), self.fixture.STATUS_READY)

    def test_fast_path_uses_four_pixels_for_four_updates(self) -> None:
        assert self.fixture is not None
        self._prepare_movement()
        for _ in range(4):
            self.fixture.queue_encoded(4)
        self.fixture.update()
        self.assertEqual(self.fixture.read_state1(self.fixture.S1_STATUS), self.fixture.STATUS_FAST)
        self.assertEqual(self.fixture.read_state2(self.fixture.S2_COUNTER), 3)
        self.assertEqual(self.fixture.read_state1(self.fixture.S1_XPIXELS), 68)
        for _ in range(3):
            self.fixture.update()
        self.assertEqual(self.fixture.read_state1(self.fixture.S1_XPIXELS), 80)
        self.assertEqual(self.fixture.read_state1(self.fixture.S1_STATUS), self.fixture.STATUS_READY)

    def test_60fps_halves_delta_and_decrements_on_phase_zero(self) -> None:
        assert self.fixture is not None
        self._prepare_movement(options2=1 << self.fixture.FPS_BIT)
        self.fixture.queue_encoded(1)
        self.fixture.queue_encoded(1)
        self.fixture.update()
        self.assertEqual(self.fixture.read_state1(self.fixture.S1_YPIXELS), 1)
        self.assertEqual(self.fixture.read_state2(self.fixture.S2_COUNTER), 8)
        self.assertEqual(self.fixture.read_state2(self.fixture.S2_PHASE), 1)
        self.fixture.update()
        self.assertEqual(self.fixture.read_state1(self.fixture.S1_YPIXELS), 2)
        self.assertEqual(self.fixture.read_state2(self.fixture.S2_COUNTER), 7)
        self.assertEqual(self.fixture.read_state2(self.fixture.S2_PHASE), 0)
        for _ in range(14):
            self.fixture.update()
        self.assertEqual(self.fixture.read_state1(self.fixture.S1_YPIXELS), 16)
        self.assertEqual(self.fixture.read_state1(self.fixture.S1_STATUS), self.fixture.STATUS_READY)

    def test_each_tick_for_all_directions_paths_and_speed_options(self) -> None:
        assert self.fixture is not None
        f = self.fixture
        vectors = {1: (1, 0), 2: (-1, 0), 3: (0, -1), 4: (0, 1)}
        for fps in (False, True):
            for path, logical_ticks, distance, status in (
                ("normal", 8, 16, f.STATUS_WALKING),
                ("fast", 4, 16, f.STATUS_FAST),
                ("ledge", 8, 32, f.STATUS_TWO_STEP),
            ):
                for direction, (dy, dx) in vectors.items():
                    with self.subTest(fps=fps, path=path, direction=direction):
                        self.setUp()
                        self._prepare_movement(options2=(1 << f.FPS_BIT) if fps else 0)
                        command = direction + (4 if path == "ledge" else 0)
                        for _ in range(4 if path == "fast" else 2):
                            f.queue_encoded(command)
                        calls = logical_ticks * (2 if fps else 1)
                        delta = distance // calls
                        for tick in range(1, calls + 1):
                            f.update()
                            self.assertEqual(f.read_state1(f.S1_YPIXELS), (dy * tick * delta) & 0xFF)
                            self.assertEqual(f.read_state1(f.S1_XPIXELS), (64 + dx * tick * delta) & 0xFF)
                            logical_elapsed = tick // 2 if fps else tick
                            self.assertEqual(f.read_state2(f.S2_COUNTER), logical_ticks - logical_elapsed)
                            self.assertEqual(f.read_state2(f.S2_PHASE), tick % 2 if fps else 0)
                            self.assertEqual(f.read_state1(f.S1_INTRA), logical_elapsed % 4)
                            self.assertEqual(f.read_state1(f.S1_ANIM), (logical_elapsed // 4) % 4)
                            self.assertEqual(f.read_state1(f.S1_STATUS), f.STATUS_READY if tick == calls else status)
                        tiles = 2 if path == "ledge" else 1
                        self.assertEqual(f.read_state2(f.S2_MAP_Y), (4 + dy * tiles) & 0xFF)
                        self.assertEqual(f.read_state2(f.S2_MAP_X), (8 + dx * tiles) & 0xFF)

    def test_ledge_directions_rejection_and_normal_step_latch_reset(self) -> None:
        assert self.fixture is not None
        f = self.fixture
        for flag, command in ((4, 5), (8, 6), (2, 7), (1, 8)):
            with self.subTest(direction=flag):
                self.setUp()
                f.write8(f.PLAYER_DIRECTION, flag)
                f.write8(f.MOVEMENT_FLAGS, 1 << f.LEDGE_BIT)
                self.assertFalse(f.queue_player()[1])
                self.assertEqual(f.read8(f.COMMAND_BUFFER), command)
                self.assertEqual(f.read8(f.LEDGE_LATCH), 1)
                self.assertTrue(f.queue_player()[1])
                self.assertEqual(f.read8(f.COMMAND_SIZE), 0)
                self.assertEqual(f.read8(f.LEDGE_LATCH), 0)
        self.setUp()
        f.write8(f.PLAYER_DIRECTION, 4)
        f.write8(f.MOVEMENT_FLAGS, 1 << f.LEDGE_BIT)
        for _ in range(16):
            f.append(1)
        self.assertTrue(f.queue_player()[1])
        self.assertEqual(f.read8(f.LEDGE_LATCH), 0)
        self.setUp()
        f.write8(f.MOVEMENT_FLAGS, 1 << f.LEDGE_BIT)
        self.assertTrue(f.queue_player()[1])  # no direction
        self.assertEqual(f.read8(f.LEDGE_LATCH), 0)
        f.write8(f.LEDGE_LATCH, 1)
        f.write8(f.MOVEMENT_FLAGS, 0)
        f.write8(f.PLAYER_DIRECTION, 1)
        self.assertFalse(f.queue_player()[1])
        self.assertEqual(f.read8(f.LEDGE_LATCH), 0)
        self.assertEqual(f.read8(f.COMMAND_BUFFER), 4)

    def test_four_tile_textbox_checks_and_rounded_up_y(self) -> None:
        assert self.fixture is not None
        f = self.fixture
        # Y=62 is two pixels into the next block. Its rounded-up bottom
        # row is not part of the rounded-down 2x2 sample.
        for rounded_up in (False, True):
            for cell in (0, 1, -20, -19):
                with self.subTest(rounded_up=rounded_up, cell=cell):
                    self.setUp()
                    f.place(0x42, f.PLACE_OVERLAP)
                    f.write_state1(f.S1_YPIXELS, 62)
                    self.assertFalse(f.visibility()[1])
                    pointer = self._tile_pointer_offset(62, 64, round_up=rounded_up)
                    f.write8(f.TILE_MAP + pointer + cell, f.MAP_TILESET_SIZE)
                    self.assertTrue(f.visibility()[1])
                    self.assertEqual(f.read_state1(f.S1_IMAGE), 0xFF)
        self.setUp()
        f.place(0x42, f.PLACE_OVERLAP)
        f.write_state2(f.S2_GRASS_PRIORITY, f.OAM_PRIO)
        self.assertFalse(f.visibility()[1])
        self.assertEqual(f.read_state2(f.S2_GRASS_PRIORITY), 0)

    def test_geometry_seed_command_and_y_priority(self) -> None:
        assert self.fixture is not None
        f = self.fixture
        for dy, dx, command in (
            (0, 0, None), (-1, 0, 1), (1, 0, 2), (0, 1, 3), (0, -1, 4),
            (-2, 0, 5), (2, 0, 6), (0, 2, 7), (0, -2, 8),
            (-3, 3, 5), (1, -2, 2),
        ):
            with self.subTest(dy=dy, dx=dx):
                self.setUp()
                f.place(0x42, f.PLACE_OVERLAP)
                f.write_state2(f.S2_MAP_Y, 24 + dy)
                f.write_state2(f.S2_MAP_X, 34 + dx)
                for _ in range(4):
                    f.append(8)
                _, carry = f.command(f.REFRESH_QUEUE)
                self.assertEqual(carry, command is None)
                self.assertEqual(f.read8(f.COMMAND_SIZE), 0xFF if command is None else 0)
                self.assertEqual(f.read8(f.COMMAND_BUFFER), command or 0)
                self.assertEqual([f.read8(f.COMMAND_BUFFER + i) for i in range(1, 16)], [0] * 15)

    def test_scheduled_spawn_waits_for_font_then_seeds_first_step(self) -> None:
        assert self.fixture is not None
        f = self.fixture
        f.write8(f.FONT_LOADED, 1)
        self.assertFalse(f.command(f.SCHEDULE, 0x42, f.PLACE_BEHIND)[1])
        self.assertEqual(f.read_state1(f.S1_STATUS), 0)
        for _ in range(3):
            f.update()
            self.assertEqual(f.read_state1(f.S1_STATUS), 0)
            self.assertEqual(f.read_state1(f.S1_IMAGE), 0xFF)
            self.assertEqual(f.read8(f.COMMAND_SIZE), 0xFF)
        f.write8(f.FONT_LOADED, 0)
        f.update()
        self.assertEqual(f.read_state1(f.S1_STATUS), f.STATUS_READY)
        self.assertEqual(f.read_state1(f.S1_IMAGE), 0xFF)
        self.assertEqual(f.read8(f.COMMAND_SIZE), 0)
        self.assertEqual(f.read8(f.COMMAND_BUFFER), 1)
        self.assertEqual(f.read_state1(f.S1_YPIXELS), 44)
        f.queue_encoded(4)  # accepted subsequent player step
        f.update()
        self.assertEqual(f.read_state1(f.S1_STATUS), f.STATUS_WALKING)
        self.assertEqual(f.read_state1(f.S1_YPIXELS), 46)
        self.assertEqual(f.read_state2(f.S2_MAP_Y), 24)
        f.clear()
        f.update()
        self.assertEqual(f.read_state1(f.S1_PICTURE), 0)
        self.assertEqual(f.read_state1(f.S1_STATUS), 0)
        self.assertEqual(f.read8(f.COMMAND_SIZE), 0xFF)

    def test_wait_overlap_and_zero_timer_wrap_match_yellow(self) -> None:
        assert self.fixture is not None
        f = self.fixture
        f.place(0x42, f.PLACE_OVERLAP)
        f.write_state2(f.S2_COUNTER, 5)
        f.update()
        self.assertEqual(f.read_state1(f.S1_IMAGE), 0xFF)
        self.assertEqual(f.read_state2(f.S2_COUNTER), 5)
        f.place(0x42, f.PLACE_BEHIND)
        f.write8(f.RANDOM_VALUE, 0x0C)
        f.update()
        self.assertEqual(f.read_state2(f.S2_COUNTER), 0xFF)
        self.assertEqual(f.read_state1(f.S1_FACING), f.FACING_DOWN)
        for _ in range(255):
            f.update()
        self.assertEqual(f.read_state2(f.S2_COUNTER), 0x20)
        self.assertEqual(f.read_state1(f.S1_FACING), f.FACING_RIGHT)
        self.assertEqual(f.read_state1(f.S1_ANIM), 0)

    def _start_idle_action(self, selection: int, fps: bool = False) -> None:
        assert self.fixture is not None
        f = self.fixture
        self.setUp()
        f.place(0x42, f.PLACE_BEHIND)
        f.queue_encoded(5)
        f.write_state2(f.S2_COUNTER, 1)
        f.write8(f.RANDOM_VALUE, selection)
        f.write8(f.OPTIONS2, 0x80 if fps else 0)
        for _ in range(2 if fps else 1):
            f.update()
        self.assertEqual(f.read_state1(f.S1_STATUS), 6 + selection)

    def test_idle_actions_exact_traces_and_both_timing_modes(self) -> None:
        assert self.fixture is not None
        f = self.fixture
        # Exact Yellow Pointer_fc8d6 data, read backwards by the routine.
        hop = list(reversed([
            (0, 0), (-2, 1), (-4, 2), (-2, 3), (0, 4), (-2, 3),
            (-4, 2), (-2, 1), (0, 0), (-2, -1), (-4, -2), (-2, -3),
            (0, -4), (-2, -3), (-4, -2), (-2, -1), (0, 0),
        ]))
        turns = [f.FACING_DOWN, f.FACING_LEFT, f.FACING_UP, f.FACING_RIGHT, f.FACING_DOWN]
        for fps in (False, True):
            for selection, duration in enumerate((17, 48, 32, 32)):
                with self.subTest(fps=fps, selection=selection):
                    self._start_idle_action(selection, fps)
                    for tick in range(1, duration + 1):
                        if tick > 1:
                            for _ in range(2 if fps else 1):
                                f.update()
                        if selection == 0:
                            dy, dx = hop[tick - 1]
                            self.assertEqual(f.read_state1(f.S1_YPIXELS), 44 + dy)
                            self.assertEqual(f.read_state1(f.S1_XPIXELS), 64 + dx)
                        elif selection in (1, 2):
                            frame = (tick // 8) % (4 if selection == 1 else 2)
                            self.assertEqual(f.read_state1(f.S1_ANIM), frame)
                        else:
                            self.assertEqual(f.read_state1(f.S1_FACING), turns[tick // 8])
                        self.assertEqual(f.read_state2(f.S2_MAP_Y), 23)
                        self.assertEqual(f.read_state2(f.S2_MAP_X), 34)
                        if tick < duration:
                            self.assertEqual(f.read_state2(f.S2_COUNTER), duration - tick)
                            self.assertEqual(f.read_state1(f.S1_STATUS), 6 + selection)
                    self.assertEqual(f.read_state1(f.S1_STATUS), f.STATUS_READY)
                    self.assertEqual(f.read_state2(f.S2_COUNTER), 0x10)
                    self.assertEqual(f.read8(f.COMMAND_SIZE), 0)
                    self.assertEqual(f.read_state1(f.S1_YVECTOR), 0)
                    self.assertEqual(f.read_state1(f.S1_XVECTOR), 0)

    def test_idle_hop_interrupt_restores_offsets_and_preserves_scroll(self) -> None:
        assert self.fixture is not None
        f = self.fixture
        for fps in (False, True):
            with self.subTest(fps=fps):
                self._start_idle_action(0, fps)
                for _ in range(2 if fps else 1):
                    f.update()
                self.assertNotEqual(f.read_state1(f.S1_YVECTOR), 0)
                f.write_state1(f.S1_XPIXELS, f.read_state1(f.S1_XPIXELS) - 1)
                f.write8(f.WALK_COUNTER, 8)
                f.update()
                self.assertEqual(f.read_state1(f.S1_YPIXELS), 44)
                self.assertEqual(f.read_state1(f.S1_XPIXELS), 63)
                self.assertEqual(f.read_state1(f.S1_YVECTOR), 0)
                self.assertEqual(f.read_state1(f.S1_XVECTOR), 0)
                self.assertEqual(f.read_state1(f.S1_STATUS), f.STATUS_READY)

    def test_new_command_restarts_half_step_phase_after_odd_idle_tick(self) -> None:
        assert self.fixture is not None
        f = self.fixture
        for command, queued, calls, distance in ((4, 2, 16, 16), (4, 4, 8, 16), (8, 2, 16, 32)):
            with self.subTest(command=command, queued=queued):
                self.setUp()
                f.place(0x42, f.PLACE_BEHIND)
                f.write8(f.OPTIONS2, 0x80)
                f.update()  # waiting advances to the first half of an idle tick
                self.assertEqual(f.read_state2(f.S2_PHASE), 1)
                for _ in range(queued):
                    f.queue_encoded(command)
                for tick in range(calls):
                    f.update()
                    self.assertEqual(f.read_state1(f.S1_XPIXELS), 64 + (tick + 1) * distance // calls)
                    if tick < calls - 1:
                        self.assertNotEqual(f.read_state1(f.S1_STATUS), f.STATUS_READY)
                self.assertEqual(f.read_state1(f.S1_STATUS), f.STATUS_READY)
                self.assertEqual(f.read_state1(f.S1_XPIXELS), 64 + distance)
                self.assertEqual(f.read_state2(f.S2_PHASE), 0)

    def test_font_pause_resets_animation_reseeds_and_respects_player_motion(self) -> None:
        assert self.fixture is not None
        f = self.fixture
        for walking in (0, 8):
            with self.subTest(walking=walking):
                self._start_idle_action(0)
                f.update()  # nonzero visual hop offset
                f.write8(f.WALK_COUNTER, walking)
                f.write8(f.FONT_LOADED, 1)
                f.update()
                self.assertEqual(f.read_state1(f.S1_YPIXELS), 44)
                self.assertEqual(f.read_state1(f.S1_XPIXELS), 64)
                self.assertEqual(f.read_state1(f.S1_ANIM), 0)
                self.assertEqual(f.read_state1(f.S1_STATUS), f.STATUS_READY)
                self.assertEqual(f.read_state2(f.S2_COUNTER), 0)
                self.assertEqual(f.read8(f.COMMAND_SIZE), 0)
                self.assertEqual(f.read8(f.COMMAND_BUFFER), 1)
                f.write_state1(f.S1_XPIXELS, 70)
                f.update()
                self.assertEqual(f.read_state1(f.S1_XPIXELS), 70 if walking else 64)

    def _expected_placement(self, facing: int, mode: int) -> tuple[int, int, int]:
        y, x = 24, 34
        if mode == self.fixture.PLACE_RIGHT:  # type: ignore[union-attr]
            x += 1
            follower_facing = facing
        elif mode == self.fixture.PLACE_LEFT:  # type: ignore[union-attr]
            x -= 1
            follower_facing = facing
        elif mode == self.fixture.PLACE_BELOW:  # type: ignore[union-attr]
            y += 1
            follower_facing = facing
        elif mode == self.fixture.PLACE_ABOVE:  # type: ignore[union-attr]
            y -= 1
            follower_facing = self._face_player(y, x)
        elif mode == self.fixture.PLACE_OVERLAP_DOWN:  # type: ignore[union-attr]
            follower_facing = self.fixture.FACING_DOWN  # type: ignore[union-attr]
        elif mode == self.fixture.PLACE_BEHIND:  # type: ignore[union-attr]
            if facing == self.fixture.FACING_DOWN:  # type: ignore[union-attr]
                y -= 1
            elif facing == self.fixture.FACING_UP:  # type: ignore[union-attr]
                y += 1
            elif facing == self.fixture.FACING_LEFT:  # type: ignore[union-attr]
                x += 1
            else:
                x -= 1
            follower_facing = self._face_player(y, x)
        elif mode == self.fixture.PLACE_AHEAD:  # type: ignore[union-attr]
            if facing == self.fixture.FACING_DOWN:  # type: ignore[union-attr]
                y += 1
                follower_facing = self.fixture.FACING_UP  # type: ignore[union-attr]
            elif facing == self.fixture.FACING_UP:  # type: ignore[union-attr]
                y -= 1
                follower_facing = self.fixture.FACING_DOWN  # type: ignore[union-attr]
            elif facing == self.fixture.FACING_LEFT:  # type: ignore[union-attr]
                x -= 1
                follower_facing = self.fixture.FACING_RIGHT  # type: ignore[union-attr]
            else:
                x += 1
                follower_facing = self.fixture.FACING_LEFT  # type: ignore[union-attr]
        else:
            follower_facing = facing
        return y, x, follower_facing

    def _face_player(self, y: int, x: int) -> int:
        assert self.fixture is not None
        player_y, player_x = 24, 34
        if y != player_y:
            return self.fixture.FACING_DOWN if y < player_y else self.fixture.FACING_UP
        if x != player_x:
            return self.fixture.FACING_RIGHT if x < player_x else self.fixture.FACING_LEFT
        return self.fixture.FACING_DOWN

    def test_placement_modes_reset_state_and_set_screen_position(self) -> None:
        assert self.fixture is not None
        for facing in (
            self.fixture.FACING_DOWN,
            self.fixture.FACING_UP,
            self.fixture.FACING_LEFT,
            self.fixture.FACING_RIGHT,
        ):
            self.fixture.write8(self.fixture.PLAYER_FACING, facing)
            for mode in range(8):
                self.fixture.write8(self.fixture.COMMAND_SIZE, 4)
                self.fixture.write_state1(self.fixture.S1_IMAGE, 0x55)
                self.assertEqual(self.fixture.place(0x42, mode)[1], False)
                expected_y, expected_x, expected_facing = self._expected_placement(facing, mode)
                self.assertEqual(self.fixture.read_state1(self.fixture.S1_PICTURE), 0x42)
                self.assertEqual(self.fixture.read_state2(self.fixture.S2_IMAGE_BASE), 2)
                self.assertEqual(self.fixture.read_state2(self.fixture.S2_MOVEMENT_BYTE), 0xFE)
                self.assertEqual(self.fixture.read_state2(self.fixture.S2_MAP_Y), expected_y)
                self.assertEqual(self.fixture.read_state2(self.fixture.S2_MAP_X), expected_x)
                self.assertEqual(self.fixture.read_state1(self.fixture.S1_YPIXELS), (expected_y - 20) * 16 - 4)
                self.assertEqual(self.fixture.read_state1(self.fixture.S1_XPIXELS), (expected_x - 30) * 16)
                self.assertEqual(self.fixture.read_state1(self.fixture.S1_FACING), expected_facing)
                self.assertEqual(self.fixture.read_state1(self.fixture.S1_STATUS), self.fixture.STATUS_READY)
                self.assertEqual(self.fixture.read_state1(self.fixture.S1_IMAGE), self.fixture.COMMAND_EMPTY)
                self.assertEqual(self.fixture.read8(self.fixture.COMMAND_SIZE), self.fixture.COMMAND_EMPTY)

                # Placement leaves the image hidden until a visibility refresh.
                self.assertFalse(self.fixture.update_image()[1])
                self.assertNotEqual(self.fixture.read_state1(self.fixture.S1_IMAGE), self.fixture.COMMAND_EMPTY)

    def test_invalid_placement_mode_is_carrying_and_atomic(self) -> None:
        assert self.fixture is not None
        for offset in range(16):
            self.fixture.write_state1(offset, 0x81 + offset)
            self.fixture.write_state2(offset, 0x91 + offset)
        self.fixture.write8(self.fixture.COMMAND_SIZE, 5)
        for offset in range(16):
            self.fixture.write8(self.fixture.COMMAND_BUFFER + offset, 0x30 + offset)
        before1 = [self.fixture.read_state1(i) for i in range(16)]
        before2 = [self.fixture.read_state2(i) for i in range(16)]
        before_queue = [self.fixture.read8(self.fixture.COMMAND_BUFFER + i) for i in range(16)]
        self.assertTrue(self.fixture.place(0x42, 8)[1])
        self.assertEqual([self.fixture.read_state1(i) for i in range(16)], before1)
        self.assertEqual([self.fixture.read_state2(i) for i in range(16)], before2)
        self.assertEqual(self.fixture.read8(self.fixture.COMMAND_SIZE), 5)
        self.assertEqual([self.fixture.read8(self.fixture.COMMAND_BUFFER + i) for i in range(16)], before_queue)

    def _tile_pointer_offset(self, ypixels: int, xpixels: int, *, round_up: bool = False) -> int:
        assert self.fixture is not None
        y = (ypixels + 4) & 0xFF
        if round_up and y & 0x0F:
            y = (y & 0xF0) + 0x10
        y = (y & 0xF0) >> 1
        x = ((xpixels + 2) & 0xFF) >> 3
        return y * 5 + 20 + x

    def test_visibility_bounds_textbox_and_grass_priority(self) -> None:
        assert self.fixture is not None
        self.fixture.write_state2(self.fixture.S2_MAP_Y, 24)
        self.fixture.write_state2(self.fixture.S2_MAP_X, 34)
        self.fixture.write_state1(self.fixture.S1_YPIXELS, 0)
        self.fixture.write_state1(self.fixture.S1_XPIXELS, 0)
        self.fixture.write_state1(self.fixture.S1_IMAGE, 0x44)
        pointer = self._tile_pointer_offset(0, 0)
        self.fixture.write8(self.fixture.TILE_MAP + pointer, self.fixture.read8(self.fixture.GRASS_TILE))
        self.assertFalse(self.fixture.visibility()[1])
        self.assertEqual(self.fixture.read_state2(self.fixture.S2_GRASS_PRIORITY), self.fixture.OAM_PRIO)

        self.fixture.write8(self.fixture.TILE_MAP + pointer, self.fixture.MAP_TILESET_SIZE)
        self.assertTrue(self.fixture.visibility()[1])
        self.assertEqual(self.fixture.read_state1(self.fixture.S1_IMAGE), self.fixture.COMMAND_EMPTY)

        self.fixture.clear()
        self.fixture.write8(self.fixture.PLAYER_Y, 0)
        self.fixture.write8(self.fixture.PLAYER_X, 0)
        self.fixture.write_state2(self.fixture.S2_MAP_Y, 9)
        self.fixture.write_state2(self.fixture.S2_MAP_X, 4)
        self.fixture.write_state1(self.fixture.S1_IMAGE, 0x44)
        self.assertTrue(self.fixture.visibility()[1])
        self.assertEqual(self.fixture.read_state1(self.fixture.S1_IMAGE), self.fixture.COMMAND_EMPTY)

        self.fixture.clear()
        self.fixture.write8(self.fixture.PLAYER_Y, 0)
        self.fixture.write8(self.fixture.PLAYER_X, 0)
        self.fixture.write_state2(self.fixture.S2_MAP_Y, 4)
        self.fixture.write_state2(self.fixture.S2_MAP_X, 4)
        self.fixture.write_state1(self.fixture.S1_YPIXELS, 0x8C)
        self.fixture.write_state1(self.fixture.S1_XPIXELS, 0)
        self.fixture.write_state1(self.fixture.S1_IMAGE, 0x44)
        self.assertTrue(self.fixture.visibility()[1])
        self.assertEqual(self.fixture.read_state1(self.fixture.S1_IMAGE), self.fixture.COMMAND_EMPTY)


if __name__ == "__main__":
    unittest.main(verbosity=2)
