"""CGB regression for the trade's deliberately separate colour redraw path."""
import unittest
import test_trade_redraw


class CGBTradeRedrawTest(unittest.TestCase):
    def test_cgb_trade_retains_colour_path_and_restores_background(self):
        test_trade_redraw.TradeRedrawTest.trade(self,cgb=True)
