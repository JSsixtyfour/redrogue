from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants


REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"


class PokemonCenterSourceContractTest(unittest.TestCase):
    def test_center_flow_uses_first_repeat_text_and_no_decline_path(self) -> None:
        source = (REPO_ROOT / "engine" / "events" / "pokecenter.asm").read_text()
        flow = source[
            source.index("DisplayPokemonCenterDialogue_::"):
            source.index("PokemonCenterFirstHealText:")
        ]

        self.assertNotIn("YesNoChoicePokeCenter", flow)
        self.assertNotIn("hCurrentMenuItem", flow)
        self.assertNotIn("declinedHealing", flow)
        self.assertIn("call SaveScreenTilesToBuffer1", flow)
        self.assertIn("bit BIT_USED_POKECENTER, [hl]", flow)
        self.assertIn("set BIT_UNKNOWN_4_1, [hl]", flow)
        self.assertIn("set BIT_USED_POKECENTER, [hl]", flow)
        self.assertLess(
            flow.index("ld hl, PokemonCenterFirstHealText"),
            flow.index("ld hl, PokemonCenterRepeatHealText"),
        )
        self.assertIn("call SetLastBlackoutMap", flow)
        self.assertIn("call LoadScreenTilesFromBuffer1", flow)
        self.assertIn("ld hl, NeedYourPokemonText\n\tcall PrintText", flow)
        self.assertIn("ld a, $28", flow)
        self.assertIn("call Delay3", flow)
        self.assertIn("predef HealParty", flow)
        self.assertIn("farcall AnimateHealingMachine", flow)
        self.assertIn("xor a\n\tld [wAudioFadeOutControl], a", flow)
        self.assertIn("ld a, [wAudioSavedROMBank]", flow)
        self.assertIn("ld a, [wMapMusicSoundID]", flow)
        self.assertIn("call PlaySound", flow)
        self.assertIn("ld a, $24", flow)
        self.assertIn("ld c, a\n\tcall DelayFrames", flow)
        self.assertIn("ld hl, PokemonCenterFarewellText\n\tcall PrintText", flow)
        self.assertIn("jp UpdateSprites", flow)
        self.assertNotIn("PokemonFightingFitText", flow)

    def test_healing_machine_loop_copies_then_delays_once_and_flashes_palette(self) -> None:
        source = (REPO_ROOT / "engine" / "overworld" / "healing_machine.asm").read_text()
        loop_start = source.index(".partyLoop")
        after_loop = source.index("\tld a, [wAudioROMBank]", loop_start)
        loop = source[loop_start:after_loop]
        sound = loop.index("ld a, SFX_HEALING_MACHINE")
        copy_phase = loop[:sound]

        self.assertIn("call CopyHealingMachineOAM", copy_phase)
        self.assertIn("dec b\n\tjr nz, .partyLoop", copy_phase)
        self.assertNotIn("SFX_HEALING_MACHINE", copy_phase)
        self.assertNotIn("DelayFrames", copy_phase)
        self.assertEqual(loop.count("ld a, SFX_HEALING_MACHINE"), 1)
        self.assertIn("ld c, 30\n\tcall DelayFrames", loop[sound:])
        flash = source[source.index("FlashSprite8Times:"):source.index("CopyHealingMachineOAM:")]
        self.assertIn("ldh [rOBP1], a\n\tcall UpdateGBCPal_OBP1", flash)
        for anchor in (
            "ld a, $ff",
            "wSprite15StateData1 + SPRITESTATEDATA1_IMAGEINDEX",
            "farcall PrepareOAMData",
            "hUpdateSpritesEnabled",
            "rOBP1",
            "UpdateGBCPal_OBP1",
            "wAudioFadeOutControl",
            "SFX_STOP_ALL_MUSIC",
            "wAudioROMBank",
            "Music_PkmnHealed",
            "FlashSprite8Times",
            "FollowerRefreshAfterHeal",
        ):
            self.assertIn(anchor, source)

    def test_center_text_blocks_are_short_and_exact(self) -> None:
        source = (REPO_ROOT / "data" / "text" / "text_4.asm").read_text()
        first = source[
            source.index("_PokemonCenterFirstHealText::"):
            source.index("_PokemonCenterRepeatHealText::")
        ]
        repeat = source[
            source.index("_PokemonCenterRepeatHealText::"):
            source.index("_NeedYourPokemonText::")
        ]
        need = source[
            source.index("_NeedYourPokemonText::"):
            source.index("_PokemonCenterFarewellText::")
        ]
        farewell = source[
            source.index("_PokemonCenterFarewellText::"):
            source.index("_CableClubNPCAreaReservedFor2FriendsLinkedByCableText::")
        ]
        self.assertIn('text "Welcome! I\'ll"', first)
        self.assertIn('line "heal your #MON."', first)
        self.assertIn("prompt", first)
        self.assertIn('text "Let\'s heal your"', repeat)
        self.assertIn('line "#MON!"', repeat)
        self.assertIn("prompt", repeat)
        self.assertIn('text "OK. We\'ll need"', need)
        self.assertIn('line "your #MON."', need)
        self.assertIn("done", need)
        self.assertIn('text "We hope to see"', farewell)
        self.assertIn('line "you again!"', farewell)
        self.assertIn("done", farewell)
        self.assertNotIn("@", first + repeat + need + farewell)

        def rendered_length(block: str) -> int:
            return sum(
                len(line.split('"', 2)[1])
                for line in block.splitlines()
                if any(line.lstrip().startswith(op) for op in ("text ", "line ", "cont ", "para "))
            )

        for block in (first, repeat, need, farewell):
            for line in block.splitlines():
                stripped = line.lstrip()
                if any(stripped.startswith(op) for op in ("text ", "line ", "cont ", "para ")):
                    self.assertLessEqual(len(stripped.split('"', 2)[1]), 17)
        self.assertLess(rendered_length(repeat), rendered_length(first))


class HealPartyRuntimeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)

    def tearDown(self) -> None:
        self.harness.close()

    def test_one_and_six_party_members_restore_hp_status_and_pp(self) -> None:
        h = self.harness
        h.boot_fight2(seed=1)
        moves = parse_rgbds_constants(REPO_ROOT / "constants" / "move_constants.asm")
        tackle = moves["TACKLE"]
        original_species = h.read_bytes("wPartySpecies", 7)

        for party_count in (1, 6):
            with self.subTest(party_count=party_count):
                h.write8("wPartyCount", party_count)
                for offset in range(7):
                    h.write8(
                        "wPartySpecies",
                        original_species[offset] if offset < party_count else 0xFF,
                        offset=offset,
                    )
                for slot in range(1, party_count + 1):
                    mon = f"wPartyMon{slot}"
                    h.write8(f"{mon}Status", 0xFF)
                    h.write8(f"{mon}HP", 0)
                    h.write8(f"{mon}HP", 0, offset=1)
                    h.write8(f"{mon}MaxHP", 1)
                    h.write8(f"{mon}MaxHP", 0x23, offset=1)
                    h.write8(f"{mon}Moves", tackle)
                    for move_offset in range(1, 4):
                        h.write8(f"{mon}Moves", 0, offset=move_offset)
                    h.write8(f"{mon}PP", 1 << 6)  # one PP Up, zero current PP
                    for pp_offset in range(1, 4):
                        h.write8(f"{mon}PP", 0, offset=pp_offset)

                h.park_before_hijack()
                h.call_routine("HealParty")

                for slot in range(1, party_count + 1):
                    mon = f"wPartyMon{slot}"
                    self.assertEqual(h.read_bytes(f"{mon}HP", 2), [1, 0x23])
                    self.assertEqual(h.read8(f"{mon}Status"), 0)
                    self.assertEqual(h.read8(f"{mon}PP"), 0x40 + 35 + 7)
                    self.assertEqual(h.read_bytes(f"{mon}PP", 3, offset=1), [0, 0, 0])


if __name__ == "__main__":
    unittest.main(verbosity=2)
