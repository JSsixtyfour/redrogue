object_const_def
	const_export MINISAFFRON_PROF_PALM

MiniSaffron_Object:
	db $0 ; border block

	def_warp_events
	warp_event 12,  9, SILPH_CO_1F, 1
	warp_event 12, 11, WARP_NO_RETURN, 1

	def_bg_events

	def_object_events
	object_event 12, 10, SPRITE_SCIENTIST, STAY, DOWN, TEXT_MINISAFFRON_PROF_PALM

	def_warps_to MINI_SAFFRON
