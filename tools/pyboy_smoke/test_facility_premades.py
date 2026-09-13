import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "check_facility_premades", ROOT / "tools" / "check_facility_premades.py"
)
assert SPEC and SPEC.loader
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)


class FacilityPremadeContractTest(unittest.TestCase):
    def test_fixture_descriptor_contract(self) -> None:
        self.assertEqual(validator.validate(), [])

    def test_selection_and_generic_fallback(self) -> None:
        for required in range(16):
            for room_id in range(1, 11):
                self.assertTrue(validator.select_fixture(room_id, 1, 1, required))
        self.assertFalse(validator.select_fixture(0, 1, 1, 1))
        self.assertFalse(validator.select_fixture(11, 1, 1, 1))
        self.assertFalse(validator.select_fixture(1, 2, 1, 1))
        self.assertFalse(validator.select_fixture(5, 1, 2, 1))
        self.assertFalse(
            validator.select_fixture(5, 1, 1, 1, corners_clear=False)
        )

    def test_large_decor_fixtures_have_safe_placement(self) -> None:
        for filename, (width, height) in validator.LARGE_DECOR_FIXTURES.items():
            payload = (ROOT / "maps" / filename).read_bytes()
            placements = [
                (room_width, room_height, x, y)
                for room_height in range(height, 8)
                for room_width in range(width, 8)
                for x, y in validator.valid_large_decor_offsets(
                    payload, width, height, room_width, room_height
                )
            ]
            self.assertTrue(placements, filename)

    def test_large_decor_protects_center_cross(self) -> None:
        payload = bytes((0x0E, 0x31, 0x45, 0x2C))
        self.assertFalse(
            validator.large_decor_offset_safe(payload, 2, 2, 2, 2, 0, 0)
        )
        self.assertTrue(
            validator.large_decor_offset_safe(payload, 2, 2, 4, 4, 0, 0)
        )

    def test_actual_door_mask_allows_compact_direction_safe_decor(self) -> None:
        payload = (
            ROOT / "maps" / "ProceduralFacility_2x2_blocktree_decor.blk"
        ).read_bytes()
        self.assertTrue(
            validator.valid_large_decor_offsets(payload, 2, 2, 2, 4, 0x02)
        )

    def test_nested_block_fixture_is_disabled_pending_redesign(self) -> None:
        self.assertNotIn(
            "ProceduralFacility_3x3_block_decor.blk",
            validator.LARGE_DECOR_RUNTIME_FIXTURES,
        )

    def test_disconnect_reproducer_is_disabled_pending_safe_placement(self) -> None:
        self.assertNotIn(
            "ProceduralFacility_2x2_blocktree_decor.blk",
            validator.LARGE_DECOR_RUNTIME_FIXTURES,
        )

    def test_table_is_item_anchor_but_not_walkable_decor(self) -> None:
        self.assertIn(0x47, validator.ITEM_ANCHOR_BLOCKS)
        self.assertNotIn(0x47, validator.FULLY_WALKABLE_DECOR_BLOCKS)
        self.assertTrue(validator.item_anchor_safe([[0x47, 0x0E]], 0, 0))
        self.assertFalse(validator.item_anchor_safe([[0x47, 0x31]], 0, 0))


if __name__ == "__main__":
    unittest.main()
