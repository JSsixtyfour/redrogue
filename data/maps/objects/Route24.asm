	object_const_def
	const_export ROUTE24_PADDING
	const_export ROUTE24_COOLTRAINER_M3
	const_export ROUTE24_YOUNGSTER1
	const_export ROUTE24_COOLTRAINER_F2
	const_export ROUTE24_YOUNGSTER2
    const_export ROUTE24_POKE_BALL
    const_export ROUTE24_ROGUE_REWARD_POKEBALL_1
    const_export ROUTE24_ROGUE_REWARD_POKEBALL_2
    const_export ROUTE24_ROGUE_REWARD_POKEBALL_3
    const_export ROUTE24_ROGUE_TRADE_NPC
    const_export ROUTE24_TM_THUNDER_WAVE
    const_export ROUTE24_COOLTRAINER_M1
	const_export ROUTE24_COOLTRAINER_M2

Route24_Object:
	db $2c ; border block

	def_warp_events
	warp_event $a, $1f, WARP_NO_RETURN, 1
	warp_event $b, $1f, WARP_NO_RETURN, 1
	warp_event $a, $3, INDIGO_PLATEAU_LOBBY, 1

	def_bg_events

	def_object_events
	; Slot 1 is padding (4-battle stages, FOUR_TRAINER_REVISION_PLAN.md): the
	; three trainers and the boss sit in slots 2-5 so the boss stays in slot 5
	; and slots 6-10 keep the reward cluster. It stands below the map, so
	; CheckSpriteAvailability never draws it.
	object_event  0, 63, SPRITE_COOLTRAINER_M, STAY, DOWN, TEXT_ROUTE24_PADDING
	object_event 11, 15, SPRITE_COOLTRAINER_M, STAY, LEFT, TEXT_ROUTE24_COOLTRAINER_M3, OPP_JR_TRAINER_M, 1
	object_event 11, 21, SPRITE_YOUNGSTER, STAY, LEFT, TEXT_ROUTE24_YOUNGSTER1, OPP_YOUNGSTER, 1
	object_event 10, 24, SPRITE_COOLTRAINER_F, STAY, RIGHT, TEXT_ROUTE24_COOLTRAINER_F2, OPP_LASS, 1
	object_event 11, 27, SPRITE_YOUNGSTER, STAY, LEFT, TEXT_ROUTE24_YOUNGSTER2, OPP_BUG_CATCHER, 1
	object_event 11, 29, SPRITE_POKE_BALL, STAY, NONE, TEXT_ROUTE24_RANDOM, 0
	object_event  5,  9, SPRITE_POKE_BALL, STAY, NONE, TEXT_ROUTE24_ROGUE_REWARD_POKEBALL_1
	object_event  7,  9, SPRITE_POKE_BALL, STAY, NONE, TEXT_ROUTE24_ROGUE_REWARD_POKEBALL_2
	object_event  9,  9, SPRITE_POKE_BALL, STAY, NONE, TEXT_ROUTE24_ROGUE_REWARD_POKEBALL_3
	object_event  5,  9, SPRITE_COOLTRAINER_M, STAY, DOWN, TEXT_ROUTE24_ROGUE_TRADE_NPC
	object_event 18,  5, SPRITE_POKE_BALL, STAY, NONE, TEXT_ROUTE24_TM_THUNDER_WAVE, TM_THUNDER_WAVE
	object_event 11, 12, SPRITE_COOLTRAINER_M, STAY, LEFT, TEXT_ROUTE24_COOLTRAINER_M1
	object_event  5, 20, SPRITE_COOLTRAINER_M, STAY, UP, TEXT_ROUTE24_COOLTRAINER_M2

	def_warps_to ROUTE_24
