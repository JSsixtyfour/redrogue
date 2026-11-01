"""Negative controls for real-menu save publication timing evidence."""
import unittest
from menu_save_journey import publication_clock_evidence


class MenuSavePublicationClockTest(unittest.TestCase):
    def test_publication_frame_is_accounted_exactly(self):
        row=publication_clock_evidence([1,0,0,59,59],
            [{'clock':[1,0,0,59,59],'timer_enabled':True}],[1,0,1,0,0])
        self.assertEqual(row['status'],'accounted')

    def test_missing_tick_cannot_be_hidden_by_timer_allowance(self):
        row=publication_clock_evidence([1,0,0,0,0],[],[1,0,0,0,1])
        self.assertEqual(row['status'],'invalid')

    def test_torn_rollover_copy_is_refused(self):
        row=publication_clock_evidence([1,0,0,59,59],
            [{'clock':[1,0,0,59,59],'timer_enabled':True}],[1,0,0,59,0])
        self.assertEqual(row['status'],'invalid')
