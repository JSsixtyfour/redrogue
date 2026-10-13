; Procedural Facility warp-pad sites (PROCEDURAL_SUBROOMS_PLAN Phase 2).
;
; A warp's ARRIVAL tile is read from ROM (LoadDestinationWarpPosition), so a pad
; can only exist where a warp_event was declared at build time. These are the
; candidate blocks, as (block x, block y) in the 20x20 player area. The pad art
; is block $2F, whose only non-floor quadrant is the bottom-right one, so each
; site's warp tile is (2x+1, 2y+1).
;
; Used by data/maps/objects/ProceduralFacility.asm (one warp_event per site),
; by PFacPlacePads/PFacArmPads, and parsed by
; tools/pyboy_smoke/audit_facility_pad_sites.py, which picked them: greedy over
; 400 layouts (seed state 0x2545F491) under the runtime validity rule. Order
; does not matter to the ROM. The warp_event index of site n is
; FACILITY_FIRST_PAD_WARP + n.
;
; At most MAX_WARP_EVENTS - FACILITY_FIRST_PAD_WARP sites fit; 27 leaves two
; warp slots free for a future floor or chamber door.

DEF FACILITY_FIRST_PAD_WARP EQU 3 ; after the entrance and the two exit tiles
DEF FACILITY_PAD_MIN_DISTANCE EQU 8 ; blocks, Manhattan, between a pair's ends
DEF FACILITY_PAD_BLOCK EQU $2F
DEF FACILITY_PAD_NONE EQU $FF

DEF NUM_FACILITY_PAD_SITES = 0
MACRO pad_site
	DEF FACILITY_PAD_SITE_{d:NUM_FACILITY_PAD_SITES}_X EQU \1
	DEF FACILITY_PAD_SITE_{d:NUM_FACILITY_PAD_SITES}_Y EQU \2
	REDEF NUM_FACILITY_PAD_SITES = NUM_FACILITY_PAD_SITES + 1
ENDM

	pad_site  9, 18
	pad_site  7, 12
	pad_site 15, 15
	pad_site 11, 12
	pad_site  3, 16
	pad_site 17, 15
	pad_site  5, 10
	pad_site 10, 11
	pad_site  5, 12
	pad_site 10, 18
	pad_site 14, 15
	pad_site 11, 18
	pad_site 11, 10
	pad_site  9, 16
	pad_site 16, 13
	pad_site 17, 17
	pad_site  2, 18
	pad_site  8, 12
	pad_site 13, 12
	pad_site 15, 17
	pad_site  8, 16
	pad_site  5, 11
	pad_site 15, 16
	pad_site 16, 14
	pad_site  4, 12
	pad_site  7, 10
	pad_site  3, 18
