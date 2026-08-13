	object_const_def
	const_export SILPHCO1F_PROF_PALM
	const_export SILPHCO1F_LINK_RECEPTIONIST

SilphCo1F_Object:
	db $2e ; border block

	def_warp_events
; Warps 1-3 keep their indices: SilphCoB1F enters via index 1 and SilphCo2F via
; index 3, so these must not be reordered or removed.
	warp_event 10, 17, LAST_MAP, 6
	warp_event 11, 17, LAST_MAP, 6
	warp_event 12, 17, INDIGO_PLATEAU_LOBBY, 1
; Warp 4, appended: the stairs the escort ends on.
	warp_event 24,  0, SILPH_CO_B1F, 1

	def_bg_events

	def_object_events
	object_event 10, 16, SPRITE_SCIENTIST, STAY, DOWN, TEXT_SILPHCO1F_PROF_PALM
	object_event  4,  2, SPRITE_LINK_RECEPTIONIST, STAY, DOWN, TEXT_SILPHCO1F_LINK_RECEPTIONIST

	def_warps_to SILPH_CO_1F
