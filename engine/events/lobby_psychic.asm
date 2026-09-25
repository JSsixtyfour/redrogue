; engine/events/lobby_psychic.asm
;
; The lobby Psychic sells GYM FORESIGHT: for a price, they name the leader
; behind the next gym door and set BIT_ROGUE_PREDICT_BADGES, which makes the
; trainer card reveal that leader's face and name (custom_functions/
; trainer_card_slots.asm, Phase 4b of the gym-leader expansion - the reveal and
; its per-gym spending were already built, only a granter was missing).
;
; Price is $1000 * (badges + 1): $1000 before gym 1, $8000 before gym 8.
;
; Lives in "Lobby NPCs" ($3C) because the lobby map's bank ($06) is full; the map
; reaches it through text_asm/farcall stubs. The "who is next" question lives in
; "rogue" ($38) and is asked through RogueNextGymLeaderFar, which answers in e.

; TESTING: 1 = the Psychic appears on EVERY gym-next lobby visit. Set to 0 for
; release, which adds the intended 50% appearance roll (still only ever on a
; gym-next visit). Same role as the witch's commented-out RollLobbyNPCAppearance
; call in custom_functions/witch_setup.asm.
DEF PSYCHIC_ALWAYS_APPEARS EQU 1

; ============================================================
; PCPsychicSetup
; Shows the Psychic only while a gym is queued, and never in the final sequence
; (all badges earned: Victory Road / Elite Four); with PSYCHIC_ALWAYS_APPEARS
; off, only half of those visits. Must run after SelectAndPatchLobbyExit, which
; is what sets wRogueMap. Rolled once per lobby entry (the caller is inside the
; EVENT_ENTER_ROOM block). The toggle resets on every warp, so both branches
; are explicit, like PCWitchSetup's.
PCPsychicSetup::
	ld a, [wObtainedBadges]
	cp $FF
	jr z, .hide
	farcall RogueNextGymLeaderFar
	ld a, e
	and a
	jr z, .hide
IF !PSYCHIC_ALWAYS_APPEARS
	call Random
	and 1
	jr nz, .hide                ; 50%: not here this visit
ENDC
	ld a, TOGGLE_PC_PSYCHIC
	ld [wToggleableObjectIndex], a
	predef_jump ShowObject
.hide
	ld a, TOGGLE_PC_PSYCHIC
	ld [wToggleableObjectIndex], a
	predef_jump HideObject

; ============================================================
; PCPsychicLeaderName
; OUTPUT: e = 1 and wNameBuffer = the queued gym leader's name, or e = 0 (and
;         wNameBuffer untouched) if the queued stage is not a gym.
; Returns in e so the door sign in bank $06 can farcall it too.
;
; Names via GetName directly rather than GetTrainerName, which would need
; wTrainerClass written - battle state that has no business changing in the lobby.
PCPsychicLeaderName::
	farcall RogueNextGymLeaderFar
	ld a, e
	and a
	ret z
	ld [wNameListIndex], a
	ld a, TRAINER_NAME
	ld [wNameListType], a
	ld a, BANK(TrainerNames)
	ld [wPredefBank], a
	call GetName                ; -> wNameBuffer
	ld e, 1
	ret

; ============================================================
; PCPsychicTalk
; The Psychic's dialogue. Reached from TEXT_PC_PSYCHIC's text_asm stub.
PCPsychicTalk::
	call PCPsychicLeaderName
	ld a, e
	and a
	ld hl, PsychicNoGymText     ; defensive: setup hides the Psychic in this case
	jp z, PrintText
	ld a, [wRogueFlagsBitfield2]
	bit BIT_ROGUE_PREDICT_BADGES, a
	ld hl, PsychicAlreadyText   ; already paid for this gym - no second charge
	jp nz, PrintText

	; price = $1000 * (badges + 1). BCD $00,(n<<4),$00 for n = 1-8, so the
	; thousands digit is just n swapped into the high nibble of the middle byte.
	ld a, [wObtainedBadges]
	ld c, a
	ld b, 1
.countBadges
	ld a, c
	and a
	jr z, .counted
	srl c
	jr nc, .countBadges
	inc b
	jr .countBadges
.counted
	ld a, b
	swap a
	ld [wPriceTemp + 1], a
	xor a
	ld [wPriceTemp], a
	ld [wPriceTemp + 2], a

	ld hl, PsychicOfferText
	call PrintText
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	ld hl, PsychicRefuseText
	jp nz, PrintText
	ld a, [wPriceTemp]
	ldh [hMoney], a
	ld a, [wPriceTemp + 1]
	ldh [hMoney + 1], a
	ld a, [wPriceTemp + 2]
	ldh [hMoney + 2], a
	call HasEnoughMoney         ; carry = cannot afford
	ld hl, PsychicNoMoneyText
	jp c, PrintText
	ld hl, wPriceTemp + 2
	ld de, wPlayerMoney + 2
	ld c, 3
	predef SubBCDPredef
	ld a, SFX_PURCHASE
	call PlaySoundWaitForCurrent
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	; Single-bit set: bits 0-6 of wRogueFlagsBitfield2 are live (slot pulls,
	; Shin Red VRAM/DMA flags). RogueSyncBadgeSlots spends it on that gym's win.
	ld hl, wRogueFlagsBitfield2
	set BIT_ROGUE_PREDICT_BADGES, [hl]
	; Re-derive the name rather than trust wNameBuffer across the menu/money
	; box/sound calls above.
	call PCPsychicLeaderName
	ld hl, PsychicRevealText
	jp PrintText

PsychicOfferText:
	text_far _PsychicOfferText
	text_end

PsychicRefuseText:
	text_far _PsychicRefuseText
	text_end

PsychicNoMoneyText:
	text_far _PsychicNoMoneyText
	text_end

PsychicRevealText:
	text_far _PsychicRevealText
	text_end

PsychicAlreadyText:
	text_far _PsychicAlreadyText
	text_end

PsychicNoGymText:
	text_far _PsychicNoGymText
	text_end
