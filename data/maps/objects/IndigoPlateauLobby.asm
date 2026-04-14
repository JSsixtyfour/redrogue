	object_const_def
	const_export INDIGOPLATEAULOBBY_NURSE
	const_export INDIGOPLATEAULOBBY_GYM_GUIDE
	const_export INDIGOPLATEAULOBBY_COOLTRAINER_F
	const_export INDIGOPLATEAULOBBY_CLERK
	const_export INDIGOPLATEAULOBBY_LINK_RECEPTIONIST

IndigoPlateauLobby_Object:
	db $0 ; border block

	def_warp_events
	warp_event  7, 11, LAST_MAP, 1
	warp_event  8, 11, LAST_MAP, 2
	warp_event  8,  0, LORELEIS_ROOM, 1

	def_bg_events

	def_object_events
	;object_event  7,  5, SPRITE_NURSE, STAY, DOWN, TEXT_INDIGOPLATEAULOBBY_NURSE
	;object_event  6,  1, SPRITE_YOUNGSTER, STAY, RIGHT, TEXT_INDIGOPLATEAULOBBY_GYM_GUIDE       ; psychic "predicts" typing of next gym
	;object_event 11, 10, SPRITE_CHANNELER, STAY, DOWN, TEXT_INDIGOPLATEAULOBBY_COOLTRAINER_F    ; issues mystical challenges that provide rewards
	;object_event  0,  5, SPRITE_CLERK, STAY, RIGHT, TEXT_INDIGOPLATEAULOBBY_CLERK               ; Sells Recovery Items
	;object_event  0,  7, SPRITE_CLERK, STAY, RIGHT, TEXT_INDIGOPLATEAULOBBY_CLERK               ; Sells evolutionary items, TMs, stat boosters
	;object_event  2, 10, SPRITE_MIDDLE_AGED_MAN, WALK, LEFT_RIGHT, TEXT_MTMOONPOKECENTER_MAGIKARP_SALESMAN ; sells a random pokemon to trainer
	;object_event  5, 11, SPRITE_SUPER_NERD, STAY, DOWN, TEXT_CINNABARLABTRADEROOM_SUPER_NERD    ; trades a random pokemon of the same rarity as a pokemon you currently have
	;object_event 14,  5, SPRITE_SILPH_PRESIDENT, STAY, LEFT, TEXT_NAMERATERSHOUSE_NAME_RATER    ; Move Tutor/Relearner
	;object_event 10,  5, SPRITE_GENTLEMAN, STAY, DOWN, TEXT_DAYCARE_GENTLEMAN                   ; takes one pokemon that will be raised to the level of most recent reward pokemon
	;object_event 12,  5, SPRITE_GRANNY, STAY, DOWN, TEXT_DAYCARE_GENTLEMAN                      ; takes one pokemon that will be raised to the level of most recent reward pokemon

	def_warps_to INDIGO_PLATEAU_LOBBY
