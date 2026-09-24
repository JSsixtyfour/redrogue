; custom_functions/run_toggle_clear.asm
;
; ============================================================
; RogueRunToggleClear - the run reset's TOGGLE step.
;
; Called by farcall from RogueResetRunState (custom_functions/credit_popup.asm),
; right after its ZONE 1 event wipe, so it runs at every run end (blackout and
; Hall of Fame).
;
; Why this is separate from the event wipe: an object hidden with HideObject
; is hidden by a bit in wToggleableObjectFlags, and those bits are NOT events.
; ResetEventRange never touches them, so an object a stage script hides stays
; hidden in every later run - while its trainer's beat event, which IS an
; event, comes back clear. Tower 7F was the case that showed this: the beaten
; rockets and Fuji stayed invisible, the rockets could not be refought, and
; its all-trainers reward could never fire again.
;
; This does NOT reset every toggle (InitializeToggleableObjectsFlags does that,
; at true new game only): some toggles may carry state that must outlive a
; run. Only toggles listed below are cleared, i.e. set back to SHOWN. To add
; one, append its TOGGLE_ constant; the object must default to ON in
; data/maps/toggleable_objects.asm, since "cleared" means visible.
;
; Clobbers everything.
; ============================================================
RogueRunToggleClear::
	ld hl, RunClearedToggles
.loop
	ld a, [hli]
	cp -1
	ret z
	push hl
	ld c, a
	ld b, FLAG_RESET                ; flag clear = object shown
	ld hl, wToggleableObjectFlags
	predef FlagActionPredef
	pop hl
	jr .loop

RunClearedToggles:
	; Pokemon Tower 7F: rockets walk off and hide when beaten; Fuji hides when
	; he warps the player to the lobby.
	db TOGGLE_POKEMON_TOWER_7F_ROCKET_1
	db TOGGLE_POKEMON_TOWER_7F_ROCKET_2
	db TOGGLE_POKEMON_TOWER_7F_ROCKET_3
	db TOGGLE_POKEMON_TOWER_7F_ROCKET_4
	db TOGGLE_POKEMON_TOWER_7F_ROCKET_5
	db TOGGLE_POKEMON_TOWER_7F_MR_FUJI
	db -1 ; end
