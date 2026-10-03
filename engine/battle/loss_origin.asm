; Blackout "You were defeated by <label>" line, printed by HandlePlayerBlackOut
; just before the normal blacked-out text.
;
; The label names where the moveset of the enemy mon that beat you came from:
; a curated set ("Elo Bandit's Special Amnesia BoltBeamSurf set."), "a Generated
; set.", "a Basic Learnset.", "a Red Rogue original set." or "your own Champion
; team.". ReadTrainer records one LossOriginLabels index per enemy slot in
; wEnemyMoveOrigins while it builds the party; this reads the slot that was out.
;
; Shares bank $35 with LossOriginLabels (data/trainers/movesets.asm), so the
; table's dw pointers are read directly.
SECTION "Loss Origin Text", ROMX, BANK[$35]

PrintLossOrigin::
	ld a, [wLinkState]
	cp LINK_STATE_BATTLING
	ret z
	ld hl, .text
	jp PrintText

.text
	text "You were defeated"
	line "by @"
	text_asm
; bc is the live text cursor: touch only a, de, hl until PlaceString.
; Wild mons, and anything out of range, read as the plain learnset. Not
; wIsTrainerBattle: HandlePlayerBlackOut zeroes it on entry.
	ldh a, [hIsInBattle]
	cp 2
	jr nz, .learnset
	ld a, [wEnemyMonPartyPos]
	cp PARTY_LENGTH
	jr nc, .learnset
	ld e, a
	ld d, 0
	ld hl, wEnemyMoveOrigins
	add hl, de
	ld a, [hl]
	cp NUM_LOSS_ORIGINS
	jr c, .gotCode
.learnset
	ASSERT LOSS_ORIGIN_LEARNSET == 0
	xor a
.gotCode
	ld l, a
	ld h, 0
	add hl, hl
	ld de, LossOriginLabels
	add hl, de
	ld a, [hli]
	ld d, [hl]
	ld e, a
	ld h, b
	ld l, c
	call PlaceString           ; returns bc = cursor after the label
	ld h, b
	ld l, c
	ld de, .prompt
	call PlaceString
	jp TextScriptEnd

.prompt
	db "<PROMPT>@"

ASSERT BANK(LossOriginLabels) == BANK(PrintLossOrigin)
