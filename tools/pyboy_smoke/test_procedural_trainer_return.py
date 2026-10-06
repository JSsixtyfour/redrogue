"""Built-ROM probes for procedural trainer sight and battle-return state."""
import io

from test_smoke import HarnessTestCase, REPO_ROOT
from source_constants import parse_map_constants, parse_rgbds_constants


AREAS = (
    ('PROCEDURAL_CAVE_1', 'PCPlaceStageEventNpcs', 6),
    ('PROCEDURAL_FOREST', 'PFPlaceStageEventNpcs', 6),
    ('PROCEDURAL_FACILITY', 'PFacPlaceStageEventNpcs', 10),
    *((f'PROCEDURAL_CEMETERY_{floor}', 'PCemPlaceStageEventNpcs', 2)
      for floor in range(1, 5)),
)


class ProceduralTrainerReturnTest(HarnessTestCase):
    def setUp(self):
        super().setUp()
        self.harness.boot_to_lobby(battle_count=17)
        self.harness.park_before_hijack()
        # call_routine resumes to the frame boundary; suspend ordinary sprite
        # and OAM updates so those cannot change the exact fixture afterward.
        self.harness.write8('hUpdateSpritesEnabled', 2)
        self.maps = parse_map_constants(REPO_ROOT / 'constants/map_constants.asm')
        self.sprites = parse_rgbds_constants(REPO_ROOT / 'constants/sprite_constants.asm')
        self.state = io.BytesIO()
        self.harness.pyboy.save_state(self.state)

    def restore(self):
        self.state.seek(0)
        self.harness.pyboy.load_state(self.state)

    def test_battle_return_preserves_both_npc_positions_and_movement(self):
        h = self.harness
        for map_name, placement, slot in AREAS:
            with self.subTest(map=map_name):
                self.restore()
                h.write8('hCurMap', self.maps[map_name])
                h.write8('wStatusFlags4', 1 << 5)  # BIT_BATTLE_OVER_OR_BLACKOUT
                # Distinct approached positions and pixel copies, not spawn points.
                for index in (slot, slot + 1):
                    for page in (1, 2):
                        for offset in range(16):
                            h.write8(f'wSprite{index:02d}StateData{page}',
                                     20 + index + offset, offset=offset)
                def movement_state():
                    # OAM refresh can recompute adjusted draw coordinates at
                    # offsets 10/11. Compare the live position/movement fields.
                    return tuple(h.read8(f'wSprite{index:02d}StateData{page}', offset)
                                 for index in (slot, slot + 1)
                                 for page, fields in ((1, range(10)), (2, range(16)))
                                 for offset in fields)
                before = movement_state()
                h.call_routine(placement)
                self.assertEqual(movement_state(), before)

    def test_sight_limit_only_applies_to_stationary_event_sprites(self):
        h = self.harness
        sprites = {name: self.sprites[constant] for name, constant in (
            ('Nurse', 'SPRITE_NURSE'), ('Jessie', 'SPRITE_JESSIE'),
            ('James', 'SPRITE_JAMES'), ('Psychic', 'SPRITE_MIDDLE_AGED_MAN'),
            ('Burglar', 'SPRITE_GAMBLER'), ('Jenny', 'SPRITE_OFFICER_JENNY'))}
        for map_name, _, slot in AREAS:
            for sprite, picture in sprites.items():
                for index in (slot, slot + 1):
                    with self.subTest(map=map_name, sprite=sprite, slot=index):
                        self.restore()
                        h.write8('hCurMap', self.maps[map_name])
                        h.write8('hActiveSpriteIndex', index)
                        h.write8('wTrainerSpriteOffset', index * 16)
                        h.write8(f'wSprite{index:02d}StateData1', picture)
                        h.write8('wTrainerEngageDistance', 4 * 16)
                        h.call_routine('StageEventLimitTrainerSight')
                        expected = 16 if sprite in ('Nurse', 'Jessie', 'James') else 64
                        self.assertEqual(h.read8('wTrainerEngageDistance'), expected)
        # A stale procedural event must not affect an ordinary-map trainer.
        h.write8('hCurMap', self.maps['OAKS_LAB'])
        h.write8('wTrainerEngageDistance', 64)
        h.write8('wSprite06StateData1', 0x29)
        h.write8('wTrainerSpriteOffset', 6 * 16)
        h.write8('hActiveSpriteIndex', 6)
        h.call_routine('StageEventLimitTrainerSight')
        self.assertEqual(h.read8('wTrainerEngageDistance'), 64)

    def test_live_sight_scan_engages_adjacent_but_keeps_other_approaches(self):
        h = self.harness
        for map_name, _, slot in AREAS:
            for picture in ('SPRITE_NURSE', 'SPRITE_JESSIE', 'SPRITE_JAMES',
                            'SPRITE_OFFICER_JENNY', 'SPRITE_GAMBLER'):
                for distance in (1, 2):
                    with self.subTest(map=map_name, picture=picture, distance=distance):
                        self.restore()
                        h.write8('hCurMap', self.maps[map_name])
                        h.write8('hActiveSpriteIndex', slot)
                        h.write8('wTrainerSpriteOffset', slot * 16)
                        h.write8(f'wSprite{slot:02d}StateData1', self.sprites[picture])
                        h.write8(f'wSprite{slot:02d}StateData1', 0, offset=2)
                        h.write8(f'wSprite{slot:02d}StateData1', 0x3c - distance * 16, offset=4)
                        h.write8(f'wSprite{slot:02d}StateData1', 0x40, offset=6)
                        h.write8(f'wSprite{slot:02d}StateData1', 0, offset=9)
                        h.write8('wTrainerEngageDistance', 64)
                        h.call_routine('TrainerEngage')
                        stationary = picture in ('SPRITE_NURSE', 'SPRITE_JESSIE', 'SPRITE_JAMES')
                        self.assertEqual(h.read8('wTrainerSpriteOffset'),
                                         0 if stationary and distance == 2 else 0xff)

    def test_joy_returns_to_standing_without_moving(self):
        h = self.harness
        for map_name, _, slot in AREAS:
            with self.subTest(map=map_name):
                self.restore()
                h.write8('hCurMap', self.maps[map_name])
                h.write8('wStageEvent', 4 | (2 << 3))  # settled Joy
                h.write8(f'wSprite{slot:02d}StateData1', 0x29)
                h.write8(f'wSprite{slot:02d}StateData1', 2, offset=7)
                h.write8(f'wSprite{slot:02d}StateData1', 1, offset=8)
                h.write8(f'wSprite{slot:02d}StateData1', 4, offset=9)  # bow/up
                h.write8(f'wSprite{slot:02d}StateData2', 22, offset=4)
                h.write8(f'wSprite{slot:02d}StateData2', 23, offset=5)
                h.pyboy.register_file.D = slot
                h.call_routine('StageEventApplyTrainers')
                self.assertEqual(h.read8(f'wSprite{slot:02d}StateData1', 7), 0)
                self.assertEqual(h.read8(f'wSprite{slot:02d}StateData1', 8), 0)
                self.assertEqual(h.read8(f'wSprite{slot:02d}StateData1', 9), 0)
                self.assertEqual(h.read8(f'wSprite{slot:02d}StateData2', 4), 22)
                self.assertEqual(h.read8(f'wSprite{slot:02d}StateData2', 5), 23)
                h.write8('hCurrentSpriteOffset', slot * 16)
                h.write8('hTilePlayerStandingOn', 0x50)
                h.call_routine('UpdateSpriteImage')
                self.assertEqual(h.read8(f'wSprite{slot:02d}StateData1', 2), 0x50)
