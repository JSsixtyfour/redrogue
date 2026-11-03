object_const_def
	const_export ROGUE_REWARD_POKEBALL_1
    const_export ROGUE_REWARD_POKEBALL_2
    const_export ROGUE_REWARD_POKEBALL_3
    const_export ROGUE_STAGE_RANDOM_ITEM
    const_export ROGUE_TRADE_NPC
    const_export REWARDROOM_DOOR1_POSTER
    const_export REWARDROOM_DOOR2_POSTER

RewardRoom_Object:
	db $a ; border block, matching the other Gate interiors

	def_warp_events
	warp_event $5, $7, WARP_NO_RETURN, 2
	warp_event $5, $7, WARP_NO_RETURN, 3
	warp_event $3, $0, ROGUE_MAP, 1
	warp_event $7, $0, ROGUE_MAP, 2

	def_bg_events

	def_object_events
	object_event  2,  4, SPRITE_POKE_BALL, STAY, NONE, TEXT_ROGUE_REWARD_POKEBALL_1
	object_event  5,  4, SPRITE_POKE_BALL, STAY, NONE, TEXT_ROGUE_REWARD_POKEBALL_2
	object_event  8,  4, SPRITE_POKE_BALL, STAY, NONE, TEXT_ROGUE_REWARD_POKEBALL_3
	; The skipped route's item ball (TOGGLE_STAGE_RANDOM_ITEM): shown only on a
	; back-to-back pair's mid-run visit, beside the three Poke Balls.
	object_event  3,  1, SPRITE_POKE_BALL, STAY, NONE, TEXT_REWARDROOM_RANDOM_ITEM
	; A route's trade NPC (TOGGLE_ROGUE_TRADE_NPC): stands in for ball 1 while a
	; trade is up (RogueRefresh), so the two never show on the tile together.
	object_event  2,  4, SPRITE_COOLTRAINER_M, STAY, DOWN, TEXT_REWARDROOM_TRADE_NPC
	; The original lobby posters, after the five toggleable reward objects.
	object_event  2,  0, SPRITE_CLIPBOARD, STAY, NONE, TEXT_REWARDROOM_DOOR1_SIGN
	object_event  8,  0, SPRITE_CLIPBOARD, STAY, NONE, TEXT_REWARDROOM_DOOR2_SIGN

	def_warps_to REWARD_ROOM
