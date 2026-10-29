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
	jr ToggleClearList

; ============================================================
; RogueStageToggleClear - the same step for the stage maps only, when the stage
; pool recycles mid-run (RecycleStagePool, custom_functions/endless.asm). The
; stage toggles are the tail of RunClearedToggles, so the two lists cannot
; drift apart. Clobbers everything.
; ============================================================
RogueStageToggleClear::
	ld hl, StageClearedToggles
ToggleClearList:
	ld a, [hli]
	cp -1
	ret z
	push hl
	ld c, a
	ld b, FLAG_RESET                ; flag clear = object shown
	ld hl, wToggleableObjectFlags
	predef FlagActionPredef
	pop hl
	jr ToggleClearList

RunClearedToggles:
	; Repair saves where an older build hid gym Giovanni after his advice.
	db TOGGLE_VIRIDIAN_GYM_GIOVANNI
	; Oak's Lab: the player's and rival's starter balls hide when taken, and
	; the rival hides after the lab battle. Starter selection replays every
	; run (wPlayerStarter/EVENT_GOT_STARTER are run-scoped), so all four must
	; come back or run 2 finds one ball, no rival, and a freeze on pickup.
	db TOGGLE_ROGUE_STARTER_POKEBALL_1
	db TOGGLE_ROGUE_STARTER_POKEBALL_2
	db TOGGLE_ROGUE_STARTER_POKEBALL_3
	db TOGGLE_OAKS_LAB_RIVAL
	; Everything from here on is on a RogueStageMapTable map.
StageClearedToggles:
	; Pokemon Tower 7F: rockets walk off and hide when beaten; Fuji hides when
	; he warps the player to the lobby.
	db TOGGLE_POKEMON_TOWER_7F_ROCKET_1
	db TOGGLE_POKEMON_TOWER_7F_ROCKET_2
	db TOGGLE_POKEMON_TOWER_7F_ROCKET_3
	db TOGGLE_POKEMON_TOWER_7F_ROCKET_5
	db TOGGLE_POKEMON_TOWER_7F_MR_FUJI
	; SS Anne B1F: the captain hides once the rooms' four trainers are beaten.
	db TOGGLE_SS_ANNE_B1F_CAPTAIN
	db -1 ; end
