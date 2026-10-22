"""Cold recovery on actual CGB emulation, preserving hardware and progress."""
import unittest
import test_loss_recovery as loss

class CgbLossRecoveryTest(unittest.TestCase):
    def test_notices_are_visible_after_battle_whiteout(self):
        for enhanced in (False,True):
            with self.subTest(enhanced=enhanced):
                h=loss.RedRogueHarness(loss.REPO_ROOT,loss.ARTIFACTS,cgb_mode=True)
                self.addCleanup(h.close)
                h.boot_to_lobby()
                h.write8('wStatusFlags6',h.read8('wStatusFlags6') & ~0x82)
                h.write8('wRentalState',0);h.write8('wCreditsEarnedThisRun',0)
                h.write8('wOptions2',(h.read8('wOptions2') & ~0x40) | (0x40 if enhanced else 0))
                h.call_routine('LossRecoveryDiscard')
                notes=loss.blackout_after_battle_palette(h)
                self.assertEqual([row['holds'] for row in notes],[30,30])
                for row in notes:
                    self.assertNotEqual(row['bgp'],0)
                    self.assertGreater(row['colors'],1)
                self.assertFalse(h.hook_errors,h.hook_errors)

    def test_cgb_recovery_keeps_actual_hardware_and_permanent_progress(self):
        h=loss.RedRogueHarness(loss.REPO_ROOT,loss.ARTIFACTS,cgb_mode=True)
        self.addCleanup(h.close)
        h.boot_to_lobby()
        h.write8('wStatusFlags6',h.read8('wStatusFlags6') & ~0x82)
        h.write8('wRentalState',0)
        h.write8('wPlayerCoins',0x12);h.write8('wPlayerCoins',0x34,1)
        h.write8('wCreditsEarnedThisRun',3)
        h.call_routine('LossRecoveryDiscard')
        # Select gamma on actual CGB hardware.
        h.write8('hGBC',2)
        h.write8('wGymsUsedMask',0xa5);h.write8('wGymsUsedMask',0x5a,1)
        dex=h.read_bytes('wPokedexOwned',64)
        player_id=h.read_bytes('wPlayerID',2)
        groups=(('sKeyItemsBitfield',4,1),('sKeyItemTiers',4,1),
                ('sRoomFurniture',2,1),('sRoomDecorSlots',8,1),('sRoomOwned',4,1),
                ('sRoomOwnedExt',4,1),('sElementPrismType',1,1),('sPrismCartridges',2,1),
                ('sRogueSpeciesGroupsEnabled',1,1),('sFinalTeamArchive',1635,1),
                ('sHallOfFame',4800,0),('sRogueOfferDVs',9,2),('sTurnRewindBuf',34,1),
                ('sStolenRecord',57,1))
        before={name:h.read_sram_bytes(name,size,bank=bank) for name,size,bank in groups}
        image=loss.LossRecoveryTest.prepared(self,h)
        boot=loss.CgbColdBoot(image);self.addCleanup(boot.close)
        loss.LossRecoveryTest.await_recovered(self,boot)
        self.assertNotEqual(boot.h.read8('wOnCGB'),0)
        self.assertEqual(boot.h.read8('hGBC'),2)
        self.assertEqual(boot.h.read_bytes('wGymsUsedMask',2),[0xa5,0x5a])
        self.assertEqual(boot.h.read_bytes('wPlayerID',2),player_id)
        self.assertEqual(boot.h.read_bytes('wPokedexOwned',64),dex)
        for name,size,bank in groups:
            self.assertEqual(boot.h.read_sram_bytes(name,size,bank=bank),before[name],name)

