	object_const_def
	const_export CAVESUB_GAMBLER
	const_export CAVESUB_SUPER_NERD
	const_export CAVESUB_BALL

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
	; The resident, one of the two per cave (BIT_CAVESUB_SUPER_NERD), on the
	; same tile; talked to from the floor below.
	object_event  9,  2, SPRITE_GAMBLER, STAY, DOWN, TEXT_CAVESUB_GAMBLER
	object_event  9,  2, SPRITE_SUPER_NERD, STAY, DOWN, TEXT_CAVESUB_SUPER_NERD
	; The item ball, in the room's top-left corner (open floor all round). Its
	; item is rolled when it is picked up, as the cave's balls roll theirs.
	object_event  2,  2, SPRITE_POKE_BALL, STAY, NONE, TEXT_CAVESUB_BALL

	def_warps_to PROCEDURAL_CAVE_SUBROOM
