; Bridge PC: see data/events/hidden_events.asm, hidden_events_for FLORAS_GROTTO
; (full note at the top of scripts/FlorasGrotto.asm).
	object_const_def
	const_export FLORASGROTTO_FLORA
	const_export FLORASGROTTO_GAMBLER

FlorasGrotto_Object:
	db $a ; border block

	def_warp_events
	warp_event  3,  7, LAST_MAP, 2

	def_bg_events

	def_object_events
	object_event  4,  3, SPRITE_BEAUTY, STAY, LEFT, TEXT_FLORASGROTTO_FLORA

	def_warps_to FLORAS_GROTTO
