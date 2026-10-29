"""Real process-tree deadline/resource controls and interrupted prep recovery."""
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import threading
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import campaign_limits as limits
import run_campaign as campaign


def sleeper(args, notify):
    notify({"kind": "phase", "name": "source_identity", "state": "start"})
    time.sleep(20)


def orphan(args, notify):
    child = subprocess.Popen(["python3", "-c", "import time; time.sleep(20)"], start_new_session=True)
    (args.output / "helper.pid").write_text(str(child.pid))
    return 0


def orphan_sleep(args, notify):
    orphan(args, notify)
    return sleeper(args, notify)


def storage(args, notify):
    (args.output / "large").write_bytes(bytes(2 * 1024 * 1024))


def aggregate_storage(args, notify):
    for number in range(3):
        (args.output / str(number)).write_bytes(bytes(600_000))
    time.sleep(20)


def success(args, notify):
    return 0


def silent_exit(args, notify):
    os._exit(0)


def abnormal_exit_after_completion(args, notify):
    notify({"kind": "finished", "code": 0})
    os._exit(9)


class LimitsTest(unittest.TestCase):
    def run_guard(self, target, **changes):
        with tempfile.TemporaryDirectory() as temporary:
            args = SimpleNamespace(output=Path(temporary), campaign_budget=0.4,
                                   storage_budget_mib=16, rss_budget_mib=1024)
            vars(args).update(changes)
            audit = limits.supervise(target, args)
            self.assertEqual(audit["cleanup_remaining_pids"], [])
            self.assertLess(audit["seconds"], 3)
            pidfile = args.output / "helper.pid"
            if pidfile.exists():
                self.assertFalse(Path(f"/proc/{pidfile.read_text()}").exists())
            return audit

    def test_clean_and_missing_completion(self):
        self.assertEqual(self.run_guard(success)["exit"], 0)
        self.assertEqual(self.run_guard(silent_exit)["execution"], "controller_error")
        self.assertEqual(self.run_guard(abnormal_exit_after_completion)["execution"], "controller_error")

    def test_deadline_in_preparation(self):
        audit = self.run_guard(sleeper)
        self.assertEqual(audit["execution"], "budget_exhausted")
        self.assertEqual(audit["phase_at_stop"], "source_identity")

    def test_deadline_kills_new_session_helper(self):
        self.assertEqual(self.run_guard(orphan_sleep)["execution"], "budget_exhausted")

    def test_success_with_orphan_cannot_pass(self):
        self.assertEqual(self.run_guard(orphan)["execution"], "orphan_processes")

    def test_storage_and_memory_caps(self):
        self.assertEqual(self.run_guard(storage, storage_budget_mib=1)["execution"], "storage_exhausted")
        self.assertEqual(self.run_guard(aggregate_storage, storage_budget_mib=1)["execution"], "storage_exhausted")
        self.assertEqual(self.run_guard(sleeper, rss_budget_mib=1)["execution"], "memory_exhausted")

    def test_keyboard_cancel_cleans_helper(self):
        timer = threading.Timer(0.2, lambda: os.kill(os.getpid(), signal.SIGINT))
        timer.start()
        try:
            self.assertEqual(self.run_guard(orphan_sleep, campaign_budget=5)["execution"], "cancelled")
        finally:
            timer.cancel()
            timer.join()

    def test_partial_archive_recovery_preserves_failed_preparation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            config = root / "config.json"
            config.write_text(json.dumps({"cases": [{"id": "one", "args": ["--seeds", "1"]}]}))
            runner = root / "worker.py"
            runner.write_text("import json,os\nfrom pathlib import Path\n"
                              "p=Path(os.environ['REDROGUE_AUTOPLAY_ARTIFACTS'])\n"
                              "(p/'autoplay_summary.json').write_text(json.dumps({'runs':[{'seed':1,'outcome':'completed'}]}))\n")
            output = root / "campaign"
            argv = [str(config), "--output", str(output), "--campaign-budget", "2"]

            def interrupted_archive(path, *args, **kwargs):
                Path(path).write_bytes(b"interrupted archive")
                time.sleep(20)

            with patch.object(campaign, "RUNNER", runner), \
                    patch.object(campaign, "validate_config", side_effect=lambda value: value["cases"]), \
                    patch.object(campaign, "source_identity", return_value={"files": {}}), \
                    patch.object(campaign, "build_identity", return_value={}), \
                    patch.object(campaign.subprocess, "check_output", return_value=b""):
                with patch.object(campaign.tarfile, "open", side_effect=interrupted_archive):
                    self.assertEqual(campaign.main(argv), 1)
                first = next(output.glob("preparation-*/source.tar.gz"))
                self.assertEqual(json.loads((output / "supervision.json").read_text())["phase_at_stop"], "archive_inputs")
                self.assertEqual(campaign.main(argv), 0)
                self.assertEqual(first.read_bytes(), b"interrupted archive")
                self.assertEqual(len(list(output.glob("preparation-*"))), 2)
                self.assertEqual(campaign.main(argv), 0)
                self.assertEqual(len(list((output / "one").glob("attempt-*"))), 1)
                self.assertEqual(len(list((output / "supervision_attempts").glob("*.json"))), 3)
                (output / "manifest.json").unlink()
                self.assertEqual(campaign.main(argv), 1)


if __name__ == "__main__":
    unittest.main()
