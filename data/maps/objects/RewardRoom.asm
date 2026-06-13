object_const_def
	const_export ROGUE_REWARD_POKEBALL_1
    const_export ROGUE_REWARD_POKEBALL_2
    const_export ROGUE_REWARD_POKEBALL_3
    const_export ROGUE_STAGE_RANDOM_ITEM

RewardRoom_Object:
	db $F ; border block

	def_warp_events
	warp_event $8, $7, LAST_MAP, 2
	warp_event $8, $7, LAST_MAP, 3
	warp_event $6, $1, ROGUE_MAP, 1
	warp_event $A, $1, ROGUE_MAP, 2

	def_bg_events

	def_object_events
	object_event  5,  5, SPRITE_POKE_BALL, STAY, NONE, TEXT_ROGUE_REWARD_POKEBALL_1
	object_event  8,  5, SPRITE_POKE_BALL, STAY, NONE, TEXT_ROGUE_REWARD_POKEBALL_2
	object_event 11,  5, SPRITE_POKE_BALL, STAY, NONE, TEXT_ROGUE_REWARD_POKEBALL_3
	object_event  5,  1, SPRITE_CLIPBOARD, STAY, NONE, TEXT_REWARDROOM_DOOR1_SIGN   ; sign for door 1 (route 1)
	object_event  9,  1, SPRITE_CLIPBOARD, STAY, NONE, TEXT_REWARDROOM_DOOR2_SIGN   ; sign for door 2 (route 2)

	def_warps_to REWARD_ROOM
