import test_optional_facility as facility


class CGBFacilityEncounterTripTest(facility.FacilityEncounterTripTest):
    harness_args = {"cgb_mode": True}
