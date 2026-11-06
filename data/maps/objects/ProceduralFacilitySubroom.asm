	object_const_def
	const_export FACSUBROOM_SUPER_NERD
	const_export FACSUBROOM_BALL
	const_export FACSUBROOM_OPTIONAL_MON

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
	; Likewise moved onto the piece's ball tile. Its item is rolled when it is
	; picked up, the way the Facility's balls roll theirs.
	object_event  6,  5, SPRITE_POKE_BALL, STAY, NONE, TEXT_FACSUBROOM_BALL
	; The optional encounter's fallback, for a Facility with no block of its own for
	; it: moved to its proven tile (OptionalEncounterPlaceFacility), otherwise its
	; picture is patched to 0.
	object_event  7,  5, SPRITE_MONSTER, WALK, ANY_DIR, TEXT_FACSUBROOM_OPTIONAL, PSYDUCK, 1 | OW_POKEMON
	ASSERT FACSUBROOM_OPTIONAL_MON == 3 ; wSprite03, OptionalSpriteAddress

	def_warps_to PROCEDURAL_FACILITY_SUBROOM
