; Trainer-card art that is indexed per gym leader, and therefore grows with the
; leader roster rather than being a fixed-size asset.
;
; Inline-pinned to bank $3C to match "Trainer Pics 2" (gfx/pics.asm), which is
; the other roster-sized art blob added by the gym-leader expansion. Deliberately
; NOT bank $39: that bank holds "Trainer Parties", whose growth headroom Phase 2
; is going to spend on party specs. Deliberately not left floating either, per
; layout.link's own rule for a section whose size is going to change.
;
; Evacuated from the pinned "bank3" section in bank $03, which had 542 bytes free
; inside its span. Every reader uses BANK(label) + a far-copy path, so nothing
; here depends on the bank.
SECTION "Trainer Card Art", ROMX, BANK[$3C]

; One 8-tile block per gym leader that can appear on the trainer card:
; tiles 0-3 are the 2x2 face, tiles 4-7 the 2x2 badge. Block order is the
; trainer-card block index (see NUM_CARD_LEADERS in constants/trainer_constants.asm
; and tools/make_placeholder_badges.py for the full block map), which is NOT the
; trainer class id: blocks 0-7 are the Kanto eight in wObtainedBadges BIT order
; because DrawBadges walks that bitfield LSB-first with the same counter.
;
; Blocks 8-16 are Phase 1c placeholders (Kanto art, index for index, so the
; eight stay visually distinct while the Phase 4 per-slot blit is developed).
; Block 16 is Janine, whose badge half is final rather than placeholder: she
; carries Koga's Soul Badge, so 17 blocks hold 16 unique badge graphics.
GymLeaderFaceAndBadgeTileGraphics::
	INCBIN "gfx/trainer_card/badges.2bpp"
GymLeaderFaceAndBadgeTileGraphicsEnd::

; The sheet is a PNG whose height carries the block count, so a mis-sized
; regeneration would assemble silently and blit whatever happened to follow.
; This catches it at link time instead.
ASSERT GymLeaderFaceAndBadgeTileGraphicsEnd - GymLeaderFaceAndBadgeTileGraphics \
       == NUM_CARD_LEADERS * CARD_TILES_PER_LEADER * TILE_SIZE, \
       "gfx/trainer_card/badges.png must hold exactly NUM_CARD_LEADERS blocks \
of CARD_TILES_PER_LEADER tiles; re-run tools/make_placeholder_badges.py"
