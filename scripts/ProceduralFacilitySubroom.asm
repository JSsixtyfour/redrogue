; The Facility's subroom (PROCEDURAL_SUBROOMS_PLAN Phase 4), on the map id of
; the unreachable SAFARI_ZONE_EAST_REST_HOUSE. Reached only by the Facility's
; subroom pad; its own pad leads back. The room itself is one of the Facility
; generator's full-room pieces, rolled per Facility and stamped at every load
; (custom_functions/facility_subroom.asm).

ProceduralFacilitySubroom_Script:
	call EnableAutoTextBoxDrawing
	; The Super Nerd's battle, if one just ended: record a win and hand over
	; the prize (facility_subroom.asm).
	farcall FacSuperNerdSettle
	jr nc, .optional
	ld a, TEXT_FACSUBROOM_PRIZE
	ldh [hTextID], a
	call DisplayTextID
.optional
	farcall OptionalEncounterMapScript
	ret

ProceduralFacilitySubroom_TextPointers:
	def_text_pointers
	; Objects first, in slot order; script-only texts after them
	; (audit_map_text_id_slots.py).
	dw_const FacSubroomSuperNerdText, TEXT_FACSUBROOM_SUPER_NERD
	dw_const FacSubroomBallText,      TEXT_FACSUBROOM_BALL
	dw_const FacSubroomOptionalText,  TEXT_FACSUBROOM_OPTIONAL
	dw_const FacSubroomPrizeText,     TEXT_FACSUBROOM_PRIZE
	dw_const FacSubroomOptionalOffer, TEXT_FACSUBROOM_OPTIONAL_OFFER

FacSubroomOptionalText:
	text_far FGEncounterText
	text_end
FacSubroomOptionalOffer:
	text_far FGEncounterOffer
	text_end

FacSubroomSuperNerdText:
	text_asm
	push bc
	farcall FacSuperNerdTalk
	pop bc
	jp TextScriptEnd

FacSubroomBallText:
	text_asm
	push bc
	farcall FacSubroomPickUpBall
	pop bc
	jp TextScriptEnd

FacSubroomPrizeText:
	text_asm
	push bc
	farcall FacSuperNerdPrize
	pop bc
	jp TextScriptEnd
