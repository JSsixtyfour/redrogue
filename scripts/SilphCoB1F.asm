SilphCoB1F_Script:
; The Silph Co 1F intro escort ends with the player's final scripted step
; landing ON the stairs, so the warp fires before
; SilphCoPalmMovementScript_Done gets a tick to clean up. Whatever is left set
; then survives onto this map, and IsPlayerCharacterBeingControlledByGame
; (home/npc_movement.asm) keeps returning true for any of
; wNPCMovementScriptPointerTableNum / BIT_SCRIPTED_MOVEMENT_STATE - so the
; player arrives unable to move.
; _EndNPCMovementScript cannot be called early to avoid this: it also zeroes the
; simulated-joypad queue, which would strand the player mid-walk. Clearing on
; arrival is the reliable side of that race.
; All of this is already zero on a normal entry, so the cleanup is harmless.
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	res BIT_CUR_MAP_LOADED_1, [hl]
	jr z, .noEscortCleanup
	xor a
	ld [wNPCMovementScriptPointerTableNum], a
	ld [wNPCMovementScriptFunctionNum], a
	ld [wNPCMovementScriptSpriteOffset], a
	ldh [hSimulatedJoypadStatesIndex], a
	ld [wSimulatedJoypadStatesEnd], a
	ldh [hJoyIgnore], a
	ld hl, wStatusFlags5
	res BIT_SCRIPTED_MOVEMENT_STATE, [hl]
	ld hl, wStatusFlags4
	res BIT_INIT_SCRIPTED_MOVEMENT, [hl]
.noEscortCleanup
	jp EnableAutoTextBoxDrawing

SilphCoB1F_TextPointers:
	def_text_pointers
