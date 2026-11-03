"""CGB double-speed execution of the full seasonal single-write contract."""
from test_procedural_optimization import SeasonalSingleWriteTest as _Contract

class CGBSeasonalSingleWriteTest(_Contract):
    cgb_mode=True

# Keep the imported base out of unittest's module discovery.
del _Contract
