; Bridge PC: see data/events/hidden_events.asm, hidden_events_for OLD_MANS_HOUSE
; (full note at the top of scripts/OldMansHouse.asm).
	object_const_def
	const_export OLDMANSHOUSE_BALDING_GUY

OldMansHouse_Object:
	db $a ; border block

	def_warp_events
	warp_event  2,  7, LAST_MAP, 4
	warp_event  3,  7, LAST_MAP, 4

	def_bg_events

	def_object_events
	object_event  5,  3, SPRITE_GAMBLER, STAY, DOWN, TEXT_OLDMANSHOUSE_BALDING_GUY

	def_warps_to OLD_MANS_HOUSE
