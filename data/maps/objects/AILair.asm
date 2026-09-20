	object_const_def
	const_export AILAIR_OPPONENT

AILair_Object:
	db $e ; border block, matching Colosseum

	def_warp_events

	def_bg_events

	def_object_events
	object_event 6, 4, SPRITE_RED, STAY, LEFT, TEXT_AILAIR_OPPONENT

	def_warps_to AI_LAIR
