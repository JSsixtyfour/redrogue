"""CGB variants live in a CGB module for the smoke hardware classifier."""
import test_cave_optional_fallback as fallback
from harness import RedRogueHarness
from source_constants import parse_map_constants


class CGBCaveOptionalFallbackTest(fallback.CaveOptionalFallbackTest):
    def setUp(self):
        self.maps=parse_map_constants(fallback.cave.ROOT/'constants/map_constants.asm')
        self.h=RedRogueHarness(fallback.cave.ROOT,fallback.cave.ARTIFACTS,cgb_mode=True)


class CGBCaveFallbackStageEventTest(fallback.CaveFallbackStageEventTest):
    setUp=CGBCaveOptionalFallbackTest.setUp
