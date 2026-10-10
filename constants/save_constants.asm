; Battery-save identification (Red Rogue Files/SAVE_COMPATIBILITY_PLAN.md).
;
; Every save writes an 8-byte header at SRAM bank 1 $a040 (sSaveHeader in
; ram/sram.asm): the ASCII magic "RRSG", SAVE_SCHEMA_ID little-endian, then its
; 16-bit complement. Continue reads the header before any saved block; a save
; whose header is missing or names another schema is refused with a message
; pointing at the patch page's converter, and left untouched.
;
; SAVE_SCHEMA_ID names the save LAYOUT AND MEANING, not the release. Bump it
; whenever a stored field moves, resizes, appears or disappears, or a stored
; value changes meaning (an ID renumbered, a flag reused) even if no byte
; moves. `make save_schema` fails when the layout changes without a bump, and
; each bump needs a migration in the patch page's converter
; (SAVE_COMPATIBILITY_RUNBOOK.md). Schema 1 is the 2026-10-01 74f82c1b
; layout plus this header; that build's untagged saves convert by tagging.
; Schema 2 (2026-10-03): the three item count arrays grew to their *_SLOTS
; sizes (21/15/4 -> 24/24/8), shifting the rest of the main data block.
; Schema 3 (2026-10-03): the legacy bag's 8 bytes (wNumBagItems, wBagItems,
; wNumBagKeyItems) and the vanilla PC item box (wNumBoxItems, wBoxItems, 102
; bytes) were deleted, shifting the rest of the main data block down.
; Schema 4 (2026-10-06): new SRAM bank 2 section "Reward Offer DVs SRAM"
; (sRogueOfferDVs, sRogueOfferDVTag, 9 bytes) after the fallen log. Nothing
; moved; old saves get it zeroed, as a new game does.
; Schema 5 (2026-10-07): wPlayerStarterForm, 1 byte carved from the ds 2 pad
; after wFossilMon in the main data block. Nothing moved; old saves get it
; zeroed (the base form), as a new game does.
; Schema 6 (2026-10-08): SRAM $BD00-$BDFF reserved in every bank (the EverDrive
; X7 menu covers it; see the end of ram/sram.asm). The forest's baked map left
; "Sprite Buffers" for its own section at $BE00 and became compact (600 -> 400
; bytes), so the bank-0 tail after it moved down 600 bytes; the dead
; sProcFacilityRoomBuf was deleted; the Ironman fallen log shrank 12 -> 10
; entries and the reward offer DVs moved down after it. Old saves: fields
; copied by label, the forest map repacked, the log trimmed and wFallenCount
; clamped (migration x7MenuPageReserved).

; Schema 7 (2026-10-09): wGymChoice (the gym-next lobby's latched pair of gyms,
; player feedback #1) took the saved `ds 1` after wCreditsEarnedThisRun, the
; byte wExpAllLevel left in 2026-09. Nothing moved; old saves get it zeroed
; (nothing latched, so the next gym-next lobby rolls a pair), migration
; gymChoiceAdded.

DEF SAVE_SCHEMA_ID EQU 7

DEF SAVE_HEADER_SIZE EQU 8
; "RRSG" as raw ASCII, not through the game's text charmap.
DEF SAVE_HEADER_MAGIC_0 EQU $52 ; R
DEF SAVE_HEADER_MAGIC_1 EQU $52 ; R
DEF SAVE_HEADER_MAGIC_2 EQU $53 ; S
DEF SAVE_HEADER_MAGIC_3 EQU $47 ; G
