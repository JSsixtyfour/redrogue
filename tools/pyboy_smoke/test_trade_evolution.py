"""Probe the built player dispatcher: trade now OR reach the authored level.

Stops before animation/group gating; full animation remains covered by
test_evolution_flow and user emulator acceptance.
"""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
METHODS = parse_rgbds_constants(ROOT / 'constants/pokemon_data_constants.asm')
SERIAL = parse_rgbds_constants(ROOT / 'constants/serial_constants.asm')


class TradeEvolutionTest(unittest.TestCase):
    def test_trade_any_level_or_level_threshold(self):
        h = RedRogueHarness(ROOT, Path(__file__).parent / 'artifacts')
        try:
            h.boot_to_lobby()
            cases = {'Rhydon': 40, 'Scyther': 40, 'Electabuzz': 40,
                     'Seadra': 40, 'Poliwhirl': 40, 'Porygon': 40, 'Porygon2': 50,
                     'Machoke': 38, 'Graveler': 38, 'Kadabra': 42, 'Haunter': 42}
            for name, threshold in cases.items():
                bank, cursor = h.symbols.get(name + 'EvosMoves')
                while h.pyboy.memory[bank, cursor] != METHODS['EVOLVE_TRADE']:
                    method = h.pyboy.memory[bank, cursor]
                    self.assertNotEqual(method, 0, name)
                    cursor += 4 if method == METHODS['EVOLVE_ITEM'] else 3
                self.assertEqual(h.pyboy.memory[bank, cursor + 1], threshold, name)
                target = h.pyboy.memory[bank, cursor + 2]
                for trading, forced, level, eligible in (
                    (False, False, threshold - 1, False),
                    (False, False, threshold, True),
                    (False, False, threshold + 1, True),
                    (True, False, 1, True),
                    (True, False, threshold - 1, True),
                    (True, False, threshold, True),
                    (False, True, threshold, False),
                ):
                    with self.subTest(species=name, trading=trading, forced=forced, level=level):
                        h.park_before_hijack()
                        h.write8('wLinkState', SERIAL['LINK_STATE_TRADING'] if trading else 0)
                        h.write8('wForceEvolution', int(forced))
                        h.write8('wLoadedMonLevel', level)
                        stub = h.address('wStringBuffer')
                        h.pyboy.memory[stub:stub + 2] = [0x18, 0xfe]
                        result = []

                        def enter(_):
                            h.pyboy.register_file.B = METHODS['EVOLVE_TRADE']
                            h.pyboy.register_file.HL = cursor + 1

                        def stop(accepted):
                            def capture(_):
                                regs = h.pyboy.register_file
                                result.append((accepted, regs.HL, regs.A))
                                regs.PC = stub
                            return capture

                        hooks = [('Evolution_PartyMonLoop.normalEvolutionChecks', enter),
                                 ('Evolution_PartyMonLoop.doEvolution', stop(True)),
                                 ('Evolution_PartyMonLoop.nextEvoEntry1', stop(False)),
                                 ('Evolution_PartyMonLoop.nextEvoEntry2', stop(False))]
                        for label, callback in hooks:
                            h.register_hook(label, callback)
                        try:
                            h.probe_routine_until(hooks[0][0], lambda: bool(result), limit=10)
                        finally:
                            for label, callback in hooks:
                                h.unregister_hook(label, callback)
                        self.assertEqual(result[0][0], eligible)
                        if eligible:
                            self.assertEqual(result[0][1:], (cursor + 2, level))
                            self.assertEqual(h.pyboy.memory[bank, cursor + 2], target)
        finally:
            h.close()
