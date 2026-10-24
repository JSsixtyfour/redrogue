"""The Sensitivity lifecycle and visual-state contracts on CGB hardware."""

import test_animation_sensitivity as sensitivity
from harness import RedRogueHarness
from test_smoke import REPO_ROOT, ARTIFACTS


class CGBSensitivityTest(sensitivity.AnimationSensitivityTest):
    def setUp(self):
        self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS, cgb_mode=True)


class CGBSensitivityEvolutionTest(sensitivity.SensitivityEvolutionTest):
    def setUp(self):
        self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS, cgb_mode=True)
