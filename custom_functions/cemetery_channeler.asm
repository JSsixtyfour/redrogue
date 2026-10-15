; custom_functions/cemetery_channeler.asm
;
; The Cemetery's possessed Channeler (PROCEDURAL_SUBROOMS_PLAN Phase 4, user
; 2026-10-14). He stands on one random floor per Cemetery (object slot 4 of
; every floor map, shown on that floor only), offers a fight, and battles as
; the Gambler does: a route trainer at MONEY_MATCH_STEP with the ordinary AI,
; no bet (BIT_MONEY_MATCH_NO_PAYOUT keeps the prize money normal). Beat him and
; he heals your party the way Mom does; he stays and says his after line.
; Losing is an ordinary blackout.
;
; State in sProcCemeteryItemGot (SRAM bank 0, cleared for every new Cemetery;
; bits 0-3 are the floors' balls): CEM_CHANNELER_FLOOR_MASK = his floor (0-3),
; BIT_CEM_CHANNELER_WON. His cell is not stored: PCemPlaceChanneler finds it
; again on every load with a fixed scan over the floor's saved blocks.
;
; Opens its own section, pinned to $14 in layout.link; farcall-only.

SECTION "Cemetery Channeler", ROMX

CemChanOpenSRAM:
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK(sProcCemeteryItemGot) == 0
	xor a
	ld [rRAMB], a
	ret

CemChanCloseSRAM:
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ret

; PCemGenerateMaps (preload), right after it cleared sProcCemeteryItemGot; SRAM
; bank 0 open (and left open). Rolls his floor and sets the four floors' flags:
; shown on that floor, hidden on the others (their maps are not loaded).
; Clobbers everything.
CemChannelerRoll::
	ld c, 4
	call Rangerandom
	ld e, a                         ; e = his floor (0-3)
	swap a
	ld b, a
	ld a, [sProcCemeteryItemGot]
	and ~(CEM_CHANNELER_FLOOR_MASK | (1 << BIT_CEM_CHANNELER_WON)) & $ff
	or b
	ld [sProcCemeteryItemGot], a
	ld d, 0                         ; d = floor being written
	ld hl, .toggles
.flag
	ld c, [hl]
	inc hl
	push hl
	push de
	ld b, FLAG_SET                  ; hidden
	ld a, d
	cp e
	jr nz, .write
	ld b, FLAG_RESET                ; shown
.write
	ld hl, wToggleableObjectFlags
	predef FlagActionPredef
	pop de
	pop hl
	inc d
	ld a, d
	cp 4
	jr c, .flag
	ret

.toggles
	db TOGGLE_CEMETERY_1_CHANNELER, TOGGLE_CEMETERY_2_CHANNELER
	db TOGGLE_CEMETERY_3_CHANNELER, TOGGLE_CEMETERY_4_CHANNELER

; Out: a = this map's floor (0-3), carry set; carry clear if hCurMap is not a
; Cemetery floor. Keeps bc/de/hl.
CemChanThisFloor:
	ldh a, [hCurMap]
	push hl
	ld hl, .floors
	push bc
	ld c, a
	ld b, 0
.find
	ld a, [hli]
	cp $ff
	jr z, .none
	cp c
	jr z, .found
	inc b
	jr .find
.found
	ld a, b
	pop bc
	pop hl
	scf
	ret
.none
	pop bc
	pop hl
	and a
	ret

.floors
	db PROCEDURAL_CEMETERY_1, PROCEDURAL_CEMETERY_2
	db PROCEDURAL_CEMETERY_3, PROCEDURAL_CEMETERY_4, $ff

; Out: carry = he is on this floor. Clobbers a/b.
CemChanIsHere:
	call CemChanThisFloor
	ret nc
	ld b, a
	call CemChanOpenSRAM
	ld a, [sProcCemeteryItemGot]
	push af
	call CemChanCloseSRAM
	pop af
	and CEM_CHANNELER_FLOOR_MASK
	swap a
	cp b
	jr nz, .no
	scf
	ret
.no
	and a
	ret

; ProcBossPatchStageSprite's Cemetery branch, every floor load before
; InitMapSprites: his picture only on his floor (a zero picture costs no VRAM
; slot). Clobbers everything.
CemChannelerPatchSprite::
	call CemChanIsHere
	ld a, SPRITE_CHANNELER
	jr c, .write
	xor a
.write
	ld [wSprite{02d:CEMETERY_1_CHANNELER}StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ret

; From his text_asm (the caller keeps bc). Offers, and on a YES arms the
; battle: the overworld starts it once the text closes.
CemChannelerTalk::
	call CemChanOpenSRAM
	ld a, [sProcCemeteryItemGot]
	ld b, a
	call CemChanCloseSRAM
	bit BIT_CEM_CHANNELER_WON, b
	ld hl, CemChannelerAfterText
	jp nz, PrintText
	ld hl, CemChannelerOfferText
	call PrintText
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	ld hl, CemChannelerDeclinedText
	jp nz, PrintText
	; The Gambler's fight, no bet: route step 3, ordinary AI, normal prize.
	ld a, (1 << BIT_MONEY_MATCH_ACTIVE) | (1 << BIT_MONEY_MATCH_NO_PAYOUT)
	ld [wMoneyMatchState], a
	ld a, 1                         ; close the box as the battle starts
	ldh [hNoWaitAfterText], a
	ld hl, wStatusFlags3
	set BIT_TALKED_TO_TRAINER, [hl]
	set BIT_PRINT_END_BATTLE_TEXT, [hl]
	ld hl, CemChannelerBeatenText
	ld de, CemChannelerWonText
	call SaveEndBattleTextPointers  ; this bank, read back after the battle
	ld a, OPP_CHANNELER
	ld [wCurOpponent], a
	ld a, 1                         ; his party is the roster's (MONEY_MATCH_STEP)
	ld [wTrainerNo], a
	ld [wIsTrainerBattle], a
	ld a, SCRIPT_CHANNELER_AFTER_BATTLE
	ld [wSafariZoneGateCurScript], a
	ret

; Every frame of each floor's script (PCemChannelerFrame). Out: carry = his
; battle just ended in a win (recorded): the floor shows its heal text.
; Clobbers a/hl.
CemChannelerSettle::
	ld a, [wSafariZoneGateCurScript]
	cp SCRIPT_CHANNELER_AFTER_BATTLE
	jr nz, .no
	ld a, [wCurOpponent]
	and a
	jr nz, .no
	xor a
	ld [wSafariZoneGateCurScript], a
	ld [wIsTrainerBattle], a
	ld hl, wStatusFlags3
	res BIT_PRINT_END_BATTLE_TEXT, [hl]
	ldh a, [hIsInBattle]
	inc a
	jr z, .no                       ; a blackout takes it from there
	call CemChanOpenSRAM
	ld hl, sProcCemeteryItemGot
	set BIT_CEM_CHANNELER_WON, [hl]
	call CemChanCloseSRAM
	scf
	ret
.no
	and a
	ret

; His heal, the Pokemon Tower 5F purified zone's way (scripts/PokemonTower5F.asm,
; user 2026-10-14): heal, a white flash, no sound. (Mom's healed jingle cannot
; play here: the Cemetery's music is on Audio Engine 3, which has no
; MUSIC_PKMN_HEALED, and the wait for it span forever.) From the floor's heal
; text_asm. Clobbers everything.
CemChannelerHeal::
	ld hl, CemChannelerHealText
	call PrintText
	predef HealParty
	call GBFadeOutToWhite
	call Delay3
	call Delay3
	call GBFadeInFromWhite
	ld hl, CemChannelerHealedText
	jp PrintText

; Placeholder lines (user, 2026-10-14).
CemChannelerOfferText:
	text "Ghhh... The spirit"
	line "wants a battle..."

	para "Will you face it?"
	done

CemChannelerDeclinedText:
	text "Ohhh... it waits."
	done

CemChannelerAfterText:
	text "The spirit is at"
	line "peace now. Thank"
	cont "you, trainer."
	done

CemChannelerHealText:
	text "The spirit left"
	line "me! Let me tend"
	cont "your #MON."
	prompt

CemChannelerHealedText:
	text "Your #MON look"
	line "rested and ready!"
	done

; In battle: he lost. Line 1 already holds "CHANNELER: " (11 of 18).
CemChannelerBeatenText:
	text "Gyaah!"
	para "It's leaving me!"
	prompt

; In battle: he won.
CemChannelerWonText:
	text "Kekeke..."
	prompt
