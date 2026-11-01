"""CGB save-transaction guard coverage."""
import test_save_commit_guard as guard


class CGBSaveCommitGuardTest(guard.SaveCommitGuardTest):
    cgb = True
