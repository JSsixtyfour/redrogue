	object_const_def
	const_export FOREST_BOSS            ; = 1, first object_event, slot used for boss

ProceduralForest_Object:
	db 2 ; border block (tree)

	def_warp_events
	warp_event 19, 34, LAST_MAP, 1 ; entrance at cell (4,8) = block(9,17)
	warp_event  1,  0, LAST_MAP, 1 ; exit left tile  — runtime-patched to (4i+2, 0)
	warp_event  2,  0, LAST_MAP, 1 ; exit right tile — runtime-patched to (4i+3, 0)

	def_bg_events
	bg_event 18, 33, TEXT_PROCEDURALFOREST_SIGN ; x,y runtime-patched in PFinalizeForest per placed block (21 vs 22)

	def_object_events
	; Slot 1: boss — a plain blocking NPC. Its overworld sprite is patched at
	; load (sProcForestBossSprite → PICTUREID), its position via wSprite01, and
	; the battle is driven by wCurOpponent in the script (cemetery-4 style), so
	; it needs NO OW_POKEMON/species data on the object itself.
	object_event  2,  2, SPRITE_MONSTER, STAY, DOWN, TEXT_PROCEDURALFOREST_BOSS, PINSIR, 5 | OW_POKEMON
	; Slots 2-5: 4 pokeballs — positions runtime-patched via wSprite01+16*(slot)
	object_event 10, 10, SPRITE_POKE_BALL, STAY, NONE, TEXT_PROCEDURALFOREST_POKEBALL_1, 0
	object_event 10, 10, SPRITE_POKE_BALL, STAY, NONE, TEXT_PROCEDURALFOREST_POKEBALL_2, 0
	object_event 10, 10, SPRITE_POKE_BALL, STAY, NONE, TEXT_PROCEDURALFOREST_POKEBALL_3, 0
	object_event 10, 10, SPRITE_POKE_BALL, STAY, NONE, TEXT_PROCEDURALFOREST_POKEBALL_4, 0

	; Slots 6-7: stage-event NPC pair (Phase 7 rollout), same shape as the
	; cave's own slots 6-7. Placeholder sprite/position/class - all four are
	; runtime-patched (StageEventStageSprites, PFPlaceStageEventNpcs,
	; StageEventApplyTrainers) before either slot can ever be seen or engaged.
	; The TRAINER flag (from declaring 8 args, not 7) is what has to be right at
	; build time - talking to an object declared as an ITEM would run the
	; pickup path, never a battle.
	object_event 10, 10, SPRITE_JESSIE, STAY, DOWN, TEXT_PROCEDURALFOREST_STAGE_NPC_1, OPP_JESSIE_JAMES, 1
	object_event 10, 10, SPRITE_JAMES, STAY, DOWN, TEXT_PROCEDURALFOREST_STAGE_NPC_2, OPP_JESSIE_JAMES, 1

	def_warps_to PROCEDURAL_FOREST
