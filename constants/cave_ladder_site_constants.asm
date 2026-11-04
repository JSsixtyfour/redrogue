; Procedural cave ladder sites (PROCEDURAL_SUBROOMS_PLAN Phase 4, the cave subroom).
;
; A warp's ARRIVAL tile is read from ROM, so a ladder the player climbs back out
; onto can only exist where a warp_event was declared at build time. These are
; the candidate blocks, as (block x, block y) in the 20x20 cave. The ladder is
; block CAVE_LADDER_BLOCK, whose only ladder quadrant is the bottom-right one,
; so each site's warp tile is (2x+1, 2y+1).
;
; Picked by tools/pyboy_smoke/audit_cave_ladder_sites.py --min-distance 8
; (greedy over 500 real caves; held-out 200: two sites at least
; CAVE_LADDER_MIN_DISTANCE apart in 96%, at least one in 100%). Used by
; data/maps/objects/ProceduralCave1.asm (one warp_event per site), by
; custom_functions/cave_subroom.asm, and parsed by the audit and the tests.
; The warp_event index of site n is CAVE_FIRST_LADDER_WARP + n.

DEF CAVE_FIRST_LADDER_WARP EQU 2 ; after the entrance and the exit
; The cave's block-map geometry, shared by the subroom code in $3F and its
; helpers in $26 (different assembly units). Mirrors PC_* in procedural_cave_gen.
DEF CAVESUB_STRIDE EQU 26 ; PC_STRIDE
DEF CAVESUB_BASE   EQU 81 ; PC_BASE
DEF CAVESUB_FLOOR  EQU 1  ; PC_BLOCK_FLOOR
DEF CAVESUB_SIZE   EQU 20 ; PC_SIZE
DEF CAVE_LADDER_MIN_DISTANCE EQU 8 ; blocks, Manhattan, between the two ladders
; DYNAMIC LADDERS (2026-11-03, FOLLOWUPS #93). Fresh caves no longer use the
; sites below: a ladder may stand on ANY block passing CaveLadderSiteValid.
; Its departure is armed at runtime in warp slot 2 (first ladder) or 3
; (second), and its return arrival is resolved at load time by
; CaveResolveArrival (through the forest grotto's FGResolveArrival seam), so
; no ROM-declared arrival is needed. The ladders are found again by scanning
; the baked map for CAVE_LADDER_BLOCK in rows/columns 1-18, skipping the exit
; (PCLadderTable can draw the exit as block 40 too). No coordinates are saved:
; A = CAVESUB_DYN_LADDER_1, B = CAVESUB_DYN_LADDER_2 (or the entrance ladder).
; The 30 sites and their warp_events stay for caves saved before this change.
; Simulated over 600 caves (PROCEDURAL_REVIEW_2026-11-03.md): two ordinary
; ladders 93.4% -> 100%, a ladder within 10 steps of the door 23% -> 0.4%.
DEF CAVESUB_DYN_LADDER_1 EQU $FD ; in A: the first ladder is dynamic (warp 2)
DEF CAVESUB_DYN_LADDER_2 EQU $FC ; in B: the second ladder is dynamic (warp 3)
DEF CAVE_DYN_MIN_DISTANCE EQU 10      ; blocks, Manhattan, between the two
DEF CAVE_DYN_ENTRANCE_CLEARANCE EQU 6 ; preferred: more than this from the entrance
DEF CAVE_LADDER_CANDIDATE EQU $FE     ; generation only: a block marked valid
; CaveDynWalk's c flags.
DEF BIT_CAVE_DYN_FAR     EQU 0 ; only blocks clear of the entrance
DEF BIT_CAVE_DYN_PARTNER EQU 1 ; only blocks CAVE_DYN_MIN_DISTANCE from CAVESUB_TMP_X/Y
DEF BIT_CAVE_DYN_COUNT   EQU 7 ; count them (b = 0) rather than stop on the b-th
DEF CAVE_DYN_FAR     EQU 1 << BIT_CAVE_DYN_FAR
DEF CAVE_DYN_PARTNER EQU 1 << BIT_CAVE_DYN_PARTNER
DEF CAVE_DYN_COUNT   EQU 1 << BIT_CAVE_DYN_COUNT
DEF CAVE_LADDER_BLOCK EQU 40
DEF CAVE_LADDER_NONE EQU $FF
; A=ordinary site, B=$FE: entrance BR supplies the second connection, returning
; via ROM entrance warp0 (BL). Its departure reuses site0's slot, or site1's
; if A occupies site0. Legacy A=$FE,B=$FF saves retain their old entrance return.
DEF CAVESUB_ENTRANCE_LADDER EQU $FE
DEF CAVESUB_ENTRANCE_X EQU 9
DEF CAVESUB_ENTRANCE_Y EQU 19

DEF NUM_CAVE_LADDER_SITES = 0
MACRO ladder_site
	DEF CAVE_LADDER_SITE_{d:NUM_CAVE_LADDER_SITES}_X EQU \1
	DEF CAVE_LADDER_SITE_{d:NUM_CAVE_LADDER_SITES}_Y EQU \2
	REDEF NUM_CAVE_LADDER_SITES = NUM_CAVE_LADDER_SITES + 1
ENDM

	ladder_site 12,  4
	ladder_site  9, 16
	ladder_site  7, 10
	ladder_site 17,  6
	ladder_site  8, 17
	ladder_site  6,  2
	ladder_site 17,  2
	ladder_site  1,  2
	ladder_site 11,  2
	ladder_site 17, 10
	ladder_site 15, 18
	ladder_site  2,  8
	ladder_site  8,  4
	ladder_site  3, 12
	ladder_site  9, 13
	ladder_site  3, 18
	ladder_site 17, 18
	ladder_site 15,  2
	ladder_site 12, 11
	ladder_site  1, 15
	ladder_site  8,  2
	ladder_site 14,  1
	ladder_site 17,  5
	ladder_site 16, 12
	ladder_site  3, 15
	ladder_site  2, 13
	ladder_site 14,  4
	ladder_site  7, 17
	ladder_site 18, 17
	ladder_site  4,  9

; The cave subroom's state, in the cave staging buffer's tail (SRAM bank 0).
; PCPreloadCave fills all 600 bytes, but the blit and the bake only ever touch
; the 20x20 block area from PC_BASE, so the last five bytes are free for the
; life of a cave (custom_functions/cave_subroom.asm).
DEF CAVESUB_TAIL EQU 81 + 19 * 26 + 20 ; the first byte after the block area
ASSERT CAVESUB_TAIL + 5 <= 600
DEF CAVESUB_LADDER_A EQUS "(sProcCaveStagingBuffer + CAVESUB_TAIL)"     ; site, or NONE
DEF CAVESUB_LADDER_B EQUS "(sProcCaveStagingBuffer + CAVESUB_TAIL + 1)" ; site, or NONE
DEF CAVESUB_STATE    EQUS "(sProcCaveStagingBuffer + CAVESUB_TAIL + 2)"
DEF CAVESUB_TMP_X    EQUS "(sProcCaveStagingBuffer + CAVESUB_TAIL + 3)" ; generation only
DEF CAVESUB_TMP_Y    EQUS "(sProcCaveStagingBuffer + CAVESUB_TAIL + 4)"
; CAVESUB_STATE bits. WON and PAID sit where the Facility keeps the Super
; Nerd's (sProcFacilityItemGot), so his routines serve both stages.
DEF BIT_CAVESUB_RESIDENT_WON  EQU 0 ; the subroom's resident was beaten
DEF BIT_CAVESUB_PRIZE_PAID    EQU 1 ; the Super Nerd's prize was handed over
DEF BIT_CAVESUB_SUPER_NERD    EQU 2 ; the resident is the Super Nerd (else the Gambler)
DEF BIT_CAVESUB_MANIAC        EQU 3 ; with SUPER_NERD: the PokeManiac, who uses his object
DEF BIT_CAVESUB_OBJECTS_SHOWN EQU 7
; The resident roll, out of 256 (2026-10-14: 40% Gambler, 40% Super
; Nerd, 20% PokeManiac).
DEF CAVESUB_GAMBLER_ODDS EQU 102
DEF CAVESUB_NERD_ODDS    EQU 102

; The subroom's drawn room and its decoration, rolled once per cave at the end
; of generation into CAVESUB_TMP_X, which is dead from there on. Bits 0-1: the
; room (CaveSubRooms); 2-3: the Pokemon on its lake (0 none); 4-6: the one on
; its unreachable mountain (0 none).
DEF CAVESUB_ROOM EQUS "CAVESUB_TMP_X"
DEF CAVESUB_ROOM_MASK  EQU %00000011
; The subroom's object slots (data/maps/objects/ProceduralCaveSubroom.asm
; ASSERTs them; its object consts are not visible outside maps.asm).
DEF CAVESUB_SLOT_GAMBLER    EQU 1
DEF CAVESUB_SLOT_SUPER_NERD EQU 2
DEF CAVESUB_SLOT_BALL       EQU 3
DEF CAVESUB_SLOT_WATER_MON  EQU 4
DEF CAVESUB_SLOT_LAND_MON   EQU 5
DEF CAVESUB_NUM_ROOMS  EQU 3 ; rows of CaveSubRooms (cave_subroom.asm)
	ASSERT CAVESUB_NUM_ROOMS <= CAVESUB_ROOM_MASK + 1
DEF CAVESUB_WATER_SHIFT EQU 2
DEF CAVESUB_WATER_MASK EQU %00001100
DEF CAVESUB_LAND_SHIFT EQU 4
DEF CAVESUB_LAND_MASK  EQU %01110000

; The resident's fallback: when no ladder fits a cave (about 1 in 300), the
; rolled resident stands in the cave itself, on a block passing the ladder rule.
; Stored in the two ladder bytes, which no ladder needs then: A = FALLBACK | X,
; B = FALLBACK_ROW | Y (any byte >= NUM_CAVE_LADDER_SITES already means "no
; ladder" to every reader). Objects 8 and 9 of ProceduralCave1, only one shown.
DEF CAVESUB_FALLBACK     EQU $80
DEF CAVESUB_FALLBACK_ROW EQU $40
; The dynamic tags must not read as a fallback block (A = $80 | 1..18) or as a
; site, and must differ from the entrance ladder and NONE.
	ASSERT CAVESUB_DYN_LADDER_2 > (CAVESUB_FALLBACK | 18)
	ASSERT CAVESUB_DYN_LADDER_1 < CAVESUB_ENTRANCE_LADDER
	ASSERT CAVESUB_DYN_LADDER_2 != CAVESUB_DYN_LADDER_1
; The marker must not be a real CAVERN block (128 of them) or the generator's
; own PC_BLOCK_PENDING_FLOOR ($FF).
	ASSERT CAVE_LADDER_CANDIDATE >= 128 && CAVE_LADDER_CANDIDATE != $FF
DEF CAVE_GAMBLER         EQU 8  ; object slot (ProceduralCave1's 8th object_event)
DEF CAVE_SUPER_NERD      EQU 9
