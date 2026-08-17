SilphCoB1F_Object:
	db 46 ; border block (facility void/solid tile, matches ProceduralFacility's border)
	object_const_def
	const_export SILPHCOB1F_PROF_PALM

	def_warp_events
	warp_event 16,  0, SILPH_CO_1F, 1
	warp_event  2,  0, SILPH_CO_DORM, 1
	warp_event  3,  0, SILPH_CO_DORM, 1
	warp_event 11,  0, SILPH_CO_VR, 2
	warp_event 10,  0, SILPH_CO_VR, 1
	warp_event  7,  0, CREDIT_EXCHANGE, 1
	warp_event  6,  0, CREDIT_EXCHANGE, 1

	def_bg_events
	bg_event 18, 0, TEXT_SILPHCOB1F_ELEVATOR

	def_object_events
	object_event 16, 1, SPRITE_SCIENTIST, STAY, DOWN, TEXT_SILPHCOB1F_SCIENTIST

	def_warps_to SILPH_CO_B1F
