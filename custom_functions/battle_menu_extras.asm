; custom_functions/battle_menu_extras.asm
;
; Battle menu additions: the END option's confirm-and-forfeit, the battle-only
; ITEM list (active key items + POKE FLUTE) with its description box, and the
; ghost-variant entrance fade.
;
; Declares its own SECTION, pinned to ROMX $3A in layout.link. "Battle Core"
; (bank $0F) has almost no free space, so core.asm keeps only thin farcall stubs
; and the logic lives here. Every entry point is reached by farcall, which
; clobbers a/b/c/h/l on the way in: inputs travel in d/e or WRAM, never hl.
;
; Text lives inline in this bank rather than behind text_far: "Rogue" text
; (bank $04, data/text/text_rogue.asm) has 5 bytes free. PrintText reads from
; the active ROM bank, which is this one while these routines run.

; ============================================================
; RogueConfirmEndBattle - the battle menu's END option (BattleMenu_RunWasSelected,
; engine/battle/core.asm). Debug builds never reach this: they keep the old RUN
; path, which auto-wins against trainers and procedural wilds.
;
; OUTPUT: carry set = the player confirmed. The whole party (and wBattleMon) is
;         at 0 HP and wBattleResult = 1, so the caller's jp HandlePlayerBlackOut
;         ends the battle exactly like an all-faint loss, and the overworld's
;         post-battle AnyPartyAlive check (home/overworld.asm) runs the blackout.
;         carry clear = declined or refused; the caller redisplays the menu.
;
; The yes/no box is drawn the way DoUseNextMonDialogue draws its own, NOT through
; YesNoChoice: YesNoChoice snapshots screen buffer 1 on entry, and buffer 1 is
; what DisplayBattleMenu restores - it would bring the prompt back forever.
; ============================================================
RogueConfirmEndBattle::
	; Refused where a forced blackout would go wrong. Link battles have a second
	; Game Boy to keep in step. Oak's Lab is the starter battle, where
	; HandlePlayerBlackOut deliberately skips the blackout, so the player would
	; walk out with a 0-HP party.
	ld a, [wLinkState]
	cp LINK_STATE_BATTLING
	jr z, .refuse
	ldh a, [hCurMap]
	cp OAKS_LAB
	jr z, .refuse

	ld hl, .ConfirmText
	call PrintText
	xor a ; YES_NO_MENU
	ld [wTwoOptionMenuID], a
	hlcoord 13, 9
	lb bc, 10, 14
	ld a, TWO_OPTION_MENU
	ld [wTextBoxID], a
	call DisplayTextBoxID
	ld a, [wMenuExitMethod]
	cp CHOSE_SECOND_ITEM ; NO, or B
	jr z, .declined

	; Forfeit: zero every party mon's HP, then the active battle copy.
	ld a, [wPartyCount]
	ld b, a
	ld hl, wPartyMon1HP
	ld de, PARTYMON_STRUCT_LENGTH - 1
.zeroLoop
	xor a
	ld [hli], a
	ld [hl], a
	add hl, de
	dec b
	jr nz, .zeroLoop
	xor a
	ld hl, wBattleMonHP
	ld [hli], a
	ld [hl], a
	ld a, 1
	ld [wBattleResult], a
	scf
	ret

.refuse
	ld hl, .RefuseText
	call PrintText
.declined
	and a
	ret

.ConfirmText:
	text "Give up and end"
	line "this run?"
	done

.RefuseText:
	text "You can't end"
	line "this battle!"
	prompt
