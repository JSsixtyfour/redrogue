; Bridge PC: see data/events/hidden_events.asm, hidden_events_for IGAS_DOJO
; (full note at the top of scripts/IgasDojo.asm).
	object_const_def
	const_export IGASDOJO_CUBONE
	const_export IGASDOJO_IGA

IgasDojo_Object:
	db $a ; border block

	; The door is the gap between the two bottom pillars in maps/IgasDojo.blk.
	; DOJO exits trigger by walking off the map edge (ExtraWarpCheck).
	def_warp_events
	warp_event  3,  7, LAST_MAP, 5
	warp_event  4,  7, LAST_MAP, 5

	def_bg_events

	def_object_events
	object_event  3,  5, SPRITE_CUBONE, STAY, UP, TEXT_IGASDOJO_CUBONE
	object_event  2,  4, SPRITE_KOGA, STAY, RIGHT, TEXT_IGASDOJO_IGA

	def_warps_to IGAS_DOJO
