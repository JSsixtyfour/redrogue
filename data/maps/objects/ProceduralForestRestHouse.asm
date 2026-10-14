	object_const_def
	; Every resident is toggleable and rolled once per forest (PROCEDURAL_SUBROOMS_PLAN
	; Phase 4). (6,6) holds EITHER the rental official or the healing clerk.
	const_export PFRESTHOUSE_RENTAL_OFFICIAL
	const_export PFRESTHOUSE_CLERK_HEALING
	const_export PFRESTHOUSE_CLERK_STOCK
	const_export PFRESTHOUSE_MOVE_TUTOR
	const_export PFRESTHOUSE_TRADER
	const_export PFRESTHOUSE_SALESMAN
	const_export PFRESTHOUSE_GAMBLER

ProceduralForestRestHouse_Object:
	db $a ; border block

	def_warp_events
	; The way back out. Its destination warp is the forest's house door, which
	; PFRestHouse patches at load to the door spot this forest used.
	warp_event  2,  7, PROCEDURAL_FOREST, 1
	warp_event  3,  7, PROCEDURAL_FOREST, 1

	def_bg_events

	def_object_events
	object_event  6,  6, SPRITE_LINK_RECEPTIONIST, STAY, LEFT, TEXT_PFRESTHOUSE_RENTAL_OFFICIAL
	object_event  6,  6, SPRITE_CLERK, STAY, LEFT, TEXT_PFRESTHOUSE_CLERK_HEALING
	object_event  6,  5, SPRITE_CLERK, STAY, UP, TEXT_PFRESTHOUSE_CLERK_STOCK
	object_event  3,  4, SPRITE_LOBBY_MOVE_TUTOR, STAY, DOWN, TEXT_PFRESTHOUSE_MOVE_TUTOR
	object_event  0,  2, SPRITE_SUPER_NERD, STAY, DOWN, TEXT_PFRESTHOUSE_TRADER
	object_event  1,  5, SPRITE_MIDDLE_AGED_MAN, WALK, ANY_DIR, TEXT_PFRESTHOUSE_SALESMAN
	object_event  5,  2, SPRITE_GAMBLER, STAY, DOWN, TEXT_PFRESTHOUSE_GAMBLER

	def_warps_to PROCEDURAL_FOREST_REST_HOUSE
