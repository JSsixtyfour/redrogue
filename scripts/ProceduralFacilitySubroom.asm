; The Facility's subroom (PROCEDURAL_SUBROOMS_PLAN Phase 4), on the map id of
; the unreachable SAFARI_ZONE_EAST_REST_HOUSE. Reached only by the Facility's
; one-way pad; its own pad leads back. The room itself is one of the Facility
; generator's full-room pieces, rolled per Facility and stamped at every load
; (custom_functions/facility_subroom.asm).

ProceduralFacilitySubroom_Script:
	jp EnableAutoTextBoxDrawing

ProceduralFacilitySubroom_TextPointers:
	def_text_pointers
	dw_const FacSubroomSuperNerdText, TEXT_FACSUBROOM_SUPER_NERD

; Placeholder until his battle is wired in (Phase 4 step 3).
FacSubroomSuperNerdText:
	text "Placeholder."
	done
