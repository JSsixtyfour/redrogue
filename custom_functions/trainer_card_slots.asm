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
	;
	; Foresight is deliberately NOT cleared here. Zero badges is also the state
	; the player is in while walking into the FIRST gym of a run, so spending it
	; on this branch would make gym 1 the one gym that can never be revealed.
	; Unspent foresight surviving into a later run is the far smaller problem,
	; and a new game zeroes the byte anyway: wRogueFlagsBitfield2 sits above
	; wGameProgressFlagsEnd, inside init_player_data's bulk clear.
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
	; Carry = this leader is newly recorded, i.e. the gym foresight was bought
	; for has just been beaten. Foresight is per-gym, so spend it here rather
	; than letting one purchase reveal the rest of the run.
	call c, RogueSpendForesight
	pop bc
.nextBit
	inc c
	ld a, c
	cp NUM_BADGES
	jr c, .bitLoop
	ret

; ============================================================
; RogueSpendForesight
; Consumes BIT_ROGUE_PREDICT_BADGES.
;
; Foresight is bought per gym, not once per run: whoever grants it reveals the
; leader behind the NEXT gym door, and beating that leader uses it up. Without
; this the bit is simply persistent run state and a single purchase would name
; every remaining leader, which is not what it is worth paying for.
;
; Single-bit `res` so the rest of wRogueFlagsBitfield2 survives - bits 0-1 are
; Credit Exchange slot pulls and bits 2-6 are the Shin Red VRAM/DMA flags.
RogueSpendForesight::
	ld hl, wRogueFlagsBitfield2
	res BIT_ROGUE_PREDICT_BADGES, [hl]
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
; INPUT:  a = trainer class id
; OUTPUT: carry set if this leader was NEWLY recorded, clear if it was already
;         there (or could not be stored). The caller uses that as "a gym has
;         just been beaten", which is the only edge in the whole system.
;
; Appends at the first empty slot. The array is always densely packed from index
; 0, so the first zero found is both the end of the recorded run and the correct
; append point.
RogueRecordBadgeSlot::
	ld b, a
	ld hl, wBadgeSlotOrder
	ld c, NUM_BADGES
.find
	ld a, [hl]
	cp b
	jr z, .notNew              ; already recorded
	and a
	jr z, .append
	inc hl
	dec c
	jr nz, .find
	                           ; all 8 slots full and this class is not among
	                           ; them: drop it rather than overwrite history
.notNew
	and a                      ; clear carry
	ret
.append
	ld [hl], b
	scf
	ret

; ============================================================
; RogueCardBlockForSlot
; INPUT:  a = card slot index (0-7)
; OUTPUT: a = block index into GymLeaderFaceAndBadgeTileGraphics (0-16)
;
; Three cases:
;   earned          the leader recorded in wBadgeSlotOrder
;   the NEXT slot   the leader of the gym currently queued, if the player has
;                   foresight and a gym really is queued
;   anything else   CARD_BLOCK_UNKNOWN, whose face half is the "?"
;
; The reveal is deliberately ONE slot, not every unearned slot. Foresight tells
; the player who is behind the next gym door; it is not a table of contents for
; the whole run. So it lands on the slot that the next victory will fill, which
; is the first empty one - and because the array is densely packed, "slot i is
; the next one" is just "slot i is empty and slot i-1 is not".
;
; The revealed leader comes from the QUEUED GYM's badge bit, not from the slot
; index. Those are different numbers once any badge has been earned: with two
; badges the next slot is 2, while the queued gym might be badge bit 5.
;
; A recorded class with no block at all (which should not happen) also draws the
; "?" rather than something arbitrary.
RogueCardBlockForSlot::
	ld e, a
	ld d, 0
	ld hl, wBadgeSlotOrder
	add hl, de
	ld a, [hl]
	and a
	jr nz, .haveClass
	call RogueCardRevealedSlot ; preserves e
	jr nc, .unknown
	cp e                       ; is THIS the one slot being revealed?
	jr nz, .unknown
	call RogueCardNextGymBadgeBit  ; carry is guaranteed: the check above passed
	call RogueCardLeaderForBadgeBit
.haveClass
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
.unknown
	ld a, CARD_BLOCK_UNKNOWN
	ret
.found
	ld a, c
	ret

; ============================================================
; RogueCardRevealedSlot
; OUTPUT: carry set and a = the single card slot the foresight reveal occupies;
;         carry clear if nothing is being revealed.
; PRESERVES de, which RogueCardBlockForSlot depends on.
;
; The revealed slot is the one the next win will fill, which - because
; wBadgeSlotOrder is always densely packed from index 0 - is simply its first
; empty entry. Three things must hold: the player has foresight, a gym is
; queued rather than a route, and there is a slot left to fill at all.
;
; Single source of truth for "which slot", used by RogueCardBlockForSlot to
; choose a face, by RogueBlitCardBadges to choose a name strip, and by
; DrawBadges to decide which cell draws the name.
RogueCardRevealedSlot::
	ld a, [wRogueFlagsBitfield2]
	bit BIT_ROGUE_PREDICT_BADGES, a
	jr z, .none
	call RogueCardNextGymBadgeBit
	jr nc, .none
	ld hl, wBadgeSlotOrder
	ld c, 0
.scan
	ld a, [hli]
	and a
	jr z, .found
	inc c
	ld a, c
	cp NUM_BADGES
	jr c, .scan
.none
	and a                      ; clear carry
	ret
.found
	ld a, c
	scf
	ret

; ============================================================
; RogueCardRevealedSlotForDraw
; OUTPUT: e = the revealed slot index, or $FF when nothing is revealed.
;
; Exists only so DrawBadges can ask the question across a farcall: it returns in
; e because Bankswitch destroys a/b/c/h/l on both sides.
;
; DrawBadges has to ask for itself rather than being handed the answer by
; RogueBlitCardBadges, even though the blit already computed it. wBadgeNameTile
; is the obvious place to pass it and is a TRAP: it shares a UNION with
; wTrainerInfoTextBoxWidth, which DrawTrainerInfo writes AFTER the blit runs, so
; anything left there would be overwritten before DrawBadges ever read it.
RogueCardRevealedSlotForDraw::
	call RogueCardRevealedSlot
	ld e, $FF
	ret nc
	ld e, a
	ret

; ============================================================
; RogueCardNextGymBadgeBit
; OUTPUT: carry set and a = badge bit (0-7) of the gym the player is queued to
;         enter; carry clear if the queued stage is a route, not a gym.
;
; _PickNextGym computes exactly this index, then discards it and keeps only the
; map id, so recover it by reverse-scanning the table it used. That costs no
; WRAM, which matters here: wRogueFlagsBitfield2 is now full and this is a
; display-only convenience that does not deserve a fresh byte.
;
; wRogueMap is the right source rather than either wLobbyDoorNStageMap: both
; doors default to it, and the bridge layer, the only thing that can repoint
; them on a gym cycle, still routes onward to wRogueMap after its gift.
;
; GymMapByBadge lives in random_stage_selection.asm, which shares SECTION "rogue"
; with this file, so this read is in-bank BY CONSTRUCTION. If either file is ever
; moved, they move together or this needs a far read.
RogueCardNextGymBadgeBit::
	ld a, [wRogueMap]
	ld b, a
	ld hl, GymMapByBadge
	ld c, 0
.scan
	ld a, [hli]
	cp b
	jr z, .found
	inc c
	ld a, c
	cp NUM_BADGES
	jr c, .scan
	and a                      ; clear carry: the queued stage is not a gym
	ret
.found
	ld a, c
	scf
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

	; The revealed leader's name, into vChars2 tile CARD_NAME_VRAM_TILE. Only
	; one name is ever on the card, so this is three tiles rather than a strip
	; per slot - see CARD_NAME_TILES for why an earned badge gets none.
	call RogueCardRevealedSlot
	ret nc
	call RogueCardBlockForSlot
	call .NameOffset
	ld de, LeaderNameTileGraphics
	add hl, de
	ld de, vChars2 tile CARD_NAME_VRAM_TILE
	ld bc, CARD_NAME_TILES tiles
	ld a, BANK(LeaderNameTileGraphics)
	jp FarCopyData2

; a -> hl = a * CARD_TILES_PER_LEADER tiles (128). The source block stride and
; the destination slot stride are both one block, so this serves both.
.BlockOffset
	ld h, 0
	ld l, a
	REPT 7
	add hl, hl
	ENDR
	ret

; a -> hl = a * CARD_NAME_TILES tiles (48). Not a power of two, so it is 32 + 16
; rather than a shift run. Clobbers de, which the caller reloads anyway.
.NameOffset
	ld h, 0
	ld l, a
	REPT 4
	add hl, hl
	ENDR
	ld d, h
	ld e, l                    ; de = a * 16
	add hl, hl                 ; hl = a * 32
	add hl, de                 ; hl = a * 48
	ret
