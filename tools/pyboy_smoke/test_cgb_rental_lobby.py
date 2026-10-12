"""CGB live rental lobby acceptance probe."""
import unittest
import test_rental_lobby as lobby

class CGBRentalLobbyTest(unittest.TestCase):
    live = lobby.RentalLobbyTest.live

    def test_live_cgb_preview_cancel_box_purchase_and_second_denial(self):
        self.live(True)
