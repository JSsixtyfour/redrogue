object_const_def

ProceduralForest_Object:
	db 2 ; border block (tree)

	def_warp_events
	warp_event 19, 34, LAST_MAP, 1 ; entrance at cell (4,8) = block(9,17)
	warp_event  1,  0, LAST_MAP, 1 ; exit left tile  — runtime-patched to (4i+2, 0)
	warp_event  2,  0, LAST_MAP, 1 ; exit right tile — runtime-patched to (4i+3, 0)

	def_bg_events

	def_object_events
	; Item pokeball (placeholder, Phase 4 will place via carving)
	object_event 10, 10, SPRITE_POKE_BALL, STAY, NONE, 0, 0
	; Boss sprite (placeholder, Phase 4 will place)
	object_event 15, 15, SPRITE_MONSTER, STAY, DOWN, 0, VENUSAUR, 50 | OW_POKEMON

	def_warps_to PROCEDURAL_FOREST
