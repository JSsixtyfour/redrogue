ProceduralCemetery2_Object:
	db 1 ; border block (wall)

	def_warp_events
	; Map 2: enter right (18,9), exit left (3,9)
	warp_event 18,  9, PROCEDURAL_CEMETERY_1, 2
	warp_event  3,  9, PROCEDURAL_CEMETERY_3, 1

	def_bg_events

	def_object_events
	object_event 5, 5, SPRITE_POKE_BALL, STAY, NONE, TEXT_PROCEDURALCEMETERY2_POKEBALL, 0

	; Slots 2-3: stage-event NPC pair (Phase 7 rollout). Sprite, position and
	; trainer class are ALL runtime-patched (StageEventStageSprites,
	; PCemPlaceStageEventNpcs, StageEventApplyTrainers) before either slot can
	; be seen or engaged; only the 8-arg TRAINER shape has to be right here.
	object_event 5, 5, SPRITE_JESSIE, STAY, DOWN, TEXT_PROCEDURALCEMETERY2_STAGE_NPC_1, OPP_JESSIE_JAMES, 1
	object_event 6, 5, SPRITE_JAMES, STAY, DOWN, TEXT_PROCEDURALCEMETERY2_STAGE_NPC_2, OPP_JESSIE_JAMES, 1

	def_warps_to PROCEDURAL_CEMETERY_2
