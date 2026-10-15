	object_const_def
	const_export CAVESUB_GAMBLER
	const_export CAVESUB_SUPER_NERD
	const_export CAVESUB_BALL
	const_export CAVESUB_WATER_MON
	const_export CAVESUB_LAND_MON

ProceduralCaveSubroom_Object:
	db $3 ; border block: solid rock

	def_warp_events
	; One per distinct ladder tile over all the drawn rooms (CaveSubRooms in
	; custom_functions/cave_subroom.asm names each room's two by index). Every
	; load arms the rolled room's two back onto the cave's ladders A and B and
	; disarms the rest; the destinations here are only the ROM defaults.
	warp_event 19,  1, PROCEDURAL_CAVE_1, 1 ; 0: Lake, Mountains1
	warp_event  1,  3, PROCEDURAL_CAVE_1, 1 ; 1: Lake
	warp_event 11,  7, PROCEDURAL_CAVE_1, 1 ; 2: Lake2
	warp_event 25,  4, PROCEDURAL_CAVE_1, 1 ; 3: Lake2
	warp_event  3,  6, PROCEDURAL_CAVE_1, 1 ; 4: Mountains1

	def_bg_events

	def_object_events
	; Every object is moved to its room's spot at load (CaveSubroomLoad); the
	; tiles here are the Lake room's.
	; The resident, one per cave (CAVESUB_STATE), on one tile; talked to from
	; the floor below. The PokeManiac uses the Super Nerd's object.
	object_event 10,  3, SPRITE_GAMBLER, STAY, DOWN, TEXT_CAVESUB_GAMBLER
	object_event 10,  3, SPRITE_SUPER_NERD, STAY, DOWN, TEXT_CAVESUB_SUPER_NERD
	; The item ball, picked up from below. Its item is rolled when it is
	; picked up, as the cave's balls roll theirs.
	object_event  3,  0, SPRITE_POKE_BALL, STAY, NONE, TEXT_CAVESUB_BALL
	; Scenery where nobody can reach: a Pokemon on the lake and one on a
	; mountain, each rolled per cave (its picture is patched; none = 0).
	object_event 12,  8, SPRITE_LAPRAS, STAY, DOWN, TEXT_CAVESUB_WATER_MON
	object_event  4,  6, SPRITE_CLEFAIRY, STAY, DOWN, TEXT_CAVESUB_LAND_MON

	ASSERT CAVESUB_GAMBLER == CAVESUB_SLOT_GAMBLER
	ASSERT CAVESUB_SUPER_NERD == CAVESUB_SLOT_SUPER_NERD
	ASSERT CAVESUB_BALL == CAVESUB_SLOT_BALL
	ASSERT CAVESUB_WATER_MON == CAVESUB_SLOT_WATER_MON
	ASSERT CAVESUB_LAND_MON == CAVESUB_SLOT_LAND_MON

	def_warps_to PROCEDURAL_CAVE_SUBROOM
