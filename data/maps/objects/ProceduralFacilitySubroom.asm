ProceduralFacilitySubroom_Object:
	db $2E ; border block: the Facility's black void

	def_warp_events
	; The pad (block $2F at block (2,4): its pad is the bottom-right quadrant).
	; The player arrives on it from the Facility and steps back onto it to
	; leave. Its destination is a placeholder until the Facility side exists.
	warp_event  5,  9, PROCEDURAL_FACILITY, 1

	def_bg_events

	def_object_events

	def_warps_to PROCEDURAL_FACILITY_SUBROOM
