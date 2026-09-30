	object_const_def
	const_export ROUTE3_PADDING
	const_export ROUTE3_LASS
	const_export ROUTE3_YOUNGSTER1
	const_export ROUTE3_YOUNGSTER2
	const_export ROUTE3_JR_TRAINER_F
    const_export ROUTE3_POKE_BALL
    const_export ROUTE3_ROGUE_REWARD_POKEBALL_1
    const_export ROUTE3_ROGUE_REWARD_POKEBALL_2
    const_export ROUTE3_ROGUE_REWARD_POKEBALL_3
    const_export ROUTE3_ROGUE_TRADE_NPC
	const_export ROUTE3_SUPER_NERD

Route3_Object:
	db $2c ; border block

	def_warp_events
	warp_event  0,  9, WARP_NO_RETURN, 1
	warp_event  0, 10, WARP_NO_RETURN, 1
	warp_event 47, 12, INDIGO_PLATEAU_LOBBY, 1
	warp_event 30,  7, INDIGO_PLATEAU_LOBBY, 1

	def_bg_events
	bg_event 59,  9, TEXT_ROUTE3_SIGN

	def_object_events
	; Slot 1 is padding (4-battle stages, FOUR_TRAINER_REVISION_PLAN.md): the
	; three trainers and the boss sit in slots 2-5 so the boss stays in slot 5
	; (MiniBossStageSlots) and slots 6-10 keep the reward cluster. It stands
	; below the map, so CheckSpriteAvailability never draws it.
	object_event  0, 63, SPRITE_YOUNGSTER, STAY, DOWN, TEXT_ROUTE3_PADDING
	object_event 11,  4, SPRITE_COOLTRAINER_F, STAY, DOWN, TEXT_ROUTE3_LASS, OPP_LASS, 1
	object_event 18,  6, SPRITE_YOUNGSTER, STAY, LEFT, TEXT_ROUTE3_YOUNGSTER1, OPP_YOUNGSTER, 1
	object_event 23,  4, SPRITE_YOUNGSTER, STAY, DOWN, TEXT_ROUTE3_YOUNGSTER2, OPP_YOUNGSTER, 1
	; Boss reclassed BUG_CATCHER slot cut -> LASS (TRAINER_CUT_AUDIT.md)
	object_event 28,  8, SPRITE_COOLTRAINER_F, STAY, LEFT, TEXT_ROUTE3_JR_TRAINER_M, OPP_LASS, 1
	object_event  5,  8, SPRITE_POKE_BALL, STAY, NONE, TEXT_ROUTE3_RANDOM, 0
	object_event 29, 10, SPRITE_POKE_BALL, STAY, NONE, TEXT_ROUTE3_ROGUE_REWARD_POKEBALL_1
	object_event 31, 10, SPRITE_POKE_BALL, STAY, NONE, TEXT_ROUTE3_ROGUE_REWARD_POKEBALL_2
	object_event 33, 10, SPRITE_POKE_BALL, STAY, NONE, TEXT_ROUTE3_ROGUE_REWARD_POKEBALL_3
	object_event 29, 10, SPRITE_COOLTRAINER_M, STAY, DOWN, TEXT_ROUTE3_ROGUE_TRADE_NPC
	object_event 17, 12, SPRITE_SUPER_NERD, STAY, NONE, TEXT_ROUTE3_SUPER_NERD

	def_warps_to ROUTE_3
