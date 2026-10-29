"""Corpus capture identity and provenance survive retention; wrong builds refuse load."""
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
import autoplay_branch as branch
import run_campaign as campaign


class SnapshotIdentityTest(unittest.TestCase):
    def test_corpus_quota_counts_unique_validated_states_and_rejects_missing_metadata(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            record = branch.retain_snapshot(self.snapshot(), self.h, root/'lobby.state', 7)
            report = root/'report.json'
            report.write_text(json.dumps({'build_identity': {'gbc': self.h.rom_sha256, 'sym': self.h.sym_sha256},
                'hardware_mode': 'DMG', 'branches': {'retained_snapshots': [record, record]}}))
            self.assertEqual(campaign.achieved_exposure({'runs': [{'report': str(report)}]})['corpus_states'], 1)
            Path(record['metadata']).unlink()
            with self.assertRaisesRegex(ValueError, 'evidence missing'):
                campaign.achieved_exposure({'runs': [{'report': str(report)}]})

    def test_feature_state_survives_temporal_thinning_with_bounded_reservations(self):
        reel = branch.SnapshotReel(limit=8, rare_limit=2)
        for frame in range(200):
            features = ['boundary:full_party'] if frame == 7 else []
            reel.offer('battle', frame, {'rare_features': features}, lambda stream: stream.write(b'x'))
        selected = reel.select(1)
        self.assertEqual([snapshot.frame for snapshot in selected], [7])
        for number in range(5):
            reel.offer('battle', 201+number, {'rare_features': [f'feature{number}']}, lambda stream: stream.write(b'x'))
        self.assertEqual(len(reel.reserved['battle']), 2)
        self.assertTrue(reel.unreserved['battle'])
        self.assertLess(len(reel.kept['battle']), 8)
        self.assertEqual(reel.select(0), [])

    def setUp(self):
        self.h = SimpleNamespace(rom_sha256='a'*64, sym_sha256='b'*64, hardware_mode='DMG')

    def snapshot(self):
        reel = branch.SnapshotReel(identity=branch.snapshot_identity(self.h))
        info = {'map': 'LOBBY', 'startup_path': 'debug2'}
        reel.offer('lobby', 10, info, lambda stream: stream.write(b'captured machine bytes'))
        info['map'] = 'changed after capture'
        return reel.select(1)[0]

    def test_retained_snapshot_binds_state_build_mode_and_copied_provenance(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)/'lobby.state'
            snapshot = self.snapshot()
            data = branch.retain_snapshot(snapshot, self.h, path, 7)
            self.assertEqual(data['origin']['info']['map'], 'LOBBY')
            self.assertEqual(branch.read_snapshot(path, self.h), snapshot.state)
            for field in ('rom_sha256','sym_sha256','hardware_mode'):
                wrong = SimpleNamespace(**{**vars(self.h), field: 'wrong'})
                with self.assertRaisesRegex(ValueError, 'identity mismatch'):
                    branch.read_snapshot(path, wrong)

    def test_tampered_and_legacy_states_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)/'lobby.state'
            branch.retain_snapshot(self.snapshot(), self.h, path, 7)
            path.write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError, 'state hash'):
                branch.read_snapshot(path, self.h)
            path.with_suffix('.state.json').unlink()
            with self.assertRaisesRegex(ValueError, 'metadata missing'):
                branch.read_snapshot(path, self.h)

    def test_missing_capture_identity_and_post_capture_changes_refuse_retention(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)/'lobby.state'
            snapshot = self.snapshot()
            snapshot.state += b'changed'
            with self.assertRaisesRegex(ValueError, 'bytes changed'):
                branch.retain_snapshot(snapshot, self.h, path, 7)
            snapshot = self.snapshot()
            snapshot.identity = None
            with self.assertRaisesRegex(ValueError, 'capture identity'):
                branch.retain_snapshot(snapshot, self.h, path, 7)
            self.assertFalse(path.exists())

    def test_replay_keeps_custom_freeze_window(self):
        command = branch.replay_command(Path('/tmp/retained.state'), 'branch/7/lobby1/0', 900, 120)
        self.assertIn('--freeze-frames 120', command)
