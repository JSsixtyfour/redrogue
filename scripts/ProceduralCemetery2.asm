; Cemetery floor 2. One of the three floors that can hold the villain's
; hideout (floor 1 is the arrival floor and is excluded from the roll), so
; this file runs the RECOVERY and never the arrival. Every shared label below
; is defined in scripts/ProceduralCemetery1.asm - all four cemetery scripts
; assemble into maps.asm's "Maps 6" section, so these are same-bank pointers.

ProceduralCemetery2_Script:
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .afterSetup
	SetEvent EVENT_ENTER_ROOM
	call PCemStageEnterSetup
.afterSetup
	call PCemCalmedCheck
	ld d, TEXT_PROCEDURALCEMETERY2_STAGE_RECOVER
	call PCemStageEventRecoverCheck
	jp PCemStageRunScripts

ProceduralCemetery2_TextPointers:
	def_text_pointers
	; ORDER IS LOAD-BEARING: see scripts/ProceduralCave1.asm's copy of this
	; note. The first wNumSprites entries must be the objects' own text, in
	; slot order, or DisplayTextID's .spriteHandling branch reroutes any
	; script-fired constant whose value is <= the object count. Measured here
	; before the reorder: CALMED printed the stage NPC's line.
	dw_const RandomPickUpItemText, TEXT_PROCEDURALCEMETERY2_POKEBALL
	dw_const PCemStageEventNpc1Text, TEXT_PROCEDURALCEMETERY2_STAGE_NPC_1
	dw_const PCemStageEventNpc2Text, TEXT_PROCEDURALCEMETERY2_STAGE_NPC_2
	; --- end of the object block (3 objects); script-only ids follow ---
	dw_const PCemCalmedText, TEXT_PROCEDURALCEMETERY2_CALMED
	dw_const PCemStageEventArrivalText, TEXT_PROCEDURALCEMETERY2_STAGE_EVENT
	dw_const PCemStageEventRecoverText, TEXT_PROCEDURALCEMETERY2_STAGE_RECOVER
