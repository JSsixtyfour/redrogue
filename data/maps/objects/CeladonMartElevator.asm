CeladonMartElevator_Object:
	db $f ; border block

	def_warp_events
	warp_event -3,  0, CELADON_MART_1F, 6
	warp_event -2, -2, CELADON_MART_1F, 6

	def_bg_events
	bg_event  3, -3, TEXT_CELADONMARTELEVATOR

	def_object_events

	def_warps_to CELADON_MART_ELEVATOR
