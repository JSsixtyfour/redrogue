; Procedural Forest rest house door spots (PROCEDURAL_SUBROOMS_PLAN Phase 4).
;
; The house is two blocks, $19 (door in its bottom-right quadrant, tile $3A)
; and $1C, drawn as maps/ProceduralForestRestHouseDrop.blk. It stands over two
; TREE blocks: a maze wall above a cell (odd x, even y) and the corner post to
; its right (always tree). Turning trees into a building cuts no path, and the
; door faces the cell below, which is always floor.
;
; A warp's ARRIVAL tile is read from ROM, so the house can only stand where a
; door warp was declared at build time: these are those spots, as the block of
; the house's LEFT half ($19). Each site's door tile is (2x+1, 2y+1); walking
; out of the house lands there, and the door tile steps the player down.
;
; Used by data/maps/objects/ProceduralForest.asm (one warp_event per site),
; PFPlaceHouse/PFArmHouseDoor, PFRestHouseLoad, and parsed by
; tools/pyboy_smoke/audit_forest_house.py. The warp_event index of site n is
; FOREST_FIRST_HOUSE_WARP + n. y = 16 skips x = 9: block (9,16) is the sign.

DEF FOREST_FIRST_HOUSE_WARP EQU 3 ; after the entrance and the two exit tiles
DEF FOREST_HOUSE_LEFT_BLOCK EQU $19
DEF FOREST_HOUSE_RIGHT_BLOCK EQU $1C
DEF FOREST_HOUSE_NONE EQU $FF ; a disarmed door warp's Y

DEF NUM_FOREST_HOUSE_SITES = 0
MACRO house_site
	ASSERT (\1) % 2 == 1 && (\2) % 2 == 0 && (\1) <= 17 && (\2) <= 16, \
		"a house site is a wall above a cell: odd x <= 17, even y <= 16"
	DEF FOREST_HOUSE_SITE_{d:NUM_FOREST_HOUSE_SITES}_X EQU \1
	DEF FOREST_HOUSE_SITE_{d:NUM_FOREST_HOUSE_SITES}_Y EQU \2
	REDEF NUM_FOREST_HOUSE_SITES = NUM_FOREST_HOUSE_SITES + 1
ENDM

	house_site  1,  2
	house_site  7,  2
	house_site 13,  2
	house_site 17,  2
	house_site  3,  4
	house_site  9,  4
	house_site 15,  4
	house_site  1,  6
	house_site  5,  6
	house_site 11,  6
	house_site 17,  6
	house_site  1,  8
	house_site  7,  8
	house_site 13,  8
	house_site  3, 10
	house_site  9, 10
	house_site 15, 10
	house_site  1, 12
	house_site  5, 12
	house_site 11, 12
	house_site 17, 12
	house_site  1, 14
	house_site  7, 14
	house_site 13, 14
	house_site  3, 16
	house_site  5, 16
	house_site 11, 16
	house_site 15, 16

	ASSERT FOREST_FIRST_HOUSE_WARP + NUM_FOREST_HOUSE_SITES <= 32, "too many door warps"
	; sProcForestItemGot keeps the site as index + 1 in bits 0-4.
	ASSERT NUM_FOREST_HOUSE_SITES < 31
	; sProcForestItemGot bit 7: scripts/ProceduralForest.asm's fresh-entry
	; show block has run for this generated forest.
DEF BIT_PF_OBJECTS_SHOWN EQU 7
	; sProcForestItemGot bit 5: the house's Money Match gambler was beaten in
	; this forest (custom_functions/money_match.asm). He stays and says his
	; after line instead of the offer.
DEF BIT_PF_MONEY_MATCH_WON EQU 5
