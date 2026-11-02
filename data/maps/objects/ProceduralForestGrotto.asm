	object_const_def
	const FOREST_GROTTO_POKEMON

ProceduralForestGrotto_Object:
	db 2 ; tree border
	def_warp_events
	; Parent N -> grove S; parent W -> grove E; parent E -> grove W.
	; FGLoadGrotto arms only the selected pair, including on Continue.
	warp_event  6, 11, PROCEDURAL_FOREST, 32
	warp_event  7, 11, PROCEDURAL_FOREST, FOREST_GROTTO_SECOND_WARP + 1
	warp_event 13,  6, PROCEDURAL_FOREST, 32
	warp_event 13,  7, PROCEDURAL_FOREST, FOREST_GROTTO_SECOND_WARP + 1
	warp_event  0,  6, PROCEDURAL_FOREST, 32
	warp_event  0,  7, PROCEDURAL_FOREST, FOREST_GROTTO_SECOND_WARP + 1
	def_bg_events
	def_object_events
	object_event 6, 5, SPRITE_MONSTER, STAY, DOWN, TEXT_PROCEDURALFORESTGROTTO_POKEMON, BUTTERFREE, 1 | OW_POKEMON
	def_warps_to PROCEDURAL_FOREST_GROTTO
