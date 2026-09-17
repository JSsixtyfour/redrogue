SilphCoB1F_Object:
	db 46 ; border block (facility void/solid tile, matches ProceduralFacility's border)
	object_const_def
	const_export SILPHCOB1F_PROF_PALM

	def_warp_events
	warp_event 16,  0, SILPH_CO_1F, 1
	warp_event  2,  0, SILPH_CO_DORM, 2
	warp_event  3,  0, SILPH_CO_DORM, 1
	warp_event 11,  0, SILPH_CO_VR, 2
	warp_event 10,  0, SILPH_CO_VR, 1
	; Wild-area test entrance. Pointed at the CAVE 2026-09-16 (was
	; PROCEDURAL_FACILITY) for visual review of the river. Destination warp 1 is
	; the cave's hardcoded entrance at block (9,19); the cave's own warp 1 leads
	; back to LAST_MAP, which is this map. The matching half of this switch is
	; the SILPH_CO_B1F branch of ProcStageLoadDispatch
	; (custom_functions/procedural_stage_hooks.asm), which stages the run on
	; entry - change both together or the door stages one stage and enters another.
	warp_event  7,  0, PROCEDURAL_CAVE_1, 1
	warp_event  6,  0, PROCEDURAL_CAVE_1, 1

	def_bg_events
	bg_event 18, 0, TEXT_SILPHCOB1F_ELEVATOR

	def_object_events
	object_event 16, 1, SPRITE_SCIENTIST, STAY, DOWN, TEXT_SILPHCOB1F_SCIENTIST

	def_warps_to SILPH_CO_B1F
