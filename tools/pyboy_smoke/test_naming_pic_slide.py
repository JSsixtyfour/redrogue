"""FOLLOWUPS #56: preserve all 49 front-picture tiles across intro naming.

Only the difficulty/appearance chooser is bypassed, selecting the tested class.
The normal intro, picture renderer, slides and name menus execute in ROM.
"""
import io

from test_smoke import HarnessTestCase


class NamingPicSlideTest(HarnessTestCase):
    def test_full_picture_survives_name_list_and_both_name_return_paths(self):
        self._check_appearance(2, 'birdkeeper')

    def test_channeler_survives_name_list_and_both_name_return_paths(self):
        self._check_appearance(27, 'channeler')

    def _check_appearance(self, appearance, art_name):
        h = self.harness
        captures = {}
        in_name_choice = {'value': False}

        def picture():
            return list(h.pyboy.memory[0x9000:0x9310])

        def capture(name):
            captures[name] = (h.read_bytes('wTileMap', 360), picture())

        def choose_character(_):
            h.write8('wPlayerAppearance', appearance)
            rf = h.pyboy.register_file
            sp = rf.SP
            rf.PC = h.pyboy.memory[sp] | h.pyboy.memory[sp + 1] << 8
            rf.SP = sp + 2

        def before_name(_):
            in_name_choice['value'] = True
            capture('centered')

        def after_slide(_):
            if in_name_choice['value']:
                capture('slid')

        def name_menu(_):
            if in_name_choice['value'] and 'menu' not in captures:
                capture('menu')

        def returned(_):
            capture('returned')

        h.register_hook('ChooseDifficultyThenCharacter', choose_character)
        h.register_hook('ChoosePlayerName', before_name)
        h.register_hook('DisplayIntroNameTextBox', after_slide)
        h.register_hook('HandleMenuInput', name_menu)
        h.register_hook('ChoosePlayerName.done', returned)
        main = h.hook_flag('MainMenu')
        h.tick(240)
        for _ in range(300):
            h.tap('start', 1)
            if main['count']:
                break
        self.assertTrue(main['count'], 'Main menu not reached')
        for _ in range(500):
            if 'menu' in captures:
                break
            h.tap('a', 2)
            h.tick(6)
        self.assertIn('menu', captures, 'Naming menu not reached')

        expected_gfx = captures['centered'][1]
        source_art = h.repo_root / 'gfx/trainers' / (art_name + '.col.2bpp')
        self.assertEqual(bytes(expected_gfx), source_art.read_bytes())

        def assert_picture(name, x):
            tilemap, gfx = captures[name]
            self.assertEqual(gfx, expected_gfx, name + ': picture graphics changed')
            for col in range(7):
                for row in range(7):
                    self.assertEqual(tilemap[(4 + row) * 20 + x + col],
                                     col * 7 + row, (name, col, row))
            for row in range(18):
                for col in range(20):
                    if 4 <= row < 11 and x <= col < x + 7:
                        continue
                    tile = tilemap[row * 20 + col]
                    if tile < 49:
                        pixels = gfx[tile * 16:(tile + 1) * 16]
                        self.assertFalse(any(pixels),
                                         (name, 'stray picture tile', col, row, tile))

        assert_picture('centered', 6)
        assert_picture('slid', 12)
        assert_picture('menu', 12)
        h.tick(1, render=True)
        h.artifacts_dir.mkdir(parents=True, exist_ok=True)
        h.pyboy.screen.image.save(h.artifacts_dir / ('naming_slide_' + art_name + '.png'))
        menu_state = io.BytesIO()
        h.save_state(menu_state)

        # A default name returns through OakSpeechSlidePicLeft.
        h.tap('down')
        h.tap('a')
        h.wait_until(lambda: 'returned' in captures, 'default-name return', 600)
        assert_picture('returned', 6)

        # NEW NAME returns by drawing the front picture again.
        h.load_state(menu_state)
        del captures['returned']
        naming_input = h.hook_flag('DisplayNamingScreen.inputLoop')
        h.tick(8)  # Release the intro's final A edge before selecting NEW NAME.
        h.tap('a')
        h.wait_until(lambda: naming_input['count'] > 0, 'custom-name input', 600)
        h.tick(8)
        h.tap('a')  # Enter A, then submit so the empty-name retry cannot fire.
        h.tick(8)
        self.assertNotEqual(h.read8('wStringBuffer'), 0x50, 'No custom name entered')
        h.tap('start')
        h.wait_until(lambda: 'returned' in captures, 'custom-name return', 600)
        assert_picture('returned', 6)
