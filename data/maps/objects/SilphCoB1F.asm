SilphCoB1F_Object:
	db 46 ; border block (facility void/solid tile, matches ProceduralFacility's border)
	object_const_def
	const_export SILPHCOB1F_SCIENTIST
	const_export SILPHCOB1F_PROF_PALM
	const_export SILPHCOB1F_LANCE
	const_export SILPHCOB1F_ROCKET

	def_warp_events
	warp_event 16,  0, SILPH_CO_1F, 1
	warp_event  2,  0, SILPH_CO_DORM, 2
	warp_event  3,  0, SILPH_CO_DORM, 1
	warp_event 11,  0, SILPH_CO_VR, 2
	warp_event 10,  0, SILPH_CO_VR, 1
	; Credit Exchange, restored 2026-09-28. From 2026-09-11 these two doors were
	; a wild-area test entrance (Facility, then the Cave) whose other half was a
	; SILPH_CO_B1F branch in ProcStageLoadDispatch; that branch was removed with
	; this restore. CreditExchange's own warps 1/2 return to ids 7/6 here.
	warp_event  7,  0, CREDIT_EXCHANGE, 2
	warp_event  6,  0, CREDIT_EXCHANGE, 1
	; Palm's locked back room. Appended so existing warp ids 1-7 remain stable.
	warp_event 20,  0, PALMS_ROOM, 1
	warp_event 21,  0, PALMS_ROOM, 2

	def_bg_events
	bg_event 18, 0, TEXT_SILPHCOB1F_ELEVATOR

	def_object_events
	object_event 16, 1, SPRITE_SCIENTIST, STAY, DOWN, TEXT_SILPHCOB1F_SCIENTIST
	object_event 16, 1, SPRITE_SCIENTIST, STAY, DOWN, TEXT_SILPHCOB1F_PROF_PALM
	object_event 16, 1, SPRITE_LANCE,     STAY, UP,   TEXT_SILPHCOB1F_LANCE
	object_event 16, 0, SPRITE_ROCKET,    STAY, DOWN, TEXT_SILPHCOB1F_ROCKET

	def_warps_to SILPH_CO_B1F
