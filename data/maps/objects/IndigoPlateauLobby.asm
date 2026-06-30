	object_const_def
	const_export PC_NURSE
	; PC_CLERK1 through PC_MOVE_TUTOR follow (must not reorder)
	; DOOR1_SIGN and DOOR2_SIGN added at end
    const_export PC_CLERK1
    const_export PC_CLERK2
    const_export PC_DAYCAREMAN
    const_export PC_DAYCAREWOMAN
    const_export PC_MOVERELEARNER
	const_export PC_PSYCHIC
	const_export PC_WITCH
	const_export PC_POKESALESMAN
    const_export PC_TRADENERD
    const_export PC_MOVETUTOR
    const_export PC_DOOR2_SIGN


IndigoPlateauLobby_Object:
	db $0 ; border block

	def_warp_events
	warp_event  7, 11, LAST_MAP, 1
	warp_event  8, 11, LAST_MAP, 2
	warp_event  8,  0, ROGUE_MAP, 1
    warp_event  10,  0, ROGUE_MAP, 1

	def_bg_events

	def_object_events
	object_event  7,  5, SPRITE_NURSE, STAY, DOWN, TEXT_PC_NURSE
	object_event  0,  5, SPRITE_CLERK, STAY, RIGHT, TEXT_PC_CLERK1                              ; Sells Recovery Items
	object_event  0,  7, SPRITE_CLERK, STAY, RIGHT, TEXT_PC_CLERK2                              ; Sells evolutionary items, TMs, stat boosters
	object_event 10,  5, SPRITE_GENTLEMAN, STAY, DOWN, TEXT_PC_DAYCARE_GENTLEMAN                ; takes one pokemon that will be raised to the level of most recent reward pokemon
	object_event 12,  5, SPRITE_GRANNY, STAY, DOWN, TEXT_PC_DAYCARE_LADY                        ; takes one pokemon that will be raised to the level of most recent reward pokemon
	object_event 14,  5, SPRITE_SILPH_PRESIDENT, STAY, DOWN, TEXT_PC_MOVE_RELEARNER             ; Move Relearner
	object_event  6,  1, SPRITE_YOUNGSTER, STAY, DOWN, TEXT_PC_PSYCHIC                          ; psychic "predicts" typing of next gym
	object_event 11, 10, SPRITE_CHANNELER, STAY, LEFT, TEXT_PC_WITCH                            ; issues mystical challenges that provide rewards
	object_event  2, 10, SPRITE_MIDDLE_AGED_MAN, WALK, LEFT_RIGHT, TEXT_PC_POKEMON_SALESMAN     ; sells a random pokemon to trainer
	object_event  5, 11, SPRITE_SUPER_NERD, STAY, UP, TEXT_PC_TRADER_SUPER_NERD                 ; trades a random pokemon of the same rarity as a pokemon you currently have
	object_event  4,  1, SPRITE_GAMEBOY_KID, STAY, DOWN, TEXT_PC_MOVE_TUTOR                     ; Move Tutor (Stadium, Special Nintendo Events, Tradebacks)
	object_event  7,  0, SPRITE_CLIPBOARD, STAY, NONE, TEXT_PC_DOOR1_SIGN                       ; sign for door 1 (route stage)
	object_event  9,  0, SPRITE_CLIPBOARD, STAY, NONE, TEXT_PC_DOOR2_SIGN                       ; sign for door 2 (gym stage)

	def_warps_to INDIGO_PLATEAU_LOBBY
