DEF AILAIR_WARMUP_TICKS EQU 8
DEF AILAIR_STATE_AFTER_BATTLE EQU $fe
DEF AILAIR_STATE_DONE EQU $ff

AILair_Script:
	call EnableAutoTextBoxDrawing
	call AILairHandleMapEntry
	ld a, [wSilphCo1FCurScript]
	cp AILAIR_STATE_DONE
	ret z
	cp AILAIR_STATE_AFTER_BATTLE
	jr z, .afterBattle
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
	call Delay3
	ld hl, wStatusFlags3
	set BIT_TALKED_TO_TRAINER, [hl]
	set BIT_PRINT_END_BATTLE_TEXT, [hl]
	ld hl, AILairDefeatedText
	ld de, AILairVictoryText
	call SaveEndBattleTextPointers
	ld a, OPP_FINAL_AI
	ld [wCurOpponent], a
	ld a, 1
	ld [wTrainerNo], a
	ld [wIsTrainerBattle], a
	xor a
	ldh [hJoyIgnore], a
	ldh [hJoyHeld], a
	ld a, AILAIR_STATE_AFTER_BATTLE
	ld [wSilphCo1FCurScript], a
	ret
.afterBattle
	ldh a, [hIsInBattle]
	cp $ff
	jr nz, .won
	; Loss. .allPokemonFainted (home/overworld.asm) runs this script once with
	; hIsInBattle = $ff before HandleBlackOut. Spend the attempt, and black out
	; to the Dorm. The Hall of Fame now defaults wLastBlackoutMap to the Dorm;
	; this store still repairs saves made before that change.
	SetEvent EVENT_AI_ATTEMPT_SPENT
	ld a, SILPH_CO_DORM
	ld [wLastBlackoutMap], a
	jr .done
.won
	; Victory (plan section 8.4). Nothing below returns to the overworld: the
	; credits end in jp Init, like a normal Hall of Fame clear.
	xor a
	ld [wIsTrainerBattle], a
	ld a, AILAIR_STATE_DONE
	ld [wSilphCo1FCurScript], a
	farcall RogueAwardCredits3 ; the largest award, live option bonuses included
	call UpdateSprites
	ld a, TEXT_AILAIR_POSTBATTLE
	ldh [hTextID], a
	call DisplayTextID
	ld a, PAD_BUTTONS | PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	; Durable before the credits: a reset during them must not replay the
	; fight. The run reset belongs in this same save so that reset also lands
	; in the Dorm with no party (the Continue redirect in main_menu.asm sends
	; an AI_LAIR save there). The Hall of Fame clear or retry that preceded
	; this fight already reset the Elite Four scripts and run events, so only
	; the restored party and this fight's run state remain.
	SetEvent EVENT_AI_DEFEATED
	farcall RogueResetRunState
	farcall SaveGameData
	farcall AIVictoryCredits
	SetEvent EVENT_POST_GAME
	farcall SaveGameData
	ld b, 5
.delayLoop
	ld c, 600 / 5
	call DelayFrames
	dec b
	jr nz, .delayLoop
	call WaitForTextScrollButtonPress
	jp Init
.done
	xor a
	ld [wIsTrainerBattle], a
	ld a, AILAIR_STATE_DONE
	ld [wSilphCo1FCurScript], a
	ret

; Once per load: silence music, and (unless returning from the battle) mark the
; AI faced, restore the player's archived team, face the player right at the
; machine, and start the warm-up counter the opening text waits on.
AILairHandleMapEntry:
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	ret z
	res BIT_CUR_MAP_LOADED_1, [hl]
	; The final arena is deliberately silent outside its battle, including
	; after the battle returns and the map song would otherwise resume.
	ld a, SFX_STOP_ALL_MUSIC
	ld [wNewSoundID], a
	call PlaySound
	; .battleOccurred (home/overworld.asm) sets BIT_CUR_MAP_LOADED_1 after
	; every battle. Returning from the AI battle is not an arrival.
	ld a, [wSilphCo1FCurScript]
	cp AILAIR_STATE_AFTER_BATTLE
	ret z
	SetEvent EVENT_AI_FACED
	farcall FinalTeamArchiveRestoreLatest ; Palm's restored team, full health
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
	dw_const AILairPostBattleText, TEXT_AILAIR_POSTBATTLE

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

AILairDefeatedText:
	text "Impossible!"
	line "You outsmarted me."
	prompt

AILairVictoryText:
	text "As expected."
	line "You need more"
	cont "training."
	prompt

AILairPostBattleText:
	text "INSERT TEST HERE"
	prompt
