"""Battle music routing and the per-round ramp (audio/play_battle_music.asm).

Drives GetBattleMusicSong directly from a FIGHT 2 park with each battle's
deciding state written in, and reads the song at its single exit. The ramp
walk and the Endless roll are exercised by swapping in a fake multi-row ramp
at .gotRamp, since every shipped ramp is one row (today's music, unchanged)."""
import io
import unittest

from source_constants import parse_map_constants, parse_rgbds_constants, parse_trainer_constants
from test_smoke import HarnessTestCase, REPO_ROOT

MUSIC = parse_rgbds_constants(REPO_ROOT / "constants/music_constants.asm")
MAPS = parse_map_constants(REPO_ROOT / "constants/map_constants.asm")
OPP = parse_trainer_constants(REPO_ROOT / "constants/trainer_constants.asm")
EVENTS = parse_rgbds_constants(REPO_ROOT / "constants/event_constants.asm")
ROUND_BATTLES = parse_rgbds_constants(
    REPO_ROOT / "constants/round_constants.asm")["ROUND_BATTLES"]
BIT_TALKED_TO_TRAINER = parse_rgbds_constants(
    REPO_ROOT / "constants/ram_constants.asm")["BIT_TALKED_TO_TRAINER"]
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
             battle_count=1, fake_ramp=None, seed=None) -> int:
        h = self.harness
        self.baseline.seek(0)
        h.load_state(self.baseline)
        if seed is not None:
            h.seed_rng(seed)
        h.write8("wCurOpponent", opponent)
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
        self.assertEqual(self.song(opponent=OPP["YOUNGSTER"], depth=3),
                         MUSIC["MUSIC_TRAINER_BATTLE"])
        self.assertEqual(calls, ["endless"])
        # control: the caller filter does see a real draw
        calls.clear()
        self.song(trainer=False, depth=1, fake_ramp=[0, 0x11, 2, 0x22])
        self.assertEqual(calls, ["endless", "Random"])


if __name__ == "__main__":
    unittest.main()
