SilphCoDorm_Object:
	db $a ; border block

	def_warp_events
	warp_event  5,  7, LAST_MAP, 1
	warp_event  4,  7, LAST_MAP, 1

	def_bg_events
	bg_event  0,  1, TEXT_SILPHCODORM_PC

	def_object_events
	; Exactly 8 decoration objects, declared FIRST so they occupy object
	; slots 1-8 (1-based). RoomPatchSprites (custom_functions/room_decor.asm)
	; overwrites PICTUREID and MAPY/MAPX for every slot at load time based on
	; sRoomFurniture/sRoomDecorSlots; the declared sprite/coords below are
	; placeholders only. Each slot has its OWN text id so the compile-time
	; def_warps_to assertion (object ids <= NUM_OBJECT_EVENTS) is satisfied;
	; every slot's text points at the same RoomDecorationText handler, which
	; tells slots apart at runtime via hActiveSpriteIndex (= this slot number).
	object_event  1,  6, SPRITE_MONSTER, STAY, DOWN, TEXT_SILPHCODORM_DECORATION_1 ; slot 0: bedside
	object_event  6,  7, SPRITE_MONSTER, STAY, DOWN, TEXT_SILPHCODORM_DECORATION_2 ; slot 1: bottom
	object_event  6,  1, SPRITE_MONSTER, STAY, DOWN, TEXT_SILPHCODORM_DECORATION_3 ; slot 2: top
	object_event  4,  4, SPRITE_MONSTER, STAY, DOWN, TEXT_SILPHCODORM_DECORATION_4 ; slot 3: middle #1
	object_event  5,  4, SPRITE_MONSTER, STAY, DOWN, TEXT_SILPHCODORM_DECORATION_5 ; slot 4: middle #2 (disabled by default furniture)
	object_event  5,  5, SPRITE_MONSTER, STAY, DOWN, TEXT_SILPHCODORM_DECORATION_6 ; slot 5: middle #3 (disabled by default furniture)
	object_event  1,  1, SPRITE_MONSTER, STAY, DOWN, TEXT_SILPHCODORM_DECORATION_7 ; slot 6: pc #1
	object_event  2,  0, SPRITE_MONSTER, STAY, DOWN, TEXT_SILPHCODORM_DECORATION_8 ; slot 7: pc #2 (disabled by default furniture)

	def_warps_to SILPH_CO_DORM
