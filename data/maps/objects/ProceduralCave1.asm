ProceduralCave1_Object:
	db 46 ; border block (solid_wall, confirmed impassable in both classification passes)

	def_warp_events
	warp_event 19, 38, LAST_MAP, 1 ; tile coords = block (9,19), matches generator's hardcoded entrance
	warp_event 15, 15, LAST_MAP, 1

	def_bg_events

	def_object_events

	def_warps_to PROCEDURAL_CAVE_1
