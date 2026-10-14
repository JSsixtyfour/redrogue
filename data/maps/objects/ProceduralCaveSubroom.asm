ProceduralCaveSubroom_Object:
	db $3 ; border block, as Mt. Moon B1F, which the placeholder room is cut from

	def_warp_events
	; Its two ladders up. Each leads back to the cave ladder of the same index
	; (the cave arms both and patches these back at load, Phase 4 cave step 2);
	; the destinations here are placeholders until then.
	warp_event 13,  3, PROCEDURAL_CAVE_1, 1
	warp_event  5,  5, PROCEDURAL_CAVE_1, 1

	def_bg_events

	def_object_events

	def_warps_to PROCEDURAL_CAVE_SUBROOM
