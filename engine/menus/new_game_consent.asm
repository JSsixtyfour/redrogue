; No RAM allocation or schema change. Both title-menu New Game paths call this
; before OakSpeech can initialize persistent companion data. NZ cancels; Z starts.
SECTION "New Game Consent", ROMX, BANK[$2E]

ConfirmNewGameOverwrite::
	rfarcall CheckForPlayerNameInSRAM_
	jr c, .prompt
	; Also protect a recognizable header when the player-name field is damaged.
	call .open
	ld hl, sSaveHeader
	ld b, SAVE_HEADER_SIZE
.checkHeader
	ld a, [hli]
	and a
	jr z, .next
	cp $ff
	jr nz, .headerPresent
.next
	dec b
	jr nz, .checkHeader
	call .close
	xor a
	ret
.headerPresent
	call .close
.prompt
	ld hl, .warning
	call PrintText
	ld a, YES_NO_MENU | (1 << BIT_SECOND_MENU_OPTION_DEFAULT)
	ld [wTwoOptionMenuID], a
	hlcoord 0, 7
	lb bc, 8, 1
	ld a, TWO_OPTION_MENU
	ld [wTextBoxID], a
	call DisplayTextBoxID
	ldh a, [hCurrentMenuItem]
	and a
	ret nz
	; YES deliberately discards the old profile now. A reset during initialization
	; must not Continue old main data paired with freshly initialized companions.
	call .open
	ld hl, sSaveHeader
	ld b, SAVE_HEADER_SIZE
	xor a
.invalidate
	ld [hli], a
	dec b
	jr nz, .invalidate
	call .close
	ld a, 1
	ld [wSaveFileStatus], a
	xor a
	ret
.open
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK(sSaveHeader) == BMODE_ADVANCED
	ld [rRAMB], a
	ret
.close
	xor a
	ld [rRAMG], a
	ld [rBMODE], a
	ret
.warning
	text "Erase old save"
	line "NOW and start a"
	cont "new game?"
	done
