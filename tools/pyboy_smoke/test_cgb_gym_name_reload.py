"""CGB cold-load coverage for gym statue names."""
import test_gym_name_reload as reload


class CGBGymNameReloadTest(reload.GymNameReloadTest):
    cgb = True
