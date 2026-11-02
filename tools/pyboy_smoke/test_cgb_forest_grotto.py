"""All six test-only assigned wall pairs with inherited winter in CGB."""
import test_forest_grotto as grove
from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants


class CGBForestGrottoTripTest(grove.ForestGrottoTripTest):
    def setUp(self):
        self.maps=parse_map_constants(grove.ROOT/'constants/map_constants.asm')
        self.toggles=parse_rgbds_constants(grove.ROOT/'constants/toggle_constants.asm')
        self.h=RedRogueHarness(grove.ROOT,grove.ARTIFACTS,cgb_mode=True)
        self.h.register_hook('FGArmForestWarp',lambda _: self.h.write_sram_bytes('sProcForestPalette',[3],bank=0))

    def press_until(self, button, arrive_map, description):
        super().press_until(button,arrive_map,description)
        self.assertEqual(self.h.read8('wEnhBasePalSet'),6,description)
        self.assertEqual(self.h.read_sram_bytes('sProcForestPalette',1,bank=0),[3])
