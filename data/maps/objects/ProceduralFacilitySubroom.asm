	object_const_def
	const_export FACSUBROOM_SUPER_NERD

ProceduralFacilitySubroom_Object:
	db $2E ; border block: the Facility's black void

	def_warp_events
	; The landing spots (constants/facility_subroom_constants.asm, chosen by
	; tools/facility_subroom.py so every room piece has one). The pad block's pad
	; is its bottom-right quadrant. FacSubroomLoad stamps the pad on this
	; piece's landing and disarms the others; the player arrives on it from the
	; Facility and steps back onto it to leave. The destination is a placeholder
	; until the Facility side exists.
	ASSERT FACSUB_NUM_LANDINGS <= 32
	FOR n, FACSUB_NUM_LANDINGS
		warp_event 2 * FACSUB_LANDING_{d:n}_X + 1, 2 * FACSUB_LANDING_{d:n}_Y + 1, PROCEDURAL_FACILITY, 1
	ENDR

	def_bg_events

	def_object_events
	; Moved at load to the tile tools/facility_subroom.py proved for the rolled
	; piece (FacSubroomLoad); he is talked to from the tile below.
	object_event  5,  5, SPRITE_SUPER_NERD, STAY, DOWN, TEXT_FACSUBROOM_SUPER_NERD

	def_warps_to PROCEDURAL_FACILITY_SUBROOM
