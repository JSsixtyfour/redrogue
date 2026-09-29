	object_const_def
	const_export FIGHTINGDOJO_KARATE_MASTER
	const_export FIGHTINGDOJO_BLACKBELT1
	const_export FIGHTINGDOJO_BLACKBELT2
	const_export FIGHTINGDOJO_BLACKBELT3
	const_export FIGHTINGDOJO_BLACKBELT4
	const_export FIGHTINGDOJO_RANDOM_ITEM

FightingDojo_Object:
	db $3 ; border block

	; Karate Master mini-boss stage. The lobby's ROGUE_MAP door lands on warp 0,
	; and the same door is the exit: FightingDojoGateScript points it at the
	; lobby once the master is beaten.
	def_warp_events
	warp_event  4, 11, WARP_NO_RETURN, 1
	warp_event  5, 11, WARP_NO_RETURN, 1

	def_bg_events

	def_object_events
	; slot 1 is patched to OPP_KARATE_MINIBOSS by MiniBossApplyStageTrainer
	object_event  5,  3, SPRITE_HIKER, STAY, DOWN, TEXT_FIGHTINGDOJO_KARATE_MASTER, OPP_BLACKBELT, 1
	object_event  3,  4, SPRITE_HIKER, STAY, RIGHT, TEXT_FIGHTINGDOJO_BLACKBELT1, OPP_BLACKBELT, 2
	object_event  3,  6, SPRITE_HIKER, STAY, RIGHT, TEXT_FIGHTINGDOJO_BLACKBELT2, OPP_BLACKBELT, 3
	object_event  5,  5, SPRITE_HIKER, STAY, LEFT, TEXT_FIGHTINGDOJO_BLACKBELT3, OPP_BLACKBELT, 4
	object_event  5,  7, SPRITE_HIKER, STAY, LEFT, TEXT_FIGHTINGDOJO_BLACKBELT4, OPP_BLACKBELT, 5
	object_event  4,  1, SPRITE_POKE_BALL, STAY, NONE, TEXT_FIGHTINGDOJO_RANDOM_ITEM

	def_warps_to FIGHTING_DOJO
