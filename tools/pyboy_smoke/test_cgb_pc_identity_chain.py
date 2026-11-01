"""CGB counterpart of the shared PC identity/persistence chains."""
import test_pc_identity_chain as pc


class CGBPCIdentityChainTest(pc.PCIdentityChainTest):
    cgb = True
