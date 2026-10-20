"""Branching from save states (autoplay_branch.py): a branch replays exactly
from its state and key, the reel keeps snapshots spread over a whole run, and
a game that stops polling for input is reported frozen."""
import io
import unittest

import autoplay
import autoplay_branch
from test_smoke import HarnessTestCase


class SnapshotReelTest(unittest.TestCase):
    def test_reel_thins_evenly_and_selects_first_to_last(self) -> None:
        reel = autoplay_branch.SnapshotReel(limit=8)
        for frame in range(100):
            reel.offer("battle", frame, {}, lambda out: out.write(b"x"))
        numbers = [s.number for s in reel.kept["battle"]]
        self.assertLess(len(numbers), 8)
        self.assertEqual(numbers[0], 1)
        gaps = {b - a for a, b in zip(numbers, numbers[1:])}
        self.assertEqual(len(gaps), 1, numbers)  # evenly spaced
        chosen = [s.number for s in reel.select(3)]
        self.assertEqual(chosen, [numbers[0], numbers[len(numbers) // 2], numbers[-1]])
        self.assertEqual(reel.select(3), reel.select(3))
        self.assertEqual(reel.select(0), [])


class BranchDriverTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        assert self.harness is not None
        autoplay.boot(self.harness, seed=1)
        state = io.BytesIO()
        self.harness.save_state(state)
        self.state = state.getvalue()
        self.driver = autoplay_branch.BranchDriver(self.harness)

    def play(self, key: str, frames: int = 900) -> tuple[dict, bytes]:
        result = self.driver.run(self.state, key, frames)
        memory = self.harness.pyboy.memory
        return result, bytes(memory[address] for address in range(0xC000, 0xE000))  # WRAM

    def test_branch_replays_exactly(self) -> None:
        first, ram_first = self.play("test/1")
        again, ram_again = self.play("test/1")
        other, _ = self.play("test/2")
        self.assertEqual(first["outcome"], "ok", first)
        self.assertEqual(first["last_inputs"], again["last_inputs"])
        self.assertEqual(ram_first, ram_again)
        self.assertNotEqual(first["last_inputs"], other["last_inputs"])

    def test_no_input_poll_is_frozen(self) -> None:
        # Park the CPU on a `jr @` in ROM0: interrupts still run, Joypad never.
        memory = self.harness.pyboy.memory
        loop = next(a for a in range(0x100, 0x3FFF) if memory[a] == 0x18 and memory[a + 1] == 0xFE)
        self.harness.pyboy.register_file.PC = loop
        state = io.BytesIO()
        self.harness.save_state(state)
        self.driver.freeze_frames = 120
        result = self.driver.run(state.getvalue(), "test/frozen", 900)
        self.assertEqual(result["outcome"], "frozen", result)


if __name__ == "__main__":
    unittest.main(verbosity=2)
