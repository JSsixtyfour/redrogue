"""Type-immune attacks receive the same saturation penalty as redundant moves."""
import unittest
import test_ai_heuristic_gaps as gaps


class TypeImmunityTest(gaps._MoveLayerGapsBase):
    def scores(self, types, moves, full=False, tier=2):
        self.prime_clean()
        h = self.h
        h.write8("wAITier", tier + 1)
        for i, name in enumerate(types):
            h.write8("wBattleMonType", self.types[name], offset=i)
        for i in range(4):
            h.write8("wEnemyMonMoves", self.moves[moves[i]] if i < len(moves) else 0, offset=i)
            h.write8("wEnemyMonPP", 10, offset=i)
            h.write8("wBuffer", self.ai["AI_SCORE_BASE"], offset=i)
        h.call_routine("AIEnemyTrainerChooseMoves" if full else "AIMoveChoiceModification3", limit=1800)
        return list(h.read_bytes("wBuffer", 4))

    def test_immunity_in_either_type_slot_and_other_immunities(self):
        for types, move in [(('GHOST', 'FIGHTING'), 'HYPER_BEAM'),
                            (('FIGHTING', 'GHOST'), 'HYPER_BEAM'),
                            (('FIRE', 'GHOST'), 'HYPER_BEAM'),
                            (('FIRE', 'GHOST'), 'SUBMISSION'),
                            (('NORMAL', 'FLYING'), 'EARTHQUAKE'),
                            (('WATER', 'GROUND'), 'THUNDERBOLT')]:
            with self.subTest(types=types, move=move):
                self.assertEqual(self.scores(types, [move])[0], self.ai['AI_SCORE_MAX'])

    def test_fixed_damage_called_moves_and_self_setup_are_not_blocked(self):
        for move in ('SEISMIC_TOSS', 'NIGHT_SHADE', 'SUPER_FANG', 'METRONOME',
                     'MIRROR_MOVE', 'SWORDS_DANCE', 'COUNTER'):
            with self.subTest(move=move):
                self.assertEqual(self.scores(('FIRE', 'GHOST'), [move])[0], self.ai['AI_SCORE_BASE'])

    def test_counter_damage_is_not_scored_off_the_type_chart(self):
        # Counter skips AdjustDamageForMoveType: neither GHOST immunity nor a
        # NORMAL weakness changes what it does.
        for types in (('NORMAL', 'NORMAL'), ('GHOST', 'POISON')):
            with self.subTest(types=types):
                self.assertEqual(self.scores(types, ['COUNTER', 'SURF'])[0],
                                 self.ai['AI_SCORE_BASE'])

    def test_resistance_keeps_existing_small_penalty(self):
        self.assertEqual(self.scores(('ROCK', 'ROCK'), ['HYPER_BEAM', 'SURF'])[0],
                         self.ai['AI_SCORE_BASE'] + self.ai['AI_NUDGE'])

    def test_full_selection_prefers_working_attack(self):
        result = self.scores(('FIRE', 'GHOST'), ['HYPER_BEAM', 'SURF'], full=True)
        self.assertEqual(result[0], 0)
        self.assertEqual(result[1], self.moves['SURF'])

    def test_all_immune_still_has_a_legal_fallback(self):
        result = self.scores(('FIGHTING', 'GHOST'), ['HYPER_BEAM', 'SUBMISSION'], full=True)
        self.assertTrue(any(result))

    def test_novice_avoids_immunity_but_does_not_rank_resistances(self):
        result = self.scores(('FIRE', 'GHOST'), ['HYPER_BEAM', 'SURF'], full=True, tier=0)
        self.assertEqual(result[0], 0)
        self.assertEqual(result[1], self.moves['SURF'])
        self.assertEqual(self.scores(('ROCK', 'ROCK'), ['HYPER_BEAM', 'SURF'], tier=0)[:2],
                         [self.ai['AI_SCORE_BASE']] * 2)


if __name__ == '__main__':
    unittest.main()
