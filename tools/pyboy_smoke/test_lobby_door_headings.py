"""Render clipboard headings through the real nested far-text interpreter."""
import io
from test_smoke import HarnessTestCase


class LobbyDoorHeadingTest(HarnessTestCase):
    def test_numbering_tracks_both_available_clipboards(self):
        h = self.harness
        h.boot_fight2(seed=17)
        h.write8('wStatusFlags5', h.read8('wStatusFlags5') | 0x40)
        baseline = io.BytesIO()
        h.save_state(baseline)
        pending = {}

        def enter(_):
            if not pending:
                return
            bank, address = h.symbols.get(pending.pop('label'))
            # Enter ROMX text through its real far-text command, preserving
            # the bank trampoline's HOME caller context.
            for i, value in enumerate((0x17, address & 255, address >> 8, bank, 0x50)):
                h.write8('wStringBuffer', value, offset=i)
            h.pyboy.register_file.HL = h.address('wStringBuffer')
            cursor = h.address('wTileMap') + 14 * 20 + 1
            h.pyboy.register_file.B = cursor >> 8
            h.pyboy.register_file.C = cursor & 255

        h.register_hook('TextCommandProcessor', enter)
        errors = h.hook_flag('NullChar')
        for signs, first_y, numbered in ((2, 0, True), (1, 0, False), (2, 255, False)):
            for door in (1, 2):
                for category, expected in (('healing', 'HEALING ITEMS'), ('stat', 'STAT BOOSTS'),
                                           ('tm', 'TM ITEMS'), ('money', 'MONEY')):
                    with self.subTest(signs=signs, first_y=first_y, door=door, category=category):
                        baseline.seek(0)
                        h.load_state(baseline)
                        h.write8('wNumSigns', signs)
                        h.write8('wSignCoords', first_y)
                        for i in range(360):
                            h.write8('wTileMap', 0x7f, offset=i)
                        pending['label'] = f'LobbyDoor{door}SignText.{category}Text'
                        # Read at the return: the parked battle menu redraws wTileMap.
                        grid = h.call_routine('TextCommandProcessor',
                                              capture=lambda h: h.read_bytes('wTileMap', 360))
                        reward = [0x7f if c == ' ' else ord(c) - ord('A') + 0x80 for c in expected]
                        row = 16 if numbered else 14
                        self.assertEqual(grid[row * 20 + 1:row * 20 + 1 + len(reward)], reward)
                        heading = [ord(c) - ord('A') + 0x80 for c in 'DOOR']
                        self.assertEqual(grid[281:285] == heading, numbered)
        self.assertEqual(errors["count"], 0)
        self.assertEqual(h.hook_errors, [])
