	object_const_def
	const_export CREDITEXCHANGE_SCIENTIST
	const_export CREDITEXCHANGE_COOLTRAINER

CreditExchange_Object:
	db $f ; border block

	def_warp_events
	warp_event  4,  7, SILPH_CO_B1F, 1
	warp_event  5,  7, SILPH_CO_B1F, 1

	def_bg_events
	bg_event  2,  2, TEXT_CREDITEXCHANGE_VENDOR_1
	bg_event  4,  2, TEXT_CREDITEXCHANGE_VENDOR_2
	bg_event  6,  2, TEXT_CREDITEXCHANGE_VENDOR_3

	def_object_events
	object_event  7,  5, SPRITE_COOLTRAINER_M, STAY, RIGHT, TEXT_CREDITEXCHANGE_COOLTRAINER
	object_event  2,  6, SPRITE_SCIENTIST, WALK, LEFT_RIGHT, TEXT_CREDITEXCHANGE_SCIENTIST

	def_warps_to CREDIT_EXCHANGE
