"""CGB evolution choreography with Enhanced Colors / 60 FPS options enabled."""
from harness import RedRogueHarness
from test_smoke import HarnessTestCase, REPO_ROOT, ARTIFACTS
from test_evolution_flow import EvolutionFlowFixture


class CGBEvolutionFlowTest(EvolutionFlowFixture, HarnessTestCase):
    def setUp(self):
        self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS, cgb_mode=True)

    def test_active_and_deferred_evolutions(self):
        self.run_evolution()

    def test_cancel_then_deferred_evolution(self):
        self.run_evolution(cancel=True)
