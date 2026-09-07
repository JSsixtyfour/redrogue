OpenPokemonCenterPC:
	ld a, [wSpritePlayerStateData1FacingDirection]
	cp SPRITE_FACING_UP
	ret nz
	call EnableAutoTextBoxDrawing
	ld a, 1 << BIT_NO_AUTO_TEXT_BOX
	ld [wAutoTextBoxDrawingControl], a
	tx_pre_jump PokemonCenterPCText

PokemonCenterPCText::
	script_pokecenter_pc

; Functional bridge-room storage access. The interaction is deliberately
; invisible until computer graphics are added, and is active only when this
; room was entered from the lobby as a bridge.
OpenBridgeBillsPC::
	ld a, [wWarpedFromWhichMap]
	cp INDIGO_PLATEAU_LOBBY
	ret nz
	ld a, [wSpritePlayerStateData1FacingDirection]
	cp SPRITE_FACING_UP
	ret nz
	call EnableAutoTextBoxDrawing
	ld a, 1 << BIT_NO_AUTO_TEXT_BOX
	ld [wAutoTextBoxDrawingControl], a
	; Use the same complete PC entry path as ordinary map computers. Its menu
	; includes Bill's PC and performs the established screen/audio cleanup.
	tx_pre_jump PokemonCenterPCText
