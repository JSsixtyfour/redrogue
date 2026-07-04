ProceduralCemetary3_Object:
	db 1 ; border block (wall)

	def_warp_events
	; Map 3: enter left (3,9), exit right (18,9)
	warp_event  3,  9, PROCEDURAL_CEMETARY_2, 2
	warp_event 18,  9, PROCEDURAL_CEMETARY_4, 1

	def_bg_events

	def_object_events
	object_event 5, 5, SPRITE_POKE_BALL, STAY, NONE, TEXT_PROCEDURALCEMETARY3_POKEBALL, 0

	def_warps_to PROCEDURAL_CEMETARY_3
