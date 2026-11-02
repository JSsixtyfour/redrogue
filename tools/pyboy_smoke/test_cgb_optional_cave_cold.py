import test_optional_cave_cold as cold
from harness import RedRogueHarness
from source_constants import parse_map_constants


class CGBCaveColdEncounterTest(cold.CaveColdEncounterTest):
    def setUp(self):
        self.maps=parse_map_constants(cold.cave.ROOT/'constants/map_constants.asm')
        self.h=RedRogueHarness(cold.cave.ROOT,cold.cave.ARTIFACTS,cgb_mode=True)
