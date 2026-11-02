import test_optional_cold_moves as cold
from harness import RedRogueHarness
from source_constants import parse_map_constants,parse_rgbds_constants


class CGBForestSnowlaxTest(cold.ForestSnowlaxTest):
    def setUp(self):
        root=cold.ROOT
        self.maps=parse_map_constants(root/'constants/map_constants.asm')
        self.toggles=parse_rgbds_constants(root/'constants/toggle_constants.asm')
        self.h=RedRogueHarness(root,root/'tools/pyboy_smoke/artifacts',cgb_mode=True)
