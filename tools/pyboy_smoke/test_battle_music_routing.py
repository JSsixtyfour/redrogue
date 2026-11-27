"""Battle music routing and the per-round ramp (audio/play_battle_music.asm).

Drives GetBattleMusicSong directly from a FIGHT 2 park with each battle's
deciding state written in, and reads the song at its single exit. The ramp
walk and the Endless roll are exercised by swapping in a fake multi-row ramp
at .gotRamp, so they don't depend on which shipped ramps have several rows."""
import io
import unittest

from source_constants import parse_map_constants, parse_rgbds_constants, parse_trainer_constants
from test_smoke import HarnessTestCase, REPO_ROOT

MUSIC = parse_rgbds_constants(REPO_ROOT / "constants/music_constants.asm")
MAPS = parse_map_constants(REPO_ROOT / "constants/map_constants.asm")
OPP = parse_trainer_constants(REPO_ROOT / "constants/trainer_constants.asm")
EVENTS = parse_rgbds_constants(REPO_ROOT / "constants/event_constants.asm")
SPECIES = parse_rgbds_constants(REPO_ROOT / "constants/pokemon_constants.asm")
ROUND_BATTLES = parse_rgbds_constants(
    REPO_ROOT / "constants/round_constants.asm")["ROUND_BATTLES"]
RAM_CONSTANTS = parse_rgbds_constants(REPO_ROOT / "constants/ram_constants.asm")
BIT_TALKED_TO_TRAINER = RAM_CONSTANTS["BIT_TALKED_TO_TRAINER"]
BIT_ROGUE_FINAL_TRAINER = RAM_CONSTANTS["BIT_ROGUE_FINAL_TRAINER"]
ROUND = parse_rgbds_constants(REPO_ROOT / "constants/round_constants.asm")
FINAL_ROUTE_STEP, FINAL_GYM_TRAINER_STEP = ROUND["FINAL_ROUTE_STEP"], ROUND["FINAL_GYM_TRAINER_STEP"]
JOHTO = EVENTS["EVENT_JOHTO_ACTIVATED"]
FAKE_RAMP = "wTileMapBackup"  # scratch the routine never touches


class BattleMusicRoutingTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        self.baseline = io.BytesIO()
        h.save_state(self.baseline)
        self.captured = {}
        self.fake_ramp = None
        h.register_hook("GetBattleMusicSong.done", self._at_done)
        h.register_hook("GetBattleMusicSong.gotRamp", self._at_ramp)

    def _at_done(self, _) -> None:
        self.captured["song"] = self.harness.pyboy.register_file.C  # hook fires before `ld a, c`

    def _at_ramp(self, _) -> None:
        if self.fake_ramp is not None:
            self.harness.pyboy.register_file.HL = self.harness.address(FAKE_RAMP)

    def song(self, *, opponent=0, trainer=True, gym_leader=0, map_name="REDS_HOUSE_1F",
             johto=False, talked=False, sprite=0, cemetery_boss=False, depth=0,
             battle_count=1, fake_ramp=None, seed=None, party=(), party_count=None,
             wild_species=None, final=False) -> int:
        h = self.harness
        self.baseline.seek(0)
        h.load_state(self.baseline)
        if seed is not None:
            h.seed_rng(seed)
        h.write8("wCurOpponent", opponent)
        # The Mewtwo override reads the wild species and the built trainer party.
        h.write8("wEnemyMonSpecies2", opponent if wild_species is None else wild_species)
        h.write8("wEnemyPartyCount", len(party) if party_count is None else party_count)
        for offset, species in enumerate(list(party) + [0xFF]):
            h.write8("wEnemyPartySpecies", species, offset)
        h.write8("wIsTrainerBattle", 1 if trainer else 0)
        h.write8("wGymLeaderNo", gym_leader)
        h.write8("hCurMap", MAPS[map_name])
        flags = h.read8("wEventFlags", JOHTO // 8)
        bit = 1 << (JOHTO % 8)
        h.write8("wEventFlags", flags | bit if johto else flags & ~bit, JOHTO // 8)
        status = h.read8("wStatusFlags3")
        bit = 1 << BIT_TALKED_TO_TRAINER
        h.write8("wStatusFlags3", status | bit if talked else status & ~bit)
        h.write8("hActiveSpriteIndex", sprite)
        h.write8("wProcCemBossBattle", 1 if cemetery_boss else 0)
        # GetRandRoster's "final trainer of the tier" bit (ReadTrainer clears it
        # for authored teams); written both ways so the baseline can't leak in.
        flags = h.read8("wRogueFlagsBitfield")
        bit = 1 << BIT_ROGUE_FINAL_TRAINER
        h.write8("wRogueFlagsBitfield", flags | bit if final else flags & ~bit)
        h.write8("wEndlessDepth", depth)
        h.write8("wBattleCount", battle_count)
        self.fake_ramp = fake_ramp
        if fake_ramp is not None:
            for offset, value in enumerate(fake_ramp + [0xFF]):
                h.write8(FAKE_RAMP, value, offset)
        self.captured.clear()
        h.call_routine("GetBattleMusicSong", limit=2000)
        self.assertIn("song", self.captured, "GetBattleMusicSong never reached .done")
        return self.captured["song"]

    def test_kanto_routing_is_unchanged(self) -> None:
        self.assertEqual(self.song(trainer=False, opponent=1), MUSIC["MUSIC_WILD_BATTLE"])
        self.assertEqual(self.song(opponent=OPP["YOUNGSTER"]), MUSIC["MUSIC_TRAINER_BATTLE"])
        self.assertEqual(self.song(opponent=OPP["BROCK"], gym_leader=1, map_name="PEWTER_GYM"),
                         MUSIC["MUSIC_GYM_LEADER_BATTLE"])
        self.assertEqual(self.song(opponent=OPP["RIVAL3"]), MUSIC["MUSIC_FINAL_BATTLE"])
        self.assertEqual(self.song(opponent=OPP["FINAL_AI"]), MUSIC["MUSIC_FINAL_BATTLE"])
        self.assertEqual(self.song(opponent=OPP["PROF_OAK"], map_name="CHAMPIONS_ROOM"),
                         MUSIC["MUSIC_FINAL_BATTLE"])
        self.assertEqual(self.song(opponent=OPP["LANCE"], map_name="LANCES_ROOM"),
                         MUSIC["MUSIC_GYM_LEADER_BATTLE"])
        for e4 in ("LORELEI", "BRUNO", "AGATHA", "KOGA_E4"):
            with self.subTest(e4=e4):
                self.assertEqual(self.song(opponent=OPP[e4]), MUSIC["MUSIC_TRAINER_BATTLE"])

    def test_johto_routing(self) -> None:
        johto_gyms = ("VIOLET_GYM", "AZALEA_GYM", "GOLDENROD_GYM", "ECRUTEAK_GYM",
                      "CIANWOOD_GYM", "OLIVINE_GYM", "MAHOGANY_GYM", "BLACKTHORN_GYM")
        for gym in johto_gyms:
            with self.subTest(gym=gym):
                self.assertEqual(self.song(opponent=OPP["COOLTRAINER_M"], map_name=gym),
                                 MUSIC["MUSIC_JOHTO_TRAINER_BATTLE"])
        # Janine leads Fuchsia, but it is a Kanto map: its trainers stay Kanto.
        self.assertEqual(self.song(opponent=OPP["JUGGLER"], map_name="FUCHSIA_GYM"),
                         MUSIC["MUSIC_TRAINER_BATTLE"])
        leaders = ("FALKNER", "BUGSY", "WHITNEY", "MORTY", "CHUCK", "JASMINE", "PRYCE",
                   "CLAIR")
        for number, leader in enumerate(leaders, start=1):
            with self.subTest(leader=leader):
                self.assertEqual(self.song(opponent=OPP[leader], gym_leader=number),
                                 MUSIC["MUSIC_JOHTO_GYM_BATTLE"])
        # Janine leads a Kanto gym: Kanto leader theme.
        self.assertEqual(self.song(opponent=OPP["JANINE"], gym_leader=5, map_name="FUCHSIA_GYM"),
                         MUSIC["MUSIC_GYM_LEADER_BATTLE"])
        for e4 in ("WILL", "KAREN"):
            with self.subTest(e4=e4):
                self.assertEqual(self.song(opponent=OPP[e4]), MUSIC["MUSIC_JOHTO_GYM_BATTLE"])
        self.assertEqual(self.song(opponent=OPP["LANCE"], map_name="CHAMPIONS_ROOM"),
                         MUSIC["MUSIC_CHAMPION_BATTLE"])

    def test_stage_bosses(self) -> None:
        wild = MUSIC["MUSIC_WILD_BATTLE"]
        suicune = MUSIC["MUSIC_SUICUNE_BATTLE"]
        for stage in ("PROCEDURAL_CAVE_1", "PROCEDURAL_FOREST", "PROCEDURAL_FACILITY"):
            with self.subTest(stage=stage):
                boss = dict(trainer=False, opponent=1, map_name=stage, talked=True, sprite=1)
                self.assertEqual(self.song(**boss), wild)
                self.assertEqual(self.song(johto=True, **boss), suicune)
                # an ordinary wild encounter on the same map
                self.assertEqual(self.song(trainer=False, opponent=1, map_name=stage,
                                           johto=True), wild)
        # the facility's fake-ball Voltorbs engage the same way from slots 6-9
        self.assertEqual(self.song(trainer=False, opponent=1, map_name="PROCEDURAL_FACILITY",
                                   talked=True, sprite=6, johto=True), wild)
        # a talked-to slot-1 overworld mon off the procedural maps is not a boss
        self.assertEqual(self.song(trainer=False, opponent=1, map_name="REDS_HOUSE_1F",
                                   talked=True, sprite=1, johto=True), wild)
        cemetery = dict(trainer=False, opponent=1, map_name="PROCEDURAL_CEMETERY_4",
                        cemetery_boss=True)
        self.assertEqual(self.song(**cemetery), wild)
        self.assertEqual(self.song(johto=True, **cemetery), suicune)

    def test_mewtwo_overrides_all_but_the_finale(self) -> None:
        mewtwo = MUSIC["MUSIC_MEWTWO_BATTLE"]
        MEWTWO, PIDGEY = SPECIES["MEWTWO"], SPECIES["PIDGEY"]
        # wild: any Mewtwo, ordinary or a stage boss, Johto or not
        self.assertEqual(self.song(trainer=False, opponent=MEWTWO), mewtwo)
        self.assertEqual(self.song(trainer=False, opponent=0, wild_species=MEWTWO), mewtwo)
        self.assertEqual(self.song(trainer=False, opponent=MEWTWO, map_name="PROCEDURAL_CAVE_1",
                                   talked=True, sprite=1, johto=True), mewtwo)
        self.assertEqual(self.song(trainer=False, opponent=PIDGEY), MUSIC["MUSIC_WILD_BATTLE"])
        # trainers: Mewtwo anywhere in the party, including the last slot
        with_mewtwo = [PIDGEY] * 5 + [MEWTWO]
        self.assertEqual(self.song(opponent=OPP["YOUNGSTER"], party=with_mewtwo), mewtwo)
        self.assertEqual(self.song(opponent=OPP["YOUNGSTER"], party=[PIDGEY] * 6),
                         MUSIC["MUSIC_TRAINER_BATTLE"])
        self.assertEqual(self.song(opponent=OPP["BROCK"], gym_leader=1, map_name="PEWTER_GYM",
                                   party=[MEWTWO]), mewtwo)
        self.assertEqual(self.song(opponent=OPP["COOLTRAINER_M"], map_name="VIOLET_GYM",
                                   party=[MEWTWO]), mewtwo)
        self.assertEqual(self.song(opponent=OPP["FALKNER"], gym_leader=1, party=[MEWTWO]),
                         mewtwo)
        # the finale keeps its own song
        self.assertEqual(self.song(opponent=OPP["RIVAL3"], party=[MEWTWO]),
                         MUSIC["MUSIC_FINAL_BATTLE"])
        self.assertEqual(self.song(opponent=OPP["PROF_OAK"], map_name="CHAMPIONS_ROOM",
                                   party=[MEWTWO]), MUSIC["MUSIC_FINAL_BATTLE"])
        self.assertEqual(self.song(opponent=OPP["LANCE"], map_name="CHAMPIONS_ROOM",
                                   party=[MEWTWO]), MUSIC["MUSIC_CHAMPION_BATTLE"])
        # a stale Mewtwo past wEnemyPartyCount is not in the party
        self.assertEqual(self.song(opponent=OPP["YOUNGSTER"], party=[PIDGEY, MEWTWO],
                                   party_count=1), MUSIC["MUSIC_TRAINER_BATTLE"])

    def test_ho_oh_overrides_all_but_the_finale(self) -> None:
        ho_oh = MUSIC["MUSIC_HO_OH_BATTLE"]
        HO_OH, MEWTWO, PIDGEY = SPECIES["HO_OH"], SPECIES["MEWTWO"], SPECIES["PIDGEY"]
        # wild: any Ho-Oh, ordinary or a Johto stage boss
        self.assertEqual(self.song(trainer=False, opponent=0, wild_species=HO_OH), ho_oh)
        self.assertEqual(self.song(trainer=False, opponent=0, wild_species=HO_OH,
                                   map_name="PROCEDURAL_CAVE_1", talked=True, sprite=1,
                                   johto=True), ho_oh)
        # trainers: Ho-Oh anywhere in the party, over gym and Rocket music
        self.assertEqual(self.song(opponent=OPP["YOUNGSTER"], party=[PIDGEY] * 5 + [HO_OH]),
                         ho_oh)
        self.assertEqual(self.song(opponent=OPP["FALKNER"], gym_leader=1, party=[HO_OH]), ho_oh)
        self.assertEqual(self.song(opponent=OPP["ROCKET"], johto=True, party=[HO_OH]), ho_oh)
        # Mewtwo wins a party with both, in either order
        for party in ([HO_OH, MEWTWO], [MEWTWO, HO_OH]):
            with self.subTest(party=party):
                self.assertEqual(self.song(opponent=OPP["YOUNGSTER"], party=party),
                                 MUSIC["MUSIC_MEWTWO_BATTLE"])
        # the finale keeps its own song
        self.assertEqual(self.song(opponent=OPP["RIVAL3"], party=[HO_OH]),
                         MUSIC["MUSIC_FINAL_BATTLE"])
        self.assertEqual(self.song(opponent=OPP["LANCE"], map_name="CHAMPIONS_ROOM",
                                   party=[HO_OH]), MUSIC["MUSIC_CHAMPION_BATTLE"])
        # a stale Ho-Oh past wEnemyPartyCount is not in the party
        self.assertEqual(self.song(opponent=OPP["YOUNGSTER"], party=[PIDGEY, HO_OH],
                                   party_count=1), MUSIC["MUSIC_TRAINER_BATTLE"])

    def test_rocket_themes(self) -> None:
        rocket = MUSIC["MUSIC_ROCKET_BATTLE"]
        kanto_rocket = MUSIC["MUSIC_POKE_CUP_BATTLE"]
        trainer = MUSIC["MUSIC_TRAINER_BATTLE"]
        # grunts: Crystal's theme with Johto on, the Kanto Rocket theme without
        self.assertEqual(self.song(opponent=OPP["ROCKET"], johto=True), rocket)
        self.assertEqual(self.song(opponent=OPP["ROCKET"]), kanto_rocket)
        # Giovanni's mini-boss: the Kanto Rocket theme either way, in any round
        for johto in (False, True):
            for count in (1, 4 * ROUND_BATTLES + 1):
                with self.subTest(johto=johto, battle_count=count):
                    self.assertEqual(self.song(opponent=OPP["GIOVANNI_MINIBOSS"], johto=johto,
                                               battle_count=count), kanto_rocket)
        # plain Giovanni and Jessie & James are not in the Rocket set
        for name in ("GIOVANNI", "JESSIE_JAMES"):
            with self.subTest(trainer=name):
                self.assertEqual(self.song(opponent=OPP[name], johto=True), trainer)
        # Mewtwo still outranks the Rocket theme
        self.assertEqual(self.song(opponent=OPP["GIOVANNI_MINIBOSS"], johto=True,
                                   party=[SPECIES["MEWTWO"]]), MUSIC["MUSIC_MEWTWO_BATTLE"])

    def test_trainer_bands_2_and_3_play_their_themes(self) -> None:
        # A band's routes and gym trainers are the rounds before its leaders'
        # wins: gyms 3-4 are rounds 2-3, gyms 5-6 rounds 4-5 (leader battles
        # land on multiples of ROUND_BATTLES and have their own category).
        trainer = MUSIC["MUSIC_TRAINER_BATTLE"]
        pika = MUSIC["MUSIC_PIKA_CUP_BATTLE"]
        petit = MUSIC["MUSIC_PETIT_CUP_BATTLE"]
        cases = {1: trainer, 2 * ROUND_BATTLES - 1: trainer,
                 2 * ROUND_BATTLES + 1: pika, 4 * ROUND_BATTLES - 1: pika,
                 4 * ROUND_BATTLES + 1: petit, 6 * ROUND_BATTLES - 1: petit,
                 6 * ROUND_BATTLES + 1: trainer, 255: trainer}
        for count, expected in cases.items():
            with self.subTest(battle_count=count):
                self.assertEqual(self.song(opponent=OPP["YOUNGSTER"], battle_count=count),
                                 expected)
        # a leader in band 3 keeps the leader theme
        self.assertEqual(self.song(opponent=OPP["BROCK"], gym_leader=1, map_name="PEWTER_GYM",
                                   battle_count=5 * ROUND_BATTLES),
                         MUSIC["MUSIC_GYM_LEADER_BATTLE"])

    def test_final_route_and_final_gym_trainers(self) -> None:
        """A round's last route trainer plays TCG's Club Master duel and its last
        gym trainer (right before the leader) TCG2's GR Leader duel (2026-11-26).
        Both are GetRandRoster's BIT_ROGUE_FINAL_TRAINER trainers; the step tells
        them apart."""
        club = MUSIC["MUSIC_TCG_CLUB_MASTER_DUEL"]
        gr = MUSIC["MUSIC_TCG2_GR_LEADER_DUEL"]
        for rnd in (0, 2, 4, 7):
            with self.subTest(round=rnd):
                route = rnd * ROUND_BATTLES + FINAL_ROUTE_STEP
                gym = rnd * ROUND_BATTLES + FINAL_GYM_TRAINER_STEP
                self.assertEqual(self.song(opponent=OPP["YOUNGSTER"], battle_count=route,
                                           final=True), club)
                self.assertEqual(self.song(opponent=OPP["COOLTRAINER_M"], battle_count=gym,
                                           final=True), gr)
        # Johto mode and a Johto gym: the final gym trainer still gets GR's theme
        self.assertEqual(self.song(opponent=OPP["COOLTRAINER_M"], map_name="VIOLET_GYM",
                                   johto=True, battle_count=FINAL_GYM_TRAINER_STEP, final=True), gr)
        # Endless: a one-row category, so the same songs and no roll
        self.assertEqual(self.song(opponent=OPP["YOUNGSTER"], depth=2,
                                   battle_count=FINAL_ROUTE_STEP, final=True), club)
        # without the bit the same steps keep the ordinary themes
        self.assertEqual(self.song(opponent=OPP["YOUNGSTER"], battle_count=FINAL_ROUTE_STEP),
                         MUSIC["MUSIC_TRAINER_BATTLE"])
        self.assertEqual(self.song(opponent=OPP["COOLTRAINER_M"], map_name="VIOLET_GYM",
                                   battle_count=FINAL_GYM_TRAINER_STEP),
                         MUSIC["MUSIC_JOHTO_TRAINER_BATTLE"])
        # the third Elite Four member lands on the final gym step; authored teams
        # never carry the bit, so the E4 keep their themes
        e4_third = ROUND["E4_FIRST_BATTLECOUNT"] + 2
        self.assertEqual(e4_third % ROUND_BATTLES, FINAL_GYM_TRAINER_STEP)
        self.assertEqual(self.song(opponent=OPP["AGATHA"], battle_count=e4_third),
                         MUSIC["MUSIC_TRAINER_BATTLE"])
        # Rocket grunts, Mewtwo and the finale keep outranking it
        self.assertEqual(self.song(opponent=OPP["ROCKET"], johto=True,
                                   battle_count=FINAL_ROUTE_STEP, final=True),
                         MUSIC["MUSIC_ROCKET_BATTLE"])
        self.assertEqual(self.song(opponent=OPP["YOUNGSTER"], battle_count=FINAL_ROUTE_STEP,
                                   final=True, party=[SPECIES["MEWTWO"]]),
                         MUSIC["MUSIC_MEWTWO_BATTLE"])
        self.assertEqual(self.song(opponent=OPP["RIVAL3"], battle_count=FINAL_ROUTE_STEP,
                                   final=True), MUSIC["MUSIC_FINAL_BATTLE"])

    def test_reward_room_plays_pinball_blue_field(self) -> None:
        h = self.harness
        bank, address = h.symbols.get("MapSongBanks")
        rom = h.rom_path.read_bytes()
        row = bank * 0x4000 + (address - (0x4000 if bank else 0)) + 2 * MAPS["REWARD_ROOM"]
        self.assertEqual(rom[row], MUSIC["MUSIC_PINBALL_CATCH_EM_BLUE"])

    def test_rocket_spotting_you_plays_look_rocket_in_johto_mode(self) -> None:
        h = self.harness
        played = []
        h.register_hook("PlayMusic", lambda _: played.append(h.pyboy.register_file.A))
        cases = (("ROCKET", True, MUSIC["MUSIC_LOOK_ROCKET"]),
                 ("ROCKET", False, MUSIC["MUSIC_MEET_EVIL_TRAINER"]),
                 ("GIOVANNI_MINIBOSS", True, MUSIC["MUSIC_MEET_EVIL_TRAINER"]),
                 ("JESSIE_JAMES", True, MUSIC["MUSIC_MEET_JESSIE_JAMES"]),
                 ("YOUNGSTER", True, MUSIC["MUSIC_MEET_MALE_TRAINER"]))
        for name, johto, expected in cases:
            with self.subTest(trainer=name, johto=johto):
                self.baseline.seek(0)
                h.load_state(self.baseline)
                h.write8("wEngagedTrainerClass", OPP[name])
                h.write8("wGymLeaderNo", 0)
                flags = h.read8("wEventFlags", JOHTO // 8)
                bit = 1 << (JOHTO % 8)
                h.write8("wEventFlags", flags | bit if johto else flags & ~bit, JOHTO // 8)
                played.clear()
                h.call_routine("PlayTrainerMusic", limit=4000)
                # SFX_STOP_ALL_MUSIC reaches PlayMusic as song 0 first
                self.assertEqual([song for song in played if song], [expected])

    def test_ramp_walk_takes_the_last_reached_row(self) -> None:
        ramp = [0, 0x11, 2, 0x22, 5, 0x33]
        cases = {0: 0x11, ROUND_BATTLES - 1: 0x11, 2 * ROUND_BATTLES - 1: 0x11,
                 2 * ROUND_BATTLES: 0x22, 5 * ROUND_BATTLES - 1: 0x22,
                 5 * ROUND_BATTLES: 0x33, 255: 0x33}
        for count, expected in cases.items():
            with self.subTest(battle_count=count):
                self.assertEqual(self.song(trainer=False, battle_count=count, fake_ramp=ramp),
                                 expected)

    def test_endless_draws_from_the_whole_pool(self) -> None:
        ramp = [0, 0x11, 2, 0x22, 5, 0x33]
        seen = set()
        for n in range(40):
            seen.add(self.song(trainer=False, depth=1, fake_ramp=ramp,
                               seed=[n, n * 7 + 1, n * 13 + 2, n * 31 + 3]))
        self.assertEqual(seen, {0x11, 0x22, 0x33})

    def test_one_row_pool_does_not_draw_in_endless(self) -> None:
        h = self.harness
        calls = []
        start = h.address("GetBattleMusicSong")
        end = h.address("GetBattleMusicCategory")

        def at_random(_):
            # VBlank draws too; count only draws returning into the routine.
            sp = h.pyboy.register_file.SP
            ret = h.pyboy.memory[sp] | h.pyboy.memory[sp + 1] << 8
            if start <= ret < end:
                calls.append("Random")

        h.register_hook("GetBattleMusicSong.endless", lambda _: calls.append("endless"))
        h.register_hook("Random", at_random)
        self.assertEqual(self.song(trainer=False, opponent=1, depth=3),
                         MUSIC["MUSIC_WILD_BATTLE"])
        self.assertEqual(calls, ["endless"])
        # control: the caller filter does see a real draw
        calls.clear()
        self.song(trainer=False, depth=1, fake_ramp=[0, 0x11, 2, 0x22])
        self.assertEqual(calls, ["endless", "Random"])


if __name__ == "__main__":
    unittest.main()
