	object_const_def
	const_export PALMSROOM_PROF_PALM
	const_export PALMSROOM_LANCE

PalmsRoom_Object:
	db $2E

	def_warp_events
	warp_event 4, 7, SILPH_CO_B1F, 8
	warp_event 5, 7, SILPH_CO_B1F, 9

	def_bg_events

	def_object_events
	object_event 6, 3, SPRITE_SCIENTIST, STAY, DOWN, TEXT_PALMSROOM_PALM
	object_event 6, 4, SPRITE_LANCE,     STAY, DOWN, TEXT_PALMSROOM_LANCE

	def_warps_to PALMS_ROOM
