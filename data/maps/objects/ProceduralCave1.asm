object_const_def
    const_export WILD_AREA_BOSS ; = 1 (first object_event = sprite slot 1)

ProceduralCave1_Object:
	db 46 ; border block (solid_wall, confirmed impassable in both classification passes)

	def_warp_events
	warp_event 19, 38, LAST_MAP, 1 ; tile coords = block (9,19), matches generator's hardcoded entrance
	warp_event 15, 15, LAST_MAP, 1 ; exit (runtime-patched position)
	; EXPERIMENT (tabled): random entrance — see size-randomization-notes.md for findings.
	; Confirmed warp_event format: (tile_X, tile_Y) where tile_X=block_X*2+1, tile_Y=block_Y*2.
	; Bottom confirmed: block(9,19)→warp_event(19,38). Left block(1,9)→(3,18), Right block(18,9)→(37,18).
	; Top view ptr falls below PC_BASE. Left/right spawn in fill — not yet solved.

	def_bg_events
	bg_event 19, 35, TEXT_PROCEDURALCAVE1_SIGN

	def_object_events
	; Boss pokemon first (slot 1) so toggle-table lookup via hActiveSpriteIndex
	; hits slot 1 after battle and HideObject works correctly via EndTrainerBattle.
	; Species (PINSIR) and level below are placeholders patched at runtime by
	; PCPlaceBoss (custom_functions/procedural_cave_gen.asm) via wMapSpriteExtraData.
	; Position is also runtime-patched to the exit ladder in PCFinalizeCave.
	; SPRITE_MONSTER is the most common follower-sprite category (~60% of all species).
	; Dynamic per-species sprite loading requires the follower branch's LoadFollowerSprite
	; to force-write tiles into the boss's VRAM slot - deferred until that branch merges.
	object_event 18, 38, SPRITE_MONSTER, STAY, DOWN, TEXT_PROCEDURALCAVE1_BOSS, PINSIR, 5 | OW_POKEMON

	; 4 wild area pokeballs (slots 2-5) - random item per dead-end target.
	; Position runtime-patched by PCPlaceWildAreaItems via wSprite0{N}StateData2MapY/MapX.
	; Standard toggle mechanism (toggleable_objects_for table) handles visibility.
	object_event 10, 10, SPRITE_POKE_BALL, STAY, NONE, TEXT_PROCEDURALCAVE1_WILD_AREA_POKEBALL_1, 0
	object_event 10, 10, SPRITE_POKE_BALL, STAY, NONE, TEXT_PROCEDURALCAVE1_WILD_AREA_POKEBALL_2, 0
	object_event 10, 10, SPRITE_POKE_BALL, STAY, NONE, TEXT_PROCEDURALCAVE1_WILD_AREA_POKEBALL_3, 0
	object_event 10, 10, SPRITE_POKE_BALL, STAY, NONE, TEXT_PROCEDURALCAVE1_WILD_AREA_POKEBALL_4, 0

	; Stage-event NPC slots (6-7), Phase 7b. Both are placeholders in every
	; respect: position is runtime-patched (in front of the player, then the
	; hideout) and the sprite is repointed by ProcBossPatchStageSprite from
	; sStageEventSprite6/7 in the window between LoadMapHeader and
	; InitMapSprites, the same load-bearing ordering the boss sprite uses.
	;
	; WHEN NO EVENT IS ARMED these slots cost nothing at all, not merely
	; nothing visible: the sprite patch writes PICTUREID = 0, and
	; LoadMapSpriteTilePatterns' `and a / jp z, .nextSpriteSlot` treats a zero
	; picture ID as an unused slot, so no VRAM tile pattern slot is allocated
	; for them. That is why a 12-tile walking sprite is a safe declared
	; default here - it is never the sprite that actually loads.
	;
	; SPRITE_JESSIE/SPRITE_JAMES are the declared placeholders because they are
	; on no map at all today, so nothing else can be affected by the choice.
	; Procedural maps are indoor (>= FIRST_INDOOR_MAP), so InitMapSprites loads
	; tiles per object from this list and the outdoor sprite-set bound that
	; restricts which SPRITE_* a route may use does not apply.
	; DECLARED AS TRAINERS (8 args), not items. The arg count is what selects
	; the branch in the object_event macro: 7 args emits `db ITEM | textid`,
	; 8 emits `db TRAINER | textid` plus a class and a team number. These were
	; briefly written with 7 args, which silently made them ITEM objects with
	; item id 0 - they would have run the pickup path instead of a battle.
	; The class and team here are placeholders, patched at finalize by
	; StageEventApplyTrainers from the rolled event type; only the TRAINER flag
	; itself has to be right at build time.
	object_event 10, 10, SPRITE_JESSIE, STAY, DOWN, TEXT_PROCEDURALCAVE1_STAGE_NPC_1, OPP_JESSIE_JAMES, 1
	object_event 10, 10, SPRITE_JAMES, STAY, DOWN, TEXT_PROCEDURALCAVE1_STAGE_NPC_2, OPP_JESSIE_JAMES, 1

	def_warps_to PROCEDURAL_CAVE_1
