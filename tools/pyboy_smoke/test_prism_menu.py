"""Prism text/menu contracts; frame waits and button input are mocked at seams."""
import io
import re
from source_constants import parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT
from test_move_tutor_prices import return_from_call

TYPES = parse_rgbds_constants(REPO_ROOT / 'constants/type_constants.asm')
TYPE_NAMES = ['NORMAL','FIGHTING','FLYING','POISON','GROUND','ROCK','BUG','GHOST',
              'FIRE','WATER','GRASS','ELECTRIC','PSYCHIC_TYPE','ICE','DRAGON']

class PrismMenuTest(HarnessTestCase):
    def boot(self):
        h = self.harness
        h.boot_fight2(seed=17)
        h.write8('wStatusFlags5', h.read8('wStatusFlags5') | 0x40)
        self.baseline = io.BytesIO()
        h.save_state(self.baseline)
        return h

    def restore(self):
        self.baseline.seek(0)
        self.harness.load_state(self.baseline)

    def hook(self, label, callback):
        self.harness.pyboy.hook_register(*self.harness.symbols.get(label), callback, None)

    def test_every_type_renders_without_error_and_waits_for_acknowledgment(self):
        h = self.boot()
        self.hook('PrintText', lambda _: setattr(h.pyboy.register_file, 'PC', h.address('PrintText_NoCreatingTextBox')))
        grids = []
        self.hook('PromptText', lambda _: (grids.append(h.read_bytes('wTileMap',360)), setattr(h.pyboy.register_file,'PC',h.address('DoneText'))))
        errors = h.hook_flag('NullChar')
        for name in TYPE_NAMES:
            with self.subTest(type=name):
                self.restore()
                h.write_sram_bytes('sElementPrismType',[TYPES[name]])
                for i in range(360): h.write8('wTileMap',0x7f,offset=i)
                h.call_routine('RoguePrismShowEquipped')
                expected = name.replace('_TYPE','')
                self.assertEqual(grids[-1][321:321+len(expected)], [ord(c)-ord('A')+0x80 for c in expected])
                self.assertEqual(errors['count'],0)
        self.assertEqual(len(grids),15)

    def test_cartridge_select_cancel_spacing_and_parent_buffer(self):
        h = self.boot()
        self.hook('PrintText', lambda _: return_from_call(h))
        seen = []
        choice = {'row':0,'key':1}
        def menu(_):
            seen.append((h.read8('wMenuWatchedKeys'),h.read8('hUILayoutFlags'),h.read8('wMaxMenuItem')))
            h.write8('hCurrentMenuItem',choice['row'])
            h.pyboy.register_file.A = choice['key']
            return_from_call(h)
        self.hook('HandleMenuInput',menu)
        for row in range(15):
            self.restore()
            h.write_sram_bytes('sPrismCartridges',[255,127])
            h.write_sram_bytes('sElementPrismType',[TYPES['NORMAL']])
            h.write8('hUILayoutFlags',0)
            backup = h.read_bytes('wTileMapBackup2',360)
            choice.update(row=row,key=1)
            h.call_routine('RoguePrismCartridgeMenu')
            self.assertEqual(h.read_sram_bytes('sElementPrismType',1),[TYPES[TYPE_NAMES[row]]])
            self.assertEqual(h.read_bytes('wTileMapBackup2',360),backup)
            self.assertEqual(h.read8('hUILayoutFlags'),0)
            self.assertEqual(seen[-1][0],3) # Only A/B terminate HandleMenuInput.
            self.assertEqual(seen[-1][2],14)
            self.assertNotEqual(seen[-1][1],0)
        self.restore()
        h.write_sram_bytes('sPrismCartridges',[255,127])
        h.write_sram_bytes('sElementPrismType',[TYPES['FIRE']])
        choice.update(row=14,key=2)
        h.call_routine('RoguePrismCartridgeMenu')
        self.assertEqual(h.read_sram_bytes('sElementPrismType',1),[TYPES['FIRE']])

    def test_transfer_cursor_clamps_and_description_background_is_blank(self):
        h = self.boot()
        for count,scroll,cursor,expected in [(10,5,2,(5,2)),(7,5,2,(5,1)),(2,5,2,(1,0)),(1,0,1,(0,0))]:
            self.restore()
            h.write8('wKeyItemPocketBuf',count)
            h.write8('wListScrollOffset',scroll)
            h.write8('hCurrentMenuItem',cursor)
            h.call_routine('PlayerPCClampSelection')
            self.assertEqual((h.read8('wListScrollOffset'),h.read8('hCurrentMenuItem')),expected)
        self.restore()
        for i in range(36): h.write8('wTextBoxBuffer',0x80,offset=i)
        h.call_routine('PlayerPCBlankTransferText')
        self.assertEqual(h.read_bytes('wTextBoxBuffer',36),[0x7f]*36)

    def test_grant_destination_matches_equipment_and_preserves_item_alias(self):
        from test_key_item_equipment import bits
        h = self.boot()
        messages = []
        self.hook('PrintText',lambda _: (messages.append(h.pyboy.register_file.HL),return_from_call(h)))
        for active,label in [(('ELEMENT_PRISM',),'equipped'),((),'stored')]:
            self.restore()
            h.write_sram_bytes('sKeyItemsBitfield',bits(('ELEMENT_PRISM',),active))
            h.write8('wCurItem',42)
            h.call_routine('PrismShowGrantDestination')
            self.assertEqual(messages[-1],h.address('PrismShowGrantDestination.'+label))
            self.assertEqual(h.read8('wCurItem'),42)

    def test_empty_cartridge_collection_does_not_open_a_menu(self):
        h = self.boot()
        self.hook('PrintText',lambda _: return_from_call(h))
        menus=h.hook_flag('HandleMenuInput')
        h.write_sram_bytes('sPrismCartridges',[0,0])
        h.write_sram_bytes('sElementPrismType',[255])
        h.call_routine('RoguePrismCartridgeMenu')
        self.assertEqual(menus['count'],0)
        self.assertEqual(h.read_sram_bytes('sElementPrismType',1),[255])
