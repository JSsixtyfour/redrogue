"""CGB coverage of the real trainer-loss blackout lifecycle."""
import unittest
from harness import RedRogueHarness
from test_smoke import HarnessTestCase, REPO_ROOT, ARTIFACTS
from test_trainer_blackout import BlackoutFixture

class CGBTrainerBlackoutTest(BlackoutFixture, HarnessTestCase):
    def setUp(self):
        self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS, cgb_mode=True)

    def test_regular_trainer_blackout(self):
        self.run_loss()

    def test_blackout_before_first_hub_visit(self):
        self.run_loss(unvisited_hub=True)

if __name__ == '__main__':
    unittest.main()
