"""Isolated sequences of direct ROM calls, without resuming the live map.

Use genuine gameplay entry for choreography. This fixture is for transaction
checks that edit party/map data and call routines synchronously.
"""
from contextlib import contextmanager
import io


@contextmanager
def isolated_routine_calls(harness):
    """Keep transaction effects between calls; restore the whole machine on exit.

    call_routine normally resumes the interrupted map for the rest of the frame.
    That map cannot safely run on a synthetic party or hCurMap. Use the same
    synthetic WRAM caller as run_entry so each call returns to a stable loop.
    SRAM and WRAM effects remain observable throughout the session.

    Like run_entry, this is not a context for routines that wait for VBlank.
    Mock dialogue/graphics waits or use the real gameplay path instead.
    """
    harness.park_before_hijack()
    baseline = io.BytesIO()
    harness.save_state(baseline)
    try:
        harness.pyboy.memory[0xC100:0xC102] = [0x18, 0xFE]  # jr @
        harness.pyboy.register_file.PC = 0xC100
        yield
    finally:
        harness.load_state(baseline)
