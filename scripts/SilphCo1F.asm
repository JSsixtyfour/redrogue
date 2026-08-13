SilphCo1F_Script:
	call EnableAutoTextBoxDrawing

; Polled state machine, not a fire-once-on-map-load script - the vanilla shape
; (OaksLab and friends run a per-map CurScript state every tick).
;
; wSilphCo1FCurScript is reused here at zero WRAM cost: it was left behind when
; the map's rogue-stage machinery was removed, and it lives at $d657, inside the
; wPlayerName..wBoxDataEnd span that PrepareOakSpeech zero-fills on a new game.
; It doubles as the warm-up counter below, then latches to $ff once the escort
; has been handed off so this never re-fires.
	ld a, [wSilphCo1FCurScript]
	cp $ff
	ret z ; escort already started

; Warm-up delay, purely so Palm is VISIBLE before he starts walking. A sprite
; needs at least two per-sprite update passes before it can be drawn: the first
; one (movement status 0) runs InitializeSpriteStatus, which sets IMAGEINDEX to
; $ff = invisible, and only a later pass through CheckSpriteAvailability turns
; it into a real image index. Handing off any earlier left him invisible until
; AnimScriptedNPCMovement happened to write one part-way through the walk.
; His POSITION is not what this is protecting - that is forced explicitly in
; SilphCoPalmMovementScript_WalkToDesk, because the escort's
; DoScriptedNPCMovement path is pure screen-pixel arithmetic and never derives
; a sprite's screen position from its map position at all.
	inc a
	ld [wSilphCo1FCurScript], a
	cp 8
	ret c ; still warming up

; Block movement only. hJoyIgnore masks hJoyPressed globally
; (engine/joypad.asm), and text waits on A/B out of that same masked byte, so
; PAD_BUTTONS here would softlock.
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a

	ld a, TEXT_SILPHCO1F_PROF_PALM
	ldh [hTextID], a
	call DisplayTextID

	ld a, $ff ; latch: escort handed off, never run this again
	ld [wSilphCo1FCurScript], a

; Hand off to the escort movement script. Saffron and Silph Co share pointer
; table 1 because both are one-shot intro escorts that can never overlap;
; Saffron starts at function 0, this one at function 3. Sharing avoids adding a
; 4th `dw` to .NPCMovementScriptPointerTables, which lives in HOME and has ZERO
; bytes of slack in the _DEBUG build.
	ld a, SILPHCO1F_PROF_PALM
	ldh [hActiveSpriteIndex], a
	ld a, $3
	ld [wNPCMovementScriptFunctionNum], a
	ld a, 1
	ld [wNPCMovementScriptPointerTableNum], a
; Must name the bank explicitly: this script and auto_movement.asm are in
; different banks, so the vanilla `ldh [hLoadedROMBank]` idiom would be wrong.
	ld a, BANK(SaffronPalmMovementScriptPointerTable)
	ld [wNPCMovementScriptBank], a
	ret

SilphCo1F_TextPointers:
	def_text_pointers
	dw_const SilphCo1FProfPalmText,          TEXT_SILPHCO1F_PROF_PALM
	dw_const SilphCo1FLinkReceptionistText,  TEXT_SILPHCO1F_LINK_RECEPTIONIST
	EXPORT TEXT_SILPHCO1F_PROF_PALM
	EXPORT TEXT_SILPHCO1F_LINK_RECEPTIONIST

SilphCo1FProfPalmText:
	text_far _SilphCo1FProfPalmText
	text_end

SilphCo1FLinkReceptionistText:
	text_far _SilphCo1FLinkReceptionistText
	text_end
