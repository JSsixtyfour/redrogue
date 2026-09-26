; Bridge PC: see data/events/hidden_events.asm, hidden_events_for REDS_HOUSE_1F
; (full note at the top of scripts/RedsHouse1F.asm).
	object_const_def
	const_export REDSHOUSE1F_MOM

RedsHouse1F_Object:
	db $a ; border block

	def_warp_events
	warp_event  2,  7, LAST_MAP, 1
	warp_event  3,  7, LAST_MAP, 1

	def_bg_events
	bg_event  5,  1, TEXT_REDSHOUSE1F_TV

	def_object_events
	object_event  5,  4, SPRITE_MOM, STAY, LEFT, TEXT_REDSHOUSE1F_MOM

	def_warps_to REDS_HOUSE_1F
