ProceduralCemetary1_Object:
	db 1 ; border block (wall)

	def_warp_events
	; Map 1: enter left (3,9), exit right (18,9)
	warp_event  3,  9, LAST_MAP, 1
	warp_event 18,  9, PROCEDURAL_CEMETARY_2, 1

	def_bg_events

	def_object_events
	; pokeball (slot 1) - position runtime-patched by PCemGenerateMaps
	object_event 5, 5, SPRITE_POKE_BALL, STAY, NONE, TEXT_PROCEDURALCEMETARY1_POKEBALL, 0

	def_warps_to PROCEDURAL_CEMETARY_1
