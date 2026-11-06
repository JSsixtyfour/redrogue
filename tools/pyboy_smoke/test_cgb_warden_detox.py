import test_warden_detox as detox


class CGBWardenDetoxTest(detox.WardenDetoxTest):
    harness_args = {"cgb_mode": True}
