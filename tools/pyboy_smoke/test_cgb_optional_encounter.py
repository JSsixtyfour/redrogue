"""CGB variant of the complete forced optional-encounter lifecycle."""
import test_optional_encounter as encounter
from harness import RedRogueHarness
from source_constants import parse_map_constants,parse_rgbds_constants


class CGBOptionalEncounterTest(encounter.OptionalEncounterTest):
    def setUp(self):
        root=encounter.geometry.ROOT
        self.maps=parse_map_constants(root/'constants/map_constants.asm')
        self.toggles=parse_rgbds_constants(root/'constants/toggle_constants.asm')
        self.h=RedRogueHarness(root,encounter.geometry.ARTIFACTS,cgb_mode=True)
