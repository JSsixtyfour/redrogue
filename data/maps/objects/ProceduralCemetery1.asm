ProceduralCemetery1_Object:
	db 1 ; border block (wall)

	def_warp_events
	; Map 1: enter left (3,9), exit right (18,9)
	warp_event  3,  9, LAST_MAP, 1
	warp_event 18,  9, PROCEDURAL_CEMETERY_2, 1

	def_bg_events

	def_object_events
	; pokeball (slot 1) - position runtime-patched by PCemGenerateMaps
	object_event 5, 5, SPRITE_POKE_BALL, STAY, NONE, TEXT_PROCEDURALCEMETERY1_POKEBALL, 0

	; Slots 2-3: stage-event NPC pair (Phase 7 rollout). Sprite, position and
	; trainer class are ALL runtime-patched (StageEventStageSprites,
	; PCemPlaceStageEventNpcs, StageEventApplyTrainers) before either slot can
	; be seen or engaged; only the 8-arg TRAINER shape has to be right here.
	object_event 5, 5, SPRITE_JESSIE, STAY, DOWN, TEXT_PROCEDURALCEMETERY1_STAGE_NPC_1, OPP_JESSIE_JAMES, 1
	object_event 6, 5, SPRITE_JAMES, STAY, DOWN, TEXT_PROCEDURALCEMETERY1_STAGE_NPC_2, OPP_JESSIE_JAMES, 1

	; The possessed Channeler (custom_functions/cemetery_channeler.asm): on one
	; random floor per Cemetery; moved, shown and given his picture there only.
	object_event 5, 5, SPRITE_CHANNELER, STAY, DOWN, TEXT_PROCEDURALCEMETERY1_CHANNELER
	ASSERT CEMETERY_1_CHANNELER == 4 ; the fourth object_event

	; The resurrection NPC (custom_functions/cemetery_resurrector.asm): on one
	; floor of 60% of Cemeteries; given her picture and cell there only.
	object_event 5, 5, SPRITE_GRANNY, STAY, DOWN, TEXT_PROCEDURALCEMETERY1_RESURRECTOR
	ASSERT CEMETERY_RESURRECTOR == 5 ; the fifth object_event
	; The generic route trainer (custom_functions/forest_generic_trainer.asm,
	; GENERIC_TRAINER_ALL_AREAS_SPEC.md): one per Cemetery, on one floor; picture
	; 0 and parked on the others. 8 args: a trainer. The class is a placeholder.
	object_event 5, 5, SPRITE_CHANNELER, STAY, DOWN, TEXT_PROCEDURALCEMETERY1_GENERIC, OPP_CHANNELER, 1
	ASSERT CEMETERY_GENERIC == 6 ; the sixth object_event

	def_warps_to PROCEDURAL_CEMETERY_1
