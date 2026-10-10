; engine/events/lobby_psychic.asm
;
; The lobby Psychic sells GYM FORESIGHT. A gym-next lobby offers two gyms
; (wGymChoice, player feedback #1, 2026-10-09): door 1's is revealed, door 2's is
; hidden, and with one unbeaten gym left the single door is hidden. For a price
; the Psychic reveals the hidden one; the door sign and the trainer card then
; name it too. Talking again repeats the reveal for free.
;
; Price is $1000 * (badges + 1): $1000 before gym 1, $8000 before gym 8.
;
; Lives in "Lobby NPCs" ($3C) because the lobby map's bank ($06) is full; the map
; reaches it through text_asm/farcall stubs. Which gym sits behind which door
; lives in "rogue" ($38) and is asked through RogueGymDoorInfoFar (answers in d/e).
; This file also builds the gym door signs' text (LobbyBuildGymSign).

; ============================================================
; LobbyRollNPC
; Shows or hides one optional lobby resident for this visit. Debug 1 and
; Debug 2 (BIT_DEBUG_MODE) always show; a normal run shows it on `b` out of
; 256 visits. The toggle resets on every warp, so both outcomes are written
; explicitly. Same rule as the witch's RollLobbyNPCAppearance
; (custom_functions/witch_setup.asm), which lives in another bank.
; Input: a = toggle index, b = chance out of 256 (a LOBBY_*_CHANCE constant)
; ============================================================
LobbyRollNPC:
	ld [wToggleableObjectIndex], a
	ld a, [wStatusFlags6]
	bit BIT_DEBUG_MODE, a
	jr nz, .show
	call Random                 ; preserves bc
	cp b
	jr nc, .hide                ; rolled at or above the chance: not here this visit
.show
	predef_jump ShowObject
.hide
	predef_jump HideObject

; ============================================================
; PCLobbyExtrasSetup
; The salesman, the trader and the move tutor each get an independent
; appearance roll. Their offers are still rolled every visit by the lobby
; script's own setups; a hidden NPC's offer simply goes unused.
; Reached through PCPsychicSetup, so the lobby script (bank $06, a handful of
; bytes free) needs no second farcall; once per lobby entry.
; ============================================================
PCLobbyExtrasSetup:
	ld a, TOGGLE_PC_POKESALESMAN
	ld b, LOBBY_SALESMAN_CHANCE
	call LobbyRollNPC
	ld a, TOGGLE_PC_TRADENERD
	ld b, LOBBY_TRADER_CHANCE
	call LobbyRollNPC
	ld a, TOGGLE_PC_MOVETUTOR
	ld b, LOBBY_TUTOR_CHANCE
	jr LobbyRollNPC

; ============================================================
; PCPsychicSetup
; Shows the Psychic on every gym-next visit (there is always a hidden gym door
; to foresee, or one already foreseen to repeat), never otherwise. Must run
; after SelectAndPatchLobbyExit, which latches the gyms. Rolled once per lobby
; entry (the caller is inside the EVENT_ENTER_ROOM block). The toggle resets on
; every warp, so both branches are explicit. Also rolls the salesman, trader
; and move tutor first.
PCPsychicSetup::
	call PCLobbyExtrasSetup
	ld a, TOGGLE_PC_PSYCHIC
	ld [wToggleableObjectIndex], a
	ld e, 1
	farcall RogueGymDoorInfoFar     ; d = door 1's leader, 0 = not a gym visit
	ld a, d
	and a
	jr z, .hide
	predef_jump ShowObject
.hide
	predef_jump HideObject

; ============================================================
; PCPsychicTarget
; OUTPUT: d = the leader behind the door the Psychic foresees (0 = none),
;         e = 1 if it is already revealed. That door is door 2 when two gyms are
;         offered, else the single last door (door 1).
PCPsychicTarget:
	ld e, 2
	farcall RogueGymDoorInfoFar
	ld a, d
	and a
	ret nz
	ld e, 1
	farcall RogueGymDoorInfoFar
	ret

; ============================================================
; PCPsychicNameLeader
; INPUT: a = leader trainer class. OUTPUT: wNameBuffer = the leader's name.
; Names via GetName directly rather than GetTrainerName, which would need
; wTrainerClass written - battle state that has no business changing in the lobby.
PCPsychicNameLeader:
	ld [wNameListIndex], a
	ld a, TRAINER_NAME
	ld [wNameListType], a
	ld a, BANK(TrainerNames)
	ld [wPredefBank], a
	jp GetName                  ; -> wNameBuffer

; ============================================================
; PCPsychicTalk
; The Psychic's dialogue. Reached from TEXT_PC_PSYCHIC's text_asm stub.
PCPsychicTalk::
	call PCPsychicTarget
	ld a, d
	and a
	ld hl, PsychicNoGymText     ; defensive: setup hides the Psychic in this case
	jp z, PrintText
	ld a, e
	and a
	jr z, .offer
	ld a, d
	call PCPsychicNameLeader
	ld hl, PsychicAlreadyText   ; already revealed: say it again, no second charge
	jp PrintText

.offer
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
	; Single-bit set: the rest of wGymChoice is the latched pair of gyms.
	ld hl, wGymChoice
	set BIT_GYM_CHOICE_REVEALED, [hl]
	; Re-derive the leader rather than trust registers across the menu, money
	; box and sound calls above.
	call PCPsychicTarget
	ld a, d
	call PCPsychicNameLeader
	ld hl, PsychicRevealText
	jp PrintText

; ============================================================
; LobbyBuildGymSign  (farcall, from the lobby's door signs in bank $06)
; INPUT: e = door (1 or 2)
; OUTPUT: wNameBuffer = "<CITY> GYM", wStringBuffer = "<LEADER>/<TYPE>", or
;         "??? GYM" / "???/???" while that door is hidden. Two buffers because
;         the longest pair ("BLACKTHORN GYM", "LT.SURGE/ELECTRIC") does not fit one.
LobbyBuildGymSign::
	farcall RogueGymDoorInfoFar     ; d = leader (0 = none), e = revealed
	ld a, d
	and a
	jr z, .hidden
	ld a, e
	and a
	jr z, .hidden
	ld hl, GymSignTable
.find
	ld a, [hli]
	cp -1
	jr z, .hidden                   ; a leader with no row: say nothing wrong
	cp d
	jr z, .found
	inc hl
	inc hl
	inc hl
	inc hl
	jr .find
.found
	ld a, [hli]
	ld c, a
	ld a, [hli]
	ld b, a                         ; bc = city string
	ld a, [hli]
	ld h, [hl]
	ld l, a                         ; hl = type string
	push bc
	push hl
	ld a, d
	call PCPsychicNameLeader        ; wNameBuffer = the leader's name
	ld hl, wNameBuffer
	ld de, wStringBuffer
	call .copy
	ld a, '/'
	ld [de], a
	inc de
	pop hl
	call .copyEnd                   ; "<LEADER>/<TYPE>@"
	pop hl
	ld de, wNameBuffer
	call .copy
	ld hl, .gymSuffix
	jr .copyEnd                     ; "<CITY> GYM@"
.hidden
	ld hl, .hiddenLeader
	ld de, wStringBuffer
	call .copyEnd
	ld hl, .hiddenGym
	ld de, wNameBuffer
	; fallthrough
; Copy hl's string to de through its '@'.
.copyEnd
	call .copy
	ld a, '@'
	ld [de], a
	ret
; Copy hl's string to de up to (not including) its '@'; de is left on the end.
.copy
	ld a, [hli]
	cp '@'
	ret z
	ld [de], a
	inc de
	jr .copy

.gymSuffix:    db " GYM@"
.hiddenGym:    db "??? GYM@"
.hiddenLeader: db "???/???@"

; Leader class -> gym city and the sign's type label. A label rather than a type
; id: the game has no STEEL type, but Jasmine's team is Steel-themed. Rows for
; all sixteen pool leaders plus Janine (she shares Koga's gym).
GymSignTable:
	db BROCK
	dw .pewter, .rock
	db MISTY
	dw .cerulean, .water
	db LT_SURGE
	dw .vermilion, .electric
	db ERIKA
	dw .celadon, .grass
	db KOGA
	dw .fuchsia, .poison
	db JANINE
	dw .fuchsia, .poison
	db SABRINA
	dw .saffron, .psychic
	db BLAINE
	dw .cinnabar, .fire
	db GIOVANNI
	dw .viridian, .ground
	db FALKNER
	dw .violet, .flying
	db BUGSY
	dw .azalea, .bug
	db WHITNEY
	dw .goldenrod, .normal
	db MORTY
	dw .ecruteak, .ghost
	db CHUCK
	dw .cianwood, .fighting
	db JASMINE
	dw .olivine, .steel
	db PRYCE
	dw .mahogany, .ice
	db CLAIR
	dw .blackthorn, .dragon
	db -1
.pewter:     db "PEWTER@"
.cerulean:   db "CERULEAN@"
.vermilion:  db "VERMILION@"
.celadon:    db "CELADON@"
.fuchsia:    db "FUCHSIA@"
.saffron:    db "SAFFRON@"
.cinnabar:   db "CINNABAR@"
.viridian:   db "VIRIDIAN@"
.violet:     db "VIOLET@"
.azalea:     db "AZALEA@"
.goldenrod:  db "GOLDENROD@"
.ecruteak:   db "ECRUTEAK@"
.cianwood:   db "CIANWOOD@"
.olivine:    db "OLIVINE@"
.mahogany:   db "MAHOGANY@"
.blackthorn: db "BLACKTHORN@"
.rock:       db "ROCK@"
.water:      db "WATER@"
.electric:   db "ELECTRIC@"
.grass:      db "GRASS@"
.poison:     db "POISON@"
.psychic:    db "PSYCHIC@"
.fire:       db "FIRE@"
.ground:     db "GROUND@"
.flying:     db "FLYING@"
.bug:        db "BUG@"
.normal:     db "NORMAL@"
.ghost:      db "GHOST@"
.fighting:   db "FIGHTING@"
.steel:      db "STEEL@"
.ice:        db "ICE@"
.dragon:     db "DRAGON@"

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
