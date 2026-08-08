SilphCoVR_Object:
	db $D ; border block
    const_export SILPHCOVR_PROF_PALM

	def_warp_events
	warp_event  2,  7, LAST_MAP, 1
	warp_event  3,  7, LAST_MAP, 1
	warp_event  3,  2, OAKS_LAB, 1

	def_bg_events

	def_object_events
    object_event  1,  5, SPRITE_SCIENTIST, STAY, UP, TEXT_SILPHCOVR_PROF_PALM

	def_warps_to SILPH_CO_VR
