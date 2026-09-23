DEF AILAIR_WARMUP_TICKS EQU 8
DEF AILAIR_STATE_DONE EQU $ff

AILair_Script:
	call EnableAutoTextBoxDrawing
	call AILairHandleMapEntry
	ld a, [wSilphCo1FCurScript]
	cp AILAIR_STATE_DONE
	ret z
	cp AILAIR_WARMUP_TICKS
	jr nc, .opening
	inc a
	ld [wSilphCo1FCurScript], a
	ret
.opening
	call UpdateSprites
	ld a, TEXT_AILAIR_OPENING
	ldh [hTextID], a
	call DisplayTextID
	xor a
	ldh [hJoyIgnore], a
	ld a, AILAIR_STATE_DONE
	ld [wSilphCo1FCurScript], a
	ret

; Once per load: silence music, mark the AI faced, face the player right at
; the machine, and start the warm-up counter the opening text waits on.
AILairHandleMapEntry:
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	ret z
	res BIT_CUR_MAP_LOADED_1, [hl]
	; The final arena is deliberately silent outside its eventual battle.
	ld a, SFX_STOP_ALL_MUSIC
	ld [wNewSoundID], a
	call PlaySound
	SetEvent EVENT_AI_FACED
	ld a, PLAYER_DIR_RIGHT
	ld [wPlayerMovingDirection], a
	ld a, SPRITE_FACING_RIGHT
	ld [wSpritePlayerStateData1FacingDirection], a
	ld a, PAD_BUTTONS | PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	xor a
	ld [wSilphCo1FCurScript], a
	ret

; wPlayerAppearance -> overworld sprite id whose SpriteSheetPointerTable row is
; the same walk sheet as that appearance's PlayerAppearanceTable row. Order must
; match data/player/appearance.asm exactly; the smoke test enforces it.
AILairMirrorSpriteIDs:
	table_width 1
	db SPRITE_RED             ; red
	db SPRITE_HIKER           ; biker (BikerSprite is a rider; walk sheet borrows Hiker)
	db SPRITE_COOLTRAINER_M   ; birdKeeper
	db SPRITE_HIKER           ; blackbelt
	db SPRITE_YOUNGSTER       ; bugCatcher
	db SPRITE_SUPER_NERD      ; burglar
	db SPRITE_COOLTRAINER_M   ; coolTrainerM
	db SPRITE_HIKER           ; cueBall
	db SPRITE_SUPER_NERD      ; engineer
	db SPRITE_FISHER          ; fisherman
	db SPRITE_GAMBLER         ; gambler
	db SPRITE_GENTLEMAN       ; gentleman
	db SPRITE_HIKER           ; hiker
	db SPRITE_COOLTRAINER_M   ; jrTrainerM
	db SPRITE_SUPER_NERD      ; juggler
	db SPRITE_SUPER_NERD      ; pokemaniac
	db SPRITE_YOUNGSTER       ; psychic
	db SPRITE_ROCKER          ; rocker
	db SPRITE_ROCKET          ; rocket
	db SPRITE_SAILOR          ; sailor
	db SPRITE_SCIENTIST       ; scientist
	db SPRITE_SUPER_NERD      ; superNerd
	db SPRITE_COOLTRAINER_M   ; swimmer (SwimmerSprite depicts swimming, not walking)
	db SPRITE_ROCKER          ; tamer
	db SPRITE_YOUNGSTER       ; youngster
	; Female entries start here.
	db SPRITE_GREEN           ; green
	db SPRITE_BEAUTY          ; beauty
	db SPRITE_CHANNELER       ; channeler
	db SPRITE_COOLTRAINER_F   ; jrTrainerF
	db SPRITE_COOLTRAINER_F   ; coolTrainerF
	db SPRITE_COOLTRAINER_F   ; lass
	assert_table_length NUM_PLAYER_APPEARANCES

; Called from ProcBossPatchStageSprite between LoadMapHeader and InitMapSprites.
; AILAIR_OPPONENT is object 1, so its slot is wSprite01.
AILairPatchMirrorSprite::
	ld a, [wPlayerAppearance]
	cp NUM_PLAYER_APPEARANCES
	jr c, .inRange
	xor a ; corrupt byte: fall back to Red rather than index past the table
.inRange
	ld hl, AILairMirrorSpriteIDs
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hl]
	ld [wSprite01StateData1PictureID], a
	ret

AILair_TextPointers:
	def_text_pointers
	dw_const AILairOpponentText, TEXT_AILAIR_OPPONENT
	dw_const AILairOpeningText, TEXT_AILAIR_OPENING

AILairOpponentText:
	text "I know you better"
	line "than yourself,"
	cont "prepare to lose."
	prompt

AILairOpeningText:
	text "I know you better"
	line "than yourself,"
	cont "prepare to lose."
	prompt
