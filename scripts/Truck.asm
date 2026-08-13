; Arrival cutscene. The player is warped in here by OakSpeech while the truck is
; already moving: it rumbles, stops, Prof Palm calls the player out (he is not
; visible - this is a plain textbox with no object behind it), and only then does
; the player get control.
;
; BIT_CUR_MAP_LOADED_1 is set by the engine on map entry and cleared here, so the
; body below runs exactly once per visit with no extra state variable. Only ONE
; BIT_CUR_MAP_LOADED_* check may run per script tick - a second one starves and
; silently never fires - and this script has exactly one.
Truck_Script:
	call EnableAutoTextBoxDrawing
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	res BIT_CUR_MAP_LOADED_1, [hl]
	ret z

; The player is a passenger: block movement until Palm speaks.
; MUST be the d-pad ONLY. hJoyIgnore masks hJoyPressed globally
; (engine/joypad.asm), and the textbox below ends on a `prompt`, whose
; ManualTextScroll wait reads A/B out of that same masked byte. Adding
; PAD_BUTTONS here softlocks the game: the '▼' sits there forever because the
; A press is filtered out before the text engine ever sees it, and the
; hJoyIgnore clear that would release it lives after the text call.
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	call Delay3

; ShakeElevator stops the music, toggles hSCY by +/-1 for 100 iterations with
; SFX_COLLISION, then ends on SFX_SAFARI_ZONE_PA and calls PlayDefaultMusic - so
; the truck shudders to a halt and this map's song starts as it settles.
	farcall ShakeElevator

	ld a, TEXT_TRUCK_PROF_PALM
	ldh [hTextID], a
	call DisplayTextID

	xor a
	ldh [hJoyIgnore], a ; hand control back
	ret

Truck_TextPointers:
	def_text_pointers
	dw_const TruckProfPalmText, TEXT_TRUCK_PROF_PALM

TruckProfPalmText:
	text_far _TruckProfPalmText
	text_end
