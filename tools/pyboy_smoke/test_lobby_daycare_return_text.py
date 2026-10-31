"""Real lobby retrieval prints the selected daycare holder's nickname."""
import json
from pathlib import Path
import unittest

import autoplay
from harness import RedRogueHarness

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).parent/'artifacts'/'daycare_return_text'


class LobbyDaycareReturnTextTest(unittest.TestCase):
    cgb = False

    def run_retrieval(self, slot, other_occupied):
        output = ARTIFACTS/('cgb' if self.cgb else 'dmg')/self._testMethodName
        output.mkdir(parents=True, exist_ok=True)
        h = RedRogueHarness(ROOT, output, cgb_mode=self.cgb)
        self.addCleanup(h.close)
        h.boot_to_lobby()
        h.write8('wPartyCount', 2)
        h.write8('wPartySpecies', 255, offset=2)
        first = [0x80+ord(c)-ord('A') for c in 'FIRST'] + [0x50]*6
        second = [0x80+ord(c)-ord('A') for c in 'SECOND'] + [0x50]*5
        mon = h.read_bytes('wPartyMons', 33)
        mon[3] = h.read8('wPartyMon1Level')
        for number, nickname in ((1, first), (2, second)):
            suffix = '2' if number == 2 else ''
            active = number == slot or other_occupied
            h.write8('wDayCareInUse'+suffix, int(active))
            h.write8('wDayCareDepositBattleCount'+suffix, h.read8('wBattleCount'))
            for label, values in (('wDayCareMonName'+suffix, nickname if active else [0]*11),
                ('wDayCareMonOT'+suffix, h.read_bytes('wPartyMonOT', 11)),
                ('wDayCareMon2' if number == 2 else 'wDayCareMon', mon)):
                for offset, value in enumerate(values): h.write8(label, value, offset=offset)
        names = {h.address('wDayCareMonName'):first, h.address('wDayCareMonName2'):second}
        printed, nulls = [], []
        def text_source(_):
            r = h.pyboy.register_file
            pointer = (r.D << 8) | r.E
            if pointer in names: printed.append({'pointer':pointer,'bytes':h.read_bytes(
                'wDayCareMonName2' if pointer == h.address('wDayCareMonName2') else 'wDayCareMonName',11)})
        h.register_hook('PlaceString', text_source)
        h.register_hook('NullChar', lambda _: nulls.append(h.pyboy.frame_count))
        agent = autoplay.AutoplayAgent(h, seed=7)
        npc = 5 if slot == 2 else 4
        face = None
        for _ in range(80):
            goal = agent.talk_goal(agent.read_grid(), {npc:agent.sprites()[npc]}, 'special')
            if agent.position() in goal.spots:
                face = goal.spots[agent.position()][0]
                break
            path = autoplay.world.find_path(agent.read_grid(),agent.position(),set(goal.spots),agent.obstacles())
            self.assertTrue(path, 'no route to daycare NPC')
            agent.walk(path[0])
        self.assertIsNotNone(face, 'did not reach an interaction tile')
        h.tap(face,3);h.tick(20)
        for _ in range(160):
            h.tap('a',3);h.tick(12)
            if h.read8('wPartyCount') == 3 and printed: break
        wanted = h.address('wDayCareMonName2' if slot == 2 else 'wDayCareMonName')
        self.assertEqual(h.read8('wPartyCount'),3,'retrieval did not append')
        self.assertEqual(nulls,[], 'retrieval rendered <NULL>')
        self.assertTrue(printed,'return nickname was not rendered')
        self.assertEqual({r['pointer'] for r in printed},{wanted},'wrong daycare holder name')
        self.assertTrue(all(r['bytes']==names[wanted] for r in printed))
        self.assertEqual(h.read_bytes('wPartyMonNicks',11,22),names[wanted])
        self.assertFalse(h.hook_errors)
        h.pyboy.tick(1,render=True);h.pyboy.screen.image.save(output/'return.png')
        (output/'result.json').write_text(json.dumps({'slot':slot,'other_occupied':other_occupied,
            'printed':printed,'nulls':nulls,'tilemap':h.read_bytes('wTileMap',360),
            'rom_sha256':h.rom_sha256,'sym_sha256':h.sym_sha256},indent=2))

    def test_lady_with_empty_first_holder(self): self.run_retrieval(2,False)
    def test_lady_with_distinct_first_holder(self): self.run_retrieval(2,True)
    def test_gentleman_keeps_first_holder_name(self): self.run_retrieval(1,True)

