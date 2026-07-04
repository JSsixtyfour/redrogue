ProceduralCemetary4_Object:
	db 1 ; border block (wall)

	def_warp_events
	; Map 4: enter right (18,9), exit south (9,16)
	warp_event 18,  9, PROCEDURAL_CEMETARY_3, 2
	warp_event  9, 16, LAST_MAP, 1

	def_bg_events

	def_object_events
	object_event 5, 5, SPRITE_POKE_BALL, STAY, NONE, TEXT_PROCEDURALCEMETARY4_POKEBALL, 0

	def_warps_to PROCEDURAL_CEMETARY_4
