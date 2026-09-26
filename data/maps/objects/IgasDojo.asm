; Bridge PC: see data/events/hidden_events.asm, hidden_events_for IGAS_DOJO
; (full note at the top of scripts/IgasDojo.asm).
	object_const_def
    const_export IGASDOJO_BOULDER
	const_export IGASDOJO_IGA
    const_export IGASDOJO_NIDORINO

IgasDojo_Object:
	db $3 ; border block

	; The door is the gap between the two bottom pillars in maps/IgasDojo.blk.
	; DOJO exits trigger by walking off the map edge (ExtraWarpCheck).
	def_warp_events
	warp_event  3,  7, LAST_MAP, 5
	warp_event  4,  7, LAST_MAP, 5

	def_bg_events

	def_object_events
	object_event  1,  4, SPRITE_BOULDER, STAY, NONE, TEXT_IGASDOJO_BOULDER
	object_event  4,  3, SPRITE_KOGA, STAY, DOWN, TEXT_IGASDOJO_IGA
    object_event  6,  5, SPRITE_NIDORINO, WALK, ANY_DIR, TEXT_IGASDOJO_NIDORINO

	def_warps_to IGAS_DOJO
