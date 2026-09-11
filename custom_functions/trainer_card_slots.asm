; custom_functions/trainer_card_slots.asm
;
; Trainer-card slot resolution (GYM_LEADER_EXPANSION_PLAN.md, Phase 4a).
;
; Vanilla's trainer card is hardwired to the Kanto eight: badge bit i is always
; leader i, and DrawTrainerInfo blits the first 64 tiles of the art sheet in one
; shot so VRAM slot i is always leader i's face/badge pair. With 17 possible
; leaders on a 17-block sheet (constants/trainer_constants.asm NUM_CARD_LEADERS)
; that no longer holds, so the blit becomes eight per-slot copies and the
; slot -> leader question moves here.
;
; The array this reads, wBadgeSlotOrder, holds leaders in DEFEAT order: beating
; Cerulean first puts Misty in slot 1 regardless of which badge bit she set.
;
; BANK-INDEPENDENT. Lives in SECTION "rogue" only because that is where the
; badge/stage logic already is and the bank has headroom; every caller reaches
; it by farcall or by an in-bank call from random_stage_selection.asm.

; Trainer classes in TRAINER-CARD BLOCK order, which is a SEPARATE index space
; from the trainer class ids and is NOT derivable from them. Blocks 0-7 must
; stay in wObtainedBadges BIT order (BIT_BOULDERBADGE..BIT_EARTHBADGE) - note
; that puts SABRINA (Marsh, bit 5) before BLAINE (Volcano, bit 6), which is the
; opposite of their class-id order. Blocks 8-16 are the Johto eight then Janine.
; The sheet's block map is documented in tools/make_placeholder_badges.py.
;
; Used in both directions: block -> class by index, class -> block by scan.
CardLeaderClasses::
	db BROCK, MISTY, LT_SURGE, ERIKA, KOGA, SABRINA, BLAINE, GIOVANNI
	db FALKNER, BUGSY, WHITNEY, MORTY, CHUCK, JASMINE, PRYCE, CLAIR
	db JANINE
CardLeaderClassesEnd::

ASSERT CardLeaderClassesEnd - CardLeaderClasses == NUM_CARD_LEADERS, \
       "CardLeaderClasses must have one row per block in gfx/trainer_card/badges.png"

; ============================================================
; RogueSyncBadgeSlots
; Brings wBadgeSlotOrder into agreement with wObtainedBadges.
;
; Deliberately a SYNC rather than an append-on-victory hook. The plan put a
; "record the leader" call in each gym script, but every one of those sites is
; reachable only through its own map-script bank, and four of the eight Kanto
; gyms live in bank $17, which had 2 bytes free - ten bytes per site there would
; have forced the floating "Maps 16" section (7,986 bytes of map scripts) into a
; different bank to buy a feature that only affects a menu. Syncing instead
; costs one in-bank call in the lobby path and one more at card-open time, and
; it is self-correcting: a wBadgeSlotOrder that is stale, partly written, or
; left over from a previous run converges on the next call.
;
; Order is still exact, because the two call sites bracket every way a badge can
; be earned: SelectAndPatchLobbyExit runs on every return to the lobby, so at
; most one new badge exists per sync, and RogueBlitCardBadges catches the case
; where the player opens the card inside the gym they just cleared.
;
; Takes no arguments and preserves nothing.
RogueSyncBadgeSlots::
	ld a, [wObtainedBadges]
	and a
	jr nz, .haveBadges
	; Zero badges means a fresh run, so anything still in the array belongs to
	; a previous one. This is what resets it; no separate run-start hook.
	ld hl, wBadgeSlotOrder
	ld bc, NUM_BADGES
	xor a
	jp FillMemory

.haveBadges
	ld b, a                    ; b = wObtainedBadges, shifted out LSB-first
	ld c, 0                    ; c = badge bit index
.bitLoop
	srl b
	jr nc, .nextBit
	push bc
	ld a, c
	call RogueCardLeaderForBadgeBit
	call RogueRecordBadgeSlot
	pop bc
.nextBit
	inc c
	ld a, c
	cp NUM_BADGES
	jr c, .bitLoop
	ret

; ============================================================
; RogueCardLeaderForBadgeBit
; INPUT:  a = badge bit index (0-7)
; OUTPUT: a = trainer class id of the leader who owns that badge slot this run
;
; Phase 7 rolls wRunGymLineup and _PickNextGym picks a random unset BADGE BIT,
; so badge bit i and wRunGymLineup[i] are the same gym by construction. Until
; that lands the lineup is all zeroes and this falls back to the vanilla
; identity mapping, badge bit i -> card block i -> the Kanto leader.
RogueCardLeaderForBadgeBit::
	ld e, a
	ld d, 0
	ld hl, wRunGymLineup
	add hl, de
	ld a, [hl]
	and a
	ret nz
	ld hl, CardLeaderClasses
	add hl, de
	ld a, [hl]
	ret

; ============================================================
; RogueRecordBadgeSlot
; INPUT: a = trainer class id
; Appends it at the first empty slot, unless it is already recorded. The array
; is always densely packed from index 0, so the first zero found is both the end
; of the recorded run and the correct append point.
RogueRecordBadgeSlot::
	ld b, a
	ld hl, wBadgeSlotOrder
	ld c, NUM_BADGES
.find
	ld a, [hl]
	cp b
	ret z                      ; already recorded
	and a
	jr z, .append
	inc hl
	dec c
	jr nz, .find
	ret                        ; all 8 slots full and this class is not among
	                           ; them: drop it rather than overwrite history
.append
	ld [hl], b
	ret

; ============================================================
; RogueCardBlockForSlot
; INPUT:  a = card slot index (0-7)
; OUTPUT: a = block index into GymLeaderFaceAndBadgeTileGraphics (0-16)
;
; An empty slot, or a class with no block (which should not happen), falls back
; to the slot index. That is exactly vanilla's mapping, so a card drawn before
; any sync still looks like the old one rather than like garbage.
RogueCardBlockForSlot::
	ld e, a
	ld d, 0
	ld hl, wBadgeSlotOrder
	add hl, de
	ld a, [hl]
	and a
	jr z, .fallback
	ld b, a
	ld hl, CardLeaderClasses
	ld c, 0
.scan
	ld a, [hli]
	cp b
	jr z, .found
	inc c
	ld a, c
	cp NUM_CARD_LEADERS
	jr c, .scan
.fallback
	ld a, e
	ret
.found
	ld a, c
	ret

; ============================================================
; RogueCardEarnedSlotMask
; OUTPUT: e = bitmask of earned card slots, bit i = slot i
;
; Returned in e because the only caller reaches this by farcall, and Bankswitch
; destroys a/b/c/h/l on both sides (project_farcall_bc_clobber_bug_class).
;
; DrawBadges used to read wObtainedBadges here, which worked only while badge
; bit i and slot i were the same thing. Badges are earned in scattered bit order
; in this tree (_PickNextGym picks a random unset bit), so with slots in defeat
; order the two have nothing to do with each other: after two wins the bitfield
; might be %00100010 while slots 0 and 1 are the filled ones.
RogueCardEarnedSlotMask::
	ld a, [wBadgeSlotOrder]
	and a
	jr z, .legacy
	ld hl, wBadgeSlotOrder + NUM_BADGES - 1
	ld c, NUM_BADGES
	ld e, 0
.loop
	ld a, [hld]                ; walk backwards so slot 0 ends up in bit 0
	and a
	jr z, .empty
	scf
	jr .shiftIn
.empty
	and a                      ; clear carry
.shiftIn
	rl e
	dec c
	jr nz, .loop
	ret

.legacy
	; Nothing recorded. Only reachable if DrawBadges runs without a sync having
	; happened; fall back to vanilla's bit-is-slot behaviour.
	ld a, [wObtainedBadges]
	ld e, a
	ret

; ============================================================
; RogueBlitCardBadges
; Copies the eight face/badge blocks this run's card needs into vChars2 tiles
; $20-$5F, one 8-tile block per slot. Replaces DrawTrainerInfo's single 64-tile
; copy, which could only ever produce the Kanto eight in bit order.
;
; MUST run with the LCD off - DrawTrainerInfo already brackets this with
; DisableLCD/EnableLCD. Syncs the slot array first so that opening the card
; inside a gym you just cleared shows the badge you just won.
RogueBlitCardBadges::
	call RogueSyncBadgeSlots
	ld c, 0                    ; c = slot index
.loop
	push bc
	ld a, c
	call RogueCardBlockForSlot
	call .BlockOffset          ; hl = block * CARD_TILES_PER_LEADER tiles
	ld de, GymLeaderFaceAndBadgeTileGraphics
	add hl, de
	pop bc
	push bc
	push hl                    ; stash source; the destination needs hl too
	ld a, c
	call .BlockOffset
	ld de, vChars2 tile $20
	add hl, de
	ld d, h
	ld e, l
	pop hl
	ld bc, CARD_TILES_PER_LEADER tiles
	ld a, BANK(GymLeaderFaceAndBadgeTileGraphics)
	call FarCopyData2
	pop bc
	inc c
	ld a, c
	cp NUM_BADGES
	jr c, .loop
	ret

; a -> hl = a * CARD_TILES_PER_LEADER tiles (128). The source block stride and
; the destination slot stride are both one block, so this serves both.
.BlockOffset
	ld h, 0
	ld l, a
	REPT 7
	add hl, hl
	ENDR
	ret
