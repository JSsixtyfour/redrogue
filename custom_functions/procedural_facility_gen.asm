; custom_functions/procedural_facility_gen.asm
;
; Procedural facility generator for PROCEDURAL_FACILITY ($F3).
;
; Room-tree generator (ground-up redesign, see Red Rogue Files/
; 1-i-need-you-foamy-otter.md): 12 fixed-role rooms (0=entry, 1-4=item rooms,
; 5-10=explore, 11=exit) placed as a parent tree (each room's parent has a
; smaller id), stamped as floor, joined by direct-manhattan corridors toward
; each room's parent, enclosed in the FACILITY tileset's directional 9-slice
; wall (top/left/right/bottom + 4 corners), then converted down to real block
; IDs. The green/red palette roll is purely cosmetic now - it no longer
; branches generation.
;
; Buffer model: PFacFillUntouched seeds the whole 20x20 player area with the
; PFAC_UNTOUCHED sentinel ($FF, "nothing has touched this cell yet"). Rooms
; are stamped PFAC_ROOMFLOOR ($F0) and corridors PFAC_CORRIDOR ($FE) - both
; pseudo values distinct from every real block ID - so later passes can tell
; "claimed floor" apart from "never touched" without ambiguity. Two final
; sweeps convert the pseudo values down to real IDs: pseudo-floors -> PFAC_FLOOR
; (14), remaining untouched cells -> PFAC_WALL (46, the same block as the map
; border/void).
;
; SRAM: uses its own sProcFacility* fields (see ram/sram.asm). sProcFacilityBaked
; controls fast re-entry. Reuses the cave's boss/wild/item engine + PC_* events
; (never concurrent), exactly like the forest.
;
; Room data model: 12 records (see PFAC_ROOM_STRIDE/PFAC_ROOM_MAX below) live in
; sProcFacilityGenScratch, one per room id, in id order - array index IS the
; room id (0=entry, 1-4=items, 5-10=explore, 11=exit; role is derived from the
; index, never stored). An explore room (5-10) that fails to place after retries
; is NOT omitted from the array - its slot is written with W=0 as a "not placed"
; sentinel, so every other id keeps its fixed slot. wPFacRoomCount therefore
; always ends at PFAC_ROOM_MAX (12) once placement finishes; consumers (stamp,
; enclose, corridors) must skip any record whose W is 0. Item rooms (ids 1-4)
; are guaranteed placed (rule e) so PFacPlaceItems addresses them directly by id
; with no scan needed.
;
; Pipeline order (PFacGenerateFacility): fill untouched -> place entry(0)/exit(11)
; /middle(1-10) rooms -> assign exit parent -> stamp room floors -> carve
; corridors (rooms 11..1 -> parent) + entry corridor -> enclose rooms in
; directional walls -> punch the north exit opening -> add doorway jambs -> finalize
; generation sentinels -> place items. v1 ships a NORTH exit only.

SECTION "ProceduralFacilityGen", ROMX

DEF PFAC_SIZE    EQU 20
DEF PFAC_STRIDE  EQU 26
DEF PFAC_BASE    EQU 81

DEF PFAC_FLOOR   EQU 14   ; facility floor block (all-$01, passable)
DEF PFAC_WALL    EQU 46   ; solid interior wall AND the map border/void block.
DEF PFAC_EXIT_N  EQU $08
DEF PFAC_EXIT_E  EQU $04
DEF PFAC_EXIT_W  EQU $05

; --- Generation-time pseudo values (never written to the final map) ---
DEF PFAC_UNTOUCHED EQU $FF   ; PFacFillUntouched's seed value: "nothing has
                             ; claimed this cell yet". Converted to PFAC_WALL
                             ; by PFacFinalizeBlocks once generation is done.
DEF PFAC_PENDING   EQU $FD   ; ambiguous corridor boundary; becomes floor after classification
DEF PFAC_CORRIDOR  EQU $FE   ; a corridor cell (PFacCarveCorridors/
                             ; PFacCarveEntryCorridor). Converted to PFAC_FLOOR
                             ; by PFacFinalizeBlocks.
DEF PFAC_ROOMFLOOR EQU $F0   ; a room-interior floor cell (PFacStampRoomFloors).
                             ; Single value this pass; a decor follow-up can
                             ; widen this to $F0-$F3 keyed off the room's Type
                             ; field without touching the structural pipeline.
                             ; Converted to PFAC_FLOOR by
                             ; PFacFinalizeBlocks.

; --- Directional wall 9-slice (block IDs pinned from facility.bst / user) ---
; Straight walls, named by which side the open floor is on:
DEF PFAC_W_TOP    EQU 65  ; floor to the SOUTH (solid top, walkable bottom)
DEF PFAC_W_BOTTOM EQU 73  ; floor to the NORTH
DEF PFAC_W_LEFT   EQU 68  ; floor to the EAST
DEF PFAC_W_RIGHT  EQU 70  ; floor to the WEST
; Corners, named by which corner of the block is solid (floor is the opposite):
DEF PFAC_C_TL     EQU 64  ; solid top-left,  floor SE  (floor to S and E)
DEF PFAC_C_TR     EQU 66  ; solid top-right, floor SW  (floor to S and W)
DEF PFAC_C_BL     EQU 72  ; solid bottom-left,  floor NE (floor to N and E)
DEF PFAC_C_BR     EQU 74  ; solid bottom-right, floor NW (floor to N and W)

; Doorway jamb/end pieces. Names describe the flank's position around the gap.
DEF PFAC_J_TOP_W    EQU $63
DEF PFAC_J_TOP_E    EQU $67
DEF PFAC_J_BOTTOM_W EQU $58
DEF PFAC_J_BOTTOM_E EQU $57
DEF PFAC_J_LEFT_N   EQU $55
DEF PFAC_J_LEFT_S   EQU $59
DEF PFAC_J_RIGHT_N  EQU $56
DEF PFAC_J_RIGHT_S  EQU $5A

; --- Structural room decor (user-authored hexadecimal block catalog) ---
; Occupancy describes the four movement quadrants, not visual tile coverage.
DEF PFAC_DECOR_SOLID_A  EQU $06
DEF PFAC_DECOR_SOLID_B  EQU $47
DEF PFAC_DECOR_SOLID_C  EQU $35
DEF PFAC_DECOR_RIGHT_A  EQU $56
DEF PFAC_DECOR_RIGHT_B  EQU $09
DEF PFAC_DECOR_LEFT_A   EQU $0D
DEF PFAC_DECOR_LEFT_B   EQU $39
DEF PFAC_DECOR_UPPER_A  EQU $07
DEF PFAC_DECOR_UPPER_B  EQU $19
DEF PFAC_DECOR_BOTTOM_A EQU $49
DEF PFAC_DECOR_BOTTOM_B EQU $1D

; Wall-decoration compatibility catalog, retained for the later perimeter/socket
; pass. These replacements become fully solid, so they must not be applied by a
; blind whole-map substitution:
;   $44 -> $5C, $46 -> $5D, $41 -> $61, $40 -> $68, $42 -> $69.

; --- Room record model (sProcFacilityGenScratch, 81 bytes: 12*6 = 72 used) ---
; Record layout (6 bytes, read/written positionally via PFacRoomRecordAddr):
;   +0 X      floor-rect top-left block col
;   +1 Y      floor-rect top-left block row
;   +2 W      floor-rect width in blocks (0 = unplaced slot, see header note)
;   +3 H      floor-rect height in blocks
;   +4 Parent parent room id (PFAC_ROOM_NONE for room 0, which has no parent)
;   +5 Type   decor category 0-3 (rolled now, used by a later decor pass)
DEF PFAC_ROOM_STRIDE EQU 6
DEF PFAC_ROOM_MAX    EQU 12   ; entry(0) + items(1-4) + explore(5-10) + exit(11)
DEF PFAC_ROOM_NONE   EQU $FF  ; Parent sentinel for room 0
DEF PFAC_TEMPLATE_FLAG EQU $80
DEF BIT_PFAC_FAKE_ROOM EQU 4
DEF PFAC_SOCKET_N EQU 1
DEF PFAC_SOCKET_E EQU 2
DEF PFAC_SOCKET_S EQU 4
DEF PFAC_SOCKET_W EQU 8
DEF PFAC_MIDDLE_ROOM_3X3_SOCKETS EQU PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W
ASSERT PFAC_MIDDLE_ROOM_3X3_SOCKETS == $0F

PFacFakeWildLevelTable:
    db 5, 9, 13, 17, 21, 25, 29, 33, 37

; --- Full-room premade library (R4) -----------------------------------------
;
; A full-room premade owns a room's ENTIRE footprint, generated wall ring
; included. Room records store the floor interior, and the generic ring is
; exactly one block thick, so a premade is eligible for a room only when
;     footprint width  == interior width  + 2
;     footprint height == interior height + 2
; That is one size test written in two coordinate systems, not an extra
; qualifier. Interiors roll 1..7, so footprints run 3x3 through 9x9.
;
; Socket POSITIONS are canonical and are not stored: the four sockets sit on the
; footprint perimeter at the room's own center row/column, which is exactly where
; PFacRoomCenter sends corridors. Which of those four a given payload can
; actually open is NOT canonical and IS stored.
;
; It has to be measured rather than assumed, because of one non-obvious property
; of this tileset: every generic ring block has its INNER quadrants walkable
; ($41 top wall BL+BR, $44 left wall TR+BR, $40 TL corner BR, and so on), so an
; intact ring is a continuous one-block walkable baseboard around the interior.
; A room whose center is solid is therefore still fully traversable - the player
; walks around the furniture - which is exactly what the pool, water and table
; payloads are for. But the wall-DECORATION variants $5C and $5D are fully
; solid, so a payload using them severs the baseboard on that side and has to
; route through its interior instead. Connectivity genuinely differs per payload.
;
; tools/check_facility_premades.py derives each mask offline: it cuts one side at
; a time to prove no uncut perimeter leaks, then cuts all four and reports the
; largest set of sides that are mutually connected. The runtime only compares
; masks.
;
; Descriptor, PFAC_TPL_STRIDE bytes:
;   +0 footprint width  (3..9)
;   +1 footprint height (3..9)
;   +2 socket mask: which of PFAC_SOCKET_N/E/S/W this payload can open
;   +3 flags (PFAC_TPL_ITEM = the payload's HUB is itself a legal item anchor,
;      so item rooms 1-4 may take it - see PFacSelectPremadeMiddleRooms for why
;      the hub specifically is what matters)
;   +4/+5 payload pointer, footprint W*H block ids, row-major
DEF PFAC_TPL_STRIDE EQU 6
DEF PFAC_TPL_ITEM   EQU 1 << 0

; Size-group index. Two bytes per (footprint W, footprint H) pair, addressed
; directly by (W - 3) * 7 + (H - 3) so selection never searches:
;   +0 first descriptor index in that group
;   +1 total descriptors in the group
; Ordering inside a group carries no meaning: PFacChooseTemplate filters the
; whole group on socket mask and role, then picks uniformly from what survives.
DEF PFAC_TPL_GROUP_STRIDE EQU 2
DEF PFAC_TPL_GROUP_COUNT  EQU 7 * 7

; Descriptors are laid out one size group after another, each group opened by a
; PFacTpl<W>x<H> label and closed by that group's End label. The group table
; PFacTpl<W>x<H> label and closed by that group's End label. The group table
; below derives first index and count from those labels.
;
; GENERATED. Socket masks and PFAC_TPL_ITEM are MEASURED, not authored: they
; come from tools/check_facility_premades.py, which decodes each payload against
; facility.bst. Do not hand-edit and do not infer a mask by eye. To add or
; change an asset, drop the .blk in maps/, then:
;     python3 tools/check_facility_premades.py --report > \
;         tools/pyboy_smoke/artifacts/facility_fullroom_audit.txt
;     python3 tools/gen_facility_room_table.py
; and replace the block below with its output.
PFacRoomDescriptors:

PFacTpl3x3:
    db 3, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData3x3BedRoom
    db 3, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData3x3BlockRoom
    db 3, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM
    dw PFacTplData3x3RockRoom
    db 3, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData3x3RockRoom2
    db 3, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData3x3ServerRoom
    db 3, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData3x3TableRoom
    db 3, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData3x3TreeRoom
    db 3, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM
    dw PFacTplData3x3TreeRoom2
PFacTpl3x3End:

PFacTpl3x6:
    db 3, 6, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData3x6TableserverRoom
PFacTpl3x6End:

PFacTpl4x3:
    db 4, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData4x3BedRoom
    db 4, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData4x3RockRoom
PFacTpl4x3End:

PFacTpl4x4:
    db 4, 4, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM
    dw PFacTplData4x4ServerRoom
    db 4, 4, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM
    dw PFacTplData4x4ServerRoom2
PFacTpl4x4End:

PFacTpl4x5:
    db 4, 5, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData4x5BlockRoom
    db 4, 5, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData4x5DoubletableRoom
    db 4, 5, PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData4x5RockRoom
    db 4, 5, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM
    dw PFacTplData4x5TableserverRoom
PFacTpl4x5End:

PFacTpl4x6:
    db 4, 6, PFAC_SOCKET_N | PFAC_SOCKET_S, 0
    dw PFacTplData4x6RockCombinedroom
PFacTpl4x6End:

PFacTpl4x7:
    db 4, 7, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData4x7DoubletableTreeCombinedroom
    db 4, 7, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData4x7ServerTableCombinedroom
PFacTpl4x7End:

PFacTpl5x3:
    db 5, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData5x3BedRoom
    db 5, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM
    dw PFacTplData5x3RockserverRoom
    db 5, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM
    dw PFacTplData5x3ServerRoom
PFacTpl5x3End:

PFacTpl5x4:
    db 5, 4, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM
    dw PFacTplData5x4DoubletabletreeRoom
    db 5, 4, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM
    dw PFacTplData5x4ServerTableRoom
PFacTpl5x4End:

PFacTpl5x5:
    db 5, 5, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData5x5RockRoom
    db 5, 5, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM
    dw PFacTplData5x5TableBedRoom
    db 5, 5, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM
    dw PFacTplData5x5TableRockRoom
    db 5, 5, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM
    dw PFacTplData5x5TableRoom
    db 5, 5, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM
    dw PFacTplData5x5TreeRoom
PFacTpl5x5End:

PFacTpl5x6:
    db 5, 6, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM
    dw PFacTplData5x6TableserverRoom
    db 5, 6, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM
    dw PFacTplData5x6TablestatueRoom
PFacTpl5x6End:

PFacTpl5x7:
    db 5, 7, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM
    dw PFacTplData5x7DoublebigtableserverRoom
PFacTpl5x7End:

PFacTpl6x3:
    db 6, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData6x3BedRoom
    db 6, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM
    dw PFacTplData6x3ServerRoom
PFacTpl6x3End:

PFacTpl6x4:
    db 6, 4, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM
    dw PFacTplData6x4BlockRoom
    db 6, 4, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM
    dw PFacTplData6x4TabletreeRoom
    db 6, 4, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM
    dw PFacTplData6x4TripletableRockRoom
PFacTpl6x4End:

PFacTpl6x5:
    db 6, 5, PFAC_SOCKET_N | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM
    dw PFacTplData6x5TableRockRoom
PFacTpl6x5End:

PFacTpl6x6:
    db 6, 6, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM
    dw PFacTplData6x6BlockRoom
    db 6, 6, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData6x6WaterRoom
    db 6, 6, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData6x6WaterRoom2
PFacTpl6x6End:

PFacTpl6x7:
    db 6, 7, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData6x7TripletableTreeCombinedroom
PFacTpl6x7End:

PFacTpl7x7:
    db 7, 7, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData7x7BlockrockRoom
    db 7, 7, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM
    dw PFacTplData7x7DoublebigtabletreeRoom
    db 7, 7, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData7x7DoubletableServerCombinedroom
    db 7, 7, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData7x7Pool
    db 7, 7, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM
    dw PFacTplData7x7TreerockCombinedroom
PFacTpl7x7End:

PFacTpl8x3:
    db 8, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData8x3BlockRoom
    db 8, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData8x3ServerRoom
    db 8, 3, PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData8x3ServerrockRoom
PFacTpl8x3End:

PFacTpl8x4:
    db 8, 4, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData8x4BlockserverCombinedroom
    db 8, 4, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData8x4TableservertreeRoom
PFacTpl8x4End:

PFacTpl8x5:
    db 8, 5, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM
    dw PFacTplData8x5CombinedtableRockRoom
PFacTpl8x5End:

PFacTpl8x6:
    db 8, 6, PFAC_SOCKET_N | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData8x6RockCombinedroom
PFacTpl8x6End:

PFacTpl8x7:
    db 8, 7, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData8x7PoolRoom
PFacTpl8x7End:

PFacTpl9x5:
    db 9, 5, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, 0
    dw PFacTplData9x5BlockrockRoom
PFacTpl9x5End:

PFacTpl9x7:
    db 9, 7, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM
    dw PFacTplData9x7TreerockCombinedroom
PFacTpl9x7End:

PFacRoomDescriptorsEnd:
DEF PFAC_TPL_TOTAL EQU (PFacRoomDescriptorsEnd - PFacRoomDescriptors) / PFAC_TPL_STRIDE
ASSERT PFAC_TPL_TOTAL == 58

; An empty size group is two zero bytes; a populated one names its run.
MACRO pfac_tpl_group ; \1 = group label, \2 = group end label
    db (\1 - PFacRoomDescriptors) / PFAC_TPL_STRIDE
    db (\2 - \1) / PFAC_TPL_STRIDE
ENDM
MACRO pfac_tpl_no_group
    db 0, 0
ENDM

; Addressed by (footprint W - 3) * 7 + (footprint H - 3). Rows are W, columns H.
PFacRoomGroupTable:
    ; footprint width 3
    pfac_tpl_group PFacTpl3x3, PFacTpl3x3End ; 3x3, 8
    pfac_tpl_no_group ; 3x4
    pfac_tpl_no_group ; 3x5
    pfac_tpl_group PFacTpl3x6, PFacTpl3x6End ; 3x6, 1
    pfac_tpl_no_group ; 3x7
    pfac_tpl_no_group ; 3x8
    pfac_tpl_no_group ; 3x9
    ; footprint width 4
    pfac_tpl_group PFacTpl4x3, PFacTpl4x3End ; 4x3, 2
    pfac_tpl_group PFacTpl4x4, PFacTpl4x4End ; 4x4, 2
    pfac_tpl_group PFacTpl4x5, PFacTpl4x5End ; 4x5, 4
    pfac_tpl_group PFacTpl4x6, PFacTpl4x6End ; 4x6, 1
    pfac_tpl_group PFacTpl4x7, PFacTpl4x7End ; 4x7, 2
    pfac_tpl_no_group ; 4x8
    pfac_tpl_no_group ; 4x9
    ; footprint width 5
    pfac_tpl_group PFacTpl5x3, PFacTpl5x3End ; 5x3, 3
    pfac_tpl_group PFacTpl5x4, PFacTpl5x4End ; 5x4, 2
    pfac_tpl_group PFacTpl5x5, PFacTpl5x5End ; 5x5, 5
    pfac_tpl_group PFacTpl5x6, PFacTpl5x6End ; 5x6, 2
    pfac_tpl_group PFacTpl5x7, PFacTpl5x7End ; 5x7, 1
    pfac_tpl_no_group ; 5x8
    pfac_tpl_no_group ; 5x9
    ; footprint width 6
    pfac_tpl_group PFacTpl6x3, PFacTpl6x3End ; 6x3, 2
    pfac_tpl_group PFacTpl6x4, PFacTpl6x4End ; 6x4, 3
    pfac_tpl_group PFacTpl6x5, PFacTpl6x5End ; 6x5, 1
    pfac_tpl_group PFacTpl6x6, PFacTpl6x6End ; 6x6, 3
    pfac_tpl_group PFacTpl6x7, PFacTpl6x7End ; 6x7, 1
    pfac_tpl_no_group ; 6x8
    pfac_tpl_no_group ; 6x9
    ; footprint width 7
    pfac_tpl_no_group ; 7x3
    pfac_tpl_no_group ; 7x4
    pfac_tpl_no_group ; 7x5
    pfac_tpl_no_group ; 7x6
    pfac_tpl_group PFacTpl7x7, PFacTpl7x7End ; 7x7, 5
    pfac_tpl_no_group ; 7x8
    pfac_tpl_no_group ; 7x9
    ; footprint width 8
    pfac_tpl_group PFacTpl8x3, PFacTpl8x3End ; 8x3, 3
    pfac_tpl_group PFacTpl8x4, PFacTpl8x4End ; 8x4, 2
    pfac_tpl_group PFacTpl8x5, PFacTpl8x5End ; 8x5, 1
    pfac_tpl_group PFacTpl8x6, PFacTpl8x6End ; 8x6, 1
    pfac_tpl_group PFacTpl8x7, PFacTpl8x7End ; 8x7, 1
    pfac_tpl_no_group ; 8x8
    pfac_tpl_no_group ; 8x9
    ; footprint width 9
    pfac_tpl_no_group ; 9x3
    pfac_tpl_no_group ; 9x4
    pfac_tpl_group PFacTpl9x5, PFacTpl9x5End ; 9x5, 1
    pfac_tpl_no_group ; 9x6
    pfac_tpl_group PFacTpl9x7, PFacTpl9x7End ; 9x7, 1
    pfac_tpl_no_group ; 9x8
    pfac_tpl_no_group ; 9x9
ASSERT @ - PFacRoomGroupTable == PFAC_TPL_GROUP_COUNT * PFAC_TPL_GROUP_STRIDE

PFacTplData3x3BedRoom:
    INCBIN "maps/ProceduralFacility_3x3_bed_room.blk"
ASSERT @ - PFacTplData3x3BedRoom == 9
PFacTplData3x3BlockRoom:
    INCBIN "maps/ProceduralFacility_3x3_block_room.blk"
ASSERT @ - PFacTplData3x3BlockRoom == 9
PFacTplData3x3RockRoom:
    INCBIN "maps/ProceduralFacility_3x3_rock_room.blkv"
ASSERT @ - PFacTplData3x3RockRoom == 9
PFacTplData3x3RockRoom2:
    INCBIN "maps/ProceduralFacility_3x3_rock_room2.blk"
ASSERT @ - PFacTplData3x3RockRoom2 == 9
PFacTplData3x3ServerRoom:
    INCBIN "maps/ProceduralFacility_3x3_server_room.blk"
ASSERT @ - PFacTplData3x3ServerRoom == 9
PFacTplData3x3TableRoom:
    INCBIN "maps/ProceduralFacility_3x3_table_room.blk"
ASSERT @ - PFacTplData3x3TableRoom == 9
PFacTplData3x3TreeRoom:
    INCBIN "maps/ProceduralFacility_3x3_tree_room.blk"
ASSERT @ - PFacTplData3x3TreeRoom == 9
PFacTplData3x3TreeRoom2:
    INCBIN "maps/ProceduralFacility_3x3_tree_room2.blk"
ASSERT @ - PFacTplData3x3TreeRoom2 == 9
PFacTplData3x6TableserverRoom:
    INCBIN "maps/ProceduralFacility_3x6_tableserver_room.blk"
ASSERT @ - PFacTplData3x6TableserverRoom == 18
PFacTplData4x3BedRoom:
    INCBIN "maps/ProceduralFacility_4x3_bed_room.blk"
ASSERT @ - PFacTplData4x3BedRoom == 12
PFacTplData4x3RockRoom:
    INCBIN "maps/ProceduralFacility_4x3_rock_room.blk"
ASSERT @ - PFacTplData4x3RockRoom == 12
PFacTplData4x4ServerRoom:
    INCBIN "maps/ProceduralFacility_4x4_server_room.blk"
ASSERT @ - PFacTplData4x4ServerRoom == 16
PFacTplData4x4ServerRoom2:
    INCBIN "maps/ProceduralFacility_4x4_server_room2.blk"
ASSERT @ - PFacTplData4x4ServerRoom2 == 16
PFacTplData4x5BlockRoom:
    INCBIN "maps/ProceduralFacility_4x5_block_room.blk"
ASSERT @ - PFacTplData4x5BlockRoom == 20
PFacTplData4x5DoubletableRoom:
    INCBIN "maps/ProceduralFacility_4x5_doubletable_room.blk"
ASSERT @ - PFacTplData4x5DoubletableRoom == 20
PFacTplData4x5RockRoom:
    INCBIN "maps/ProceduralFacility_4x5_rock_room.blk"
ASSERT @ - PFacTplData4x5RockRoom == 20
PFacTplData4x5TableserverRoom:
    INCBIN "maps/ProceduralFacility_4x5_tableserver_room.blk"
ASSERT @ - PFacTplData4x5TableserverRoom == 20
PFacTplData4x6RockCombinedroom:
    INCBIN "maps/ProceduralFacility_4x6_rock_combinedroom.blk"
ASSERT @ - PFacTplData4x6RockCombinedroom == 24
PFacTplData4x7DoubletableTreeCombinedroom:
    INCBIN "maps/ProceduralFacility_4x7_doubletable_tree_combinedroom.blk"
ASSERT @ - PFacTplData4x7DoubletableTreeCombinedroom == 28
PFacTplData4x7ServerTableCombinedroom:
    INCBIN "maps/ProceduralFacility_4x7_server_table_combinedroom.blk"
ASSERT @ - PFacTplData4x7ServerTableCombinedroom == 28
PFacTplData5x3BedRoom:
    INCBIN "maps/ProceduralFacility_5x3_bed_room.blk"
ASSERT @ - PFacTplData5x3BedRoom == 15
PFacTplData5x3RockserverRoom:
    INCBIN "maps/ProceduralFacility_5x3_rockserver_room.blk"
ASSERT @ - PFacTplData5x3RockserverRoom == 15
PFacTplData5x3ServerRoom:
    INCBIN "maps/ProceduralFacility_5x3_server_room.blk"
ASSERT @ - PFacTplData5x3ServerRoom == 15
PFacTplData5x4DoubletabletreeRoom:
    INCBIN "maps/ProceduralFacility_5x4_doubletabletree_room.blk"
ASSERT @ - PFacTplData5x4DoubletabletreeRoom == 20
PFacTplData5x4ServerTableRoom:
    INCBIN "maps/ProceduralFacility_5x4_server_table_room.blk"
ASSERT @ - PFacTplData5x4ServerTableRoom == 20
PFacTplData5x5RockRoom:
    INCBIN "maps/ProceduralFacility_5x5__rock_room.blk"
ASSERT @ - PFacTplData5x5RockRoom == 25
PFacTplData5x5TableBedRoom:
    INCBIN "maps/ProceduralFacility_5x5__table_bed_room.blk"
ASSERT @ - PFacTplData5x5TableBedRoom == 25
PFacTplData5x5TableRockRoom:
    INCBIN "maps/ProceduralFacility_5x5_table_rock_room.blk"
ASSERT @ - PFacTplData5x5TableRockRoom == 25
PFacTplData5x5TableRoom:
    INCBIN "maps/ProceduralFacility_5x5_table_room.blk"
ASSERT @ - PFacTplData5x5TableRoom == 25
PFacTplData5x5TreeRoom:
    INCBIN "maps/ProceduralFacility_5x5_tree_room.blk"
ASSERT @ - PFacTplData5x5TreeRoom == 25
PFacTplData5x6TableserverRoom:
    INCBIN "maps/ProceduralFacility_5x6_tableserver_room.blk"
ASSERT @ - PFacTplData5x6TableserverRoom == 30
PFacTplData5x6TablestatueRoom:
    INCBIN "maps/ProceduralFacility_5x6_tablestatue_room.blk"
ASSERT @ - PFacTplData5x6TablestatueRoom == 30
PFacTplData5x7DoublebigtableserverRoom:
    INCBIN "maps/ProceduralFacility_5x7_doublebigtableserver_room.blk"
ASSERT @ - PFacTplData5x7DoublebigtableserverRoom == 35
PFacTplData6x3BedRoom:
    INCBIN "maps/ProceduralFacility_6x3_bed_room.blk"
ASSERT @ - PFacTplData6x3BedRoom == 18
PFacTplData6x3ServerRoom:
    INCBIN "maps/ProceduralFacility_6x3_server_room.blk"
ASSERT @ - PFacTplData6x3ServerRoom == 18
PFacTplData6x4BlockRoom:
    INCBIN "maps/ProceduralFacility_6x4_block_room.blk"
ASSERT @ - PFacTplData6x4BlockRoom == 24
PFacTplData6x4TabletreeRoom:
    INCBIN "maps/ProceduralFacility_6x4_tabletree_room.blk"
ASSERT @ - PFacTplData6x4TabletreeRoom == 24
PFacTplData6x4TripletableRockRoom:
    INCBIN "maps/ProceduralFacility_6x4_tripletable_rock_room.blk"
ASSERT @ - PFacTplData6x4TripletableRockRoom == 24
PFacTplData6x5TableRockRoom:
    INCBIN "maps/ProceduralFacility_6x5_table_rock_room.blk"
ASSERT @ - PFacTplData6x5TableRockRoom == 30
PFacTplData6x6BlockRoom:
    INCBIN "maps/ProceduralFacility_6x6_block_room.blk"
ASSERT @ - PFacTplData6x6BlockRoom == 36
PFacTplData6x6WaterRoom:
    INCBIN "maps/ProceduralFacility_6x6_water_room.blk"
ASSERT @ - PFacTplData6x6WaterRoom == 36
PFacTplData6x6WaterRoom2:
    INCBIN "maps/ProceduralFacility_6x6_water_room2.blk"
ASSERT @ - PFacTplData6x6WaterRoom2 == 36
PFacTplData6x7TripletableTreeCombinedroom:
    INCBIN "maps/ProceduralFacility_6x7_tripletable_tree_combinedroom.blk"
ASSERT @ - PFacTplData6x7TripletableTreeCombinedroom == 42
PFacTplData7x7BlockrockRoom:
    INCBIN "maps/ProceduralFacility_7x7_blockrock_room.blk"
ASSERT @ - PFacTplData7x7BlockrockRoom == 49
PFacTplData7x7DoublebigtabletreeRoom:
    INCBIN "maps/ProceduralFacility_7x7_doublebigtabletree_room.blk"
ASSERT @ - PFacTplData7x7DoublebigtabletreeRoom == 49
PFacTplData7x7DoubletableServerCombinedroom:
    INCBIN "maps/ProceduralFacility_7x7_doubletable_server_combinedroom.blk"
ASSERT @ - PFacTplData7x7DoubletableServerCombinedroom == 49
PFacTplData7x7Pool:
    INCBIN "maps/ProceduralFacility_7x7_pool.blk"
ASSERT @ - PFacTplData7x7Pool == 49
PFacTplData7x7TreerockCombinedroom:
    INCBIN "maps/ProceduralFacility_7x7_treerock_combinedroom.blk"
ASSERT @ - PFacTplData7x7TreerockCombinedroom == 49
PFacTplData8x3BlockRoom:
    INCBIN "maps/ProceduralFacility_8x3_block_room.blk"
ASSERT @ - PFacTplData8x3BlockRoom == 24
PFacTplData8x3ServerRoom:
    INCBIN "maps/ProceduralFacility_8x3_server_room.blk"
ASSERT @ - PFacTplData8x3ServerRoom == 24
PFacTplData8x3ServerrockRoom:
    INCBIN "maps/ProceduralFacility_8x3_serverrock_room.blk"
ASSERT @ - PFacTplData8x3ServerrockRoom == 24
PFacTplData8x4BlockserverCombinedroom:
    INCBIN "maps/ProceduralFacility_8x4_blockserver_combinedroom.blk"
ASSERT @ - PFacTplData8x4BlockserverCombinedroom == 32
PFacTplData8x4TableservertreeRoom:
    INCBIN "maps/ProceduralFacility_8x4_tableservertree_room.blk"
ASSERT @ - PFacTplData8x4TableservertreeRoom == 32
PFacTplData8x5CombinedtableRockRoom:
    INCBIN "maps/ProceduralFacility_8x5_combinedtable_rock_room.blk"
ASSERT @ - PFacTplData8x5CombinedtableRockRoom == 40
PFacTplData8x6RockCombinedroom:
    INCBIN "maps/ProceduralFacility_8x6_rock_combinedroom.blk"
ASSERT @ - PFacTplData8x6RockCombinedroom == 48
PFacTplData8x7PoolRoom:
    INCBIN "maps/ProceduralFacility_8x7_pool_room.blk"
ASSERT @ - PFacTplData8x7PoolRoom == 56
PFacTplData9x5BlockrockRoom:
    INCBIN "maps/ProceduralFacility_9x5_blockrock_room.blk"
ASSERT @ - PFacTplData9x5BlockrockRoom == 45
PFacTplData9x7TreerockCombinedroom:
    INCBIN "maps/ProceduralFacility_9x7_treerock_combinedroom.blk"
ASSERT @ - PFacTplData9x7TreerockCombinedroom == 63

; generated by tools/gen_facility_room_table.py from tools/pyboy_smoke/artifacts/facility_fullroom_audit.txt


DEF PFAC_LARGE_DECOR_COUNT EQU 8
; Interior-only large-decor descriptors: width, height, payload pointer.
; These may be placed in any larger compatible middle-room interior. They do
; not own or replace the room's surrounding wall ring.
PFacLargeDecorDescriptors:
    db 1, 3
    dw PFacLargeDecor1x3DoubleTableTree
    db 2, 1
    dw PFacLargeDecor2x1DoubleTable
    db 2, 2
    dw PFacLargeDecor2x2RockTree
    db 2, 3
    dw PFacLargeDecor2x3Block
    db 3, 2
    dw PFacLargeDecor3x2Tree
    db 3, 3
    dw PFacLargeDecor3x3BlockRock
    db 3, 3
    dw PFacLargeDecor3x3RockTree
    db 3, 3
    dw PFacLargeDecor3x3TripleBigTable
PFacLargeDecor1x3DoubleTableTree:
    INCBIN "maps/ProceduralFacility_1x3_doubletabletree_decor.blk"
ASSERT @ - PFacLargeDecor1x3DoubleTableTree == 3
PFacLargeDecor2x1DoubleTable:
    INCBIN "maps/ProceduralFacility_2x1_doubletable_decor.blk"
ASSERT @ - PFacLargeDecor2x1DoubleTable == 2
PFacLargeDecor2x2RockTree:
    INCBIN "maps/ProceduralFacility_2x2_rocktree_decor.blk"
ASSERT @ - PFacLargeDecor2x2RockTree == 4
PFacLargeDecor2x3Block:
    INCBIN "maps/ProceduralFacility_2x3_block_decor.blk"
ASSERT @ - PFacLargeDecor2x3Block == 6
PFacLargeDecor3x2Tree:
    INCBIN "maps/ProceduralFacility_3x2_tree_decor.blk"
ASSERT @ - PFacLargeDecor3x2Tree == 6
PFacLargeDecor3x3BlockRock:
    INCBIN "maps/ProceduralFacility_3x3_blockrock_decor.blk"
ASSERT @ - PFacLargeDecor3x3BlockRock == 9
PFacLargeDecor3x3RockTree:
    INCBIN "maps/ProceduralFacility_3x3_rocktree_decor.blk"
ASSERT @ - PFacLargeDecor3x3RockTree == 9
PFacLargeDecor3x3TripleBigTable:
    INCBIN "maps/ProceduralFacility_3x3_triplebigtable_decor.blk"
ASSERT @ - PFacLargeDecor3x3TripleBigTable == 9

ASSERT PFAC_SIZE <= PFAC_STRIDE
ASSERT PFAC_ROOM_MAX * PFAC_ROOM_STRIDE <= 81

; wBuffer scratch offsets. Facility never runs concurrently with cave/cemetery/
; forest generation, so it reuses the same 30-byte wBuffer window they use
; (ram/wram.asm: wBuffer:: ds 30 - offsets 0-29 are the entire budget).
DEF wPFacTargetBaseLo EQU 0
DEF wPFacTargetBaseHi EQU 1
DEF wPFacCurX         EQU 2   ; block-space X for PFacWriteBlock/PFacReadBlock
DEF wPFacCurY         EQU 3   ; block-space Y

; Room count persists across the WHOLE pipeline (placement through item
; placement), so it gets a fixed offset outside the per-phase reuse window
; below. Always ends at PFAC_ROOM_MAX once placement finishes (see header note
; on the W=0 "unplaced slot" sentinel).
DEF wPFacRoomCount    EQU 25

; --- Per-phase scratch (offsets 4-24). Phases never run concurrently (mirrors
; the cave/forest/cemetery convention), so each phase freely reuses this same
; numeric range under its own names. Room-placement and corridor-carving
; (pending, see header note) may reuse 4-24 too, as long as they don't touch
; offset 25 (wPFacRoomCount) or write invalid room records. ---

; PFacStampRoomFloors / PFacEncloseRooms / PFacPlaceItems:
DEF wPFacRmIdx        EQU 4   ; room loop index (Stamp/Enclose)
DEF wPFacRmX          EQU 5   ; loaded room record: X
DEF wPFacRmY          EQU 6   ; loaded room record: Y
DEF wPFacRmW          EQU 7   ; loaded room record: W
DEF wPFacRmH          EQU 8   ; loaded room record: H
DEF wPFacRmCounter    EQU 9   ; inner row/col loop counter (Stamp/Enclose)
DEF wPFacBallIdx      EQU 10  ; PFacPlaceItems: item-room loop index (0-3)
DEF wPFacItemRetry    EQU 11  ; PFacPlaceItems: item-dedup retry counter
DEF wPFacItemTemp     EQU 12  ; 4 bytes (12-15): rolled item IDs. PFacFinalize's
                              ; existing bake step copies this to
                              ; sProcFacilityBallItems by name, unchanged.
DEF wPFacItemCheckX   EQU 16  ; item-anchor adjacency check: saved block X
DEF wPFacItemCheckY   EQU 17  ; item-anchor adjacency check: saved block Y
DEF wPFacFakeRoomId   EQU 18  ; PFacPlaceFakeBalls: current middle-room id
DEF wPFacFakeRoomTries EQU 19 ; rooms remaining in the circular scan
DEF wPFacFakeReusePass EQU 20 ; 0 = distinct rooms only, 1 = reuse allowed

; Corridor-wall and doorway-jamb passes. These run before item placement, so
; offsets 16-24 are phase-local and do not overlap the four rolled item bytes.
DEF wPFacLoopX        EQU 16
DEF wPFacLoopY        EQU 17
DEF wPFacFlags        EQU 18
DEF wPFacDX           EQU 19
DEF wPFacDY           EQU 20
DEF wPFacFlankExpect  EQU 21
DEF wPFacFlankFirst   EQU 22
DEF wPFacFlankSecond  EQU 23

; Room-placement phase (PFacPlaceEntryRoom/PFacPlaceExitRoom/PFacPlaceMiddleRooms
; and their helpers). Reuses 4-15; must not touch 25 (wPFacRoomCount).
DEF wPFacPlaceId      EQU 4   ; id of the room being placed / init loop var
DEF wPFacCandX        EQU 5   ; candidate room rect
DEF wPFacCandY        EQU 6
DEF wPFacCandW        EQU 7
DEF wPFacCandH        EQU 8
DEF wPFacParent       EQU 9   ; chosen parent id for the candidate
DEF wPFacRetry        EQU 10  ; placement retry counter
DEF wPFacScanId       EQU 11  ; overlap/parent/exit scan index
DEF wPFacBX           EQU 12  ; scanned room B rect (overlap test) / exit-parent temps
DEF wPFacBY           EQU 13
DEF wPFacBW           EQU 14
DEF wPFacBH           EQU 15

ASSERT wPFacItemTemp + 3 < 30
ASSERT wPFacFlankSecond < 30
ASSERT wPFacRoomCount < 30
; Corridor phase (PFacCarveCorridors/PFacCarveEntryCorridor). Same 4-8 window,
; different names (placement is finished by the time corridors run).
DEF wPFacCorId        EQU 4   ; source room whose corridor we're carving
DEF wPFacCorTX        EQU 5   ; target center X
DEF wPFacCorTY        EQU 6   ; target center Y

; Full-room premade phase (PFacSelectPremadeMiddleRooms, which also stamps).
; Runs between the two corridor passes: room placement and the first corridor
; plan are both finished, and item rolling (12-15) has not started, so 10-17
; are free. wPFacRmX/Y/W/H (5-8) and wPFacRmCounter (9) stay live across it.
DEF wPFacTplW         EQU 10  ; selected footprint width  (= RmW + 2)
DEF wPFacTplH         EQU 11  ; selected footprint height (= RmH + 2)
DEF wPFacTplPtrLo     EQU 12  ; payload cursor, advanced one block at a time
DEF wPFacTplPtrHi     EQU 13
DEF wPFacTplRow       EQU 14  ; blit row counter
DEF wPFacTplCol       EQU 15  ; blit / perimeter-scan column counter
DEF wPFacTplFirst     EQU 16  ; first descriptor index of the matching size group
DEF wPFacTplSX        EQU 17  ; absolute socket column (RmX + RmW/2)
DEF wPFacTplSY        EQU 18  ; absolute socket row    (RmY + RmH/2)
DEF wPFacTplNeed      EQU 19  ; N/E/S/W sockets this room's corridors actually use
DEF wPFacTplCount     EQU 20  ; descriptors in the matching size group
DEF wPFacTplPick      EQU 21  ; countdown to the chosen eligible descriptor
DEF wPFacTplItemOnly  EQU 22  ; non-zero for item rooms 1-4 (hub must be an anchor)
ASSERT wPFacTplItemOnly < wPFacRoomCount

; PFacDecorateExploreRooms. Runs after item placement; offsets 12-15 remain
; untouched because PFacFinalize still needs the rolled item IDs there.
DEF wPFacDecorId      EQU 16
DEF wPFacDecorX       EQU 17
DEF wPFacDecorY       EQU 18
DEF wPFacDecorW       EQU 19
DEF wPFacDecorH       EQU 20
DEF wPFacDecorType    EQU 21
DEF wPFacDecorCenterX EQU 23
DEF wPFacDecorCenterY EQU 24

; PFacPlaceLargeDecor. Runs after sentinel finalization and before item
; placement. Item coordinates/IDs are not yet using offsets 9-24.
DEF wPFacLargeTemplate EQU 9
DEF wPFacLargeTries    EQU 10
DEF wPFacLargeW        EQU 11
DEF wPFacLargeH        EQU 12
DEF wPFacLargePtrLo    EQU 13
DEF wPFacLargePtrHi    EQU 14
DEF wPFacLargeOffX     EQU 15
DEF wPFacLargeOffY     EQU 16
DEF wPFacLargeRow      EQU 17
DEF wPFacLargeCol      EQU 18
DEF wPFacLargeCenterX  EQU 19
DEF wPFacLargeCenterY  EQU 20
DEF wPFacLargeMaxX     EQU 21
DEF wPFacLargeMaxY     EQU 22
DEF wPFacLargeBlock    EQU 23
DEF wPFacLargeDoors    EQU 24 ; N/E/S/W bits for actual finalized door openings
ASSERT wPFacLargeDoors < wPFacRoomCount

; ============================================================
; PFacRowOffsetTable / PFacWriteBlock / PFacReadBlock / PFacRoomRecordAddr
; Shared primitives used by every generation phase.
; ============================================================
PFacRowOffsetTable:
    FOR pfac_row, PFAC_SIZE
    dw pfac_row * PFAC_STRIDE
    ENDR

; INPUT: a = block ID; [wBuffer+wPFacCurX/Y] = logical coords (0-19). Preserves BC.
; Invalid coordinates are ignored so a failed placement cannot index past the
; row table and corrupt unrelated WRAM.
PFacWriteBlock:
    push af
    ld a, [wBuffer + wPFacCurX]
    cp PFAC_SIZE
    jr nc, .skip
    ld a, [wBuffer + wPFacCurY]
    cp PFAC_SIZE
    jr nc, .skip
    pop af
    push af
    push bc
    ld a, [wBuffer + wPFacTargetBaseLo]
    ld l, a
    ld a, [wBuffer + wPFacTargetBaseHi]
    ld h, a
    push hl
    ld a, [wBuffer + wPFacCurY]
    add a, a
    ld c, a
    ld b, 0
    ld hl, PFacRowOffsetTable
    add hl, bc
    ld a, [hli]
    ld e, a
    ld a, [hl]
    ld d, a
    pop hl
    add hl, de
    ld a, [wBuffer + wPFacCurX]
    add a, l
    ld l, a
    jr nc, .noCarry
    inc h
.noCarry
    pop bc
    pop af
    ld [hl], a
    ret
.skip
    pop af
    ret

; INPUT: [wBuffer+wPFacCurX/Y] = logical coords. OUTPUT: a = block value. Preserves BC.
; Invalid coordinates read as a solid wall instead of reading outside the map.
PFacReadBlock:
    ld a, [wBuffer + wPFacCurX]
    cp PFAC_SIZE
    jr nc, .oob
    ld a, [wBuffer + wPFacCurY]
    cp PFAC_SIZE
    jr nc, .oob
    push bc
    ld a, [wBuffer + wPFacTargetBaseLo]
    ld l, a
    ld a, [wBuffer + wPFacTargetBaseHi]
    ld h, a
    push hl
    ld a, [wBuffer + wPFacCurY]
    add a, a
    ld c, a
    ld b, 0
    ld hl, PFacRowOffsetTable
    add hl, bc
    ld a, [hli]
    ld e, a
    ld a, [hl]
    ld d, a
    pop hl
    add hl, de
    ld a, [wBuffer + wPFacCurX]
    add a, l
    ld l, a
    jr nc, .noCarry
    inc h
.noCarry
    ld a, [hl]
    pop bc
    ret

.oob
    ld a, PFAC_WALL
    ret
; INPUT: a = room id (0..PFAC_ROOM_MAX-1). OUTPUT: hl = address of that room's
; 6-byte record in sProcFacilityGenScratch. Clobbers de.
PFacRoomRecordAddr:
    ld h, 0
    ld l, a
    add hl, hl      ; hl = id*2
    ld d, h
    ld e, l         ; de = id*2
    add hl, hl      ; hl = id*4
    add hl, de      ; hl = id*4 + id*2 = id*6
    ld de, sProcFacilityGenScratch
    add hl, de
    ret

; ============================================================
; PFacFillUntouched
; Seed the whole 20x20 player area with PFAC_UNTOUCHED so every later pass can
; tell "nothing has claimed this cell yet" from real content. The .blk's floor
; fill is only a placeholder; this always overwrites it. Border padding
; (already PFAC_WALL from the object file's border block) is untouched.
; ============================================================
PFacFillUntouched:
    ld hl, wOverworldMap + PFAC_BASE
    ld b, PFAC_SIZE
.rowLoop
    push bc
    ld c, PFAC_SIZE
.colLoop
    ld a, PFAC_UNTOUCHED
    ld [hli], a
    dec c
    jr nz, .colLoop
    ld a, l
    add a, PFAC_STRIDE - PFAC_SIZE
    ld l, a
    jr nc, .noCarry
    inc h
.noCarry
    pop bc
    dec b
    jr nz, .rowLoop
    ret

; ============================================================
; PFacStampRoomFloors
; Fills every registered room's floor rect with PFAC_ROOMFLOOR ($F0). Rooms are
; read from sProcFacilityGenScratch (populated by PFacPlaceEntryRoom/
; PFacPlaceExitRoom/PFacPlaceMiddleRooms). A W=0 record (an explore room that
; failed to place) is skipped. Runs after all placement, before corridors, so
; PFacCarveCorridors can test "is this cell already room floor".
; ============================================================
; ============================================================
; PFacSelectPremadeMiddleRooms
; Selects AND stamps full-room premades for middle rooms 1-10. Entry 0 and exit
; 11 are excluded: their spawn, edge-socket, warp, and boss-approach lifecycles
; have no template validation yet.
;
; Selection and stamping are one pass on purpose. The chosen descriptor index is
; then never stored anywhere - it lives in a register for the length of one room
; - because every later pass (enclosure, corner validation, isolated-corner
; cleanup, socket re-cutting, decoration) only needs to know THAT a template owns
; the footprint, which is what the room record's Type bit 7 already records. The
; room record has no spare field for an index, and this avoids inventing one.
;
; Runs between the two PFacCarveCorridors passes, which is what makes the socket
; test possible: the complete corridor plan is already drawn on the map, so the
; room's OWN perimeter tells us which sides it actually needs, and the second
; pass reopens the sockets the stamp covered.
; ============================================================
PFacSelectPremadeMiddleRooms:
    ld b, 1
.loop
    push bc
    ld a, b
    call PFacRoomRecordAddr
    ld a, [hli]
    ld [wBuffer + wPFacRmX], a
    ld a, [hli]
    ld [wBuffer + wPFacRmY], a
    ld a, [hli]
    ld [wBuffer + wPFacRmW], a
    and a
    jr z, .next                 ; unplaced slot
    ld a, [hl]
    ld [wBuffer + wPFacRmH], a

    ; Item rooms 1-4 may only take a template whose hub is itself a legal item
    ; anchor. PFacPlaceItems falls back unconditionally to the room center when
    ; its random samples miss, and the room center IS the hub, so a template
    ; with an occupied hub would drop that room's pokeball onto a solid block.
    ld a, b
    cp 5
    ld a, 0
    jr nc, .roleStored
    inc a
.roleStored
    ld [wBuffer + wPFacTplItemOnly], a

    ; Footprint = interior + the one-block generic ring on each side.
    ld a, [wBuffer + wPFacRmW]
    add a, 2
    ld [wBuffer + wPFacTplW], a
    sub 3
    ld c, a                     ; c = W - 3
    ld a, [wBuffer + wPFacRmH]
    add a, 2
    ld [wBuffer + wPFacTplH], a
    sub 3
    ld e, a                     ; e = H - 3

    ; group entry = PFacRoomGroupTable + ((W-3)*7 + (H-3)) * 2
    ld a, c
    add a, a
    add a, a
    add a, a                    ; 8*(W-3)
    sub c                       ; 7*(W-3)
    add a, e
    add a, a                    ; *PFAC_TPL_GROUP_STRIDE
    ld c, a
    ld b, 0
    ld hl, PFacRoomGroupTable
    add hl, bc
    ld a, [hli]
    ld [wBuffer + wPFacTplFirst], a
    ld a, [hl]
    ld [wBuffer + wPFacTplCount], a
    and a
    jr z, .next                 ; no template of this size, stay generic

    call PFacPremadePerimeterClear
    jr nc, .next
    call PFacChooseTemplate
    jr nc, .next                ; nothing in the group fits this room's sockets

    inc hl
    inc hl
    inc hl
    inc hl                      ; hl -> descriptor payload pointer
    ld a, [hli]
    ld [wBuffer + wPFacTplPtrLo], a
    ld a, [hl]
    ld [wBuffer + wPFacTplPtrHi], a
    call PFacStampPremadeFootprint

    pop bc
    push bc
    ld a, b
    call PFacRoomRecordAddr
    ld de, 5
    add hl, de
    set 7, [hl]
.next
    pop bc
    inc b
    ld a, b
    cp 11
    jp nz, .loop
    ret

; ============================================================
; PFacChooseTemplate
; Picks one descriptor uniformly from the matching size group, considering only
; descriptors that can open every side this room's corridors actually use and,
; for item rooms, that carry PFAC_TPL_ITEM.
;
; Two deterministic passes (count, then take the nth) rather than rejection
; sampling: groups are small, and a bounded retry loop would both bias the
; choice and consume a variable number of RNG draws, which would shift every
; later roll in the generation and drift the deterministic corpus.
;
; INPUT: wPFacTplFirst, wPFacTplCount, wPFacTplNeed, wPFacTplItemOnly.
; OUTPUT: carry set and hl -> chosen descriptor; carry clear if none qualify.
; Clobbers a, bc, de, hl.
; ============================================================
PFacChooseTemplate:
    call .firstDescriptor       ; hl -> group start, b = group count
    ld c, 0
.countLoop
    call .eligible
    jr nc, .countNext
    inc c
.countNext
    REPT PFAC_TPL_STRIDE
    inc hl
    ENDR
    dec b
    jr nz, .countLoop
    ld a, c
    and a
    ret z                       ; carry already clear

    ld c, a
    call Rangerandom            ; a = 0 .. eligible-1
    ld [wBuffer + wPFacTplPick], a
    call .firstDescriptor
.pickLoop
    call .eligible
    jr nc, .pickNext
    ld a, [wBuffer + wPFacTplPick]
    and a
    jr z, .found
    dec a
    ld [wBuffer + wPFacTplPick], a
.pickNext
    REPT PFAC_TPL_STRIDE
    inc hl
    ENDR
    dec b
    jr nz, .pickLoop
    ; Unreachable: the second pass sees exactly the eligible set the first one
    ; counted. Fail closed to the generic room rather than stamp hl blindly.
    and a
    ret
.found
    scf
    ret

.firstDescriptor
    ld a, [wBuffer + wPFacTplFirst]
    ld h, 0
    ld l, a
    ld d, h
    ld e, l
    add hl, hl                  ; 2i
    add hl, de                  ; 3i
    add hl, hl                  ; 6i = i * PFAC_TPL_STRIDE
    ASSERT PFAC_TPL_STRIDE == 6
    ld de, PFacRoomDescriptors
    add hl, de
    ld a, [wBuffer + wPFacTplCount]
    ld b, a
    ret

.eligible
    ; Carry set if the descriptor at hl can serve this room. Preserves hl and b.
    push hl
    inc hl
    inc hl
    ld a, [hli]                 ; +2 socket mask
    cpl
    ld d, a
    ld a, [wBuffer + wPFacTplNeed]
    and d
    jr nz, .reject              ; room needs a side this template cannot open
    ld a, [wBuffer + wPFacTplItemOnly]
    and a
    jr z, .accept
    ld a, [hl]                  ; +3 flags
    and PFAC_TPL_ITEM
    jr z, .reject
.accept
    pop hl
    scf
    ret
.reject
    pop hl
    and a
    ret

; ============================================================
; PFacPremadePerimeterClear
; Decides whether a template may own this footprint at all, and reports which
; sides it would have to open.
;
; Carry CLEAR: a corridor already crosses the footprint perimeter somewhere
; that is not one of the four canonical socket cells. The stamp would seal that
; corridor and PFacTryCutPremadeSocket would not reopen it, so the room stays
; generic.
;
; Carry SET: wPFacTplNeed holds the N/E/S/W mask of sockets that carry a
; corridor and therefore must be re-cuttable through whichever template is
; chosen. Sockets sit at the room's own center row/column, which is exactly
; where PFacRoomCenter aims corridors.
;
; The scan is ring-only rather than a full rect sweep because the caller runs
; inside the layout-retry loop, where sweeping ten whole footprints per attempt
; would cost real frames.
;
; INPUT: wPFacRmX/RmY/RmW/RmH (floor interior), wPFacTplW/TplH (footprint).
; Clobbers a, bc, de, hl, wPFacCurX/CurY, wPFacTplCol/TplSX/TplSY/TplNeed.
; ============================================================
PFacPremadePerimeterClear:
    ld a, [wBuffer + wPFacRmW]
    srl a                       ; W/2, matching PFacRoomCenter exactly
    ld hl, wBuffer + wPFacRmX
    add a, [hl]
    ld [wBuffer + wPFacTplSX], a
    ld a, [wBuffer + wPFacRmH]
    srl a
    ld hl, wBuffer + wPFacRmY
    add a, [hl]
    ld [wBuffer + wPFacTplSY], a
    ld c, 0                     ; accumulated required-socket mask

    ; Top row, then bottom row: full footprint width. PFacReadBlock preserves
    ; bc, so b (the side under test) and c (the mask) survive the whole scan.
    ld a, [wBuffer + wPFacRmY]
    dec a
    ld [wBuffer + wPFacCurY], a
    ld b, PFAC_SOCKET_N
    call .scanRow
    ret nc
    ld a, [wBuffer + wPFacRmY]
    ld hl, wBuffer + wPFacRmH
    add a, [hl]
    ld [wBuffer + wPFacCurY], a
    ld b, PFAC_SOCKET_S
    call .scanRow
    ret nc

    ; Left column, then right column: interior rows only, the corners having
    ; already been covered by the two row scans.
    ld a, [wBuffer + wPFacRmX]
    dec a
    ld [wBuffer + wPFacCurX], a
    ld b, PFAC_SOCKET_W
    call .scanCol
    ret nc
    ld a, [wBuffer + wPFacRmX]
    ld hl, wBuffer + wPFacRmW
    add a, [hl]
    ld [wBuffer + wPFacCurX], a
    ld b, PFAC_SOCKET_E
    call .scanCol
    ret nc

    ld a, c
    ld [wBuffer + wPFacTplNeed], a
    scf
    ret

.scanRow
    ld a, [wBuffer + wPFacRmX]
    dec a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacTplW]
    ld [wBuffer + wPFacTplCol], a
.rowCell
    ld a, [wBuffer + wPFacCurX]
    ld hl, wBuffer + wPFacTplSX
    cp [hl]
    jr nz, .rowWall
    call PFacReadBlock          ; the socket cell itself
    cp PFAC_UNTOUCHED
    jr z, .rowNext
    ld a, c                     ; a corridor arrives here: this side is required
    or b
    ld c, a
    jr .rowNext
.rowWall
    call PFacReadBlock
    cp PFAC_UNTOUCHED
    jr nz, .blocked
.rowNext
    ld hl, wBuffer + wPFacCurX
    inc [hl]
    ld hl, wBuffer + wPFacTplCol
    dec [hl]
    jr nz, .rowCell
    scf
    ret

.scanCol
    ld a, [wBuffer + wPFacRmY]  ; first interior row
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacRmH]
    ld [wBuffer + wPFacTplCol], a
.colCell
    ld a, [wBuffer + wPFacCurY]
    ld hl, wBuffer + wPFacTplSY
    cp [hl]
    jr nz, .colWall
    call PFacReadBlock
    cp PFAC_UNTOUCHED
    jr z, .colNext
    ld a, c
    or b
    ld c, a
    jr .colNext
.colWall
    call PFacReadBlock
    cp PFAC_UNTOUCHED
    jr nz, .blocked
.colNext
    ld hl, wBuffer + wPFacCurY
    inc [hl]
    ld hl, wBuffer + wPFacTplCol
    dec [hl]
    jr nz, .colCell
    scf
    ret

.blocked
    and a
    ret

; ============================================================
; PFacStampPremadeFootprint
; Blits the selected descriptor's payload over the room's full footprint. The
; footprint's top-left is one block up and left of the floor interior, which is
; exactly where PFacEncloseRooms would otherwise have written the generic ring.
;
; INPUT: wPFacRmX/RmY = floor-interior top-left, wPFacTplW/TplH = footprint
; size, wPFacTplPtrLo/Hi = payload start. Consumes the pointer as it walks.
; Clobbers a, hl and wPFacCurX/CurY, wPFacRmCounter, wPFacTplRow.
; ============================================================
PFacStampPremadeFootprint:
    ld a, [wBuffer + wPFacTplH]
    ld [wBuffer + wPFacTplRow], a
    ld a, [wBuffer + wPFacRmY]
    dec a
    ld [wBuffer + wPFacCurY], a
.row
    ld a, [wBuffer + wPFacRmX]
    dec a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacTplW]
    ld [wBuffer + wPFacRmCounter], a
.col
    ld a, [wBuffer + wPFacTplPtrLo]
    ld l, a
    ld a, [wBuffer + wPFacTplPtrHi]
    ld h, a
    ld a, [hli]
    ld b, h
    ld c, l                     ; PFacWriteBlock clobbers hl and de but keeps
    call PFacWriteBlock         ; bc, so park the advanced cursor there
    ld a, c
    ld [wBuffer + wPFacTplPtrLo], a
    ld a, b
    ld [wBuffer + wPFacTplPtrHi], a
    ld hl, wBuffer + wPFacCurX
    inc [hl]
    ld hl, wBuffer + wPFacRmCounter
    dec [hl]
    jr nz, .col
    ld hl, wBuffer + wPFacCurY
    inc [hl]
    ld hl, wBuffer + wPFacTplRow
    dec [hl]
    jr nz, .row
    ret
PFacStampRoomFloors:
    xor a
    ld [wBuffer + wPFacRmIdx], a
.roomLoop
    ld a, [wBuffer + wPFacRmIdx]
    ld hl, wBuffer + wPFacRoomCount
    cp [hl]
    ret nc

    ld a, [wBuffer + wPFacRmIdx]
    call PFacRoomRecordAddr
    ld a, [hli]
    ld [wBuffer + wPFacRmX], a
    ld a, [hli]
    ld [wBuffer + wPFacRmY], a
    ld a, [hli]
    ld [wBuffer + wPFacRmW], a
    ld a, [hl]
    ld [wBuffer + wPFacRmH], a

    ld a, [wBuffer + wPFacRmW]
    and a
    jr z, .roomNext            ; unplaced slot, skip

    ld a, [wBuffer + wPFacRmY]
    ld [wBuffer + wPFacCurY], a
.rowLoop
    ld a, [wBuffer + wPFacRmX]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmW]
    ld [wBuffer + wPFacRmCounter], a
.colLoop
    ld a, PFAC_ROOMFLOOR
    call PFacWriteBlock
    ld a, [wBuffer + wPFacCurX]
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmCounter]
    dec a
    ld [wBuffer + wPFacRmCounter], a
    jr nz, .colLoop

    ld a, [wBuffer + wPFacRmY]
    ld b, a
    ld a, [wBuffer + wPFacRmH]
    add a, b                    ; a = Y + H (exclusive row bound)
    ld c, a
    ld a, [wBuffer + wPFacCurY]
    inc a
    ld [wBuffer + wPFacCurY], a
    cp c
    jr c, .rowLoop

.roomNext
    ld a, [wBuffer + wPFacRmIdx]
    inc a
    ld [wBuffer + wPFacRmIdx], a
    jp .roomLoop

; ============================================================
; PFacEncloseRooms
; For every registered room (W=0 slots skipped), draws the directional 9-slice
; wall ring on the cells immediately outside its floor rect (X-1..X+W,
; Y-1..Y+H). A ring cell already PFAC_CORRIDOR or PFAC_ROOMFLOOR (a doorway
; carved by PFacCarveCorridors/PFacCarveEntryCorridor, or another room's floor)
; is left untouched - that's how doorways survive. Everything else in the ring
; becomes a straight wall (65/68/70/73) or corner post (64/66/72/74). Relies on
; every placed room's floor rect staying within blocks 1..18 (guaranteed by
; PFacPlaceEntryRoom/PFacPlaceExitRoom/PFacPlaceMiddleRooms), so the ring never
; leaves the 20x20 player area.
; ============================================================
PFacEncloseRooms:
    xor a
    ld [wBuffer + wPFacRmIdx], a
.roomLoop
    ld a, [wBuffer + wPFacRmIdx]
    ld hl, wBuffer + wPFacRoomCount
    cp [hl]
    ret nc

    ld a, [wBuffer + wPFacRmIdx]
    call PFacRoomRecordAddr
    ld a, [hli]
    ld [wBuffer + wPFacRmX], a
    ld a, [hli]
    ld [wBuffer + wPFacRmY], a
    ld a, [hli]
    ld [wBuffer + wPFacRmW], a
    ld a, [hl]
    ld [wBuffer + wPFacRmH], a

    ld a, [wBuffer + wPFacRmW]
    and a
    jp z, .roomNext            ; unplaced slot, skip
    ld a, [wBuffer + wPFacRmIdx]
    call PFacRoomRecordAddr
    ld de, 5
    add hl, de
    bit 7, [hl]
    jp nz, .roomNext           ; complete premade owns its perimeter

    ; --- Top edge (row Y-1, cols X..X+W-1): PFAC_W_TOP ---
    ld a, [wBuffer + wPFacRmY]
    dec a
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacRmX]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmW]
    ld [wBuffer + wPFacRmCounter], a
.topLoop
    ld a, PFAC_W_TOP
    call PFacRingWrite
    ld a, [wBuffer + wPFacCurX]
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmCounter]
    dec a
    ld [wBuffer + wPFacRmCounter], a
    jr nz, .topLoop

    ; --- Bottom edge (row Y+H, cols X..X+W-1): PFAC_W_BOTTOM ---
    ld a, [wBuffer + wPFacRmY]
    ld b, a
    ld a, [wBuffer + wPFacRmH]
    add a, b
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacRmX]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmW]
    ld [wBuffer + wPFacRmCounter], a
.bottomLoop
    ld a, PFAC_W_BOTTOM
    call PFacRingWrite
    ld a, [wBuffer + wPFacCurX]
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmCounter]
    dec a
    ld [wBuffer + wPFacRmCounter], a
    jr nz, .bottomLoop

    ; --- Left edge (col X-1, rows Y..Y+H-1): PFAC_W_LEFT ---
    ld a, [wBuffer + wPFacRmX]
    dec a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmY]
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacRmH]
    ld [wBuffer + wPFacRmCounter], a
.leftLoop
    ld a, PFAC_W_LEFT
    call PFacRingWrite
    ld a, [wBuffer + wPFacCurY]
    inc a
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacRmCounter]
    dec a
    ld [wBuffer + wPFacRmCounter], a
    jr nz, .leftLoop

    ; --- Right edge (col X+W, rows Y..Y+H-1): PFAC_W_RIGHT ---
    ld a, [wBuffer + wPFacRmX]
    ld b, a
    ld a, [wBuffer + wPFacRmW]
    add a, b
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmY]
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacRmH]
    ld [wBuffer + wPFacRmCounter], a
.rightLoop
    ld a, PFAC_W_RIGHT
    call PFacRingWrite
    ld a, [wBuffer + wPFacCurY]
    inc a
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacRmCounter]
    dec a
    ld [wBuffer + wPFacRmCounter], a
    jr nz, .rightLoop

    ; --- 4 corners ---
    ld a, [wBuffer + wPFacRmX]
    dec a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmY]
    dec a
    ld [wBuffer + wPFacCurY], a
    ld a, PFAC_C_TL
    call PFacRingWrite

    ld a, [wBuffer + wPFacRmX]
    ld b, a
    ld a, [wBuffer + wPFacRmW]
    add a, b
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmY]
    dec a
    ld [wBuffer + wPFacCurY], a
    ld a, PFAC_C_TR
    call PFacRingWrite

    ld a, [wBuffer + wPFacRmX]
    dec a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmY]
    ld b, a
    ld a, [wBuffer + wPFacRmH]
    add a, b
    ld [wBuffer + wPFacCurY], a
    ld a, PFAC_C_BL
    call PFacRingWrite

    ld a, [wBuffer + wPFacRmX]
    ld b, a
    ld a, [wBuffer + wPFacRmW]
    add a, b
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmY]
    ld b, a
    ld a, [wBuffer + wPFacRmH]
    add a, b
    ld [wBuffer + wPFacCurY], a
    ld a, PFAC_C_BR
    call PFacRingWrite

.roomNext
    ld a, [wBuffer + wPFacRmIdx]
    inc a
    ld [wBuffer + wPFacRmIdx], a
    jp .roomLoop

; Writes A (a wall/corner block) to [wPFacCurX/Y] UNLESS that cell is already
; PFAC_CORRIDOR or PFAC_ROOMFLOOR (a doorway or another room's floor), in which
; case it's left untouched so the doorway survives.
PFacRingWrite:
    push af
    call PFacReadBlock
    cp PFAC_CORRIDOR
    jr z, .skip
    cp PFAC_ROOMFLOOR
    jr z, .skip
    pop af
    jp PFacWriteBlock
.skip
    pop af
    ret

; Carry set when every generated room still owns its four exact corner blocks.
; A mismatch means a planned center-to-center corridor crossed a diagonal ring
; corner. Rejecting that topology before decor/object RNG is safer and smaller
; than trying to patch a severed corridor after enclosure.
PFacValidateGeneratedCorners:
    xor a
    ld [wBuffer + wPFacRmIdx], a
.room
    ld a, [wBuffer + wPFacRmIdx]
    cp PFAC_ROOM_MAX
    jr nc, .valid
    call PFacRoomRecordAddr
    ld a, [hli]
    ld [wBuffer + wPFacRmX], a
    ld a, [hli]
    ld [wBuffer + wPFacRmY], a
    ld a, [hli]
    ld [wBuffer + wPFacRmW], a
    and a
    jr z, .next
    ld a, [hli]
    ld [wBuffer + wPFacRmH], a
    inc hl
    bit 7, [hl]
    jr nz, .next

    ld a, [wBuffer + wPFacRmX]
    dec a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmY]
    dec a
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_C_TL
    jr nz, .invalid

    ld a, [wBuffer + wPFacRmX]
    ld hl, wBuffer + wPFacRmW
    add a, [hl]
    ld [wBuffer + wPFacCurX], a
    call PFacReadBlock
    cp PFAC_C_TR
    jr nz, .invalid

    ld a, [wBuffer + wPFacRmY]
    ld hl, wBuffer + wPFacRmH
    add a, [hl]
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_C_BR
    jr nz, .invalid

    ld a, [wBuffer + wPFacRmX]
    dec a
    ld [wBuffer + wPFacCurX], a
    call PFacReadBlock
    cp PFAC_C_BL
    jr nz, .invalid
.next
    ld hl, wBuffer + wPFacRmIdx
    inc [hl]
    jr .room
.valid
    scf
    ret
.invalid
    and a
    ret

; Remove only generated ring corners that became completely isolated by
; legitimate openings on all four sides. Authored premade footprints are
; skipped, so their structural art is never normalized by this pass.
PFacRemoveIsolatedGeneratedCorners:
    xor a
    ld [wBuffer + wPFacRmIdx], a
.room
    ld a, [wBuffer + wPFacRmIdx]
    cp PFAC_ROOM_MAX
    ret nc
    call PFacRoomRecordAddr
    ld a, [hli]
    ld [wBuffer + wPFacRmX], a
    ld a, [hli]
    ld [wBuffer + wPFacRmY], a
    ld a, [hli]
    ld [wBuffer + wPFacRmW], a
    and a
    jr z, .next
    ld a, [hli]
    ld [wBuffer + wPFacRmH], a
    inc hl
    bit 7, [hl]
    jr nz, .next

    ld a, [wBuffer + wPFacRmX]
    dec a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmY]
    dec a
    ld [wBuffer + wPFacCurY], a
    call PFacRemoveCornerIfIsolated
    ld a, [wBuffer + wPFacRmX]
    ld hl, wBuffer + wPFacRmW
    add a, [hl]
    ld [wBuffer + wPFacCurX], a
    call PFacRemoveCornerIfIsolated
    ld a, [wBuffer + wPFacRmY]
    ld hl, wBuffer + wPFacRmH
    add a, [hl]
    ld [wBuffer + wPFacCurY], a
    call PFacRemoveCornerIfIsolated
    ld a, [wBuffer + wPFacRmX]
    dec a
    ld [wBuffer + wPFacCurX], a
    call PFacRemoveCornerIfIsolated
.next
    ld hl, wBuffer + wPFacRmIdx
    inc [hl]
    jr .room

PFacRemoveCornerIfIsolated:
    ld a, [wBuffer + wPFacCurX]
    ld [wBuffer + wPFacItemCheckX], a
    ld a, [wBuffer + wPFacCurY]
    ld [wBuffer + wPFacItemCheckY], a
    ld hl, wBuffer + wPFacCurX
    dec [hl]
    call PFacReadBlock
    cp PFAC_FLOOR
    jr nz, .restore
    ld a, [wBuffer + wPFacItemCheckX]
    inc a
    ld [wBuffer + wPFacCurX], a
    call PFacReadBlock
    cp PFAC_FLOOR
    jr nz, .restore
    ld a, [wBuffer + wPFacItemCheckX]
    ld [wBuffer + wPFacCurX], a
    ld hl, wBuffer + wPFacCurY
    dec [hl]
    call PFacReadBlock
    cp PFAC_FLOOR
    jr nz, .restore
    ld a, [wBuffer + wPFacItemCheckY]
    inc a
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_FLOOR
    jr nz, .restore
    ld a, [wBuffer + wPFacItemCheckX]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacItemCheckY]
    ld [wBuffer + wPFacCurY], a
    ld a, PFAC_FLOOR
    jp PFacWriteBlock
.restore
    ld a, [wBuffer + wPFacItemCheckX]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacItemCheckY]
    ld [wBuffer + wPFacCurY], a
    ret

; ============================================================
; PFacBuildCorridorWalls
; Classify untouched cells immediately beside corridor sentinels. Room rings
; are already complete and remain authoritative. This is the orthogonal subset
; of the 6baa4a29 classifier: N/S/E/W bits are 1/2/4/8. Opposite and ambiguous
; masks become PFAC_PENDING and resolve to floor after the cascade-safe scan.
; ============================================================
PFacBuildCorridorWalls:
    xor a
    ld [wBuffer + wPFacLoopY], a
.row
    xor a
    ld [wBuffer + wPFacLoopX], a
.col
    ld a, [wBuffer + wPFacLoopX]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacLoopY]
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_UNTOUCHED
    jr nz, .next
    call PFacClassifyCorridorWall
    call PFacWriteBlock
.next
    ld a, [wBuffer + wPFacLoopX]
    inc a
    ld [wBuffer + wPFacLoopX], a
    cp PFAC_SIZE
    jr nz, .col
    ld a, [wBuffer + wPFacLoopY]
    inc a
    ld [wBuffer + wPFacLoopY], a
    cp PFAC_SIZE
    jr nz, .row
    ret

PFacClassifyCorridorWall:
    ld a, [wBuffer + wPFacCurX]
    ld [wBuffer + wPFacDX], a
    ld a, [wBuffer + wPFacCurY]
    ld [wBuffer + wPFacDY], a
    xor a
    ld [wBuffer + wPFacFlags], a

    ; north
    ld a, [wBuffer + wPFacDY]
    and a
    jr z, .south
    dec a
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacDX]
    ld [wBuffer + wPFacCurX], a
    ld b, 1
    call PFacMarkCorridorNeighbor
.south
    ld a, [wBuffer + wPFacDY]
    cp PFAC_SIZE - 1
    jr z, .east
    inc a
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacDX]
    ld [wBuffer + wPFacCurX], a
    ld b, 2
    call PFacMarkCorridorNeighbor
.east
    ld a, [wBuffer + wPFacDX]
    cp PFAC_SIZE - 1
    jr z, .west
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacDY]
    ld [wBuffer + wPFacCurY], a
    ld b, 4
    call PFacMarkCorridorNeighbor
.west
    ld a, [wBuffer + wPFacDX]
    and a
    jr z, .result
    dec a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacDY]
    ld [wBuffer + wPFacCurY], a
    ld b, 8
    call PFacMarkCorridorNeighbor
.result
    ld a, [wBuffer + wPFacDX]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacDY]
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacFlags]
    and a
    jr z, PFacClassifyCorridorDiagonal
    ld c, a
    ld b, 0
    ld hl, PFacCorridorWallTable
    add hl, bc
    ld a, [hl]
    ret

; No cardinal corridor neighbor exists. A single diagonal corridor still needs
; a matching corner cap so the walkable half of the adjacent straight wall
; cannot open directly onto $2E at a path end or turn.
PFacClassifyCorridorDiagonal:
    ld a, [wBuffer + wPFacDX]
    and a
    jr z, .northEast
    ld a, [wBuffer + wPFacDY]
    and a
    jr z, .southWest
    dec a
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacDX]
    dec a
    ld [wBuffer + wPFacCurX], a
    call PFacReadBlock
    cp PFAC_CORRIDOR
    jr z, .useBR
.northEast
    ld a, [wBuffer + wPFacDX]
    cp PFAC_SIZE - 1
    jr z, .southWest
    ld a, [wBuffer + wPFacDY]
    and a
    jr z, .southEast
    dec a
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacDX]
    inc a
    ld [wBuffer + wPFacCurX], a
    call PFacReadBlock
    cp PFAC_CORRIDOR
    jr z, .useBL
.southWest
    ld a, [wBuffer + wPFacDX]
    and a
    jr z, .southEast
    ld a, [wBuffer + wPFacDY]
    cp PFAC_SIZE - 1
    jr z, .none
    inc a
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacDX]
    dec a
    ld [wBuffer + wPFacCurX], a
    call PFacReadBlock
    cp PFAC_CORRIDOR
    jr z, .useTR
.southEast
    ld a, [wBuffer + wPFacDX]
    cp PFAC_SIZE - 1
    jr z, .none
    ld a, [wBuffer + wPFacDY]
    cp PFAC_SIZE - 1
    jr z, .none
    inc a
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacDX]
    inc a
    ld [wBuffer + wPFacCurX], a
    call PFacReadBlock
    cp PFAC_CORRIDOR
    jr z, .useTL
.none
    ld a, PFAC_WALL
    jr .restore
.useBR
    ld a, PFAC_C_BR
    jr .restore
.useBL
    ld a, PFAC_C_BL
    jr .restore
.useTR
    ld a, PFAC_C_TR
    jr .restore
.useTL
    ld a, PFAC_C_TL
.restore
    push af
    ld a, [wBuffer + wPFacDX]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacDY]
    ld [wBuffer + wPFacCurY], a
    pop af
    ret

PFacMarkCorridorNeighbor:
    call PFacReadBlock
    cp PFAC_CORRIDOR
    ret nz
    ld a, [wBuffer + wPFacFlags]
    or b
    ld [wBuffer + wPFacFlags], a
    ret

PFacCorridorWallTable:
    ; 0, N, S, NS, E, NE, SE, NSE
    db PFAC_WALL, PFAC_W_BOTTOM, PFAC_W_TOP, PFAC_PENDING
    db PFAC_W_LEFT, PFAC_C_BL, PFAC_C_TL, PFAC_PENDING
    ; W, NW, SW, NSW, EW, NEW, SEW, NSEW
    db PFAC_W_RIGHT, PFAC_C_BR, PFAC_C_TR, PFAC_PENDING
    db PFAC_PENDING, PFAC_PENDING, PFAC_PENDING, PFAC_PENDING

; ============================================================
; PFacApplyDoorJambs
; A corridor sentinel directly beside room-floor marks a cut through that
; room's ring. Rewrite only the two still-plain wall flanks around that gap,
; preserving corners, existing jambs, and unrelated art. Mapping is the guarded
; doorway rule from 0640346a.
; ============================================================
PFacApplyDoorJambs:
    xor a
    ld [wBuffer + wPFacLoopY], a
.row
    xor a
    ld [wBuffer + wPFacLoopX], a
.col
    ld a, [wBuffer + wPFacLoopX]
    ld [wBuffer + wPFacCurX], a
    ld [wBuffer + wPFacDX], a
    ld a, [wBuffer + wPFacLoopY]
    ld [wBuffer + wPFacCurY], a
    ld [wBuffer + wPFacDY], a
    call PFacReadBlock
    cp PFAC_CORRIDOR
    call z, PFacJambDoorway
    ld a, [wBuffer + wPFacLoopX]
    inc a
    ld [wBuffer + wPFacLoopX], a
    cp PFAC_SIZE
    jr nz, .col
    ld a, [wBuffer + wPFacLoopY]
    inc a
    ld [wBuffer + wPFacLoopY], a
    cp PFAC_SIZE
    jr nz, .row
    ret
PFacJambDoorway:
    ld a, [wBuffer + wPFacCurX]
    ld [wBuffer + wPFacDX], a
    ld a, [wBuffer + wPFacCurY]
    ld [wBuffer + wPFacDY], a
    ; room floor north: doorway is in a bottom wall
    ld a, [wBuffer + wPFacDY]
    and a
    jr z, .south
    dec a
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacDX]
    ld [wBuffer + wPFacCurX], a
    call PFacReadBlock
    cp PFAC_ROOMFLOOR
    jr nz, .south
    ld a, PFAC_W_BOTTOM
    ld [wBuffer + wPFacFlankExpect], a
    ld a, PFAC_J_BOTTOM_W
    ld [wBuffer + wPFacFlankFirst], a
    ld a, PFAC_J_BOTTOM_E
    ld [wBuffer + wPFacFlankSecond], a
    jp PFacRewriteHorizontalFlanks
.south
    ld a, [wBuffer + wPFacDY]
    cp PFAC_SIZE - 1
    jr z, .east
    inc a
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacDX]
    ld [wBuffer + wPFacCurX], a
    call PFacReadBlock
    cp PFAC_ROOMFLOOR
    jr nz, .east
    ld a, PFAC_W_TOP
    ld [wBuffer + wPFacFlankExpect], a
    ld a, PFAC_J_TOP_W
    ld [wBuffer + wPFacFlankFirst], a
    ld a, PFAC_J_TOP_E
    ld [wBuffer + wPFacFlankSecond], a
    jp PFacRewriteHorizontalFlanks
.east
    ld a, [wBuffer + wPFacDX]
    cp PFAC_SIZE - 1
    jr z, .west
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacDY]
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_ROOMFLOOR
    jr nz, .west
    ld a, PFAC_W_LEFT
    ld [wBuffer + wPFacFlankExpect], a
    ld a, PFAC_J_LEFT_N
    ld [wBuffer + wPFacFlankFirst], a
    ld a, PFAC_J_LEFT_S
    ld [wBuffer + wPFacFlankSecond], a
    jp PFacRewriteVerticalFlanks
.west
    ld a, [wBuffer + wPFacDX]
    and a
    ret z
    dec a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacDY]
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_ROOMFLOOR
    ret nz
    ld a, PFAC_W_RIGHT
    ld [wBuffer + wPFacFlankExpect], a
    ld a, PFAC_J_RIGHT_N
    ld [wBuffer + wPFacFlankFirst], a
    ld a, PFAC_J_RIGHT_S
    ld [wBuffer + wPFacFlankSecond], a
    jp PFacRewriteVerticalFlanks

PFacRewriteHorizontalFlanks:
    ld a, [wBuffer + wPFacDY]
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacDX]
    dec a
    ld [wBuffer + wPFacCurX], a
    call PFacReadBlock
    ld hl, wBuffer + wPFacFlankExpect
    cp [hl]
    jr nz, .right
    ld a, [wBuffer + wPFacFlankFirst]
    call PFacWriteBlock
.right
    ld a, [wBuffer + wPFacDX]
    inc a
    ld [wBuffer + wPFacCurX], a
    call PFacReadBlock
    ld hl, wBuffer + wPFacFlankExpect
    cp [hl]
    ret nz
    ld a, [wBuffer + wPFacFlankSecond]
    jp PFacWriteBlock

PFacRewriteVerticalFlanks:
    ld a, [wBuffer + wPFacDX]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacDY]
    dec a
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    ld hl, wBuffer + wPFacFlankExpect
    cp [hl]
    jr nz, .below
    ld a, [wBuffer + wPFacFlankFirst]
    call PFacWriteBlock
.below
    ld a, [wBuffer + wPFacDY]
    inc a
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    ld hl, wBuffer + wPFacFlankExpect
    cp [hl]
    ret nz
    ld a, [wBuffer + wPFacFlankSecond]
    jp PFacWriteBlock
; ============================================================
; PFacFinalizeBlocks
; One full-map pass converts every generation sentinel to its final block:
; room/corridor/pending cells become $0E floor and untouched cells become $2E
; void. Directional walls, corners, jambs, and other real blocks are unchanged.
; ============================================================
PFacFinalizeBlocks:
    ld a, [wBuffer + wPFacTargetBaseLo]
    ld l, a
    ld a, [wBuffer + wPFacTargetBaseHi]
    ld h, a
    ld b, PFAC_SIZE
.rowLoop
    ld c, PFAC_SIZE
.colLoop
    ld a, [hl]
    cp PFAC_UNTOUCHED
    jr z, .toWall
    cp PFAC_ROOMFLOOR
    jr z, .toFloor
    cp PFAC_CORRIDOR
    jr z, .toFloor
    cp PFAC_PENDING
    jr nz, .next
.toFloor
    ld a, PFAC_FLOOR
    jr .write
.toWall
    ld a, PFAC_WALL
.write
    ld [hl], a
.next
    inc hl
    dec c
    jr nz, .colLoop
    ld de, PFAC_STRIDE - PFAC_SIZE
    add hl, de
    dec b
    jr nz, .rowLoop
    ret

; ============================================================
; PFacPlaceLargeDecor
; Try the five connectivity-safe user-authored interior payloads in a
; room-specific cyclic order
; for every middle room (items 1-4, exploration 5-10). A payload may sit inside
; any interior at least as large as itself. Candidate offsets are scanned until
; the room hub remains fully walkable and every actual doorway approach retains
; a path in its travel direction. Authored payload connectivity is validated
; offline. If no payload/offset is safe, the ordinary interior remains unchanged.
; ============================================================
PFacPlaceLargeDecor:
    ld a, 1
    ld [wBuffer + wPFacRmIdx], a
.roomLoop
    ld a, [wBuffer + wPFacRmIdx]
    cp 11
    ret nc
    call PFacRoomRecordAddr
    ld a, [hli]
    ld [wBuffer + wPFacRmX], a
    ld a, [hli]
    ld [wBuffer + wPFacRmY], a
    ld a, [hli]
    ld [wBuffer + wPFacRmW], a
    and a
    jp z, .nextRoom
    ld a, [hl]
    ld [wBuffer + wPFacRmH], a
    ; A full-room premade owns its whole footprint, authored interior included.
    ; Large decor would stamp over that art and, worse, is only validated
    ; against the GENERIC room's socket-to-center cross - a template's interior
    ; routes are its own. Skip it. This never mattered while templates were
    ; 1x1 interiors, because decor skips 1xN rooms anyway (R4).
    inc hl
    inc hl
    bit 7, [hl]
    jp nz, .nextRoom

    ld a, [wBuffer + wPFacRmW]
    srl a
    ld hl, wBuffer + wPFacRmX
    add a, [hl]
    ld [wBuffer + wPFacLargeCenterX], a
    ld a, [wBuffer + wPFacRmH]
    srl a
    ld hl, wBuffer + wPFacRmY
    add a, [hl]
    ld [wBuffer + wPFacLargeCenterY], a
    call PFacLoadLargeDecorDoorMask

    ; Room id supplies a deterministic rotating start so every payload appears
    ; across ordinary layouts without perturbing item RNG.
    ld a, [wBuffer + wPFacRmIdx]
.reduceTemplate
    cp PFAC_LARGE_DECOR_COUNT
    jr c, .templateReady
    sub PFAC_LARGE_DECOR_COUNT
    jr .reduceTemplate
.templateReady
    ld [wBuffer + wPFacLargeTemplate], a
    ld a, PFAC_LARGE_DECOR_COUNT
    ld [wBuffer + wPFacLargeTries], a
.templateLoop
    call PFacLoadLargeDecorDescriptor
    ld a, [wBuffer + wPFacRmW]
    ld hl, wBuffer + wPFacLargeW
    sub [hl]
    jr c, .nextTemplate
    ld [wBuffer + wPFacLargeMaxX], a
    ld a, [wBuffer + wPFacRmH]
    ld hl, wBuffer + wPFacLargeH
    sub [hl]
    jr c, .nextTemplate
    ld [wBuffer + wPFacLargeMaxY], a
    xor a
    ld [wBuffer + wPFacLargeOffX], a
    ld [wBuffer + wPFacLargeOffY], a
.offsetLoop
    call PFacLargeDecorCandidateSafe
    jr c, .stamp
    ld hl, wBuffer + wPFacLargeOffX
    inc [hl]
    ld a, [wBuffer + wPFacLargeMaxX]
    cp [hl]
    jr nc, .offsetLoop
    xor a
    ld [wBuffer + wPFacLargeOffX], a
    ld hl, wBuffer + wPFacLargeOffY
    inc [hl]
    ld a, [wBuffer + wPFacLargeMaxY]
    cp [hl]
    jr nc, .offsetLoop
.nextTemplate
    ld a, [wBuffer + wPFacLargeTemplate]
    inc a
    cp PFAC_LARGE_DECOR_COUNT
    jr c, .storeTemplate
    xor a
.storeTemplate
    ld [wBuffer + wPFacLargeTemplate], a
    ld hl, wBuffer + wPFacLargeTries
    dec [hl]
    jr nz, .templateLoop
    jr .nextRoom
.stamp
    call PFacStampLargeDecor
    ; Bit 6 records ownership of the interior so the later light pass and tests
    ; can distinguish authored payload blocks from one-cell decoration.
    ld a, [wBuffer + wPFacRmIdx]
    call PFacRoomRecordAddr
    ld de, 5
    add hl, de
    set 6, [hl]
.nextRoom
    ld hl, wBuffer + wPFacRmIdx
    inc [hl]
    jp .roomLoop

PFacLoadLargeDecorDescriptor:
    ld a, [wBuffer + wPFacLargeTemplate]
    add a, a
    add a, a
    ld c, a
    ld b, 0
    ld hl, PFacLargeDecorDescriptors
    add hl, bc
    ld a, [hli]
    ld [wBuffer + wPFacLargeW], a
    ld a, [hli]
    ld [wBuffer + wPFacLargeH], a
    ld a, [hli]
    ld [wBuffer + wPFacLargePtrLo], a
    ld a, [hl]
    ld [wBuffer + wPFacLargePtrHi], a
    ret

; Read the finalized wall ring and record only doorway approaches that really
; exist. Corridor/door openings are plain floor; walls and void are not.
PFacLoadLargeDecorDoorMask:
    xor a
    ld [wBuffer + wPFacLargeDoors], a
    ld a, [wBuffer + wPFacLargeCenterX]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmY]
    dec a
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_FLOOR
    jr nz, .east
    ld hl, wBuffer + wPFacLargeDoors
    set 0, [hl]
.east
    ld a, [wBuffer + wPFacRmX]
    ld hl, wBuffer + wPFacRmW
    add a, [hl]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacLargeCenterY]
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_FLOOR
    jr nz, .south
    ld hl, wBuffer + wPFacLargeDoors
    set 1, [hl]
.south
    ld a, [wBuffer + wPFacLargeCenterX]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmY]
    ld hl, wBuffer + wPFacRmH
    add a, [hl]
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_FLOOR
    jr nz, .west
    ld hl, wBuffer + wPFacLargeDoors
    set 2, [hl]
.west
    ld a, [wBuffer + wPFacRmX]
    dec a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacLargeCenterY]
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_FLOOR
    ret nz
    ld hl, wBuffer + wPFacLargeDoors
    set 3, [hl]
    ret

PFacLargeDecorCandidateSafe:
    ld a, [wBuffer + wPFacLargePtrLo]
    ld l, a
    ld a, [wBuffer + wPFacLargePtrHi]
    ld h, a
    xor a
    ld [wBuffer + wPFacLargeRow], a
.row
    xor a
    ld [wBuffer + wPFacLargeCol], a
.col
    ld a, [hli]
    ld [wBuffer + wPFacLargeBlock], a
    push hl
    ld a, [wBuffer + wPFacRmX]
    ld hl, wBuffer + wPFacLargeOffX
    add a, [hl]
    ld hl, wBuffer + wPFacLargeCol
    add a, [hl]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmY]
    ld hl, wBuffer + wPFacLargeOffY
    add a, [hl]
    ld hl, wBuffer + wPFacLargeRow
    add a, [hl]
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_FLOOR
    jp nz, .unsafePop
    ; The hub is the join between every doorway route.
    ld a, [wBuffer + wPFacCurX]
    ld hl, wBuffer + wPFacLargeCenterX
    cp [hl]
    jr nz, .checkNorthSouth
    ld a, [wBuffer + wPFacCurY]
    ld hl, wBuffer + wPFacLargeCenterY
    cp [hl]
    jr nz, .checkNorthSouth
    ld a, [wBuffer + wPFacLargeBlock]
    call PFacLargeDecorBlockFullyWalkable
    jp nz, .unsafePop
    jr .cellOK
.checkNorthSouth
    ld a, [wBuffer + wPFacCurX]
    ld hl, wBuffer + wPFacLargeCenterX
    cp [hl]
    jr nz, .checkEastWest
    ld a, [wBuffer + wPFacCurY]
    ld hl, wBuffer + wPFacLargeCenterY
    cp [hl]
    jr z, .checkEastWest
    jr c, .northLane
    ld a, [wBuffer + wPFacLargeDoors]
    bit 2, a
    jr z, .checkEastWest
    jr .checkVertical
.northLane
    ld a, [wBuffer + wPFacLargeDoors]
    bit 0, a
    jr z, .checkEastWest
.checkVertical
    ld a, [wBuffer + wPFacLargeBlock]
    call PFacLargeDecorBlockVerticalPass
    jp nz, .unsafePop
.checkEastWest
    ld a, [wBuffer + wPFacCurY]
    ld hl, wBuffer + wPFacLargeCenterY
    cp [hl]
    jr nz, .cellOK
    ld a, [wBuffer + wPFacCurX]
    ld hl, wBuffer + wPFacLargeCenterX
    cp [hl]
    jr z, .cellOK
    jr c, .westLane
    ld a, [wBuffer + wPFacLargeDoors]
    bit 1, a
    jr z, .cellOK
    jr .checkHorizontal
.westLane
    ld a, [wBuffer + wPFacLargeDoors]
    bit 3, a
    jr z, .cellOK
.checkHorizontal
    ld a, [wBuffer + wPFacLargeBlock]
    call PFacLargeDecorBlockHorizontalPass
    jp nz, .unsafePop
.cellOK
    pop hl
    push hl
    ld hl, wBuffer + wPFacLargeCol
    inc [hl]
    ld a, [wBuffer + wPFacLargeW]
    cp [hl]
    jr nz, .moreColumns
    ld hl, wBuffer + wPFacLargeRow
    inc [hl]
    ld a, [wBuffer + wPFacLargeH]
    cp [hl]
    jr nz, .moreRows
    pop hl
    scf
    ret
.moreColumns
    pop hl
    jp .col
.moreRows
    pop hl
    jp .row
.unsafePop
    pop hl
    and a
    ret

; Z set for payload blocks whose four movement quadrants are all walkable.
PFacLargeDecorBlockFullyWalkable:
    cp $0E
    ret z
    cp $2C
    ret z
    cp $3B
    ret z
    cp $3F
    ret

; Z set when a payload block has a continuous north/south lane.
PFacLargeDecorBlockVerticalPass:
    call PFacLargeDecorBlockFullyWalkable
    ret z
    cp $31
    ret z
    cp $45
    ret z
    cp $39
    ret z
    cp $77
    ret z
    cp $20
    ret z
    cp $38
    ret

; Z set when a payload block has a continuous west/east lane.
PFacLargeDecorBlockHorizontalPass:
    call PFacLargeDecorBlockFullyWalkable
    ret z
    cp $19
    ret

PFacStampLargeDecor:
    ld a, [wBuffer + wPFacLargePtrLo]
    ld l, a
    ld a, [wBuffer + wPFacLargePtrHi]
    ld h, a
    xor a
    ld [wBuffer + wPFacLargeRow], a
.row
    xor a
    ld [wBuffer + wPFacLargeCol], a
.col
    ld a, [hli]
    push hl
    push af
    ld a, [wBuffer + wPFacRmX]
    ld hl, wBuffer + wPFacLargeOffX
    add a, [hl]
    ld hl, wBuffer + wPFacLargeCol
    add a, [hl]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmY]
    ld hl, wBuffer + wPFacLargeOffY
    add a, [hl]
    ld hl, wBuffer + wPFacLargeRow
    add a, [hl]
    ld [wBuffer + wPFacCurY], a
    pop af
    call PFacWriteBlock
    pop hl
    push hl
    ld hl, wBuffer + wPFacLargeCol
    inc [hl]
    ld a, [wBuffer + wPFacLargeW]
    cp [hl]
    jr nz, .moreColumns
    ld hl, wBuffer + wPFacLargeRow
    inc [hl]
    ld a, [wBuffer + wPFacLargeH]
    cp [hl]
    jr nz, .moreRows
    pop hl
    ret
.moreColumns
    pop hl
    jr .col
.moreRows
    pop hl
    jr .row

; ============================================================
; PFacPlaceItems
; One pokeball per item room (fixed room ids 1-4; rule e guarantees these are
; always placed, so no scan is needed - just address them directly). Picks a
; random approved object anchor within each room's decorated interior, rolls a unique item (dedup
; against earlier rolls, same rejection-sampling pattern the retired
; PFacScanForBall used), and stores block coords + item IDs into
; sProcFacilityGenScratch[0..7] / wPFacItemTemp[0..3] - the exact contract
; PFacFinalize's existing bake step already reads (X,Y pairs per ball, then 4
; item IDs), so that copy-to-SRAM code needs no changes.
; Runs after block finalization and the large-decor pass. Room record bytes
; (X/Y/W/H) are never touched by the stamp/enclose/convert passes, only the map buffer, so re-reading a
; room's record here is safe.
; ============================================================
PFacPlaceItems:
    xor a
    ld [wBuffer + wPFacBallIdx], a
.ballLoop
    ld a, [wBuffer + wPFacBallIdx]
    inc a                        ; item room ids are 1-4 (ball index 0-3 -> id 1-4)
    call PFacRoomRecordAddr
    ld a, [hli]
    ld [wBuffer + wPFacRmX], a
    ld a, [hli]
    ld [wBuffer + wPFacRmY], a
    ld a, [hli]
    ld [wBuffer + wPFacRmW], a
    ld a, [hl]
    ld [wBuffer + wPFacRmH], a

    ld a, [wBuffer + wPFacRmW]
    and a
    jr nz, .havePosition
    ; Defensive fallback (should not happen - rule e guarantees item rooms
    ; always place): default to the fixed entrance block.
    ld a, 9
    ld [wBuffer + wPFacRmX], a
    ld a, 1
    ld [wBuffer + wPFacRmW], a
    ld a, 17
    ld [wBuffer + wPFacRmY], a
    ld a, 1
    ld [wBuffer + wPFacRmH], a
.havePosition
    ld a, 32
    ld [wBuffer + wPFacItemRetry], a
.positionRetry
    ld a, [wBuffer + wPFacRmW]
    ld c, a
    call Rangerandom              ; 0..W-1
    ld b, a
    ld a, [wBuffer + wPFacRmX]
    add a, b
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmH]
    ld c, a
    call Rangerandom              ; 0..H-1
    ld b, a
    ld a, [wBuffer + wPFacRmY]
    add a, b
    ld [wBuffer + wPFacCurY], a

    call PFacItemAnchorAtCurrentValid
    jr z, .positionOK
    ld hl, wBuffer + wPFacItemRetry
    dec [hl]
    jr nz, .positionRetry
    ; The protected center cross guarantees a fallback anchor even when a
    ; decorated room's random samples repeatedly hit occupied machinery.
    ld a, [wBuffer + wPFacRmW]
    srl a
    ld hl, wBuffer + wPFacRmX
    add a, [hl]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmH]
    srl a
    ld hl, wBuffer + wPFacRmY
    add a, [hl]
    ld [wBuffer + wPFacCurY], a
.positionOK

    ; Save block coords -> sProcFacilityGenScratch[ballIdx*2 .. +1] (X,Y)
    ld a, [wBuffer + wPFacBallIdx]
    add a, a
    ld e, a
    ld d, 0
    ld hl, sProcFacilityGenScratch
    add hl, de
    ld a, [wBuffer + wPFacCurX]
    ld [hli], a
    ld a, [wBuffer + wPFacCurY]
    ld [hl], a

    ; Roll this ball's item, rejecting an exact duplicate of an earlier one.
    ld a, 8
    ld [wBuffer + wPFacItemRetry], a
.rollItem
    ld c, 4
    call Rangerandom
    ld [wRogueDoorSelection], a
    farcall Random_Item_Selection
    call PFacRestoreSRAMBank
    ld a, [wBuffer + wPFacBallIdx]
    and a
    jr z, .itemOK
    ld b, a
    ld hl, wBuffer + wPFacItemTemp
    ld a, [wRogueItem]
    ld c, a
.itemDupCheck
    ld a, [hli]
    cp c
    jr z, .itemDup
    dec b
    jr nz, .itemDupCheck
    jr .itemOK
.itemDup
    ld a, [wBuffer + wPFacItemRetry]
    dec a
    ld [wBuffer + wPFacItemRetry], a
    jr nz, .rollItem
.itemOK
    ld a, [wBuffer + wPFacBallIdx]
    ld c, a
    ld b, 0
    ld hl, wBuffer + wPFacItemTemp
    add hl, bc
    ld a, [wRogueItem]
    ld [hl], a

    ld a, [wBuffer + wPFacBallIdx]
    inc a
    ld [wBuffer + wPFacBallIdx], a
    cp 4
    jp nz, .ballLoop
    ret

; Z set when the current block is an approved item-display anchor. $47 is a
; solid table, so it is accepted only when a fully walkable cardinal neighbor
; provides a conservative interaction position. Object-anchor safety is
; deliberately broader than player walkability.
PFacItemAnchorAtCurrentValid:
    call PFacReadBlock
    cp $0E
    ret z
    cp $2C
    ret z
    cp $3B
    ret z
    cp $3F
    ret z
    cp $47
    ret nz
PFacSolidAnchorHasNeighbor:
    ld a, [wBuffer + wPFacCurX]
    ld [wBuffer + wPFacItemCheckX], a
    ld a, [wBuffer + wPFacCurY]
    ld [wBuffer + wPFacItemCheckY], a

    ld hl, wBuffer + wPFacCurX
    dec [hl]
    call PFacItemAnchorCheckNeighbor
    jr z, .found
    ld a, [wBuffer + wPFacItemCheckX]
    inc a
    ld [wBuffer + wPFacCurX], a
    call PFacItemAnchorCheckNeighbor
    jr z, .found
    ld a, [wBuffer + wPFacItemCheckX]
    ld [wBuffer + wPFacCurX], a
    ld hl, wBuffer + wPFacCurY
    dec [hl]
    call PFacItemAnchorCheckNeighbor
    jr z, .found
    ld a, [wBuffer + wPFacItemCheckY]
    inc a
    ld [wBuffer + wPFacCurY], a
    call PFacItemAnchorCheckNeighbor
    jr z, .found
    or 1
    ret
.found
    ld a, [wBuffer + wPFacItemCheckX]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacItemCheckY]
    ld [wBuffer + wPFacCurY], a
    xor a
    ret

; Place four fake item-ball encounters after both decor passes. Search every
; intact middle-room record (2-10) from a random circular starting point and
; prefer a distinct room for each ball. Only reuse a room after every placed
; room has been tried. Room 1 is excluded because PFacPlaceItems has already
; reused its X/Y bytes for real-ball coordinates.
PFacPlaceFakeBalls:
    xor a
    ld [wBuffer + wPFacBallIdx], a
.ballLoop
    ld c, 9
    call Rangerandom
    add a, 2
    ld [wBuffer + wPFacFakeRoomId], a
    xor a
    ld [wBuffer + wPFacFakeReusePass], a
.roomPass
    ld a, 9
    ld [wBuffer + wPFacFakeRoomTries], a
.roomLoop
    ld a, [wBuffer + wPFacFakeRoomId]
    call PFacRoomRecordAddr
    inc hl
    inc hl
    ld a, [hl]
    and a
    jr z, .nextRoom
    ld a, [wBuffer + wPFacFakeReusePass]
    and a
    jr nz, .loadRoom
    ld a, [wBuffer + wPFacFakeRoomId]
    call PFacRoomRecordAddr
    ld de, 5
    add hl, de
    bit BIT_PFAC_FAKE_ROOM, [hl]
    jr nz, .nextRoom
.loadRoom
    ld a, [wBuffer + wPFacFakeRoomId]
    call PFacRoomRecordAddr
    ld a, [hli]
    ld [wBuffer + wPFacRmX], a
    ld [wBuffer + wPFacCurX], a
    ld a, [hli]
    ld [wBuffer + wPFacRmY], a
    ld [wBuffer + wPFacCurY], a
    ld a, [hli]
    ld [wBuffer + wPFacRmW], a
    ld a, [hl]
    ld [wBuffer + wPFacRmH], a
.scan
    call PFacFakeAnchorAtCurrentValid
    jr nz, .advance
    call PFacFakeAnchorUnused
    jp z, .save
.advance
    ld hl, wBuffer + wPFacCurX
    inc [hl]
    ld a, [wBuffer + wPFacRmX]
    ld hl, wBuffer + wPFacRmW
    add a, [hl]
    ld hl, wBuffer + wPFacCurX
    cp [hl]
    jr nz, .scan
    ld a, [wBuffer + wPFacRmX]
    ld [wBuffer + wPFacCurX], a
    ld hl, wBuffer + wPFacCurY
    inc [hl]
    ld a, [wBuffer + wPFacRmY]
    ld hl, wBuffer + wPFacRmH
    add a, [hl]
    ld hl, wBuffer + wPFacCurY
    cp [hl]
    jr nz, .scan
.nextRoom
    ld hl, wBuffer + wPFacFakeRoomId
    inc [hl]
    ld a, [hl]
    cp 11
    jr c, .roomAdvanced
    ld [hl], 2
.roomAdvanced
    ld hl, wBuffer + wPFacFakeRoomTries
    dec [hl]
    jr nz, .roomLoop
    ld hl, wBuffer + wPFacFakeReusePass
    bit 0, [hl]
    jr nz, .globalFallback
    ; Before allowing a room to hold a second fake ball, use safe one-wide
    ; corridor straightaways. This materially spreads encounters away from
    ; item rooms without putting them on sockets, turns, or branches.
    call PFacFindFakeCorridorAnchor
    jr z, .save
    ld hl, wBuffer + wPFacFakeReusePass
    set 0, [hl]
    jp .roomPass
.globalFallback
    ; A cramped decorated room can have no second legal object anchor. Fall
    ; back to a bounded scan of the connected interior, excluding the north
    ; exit/boss rows and the outer wall ring.
    ld a, 2
    ld [wBuffer + wPFacCurY], a
.globalRow
    ld a, 1
    ld [wBuffer + wPFacCurX], a
.globalColumn
    call PFacFakeAnchorAtCurrentValid
    jr nz, .globalAdvance
    call PFacFakeAnchorUnused
    jr z, .save
.globalAdvance
    ld hl, wBuffer + wPFacCurX
    inc [hl]
    ld a, [hl]
    cp 19
    jr c, .globalColumn
    ld hl, wBuffer + wPFacCurY
    inc [hl]
    ld a, [hl]
    cp 19
    jr c, .globalRow
    ; Every valid Facility has substantially more than eight walkable anchors.
    ; Keep a deterministic defensive value for malformed debug fixtures.
    ld a, 9
    ld [wBuffer + wPFacCurX], a
    ld a, 17
    ld [wBuffer + wPFacCurY], a
    xor a
    ld [wBuffer + wPFacFakeRoomId], a
.save
    ld a, [wBuffer + wPFacFakeRoomId]
    and a
    jr z, .saveCoordinate
    call PFacRoomRecordAddr
    ld de, 5
    add hl, de
    set BIT_PFAC_FAKE_ROOM, [hl]
.saveCoordinate
    ld a, [wBuffer + wPFacBallIdx]
    add a, a
    ld e, a
    ld d, 0
    ld hl, sProcFacilityGenScratch + 72
    add hl, de
    ld a, [wBuffer + wPFacCurY]
    add a, a
    add a, 4
    ld b, a
    push hl
    call PFacReadBlock
    cp $37
    pop hl
    ld a, b
    jr nz, .fakeYReady
    inc a                         ; $37 is walkable on its bottom half
.fakeYReady
    ld [hli], a
    ld a, [wBuffer + wPFacCurX]
    add a, a
    add a, 4
    ld [hl], a
    ld hl, wBuffer + wPFacBallIdx
    inc [hl]
    ld a, [hl]
    cp 4
    jp nz, .ballLoop
    ; Roll one ordinary-wild level from the same entry snapshot and persist it
    ; for all four encounters and every later re-entry.
    ld a, [sProcFacilityEntryBattleCount]
    cp 90
    jr c, .noClamp
    ld a, 89
.noClamp
    ld b, 0
.round
    cp 10
    jr c, .gotRound
    sub 10
    inc b
    jr .round
.gotRound
    ld hl, PFacFakeWildLevelTable
    ld c, b
    ld b, 0
    add hl, bc
    ld a, [hl]
    push af
    ld c, 3
    call Rangerandom
    pop bc
    add a, b
    ld [sProcFacilityGenScratch + 80], a
    ret

; Fake encounters may additionally occupy the explicitly approved authored
; blocks. $34 uses its walkable upper half; $37 is shifted to its walkable
; lower half when saved; solid $36 requires a walkable interaction neighbor.
PFacFakeAnchorAtCurrentValid:
    call PFacItemAnchorAtCurrentValid
    ret z
    call PFacReadBlock
    cp $34
    ret z
    cp $37
    ret z
    cp $36
    ret nz
    jp PFacSolidAnchorHasNeighbor

; Z set with CurX/CurY on a free corridor anchor. The bounded center-area scan
; excludes all room interiors plus the north/side boss bands and south entry.
PFacFindFakeCorridorAnchor:
    ld a, 3
    ld [wBuffer + wPFacCurY], a
.row
    ld a, 2
    ld [wBuffer + wPFacCurX], a
.column
    call PFacCorridorAnchorValid
    jr nz, .advance
    call PFacFakeAnchorUnused
    jr nz, .advance
    xor a
    ld [wBuffer + wPFacFakeRoomId], a
    ret
.advance
    ld hl, wBuffer + wPFacCurX
    inc [hl]
    ld a, [hl]
    cp 18
    jp c, .column
    ld hl, wBuffer + wPFacCurY
    inc [hl]
    ld a, [hl]
    cp 17
    jp c, .row
    or 1
    ret

; Z set only for finalized plain floor outside every room floor rectangle, with
; exactly one straight pair of plain-floor neighbors. CurX/CurY are preserved.
PFacCorridorAnchorValid:
    call PFacReadBlock
    cp PFAC_FLOOR
    ret nz
    xor a
    ld [wBuffer + wPFacScanId], a
.room
    ld a, [wBuffer + wPFacScanId]
    cp PFAC_ROOM_MAX
    jr nc, .topology
    call PFacRoomRecordAddr
    ld a, [hli]
    ld b, a
    ld a, [hli]
    ld c, a
    ld a, [hli]
    and a
    jr z, .nextRoom
    ld d, a
    ld e, [hl]
    ld a, [wBuffer + wPFacCurX]
    cp b
    jr c, .nextRoom
    sub b
    cp d
    jr nc, .nextRoom
    ld a, [wBuffer + wPFacCurY]
    cp c
    jr c, .nextRoom
    sub c
    cp e
    jr c, .invalid
.nextRoom
    ld hl, wBuffer + wPFacScanId
    inc [hl]
    jr .room
.topology
    ; Record N,S,W,E plain-floor membership as bits 0-3 in b.
    ld b, 0
    ld hl, wBuffer + wPFacCurY
    dec [hl]
    call PFacReadBlock
    cp PFAC_FLOOR
    jr nz, .south
    set 0, b
.south
    ld hl, wBuffer + wPFacCurY
    inc [hl]
    inc [hl]
    call PFacReadBlock
    cp PFAC_FLOOR
    jr nz, .west
    set 1, b
.west
    ld hl, wBuffer + wPFacCurY
    dec [hl]
    ld hl, wBuffer + wPFacCurX
    dec [hl]
    call PFacReadBlock
    cp PFAC_FLOOR
    jr nz, .east
    set 2, b
.east
    ld hl, wBuffer + wPFacCurX
    inc [hl]
    inc [hl]
    call PFacReadBlock
    cp PFAC_FLOOR
    jr nz, .restore
    set 3, b
.restore
    ld hl, wBuffer + wPFacCurX
    dec [hl]
    ld a, b
    cp %00000011                 ; north + south only
    ret z
    cp %00001100                 ; west + east only
    ret
.invalid
    or 1
    ret

; Z set when current X/Y does not overlap a real item or an earlier fake ball.
PFacFakeAnchorUnused:
    ld a, [wBuffer + wPFacCurX]
    cp 9
    jr nz, .checkReal
    ld a, [wBuffer + wPFacCurY]
    cp 17
    jr z, .used
.checkReal
    ld hl, sProcFacilityGenScratch
    ld b, 4
.real
    ld a, [hli]
    ld c, a
    ld a, [wBuffer + wPFacCurX]
    cp c
    jr nz, .realNext
    ld a, [hl]
    ld c, a
    ld a, [wBuffer + wPFacCurY]
    cp c
    jr z, .used
.realNext
    inc hl
    dec b
    jr nz, .real
    ld a, [wBuffer + wPFacBallIdx]
    and a
    jr z, .free
    ld b, a
    ld hl, sProcFacilityGenScratch + 72
.fake
    ld a, [hli]
    sub 4
    srl a
    ld c, a
    ld a, [wBuffer + wPFacCurY]
    cp c
    jr nz, .fakeNext
    ld a, [hl]
    sub 4
    srl a
    ld c, a
    ld a, [wBuffer + wPFacCurX]
    cp c
    jr z, .used
.fakeNext
    inc hl
    dec b
    jr nz, .fake
.free
    xor a
    ret
.used
    or 1
    ret
PFacItemAnchorCheckNeighbor:
    call PFacReadBlock
    call PFacLargeDecorBlockFullyWalkable
    push af
    ld a, [wBuffer + wPFacItemCheckX]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacItemCheckY]
    ld [wBuffer + wPFacCurY], a
    pop af
    ret

; ============================================================
; PFacDecorateExploreRooms
; Place at most one structural obstruction in each placed exploration room
; (ids 5-10), selected by its authored Type. Entry, item, and exit rooms are
; excluded categorically. A candidate must still be plain floor and must be off
; the room's full center cross; that cross is the generator's protected
; socket-to-center route. A bounded scan guarantees placement when a safe cell exists;
; thin rooms receive an orientation-safe half obstruction and 1x1 rooms skip.
;
; This runs after PFacPlaceItems so decor RNG cannot change item positions or
; contents. Item IDs in wBuffer+12..15 and explore records at SRAM offsets
; 30..65 remain intact.
; ============================================================
PFacDecorTypeTable:
    ; count, up to four block ids
    db 3, PFAC_DECOR_SOLID_A,  PFAC_DECOR_SOLID_B,  PFAC_DECOR_SOLID_C,  PFAC_DECOR_SOLID_A
    db 3, PFAC_DECOR_UPPER_A,  PFAC_DECOR_UPPER_B,  PFAC_DECOR_BOTTOM_B, PFAC_DECOR_UPPER_A
    db 1, PFAC_DECOR_RIGHT_B,  PFAC_DECOR_RIGHT_B,  PFAC_DECOR_RIGHT_B,  PFAC_DECOR_RIGHT_B
    db 2, PFAC_DECOR_LEFT_A,   PFAC_DECOR_LEFT_B,   PFAC_DECOR_LEFT_A,   PFAC_DECOR_LEFT_B

; Thin rooms cannot spare a whole 2x2 movement block. These tables select an
; obstruction whose opposite half remains continuously walkable along the long
; axis. Entries intentionally avoid $49/$56, which are also structural blocks.
PFacDecorThinHorizontalTable:
    db PFAC_DECOR_UPPER_A, PFAC_DECOR_UPPER_B, PFAC_DECOR_BOTTOM_B, PFAC_DECOR_UPPER_A
PFacDecorThinVerticalTable:
    db PFAC_DECOR_RIGHT_B, PFAC_DECOR_LEFT_A, PFAC_DECOR_LEFT_B, PFAC_DECOR_RIGHT_B

PFacDecorateExploreRooms:
    ld a, 5
    ld [wBuffer + wPFacDecorId], a
.roomLoop
    ld a, [wBuffer + wPFacDecorId]
    cp 11
    ret nc
    call PFacRoomRecordAddr
    ld a, [hli]
    ld [wBuffer + wPFacDecorX], a
    ld a, [hli]
    ld [wBuffer + wPFacDecorY], a
    ld a, [hli]
    ld [wBuffer + wPFacDecorW], a
    and a
    jp z, .nextRoom
    ld a, [hli]
    ld [wBuffer + wPFacDecorH], a
    inc hl
    bit 7, [hl]
    jp nz, .nextRoom            ; full-room premade owns its own interior (R4)
    ld a, [hl]
    and 3
    ld [wBuffer + wPFacDecorType], a

    ld a, [wBuffer + wPFacDecorW]
    cp 1
    jp z, .nextRoom
.checkThinHorizontal
    ld a, [wBuffer + wPFacDecorH]
    cp 1
    jp z, .nextRoom

    ld a, [wBuffer + wPFacDecorId]
    call PFacRoomRecordAddr
    ld de, 5
    add hl, de
    bit 6, [hl]
    jr z, .scanReady

    ; The door-mask helper consumes wPFacRm*. Reload this room before the
    ; center aliases overwrite wPFacDecorW/H below. Without this handoff, the
    ; last room visited by the large-decor phase leaks its dimensions into the
    ; light-decor scan and can let decor overwrite a doorway or wall ring.
    ld a, [wBuffer + wPFacDecorX]
    ld [wBuffer + wPFacRmX], a
    ld a, [wBuffer + wPFacDecorY]
    ld [wBuffer + wPFacRmY], a
    ld a, [wBuffer + wPFacDecorW]
    ld [wBuffer + wPFacRmW], a
    ld a, [wBuffer + wPFacDecorH]
    ld [wBuffer + wPFacRmH], a

    ld a, [wBuffer + wPFacRmW]
    srl a
    ld hl, wBuffer + wPFacRmX
    add a, [hl]
    ld [wBuffer + wPFacDecorCenterX], a
    ld a, [wBuffer + wPFacRmH]
    srl a
    ld hl, wBuffer + wPFacRmY
    add a, [hl]
    ld [wBuffer + wPFacDecorCenterY], a

    ; A room or stamped payload may rely on open cells outside the center cross
    ; to connect multiple doorway lanes. Layer light decor only in a terminal
    ; branch with exactly one actual doorway; its protected door-to-hub lane is
    ; then the complete connectivity contract.
    ; Keep the layered light pass to terminal large-decor rooms. A multi-door
    ; room is transit space, and quadrant-level wall geometry makes a one-block
    ; obstruction capable of cutting a turn around the hub.
    ld a, [wBuffer + wPFacDecorCenterX]
    ld [wBuffer + wPFacLargeCenterX], a
    ld a, [wBuffer + wPFacDecorCenterY]
    ld [wBuffer + wPFacLargeCenterY], a
    call PFacLoadLargeDecorDoorMask
    ld a, [wBuffer + wPFacRmW]
    ld [wBuffer + wPFacDecorW], a
    ld a, [wBuffer + wPFacRmH]
    ld [wBuffer + wPFacDecorH], a
    ld a, [wBuffer + wPFacLargeDoors]
    cp 1
    jr z, .scanReady
    cp 2
    jr z, .scanReady
    cp 4
    jr z, .scanReady
    cp 8
    jp nz, .nextRoom
.scanReady

    ; A complete bounded scan guarantees one obstruction whenever the room has
    ; a plain floor cell outside its protected center row and column.
    ld a, [wBuffer + wPFacDecorY]
    ld [wBuffer + wPFacCurY], a
.scanRow
    ld a, [wBuffer + wPFacDecorX]
    ld [wBuffer + wPFacCurX], a
.scanColumn
    ld a, [wBuffer + wPFacCurX]
    ld hl, wBuffer + wPFacDecorCenterX
    cp [hl]
    jr z, .advanceColumn
    ld a, [wBuffer + wPFacCurY]
    ld hl, wBuffer + wPFacDecorCenterY
    cp [hl]
    jr z, .advanceColumn
    call PFacReadBlock
    cp PFAC_FLOOR
    jr z, .placeTyped
.advanceColumn
    ld hl, wBuffer + wPFacCurX
    inc [hl]
    ld a, [wBuffer + wPFacDecorX]
    ld hl, wBuffer + wPFacDecorW
    add a, [hl]
    ld hl, wBuffer + wPFacCurX
    cp [hl]
    jr nz, .scanColumn
    ld hl, wBuffer + wPFacCurY
    inc [hl]
    ld a, [wBuffer + wPFacDecorY]
    ld hl, wBuffer + wPFacDecorH
    add a, [hl]
    ld hl, wBuffer + wPFacCurY
    cp [hl]
    jr nz, .scanRow
    jr .nextRoom

.placeTyped
    ld a, [wBuffer + wPFacDecorType]
    ld c, a
    add a, a
    add a, a
    add a, c
    ld c, a
    ld b, 0
    ld hl, PFacDecorTypeTable
    add hl, bc
    ld a, [hli]
    ld c, a
    call Rangerandom
    ld c, a
    ld b, 0
    add hl, bc
    ld a, [hl]
    call PFacWriteBlock
    call PFacMarkSmallDecor
    jr .nextRoom

.thinHorizontal
    ld a, [wBuffer + wPFacDecorY]
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacDecorX]
    ld [wBuffer + wPFacCurX], a
    call PFacReadBlock
    cp PFAC_FLOOR
    jr nz, .nextRoom
    ld hl, PFacDecorThinHorizontalTable
    jr .placeThin

.thinVertical
    ld a, [wBuffer + wPFacDecorX]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacDecorY]
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_FLOOR
    jr nz, .nextRoom
    ld hl, PFacDecorThinVerticalTable
.placeThin
    ld a, [wBuffer + wPFacDecorType]
    ld c, a
    ld b, 0
    add hl, bc
    ld a, [hl]
    call PFacWriteBlock
    call PFacMarkSmallDecor
.nextRoom
    ld a, [wBuffer + wPFacDecorId]
    inc a
    ld [wBuffer + wPFacDecorId], a
    jp .roomLoop

; Bit 5 records that the light pass found and filled a remaining plain-floor
; cell. Bit 6 independently records large-decor ownership.
PFacMarkSmallDecor:
    ld a, [wBuffer + wPFacDecorId]
    call PFacRoomRecordAddr
    ld de, 5
    add hl, de
    set 5, [hl]
    ret

; ============================================================
; PFacGenerateFacility  (top-level driver)
; Runs the whole room-tree pipeline into wOverworldMap (already seeded with
; PFAC_UNTOUCHED by PFacFillUntouched). On return the map holds only real block
; IDs ($0E floor, $2E void, directional walls, and doorway jambs) plus
; sProcFacilityGenScratch/
; wPFacItemTemp hold the 4 ball block-coords + item IDs for PFacFinalize to bake.
; ============================================================
PFacGenerateFacility:
    ld b, 64
.layoutRetry
    push bc
    call PFacFillUntouched
    call PFacInitRoomRecords
    call PFacPlaceEntryRoom       ; room 0
    call PFacPlaceExitRoom        ; room 11 (+ sProcFacilityExitI)
    call PFacPlaceMiddleRooms     ; rooms 1-10 (items guaranteed, explore best-effort)
    call PFacAssignExitParent     ; room 11's parent = nearest placed room
    call PFacStampRoomFloors
    call PFacCarveCorridors        ; establish the complete corridor plan
    call PFacSelectPremadeMiddleRooms
    ; PFacSelectPremadeMiddleRooms stamps in the same pass (R4).
    call PFacCarveCorridors        ; reopen only traversed cardinal sockets
    call PFacEncloseRooms
    call PFacValidateGeneratedCorners
    jr c, .layoutAccepted
    pop bc
    dec b
    jp nz, .layoutRetry
    ; Defensive exhaustion path: retain the final connected layout. The
    ; deterministic corpus proves ordinary generation accepts well before it.
    jr .layoutContinue
.layoutAccepted
    pop bc
.layoutContinue
    call PFacCarveEdgeOpenings
    call PFacBuildCorridorWalls
    call PFacApplyDoorJambs
    call PFacFinalizeBlocks
    call PFacRemoveIsolatedGeneratedCorners
    call PFacNormalizeReversedCorners
    call PFacPlaceLargeDecor
    call PFacPlaceItems
    call PFacDecorateExploreRooms
    call PFacPlaceFakeBalls
    ret

; Normalize the observed reversed right-corner pair: $4A directly above $42.
; It becomes a continuous right wall with the same open side.
PFacNormalizeReversedCorners:
    ld a, 1
    ld [wBuffer + wPFacCurY], a
.row
    ld a, 1
    ld [wBuffer + wPFacCurX], a
.column
    call PFacReadBlock
    cp PFAC_C_BR
    jr nz, .advance
    ld hl, wBuffer + wPFacCurY
    inc [hl]
    call PFacReadBlock
    cp PFAC_C_TR
    jr z, .fix
    ld hl, wBuffer + wPFacCurY
    dec [hl]
    jr .advance
.fix
    ld a, PFAC_W_RIGHT
    call PFacWriteBlock
    ld hl, wBuffer + wPFacCurY
    dec [hl]
    ld a, PFAC_W_RIGHT
    call PFacWriteBlock
.advance
    ld hl, wBuffer + wPFacCurX
    inc [hl]
    ld a, [hl]
    cp PFAC_SIZE - 1
    jp c, .column
    ld hl, wBuffer + wPFacCurY
    inc [hl]
    ld a, [hl]
    cp PFAC_SIZE - 1
    jp c, .row
    ret

; ============================================================
; PFacRoomCenter
; INPUT a = room id. OUTPUT b = center block col (X + W/2), c = center row
; (Y + H/2). Clobbers a, d, e, hl. Only valid for placed rooms.
; ============================================================
PFacRoomCenter:
    call PFacRoomRecordAddr
    ld a, [hli]                 ; X
    ld d, a
    ld a, [hli]                 ; Y
    ld e, a
    ld a, [hli]                 ; W
    srl a
    add a, d
    ld b, a                     ; cx = X + W/2
    ld a, [hl]                  ; H
    srl a
    add a, e
    ld c, a                     ; cy = Y + H/2
    ret

; ============================================================
; PFacInitRoomRecords
; Clear all 12 room records and set wPFacRoomCount = 12. Full clearing matters
; when a rejected layout is retried: an unplaced slot must not retain template,
; decor, or fake-room ownership bits from the prior attempt.
; ============================================================
PFacInitRoomRecords:
    ld hl, sProcFacilityGenScratch
    ld b, PFAC_ROOM_MAX * PFAC_ROOM_STRIDE
.loop
    xor a
    ld [hli], a
    dec b
    jr nz, .loop
    ld a, PFAC_ROOM_MAX
    ld [wBuffer + wPFacRoomCount], a
    ret

; ============================================================
; PFacStoreRoom
; Write wPFacCand{X,Y,W,H} + wPFacParent + a freshly rolled Type into the record
; for room wPFacPlaceId. Clobbers a, de, hl.
; ============================================================
PFacStoreRoom:
    ld a, [wBuffer + wPFacPlaceId]
    call PFacRoomRecordAddr
    ld a, [wBuffer + wPFacCandX]
    ld [hli], a
    ld a, [wBuffer + wPFacCandY]
    ld [hli], a
    ld a, [wBuffer + wPFacCandW]
    ld [hli], a
    ld a, [wBuffer + wPFacCandH]
    ld [hli], a
    ld a, [wBuffer + wPFacParent]
    ld [hli], a
    call Random
    and 3
    ld [hl], a                  ; Type 0-3 (decor category, used by a later pass)
    ret

; ============================================================
; PFacRollRoomDim
; OUTPUT a = a floor dimension in [1,7] (room footprint 3-9 per side once the
; 1-cell wall ring is added), HEAVILY biased toward small. Full max is retained
; (7 floor = 9 footprint) but big rooms are rare: taking the minimum of two
; independent 0-6 rolls skews the result low. Resulting floor distribution ~=
; 1:27% 2:22% 3:18% 4:14% 5:10% 6:6% 7:2%. Clobbers a, b, c.
; ============================================================
PFacRollRoomDim:
    ld c, 7
    call Rangerandom            ; r1 = 0..6
    push af
    ld c, 7
    call Rangerandom            ; r2 = 0..6 (in a)
    pop bc                      ; b = r1
    cp b
    jr c, .haveMin              ; a < b -> a is the min
    ld a, b
.haveMin
    inc a                       ; 1..7
    ret

; ============================================================
; PFacPlaceEntryRoom  (room 0)
; Small floor rect, bottom-aligned (floor bottom = row 18, wall ring at row 19),
; positioned so the fixed spawn block (9,17) is inside it. Always succeeds.
; ============================================================
PFacPlaceEntryRoom:
    xor a
    ld [wBuffer + wPFacPlaceId], a
    call PFacRollRoomDim
    ld [wBuffer + wPFacCandW], a  ; floor W 1-7, biased small
    call PFacRollRoomDim
    cp 2
    jr nc, .heightOK
    inc a
.heightOK
    ld [wBuffer + wPFacCandH], a  ; floor H 2-7, must contain spawn row 17
    ; Y = 19 - H
    ld a, 19
    ld hl, wBuffer + wPFacCandH
    sub [hl]
    ld [wBuffer + wPFacCandY], a
    ; X = 9 - rand(W), clamped to [1, 19-W]
    ld a, [wBuffer + wPFacCandW]
    ld c, a
    call Rangerandom
    ld b, a
    ld a, 9
    sub b
    cp 1
    jr nc, .xLowOK
    ld a, 1
.xLowOK
    ld b, a
    ld a, 19
    ld hl, wBuffer + wPFacCandW
    sub [hl]                     ; a = maxX = 19 - W
    cp b
    jr nc, .xHiOK                ; maxX >= b, keep b
    ld b, a
.xHiOK
    ld a, b
    ld [wBuffer + wPFacCandX], a
    ld a, PFAC_ROOM_NONE
    ld [wBuffer + wPFacParent], a
    jp PFacStoreRoom

; ============================================================
; PFacPlaceExitRoom  (room 11, north/west/east edge)
; The floor starts two blocks in from the selected edge, leaving a wall ring
; and an edge socket. sProcFacilityExitI is the coordinate along that edge.
; ============================================================
PFacPlaceExitRoom:
    ld a, 11
    ld [wBuffer + wPFacPlaceId], a
    call PFacRollRoomDim
    ld [wBuffer + wPFacCandW], a
    call PFacRollRoomDim
    ld [wBuffer + wPFacCandH], a
    ld a, [sProcFacilityExitEdge]
    and a
    jr z, .north
    dec a
    jr z, .west
    ; East: X = 18-W; random Y; exit row = Y+rand(H).
    ld a, 18
    ld hl, wBuffer + wPFacCandW
    sub [hl]
    ld [wBuffer + wPFacCandX], a
    jr .side
.west
    ld a, 2
    ld [wBuffer + wPFacCandX], a
.side
    ld a, 32
    ld [wBuffer + wPFacRetry], a
.sideRoll
    ld a, 19
    ld hl, wBuffer + wPFacCandH
    sub [hl]
    ld c, a
    call Rangerandom
    inc a
    ld [wBuffer + wPFacCandY], a
    call PFacCandOverlaps
    and a
    jr z, .sideAccepted
    ld hl, wBuffer + wPFacRetry
    dec [hl]
    jr nz, .sideRoll
    ; The entry is bottom-aligned, so this deterministic fallback is separated.
    ld a, 1
    ld [wBuffer + wPFacCandY], a
.sideAccepted
    ld a, [wBuffer + wPFacCandH]
    ld c, a
    call Rangerandom
    ld hl, wBuffer + wPFacCandY
    add a, [hl]
    ld [sProcFacilityExitI], a
    ; Keep side exits at least 12 block steps from the south entry (9,19).
    ; West contributes 9 horizontal steps, so row <=16; east contributes 10,
    ; so row <=17.
    ld b, a
    ld a, [sProcFacilityExitEdge]
    cp 1
    ld a, b
    jr nz, .eastDistance
    cp 17
    jr c, .store
    jr .sideDistanceReject
.eastDistance
    cp 18
    jr c, .store
.sideDistanceReject
    ld hl, wBuffer + wPFacRetry
    dec [hl]
    jr nz, .sideRoll
    ld a, 1
    ld [wBuffer + wPFacCandY], a
    ld [sProcFacilityExitI], a
    jr .store
.north
    ld a, 2
    ld [wBuffer + wPFacCandY], a
    ; X = 1 + rand(19 - W)
    ld a, 19
    ld hl, wBuffer + wPFacCandW
    sub [hl]
    ld c, a
    call Rangerandom
    inc a
    ld [wBuffer + wPFacCandX], a
    ; exit column = X + rand(W)
    ld a, [wBuffer + wPFacCandW]
    ld c, a
    call Rangerandom
    ld hl, wBuffer + wPFacCandX
    add a, [hl]
    ld [sProcFacilityExitI], a
.store
    ld a, PFAC_ROOM_NONE
    ld [wBuffer + wPFacParent], a
    jp PFacStoreRoom

; ============================================================
; PFacPlaceMiddleRooms  (rooms 1-10)
; Item rooms (1-4) are guaranteed a spot (retry hard, then a linear-scan 3x3
; fallback). Explore rooms (5-10) are best-effort and left W=0 if they can't fit.
; ============================================================
PFacPlaceMiddleRooms:
    ld a, 1
    ld [wBuffer + wPFacPlaceId], a
.roomLoop
    ld a, [wBuffer + wPFacPlaceId]
    cp 11
    ret nc                       ; done after id 10
    cp 5
    jr nc, .exploreRetries
    ld a, 40                     ; item rooms get more tries
    jr .setRetries
.exploreRetries
    ld a, 16
.setRetries
    ld [wBuffer + wPFacRetry], a
.attempt
    call PFacRollCandidate        ; a=0 accept, a=1 reject
    and a
    jr z, .accepted
    ld a, [wBuffer + wPFacRetry]
    dec a
    ld [wBuffer + wPFacRetry], a
    jr nz, .attempt
    ; retries exhausted
    ld a, [wBuffer + wPFacPlaceId]
    cp 5
    jr nc, .roomNext             ; explore: leave unplaced (W already 0)
    call PFacForceItemRoom        ; item room: guaranteed, prefers 3x3
    jr .roomNext
.accepted
    call PFacStoreRoom
.roomNext
    ld a, [wBuffer + wPFacPlaceId]
    inc a
    ld [wBuffer + wPFacPlaceId], a
    jp .roomLoop

; Roll one placement candidate near a chosen parent. OUT a=0 accept, a=1 reject.
PFacRollCandidate:
    call PFacPickParent           ; -> wPFacParent (a placed id < placeId)
    call PFacRollRoomDim
    ld [wBuffer + wPFacCandW], a
    call PFacRollRoomDim
    ld [wBuffer + wPFacCandH], a
    ld a, [wBuffer + wPFacParent]
    call PFacRoomCenter           ; b=pcx c=pcy
    ; candidate center X = pcx + rand(-5..5), then X = centerX - W/2
    push bc
    ld c, 11
    call Rangerandom
    sub 5
    pop bc
    add a, b
    ld hl, wBuffer + wPFacCandW
    ld d, [hl]
    srl d
    sub d
    ld [wBuffer + wPFacCandX], a
    ; center Y = pcy + rand(-5..5), Y = centerY - H/2
    push bc
    ld c, 11
    call Rangerandom
    sub 5
    pop bc
    add a, c
    ld hl, wBuffer + wPFacCandH
    ld d, [hl]
    srl d
    sub d
    ld [wBuffer + wPFacCandY], a
    call PFacCandInBounds
    and a
    jr z, .checkOverlap
    ld a, 1
    ret
.checkOverlap
    jp PFacCandOverlaps           ; a=0 clear (accept), a=1 overlap (reject)

; Pick a placed room id < placeId into wPFacParent (room 0 is always placed).
PFacPickParent:
    ld a, [wBuffer + wPFacPlaceId]
    ld c, a
    call Rangerandom              ; 0..placeId-1
    ld [wBuffer + wPFacParent], a
.check
    ld a, [wBuffer + wPFacParent]
    call PFacRoomRecordAddr
    inc hl
    inc hl
    ld a, [hl]
    and a
    ret nz                        ; placed
    ld a, [wBuffer + wPFacParent]
    and a
    jr z, .useZero
    dec a
    ld [wBuffer + wPFacParent], a
    jr .check
.useZero
    xor a
    ld [wBuffer + wPFacParent], a
    ret

; a=0 if wPFacCand rect is within blocks [1,18] with X+W<=19, Y+H<=19; else a=1.
PFacCandInBounds:
    ld a, [wBuffer + wPFacCandX]
    and a
    jr z, .bad
    cp 19
    jr nc, .bad
    ld a, [wBuffer + wPFacCandY]
    and a
    jr z, .bad
    cp 19
    jr nc, .bad
    ld a, [wBuffer + wPFacCandX]
    ld hl, wBuffer + wPFacCandW
    add a, [hl]
    cp 20
    jr nc, .bad
    ld a, [wBuffer + wPFacCandY]
    ld hl, wBuffer + wPFacCandH
    add a, [hl]
    cp 20
    jr nc, .bad
    xor a
    ret
.bad
    ld a, 1
    ret

; a=0 if wPFacCand rect keeps >=3 floor-cell separation from every placed
; room, leaving a full void cell between their one-block wall rings.
PFacCandOverlaps:
    xor a
    ld [wBuffer + wPFacScanId], a
.loop
    ld a, [wBuffer + wPFacScanId]
    cp PFAC_ROOM_MAX
    jr nc, .clear
    ld a, [wBuffer + wPFacScanId]
    call PFacRoomRecordAddr
    ld a, [hli]
    ld [wBuffer + wPFacBX], a
    ld a, [hli]
    ld [wBuffer + wPFacBY], a
    ld a, [hli]
    ld [wBuffer + wPFacBW], a
    ld a, [hl]
    ld [wBuffer + wPFacBH], a
    ld a, [wBuffer + wPFacBW]
    and a
    jr z, .next                  ; unplaced, ignore
    ; separated if any of the 4 hold; else overlap. The +2 before
    ; each cp is deliberate: a >=1 gap lets two rooms' wall rings (each 1 cell
    ; wide) land on the same shared cell, so whichever room's PFacEncloseRooms
    ; pass runs later silently overwrites the other's corner/edge there. >=2
    ; gap gives every room's ring its own dedicated cell; the second increment
    ; prevents those two dedicated ring cells from touching one another.
    ld a, [wBuffer + wPFacCandX]
    ld hl, wBuffer + wPFacCandW
    add a, [hl]
    inc a
    inc a
    ld hl, wBuffer + wPFacBX
    cp [hl]
    jr c, .next                  ; candX+candW+2 < Bx
    ld a, [wBuffer + wPFacBX]
    ld hl, wBuffer + wPFacBW
    add a, [hl]
    inc a
    inc a
    ld hl, wBuffer + wPFacCandX
    cp [hl]
    jr c, .next                  ; Bx+Bw+2 < candX
    ld a, [wBuffer + wPFacCandY]
    ld hl, wBuffer + wPFacCandH
    add a, [hl]
    inc a
    inc a
    ld hl, wBuffer + wPFacBY
    cp [hl]
    jr c, .next                  ; candY+candH+2 < By
    ld a, [wBuffer + wPFacBY]
    ld hl, wBuffer + wPFacBH
    add a, [hl]
    inc a
    inc a
    ld hl, wBuffer + wPFacCandY
    cp [hl]
    jr c, .next                  ; By+Bh+2 < candY
    ld a, 1                      ; none separated -> overlap
    ret
.next
    ld a, [wBuffer + wPFacScanId]
    inc a
    ld [wBuffer + wPFacScanId], a
    jr .loop
.clear
    xor a
    ret

; Guaranteed placement for an item room: scan first for a non-overlapping 3x3.
; If none fits, scan for a 1x1 room instead. This preserves the two-cell room
; separation invariant rather than silently overlapping at (1,1).
PFacForceItemRoom:
    call PFacPickParent
    ld a, 3
    ld [wBuffer + wPFacCandW], a
    ld [wBuffer + wPFacCandH], a
    ld b, 17
    call .scan
    ret nc
    ld a, 1
    ld [wBuffer + wPFacCandW], a
    ld [wBuffer + wPFacCandH], a
    ld b, 19
.scan
    ld a, 1
    ld [wBuffer + wPFacCandY], a
.scanY
    ld a, 1
    ld [wBuffer + wPFacCandX], a
.scanX
    call PFacCandOverlaps
    and a
    jr z, .found
    ld a, [wBuffer + wPFacCandX]
    inc a
    ld [wBuffer + wPFacCandX], a
    cp b
    jr c, .scanX
    ld a, [wBuffer + wPFacCandY]
    inc a
    ld [wBuffer + wPFacCandY], a
    cp b
    jr c, .scanY
    scf
    ret
.found
    call PFacStoreRoom
    and a
    ret

; ============================================================
; PFacAssignExitParent
; Set room 11's Parent to the placed room (0-10) whose center is nearest the
; exit center (manhattan). Room 0 always qualifies, so a parent always exists.
; ============================================================
PFacAssignExitParent:
    ld a, 11
    call PFacRoomCenter
    ld a, b
    ld [wBuffer + wPFacBX], a    ; exit cx
    ld a, c
    ld [wBuffer + wPFacBY], a    ; exit cy
    ld a, 255
    ld [wBuffer + wPFacBW], a    ; best distance
    xor a
    ld [wBuffer + wPFacBH], a    ; best parent id
    ld [wBuffer + wPFacScanId], a
.loop
    ld a, [wBuffer + wPFacScanId]
    cp 11
    jr nc, .done
    ld a, [wBuffer + wPFacScanId]
    call PFacRoomRecordAddr
    inc hl
    inc hl
    ld a, [hl]
    and a
    jr z, .next                  ; unplaced
    ld a, [wBuffer + wPFacScanId]
    call PFacRoomCenter          ; b=cx c=cy
    ld a, b
    ld hl, wBuffer + wPFacBX
    sub [hl]
    call PFacAbs
    ld d, a
    ld a, c
    ld hl, wBuffer + wPFacBY
    sub [hl]
    call PFacAbs
    add a, d                     ; manhattan distance
    ld hl, wBuffer + wPFacBW
    cp [hl]
    jr nc, .next                 ; not closer
    ld [hl], a
    ld a, [wBuffer + wPFacScanId]
    ld [wBuffer + wPFacBH], a
.next
    ld a, [wBuffer + wPFacScanId]
    inc a
    ld [wBuffer + wPFacScanId], a
    jr .loop
.done
    ld a, 11
    call PFacRoomRecordAddr
    ld de, 4
    add hl, de
    ld a, [wBuffer + wPFacBH]
    ld [hl], a
    ret

; ============================================================
; PFacCarveCorridors
; For room ids 11 down to 1 (skipping unplaced W=0 slots): carve a corridor to
; the room's parent, plus a 20% chance of an extra corridor to a random other
; placed room.
; ============================================================
PFacCarveCorridors:
    ld a, 11
    ld [wBuffer + wPFacCorId], a
.loop
    ld a, [wBuffer + wPFacCorId]
    and a
    ret z                        ; room 0 (entry) needs no corridor of its own -
                                 ; it is the parent tree's root, reached by the
                                 ; corridors its children (incl. item room 1) carve.
    call PFacCorRoomPlaced
    jr z, .next                  ; unplaced, skip
    ; parent
    ld a, [wBuffer + wPFacCorId]
    call PFacRoomRecordAddr
    ld de, 4
    add hl, de
    ld a, [hl]
    call PFacCarveOneCorridor
.next
    ld a, [wBuffer + wPFacCorId]
    dec a
    ld [wBuffer + wPFacCorId], a
    jp .loop

; ============================================================
; PFacCarveEntryCorridor
; Room 0 -> a random placed room, +25% chance of a second one.
; ============================================================
PFacCarveEntryCorridor:
    xor a
    ld [wBuffer + wPFacCorId], a
    call PFacRandOtherRoom
    cp 255
    ret z
    call PFacCarveOneCorridor
    call Random
    cp 64
    ret nc
    call PFacRandOtherRoom
    cp 255
    ret z
    jp PFacCarveOneCorridor

; Z set (a=0) if room wPFacCorId is unplaced (W=0); else NZ.
PFacCorRoomPlaced:
    ld a, [wBuffer + wPFacCorId]
    call PFacRoomRecordAddr
    inc hl
    inc hl
    ld a, [hl]
    and a
    ret

; OUT a = a random placed room id != wPFacCorId, or 255 if none exists.
PFacRandOtherRoom:
    ld c, PFAC_ROOM_MAX
    call Rangerandom
    ld e, a                      ; start id
    ld b, PFAC_ROOM_MAX
.loop
    ld a, e
    cp PFAC_ROOM_MAX
    jr c, .noWrap
    xor a
    ld e, a
.noWrap
    ld a, [wBuffer + wPFacCorId]
    cp e
    jr z, .advance
    ld a, e
    call PFacRoomRecordAddr
    inc hl
    inc hl
    ld a, [hl]
    and a
    jr z, .advance
    ld a, e
    ret
.advance
    inc e
    dec b
    jr nz, .loop
    ld a, 255
    ret

; ============================================================
; PFacCarveOneCorridor
; INPUT a = target room id; wPFacCorId = source room id. Carves a 1-wide
; direct-manhattan (L-shaped) corridor of PFAC_CORRIDOR from the source center
; all the way to the target center. Crossing another room or corridor does not
; stop the walk, preserving the recorded parent-tree connectivity contract.
; ============================================================
PFacCarveOneCorridor:
    push af
    ld a, [wBuffer + wPFacCorId]
    call PFacRoomCenter
    ld a, b
    ld [wBuffer + wPFacCurX], a
    ld a, c
    ld [wBuffer + wPFacCurY], a
    pop af
    call PFacRoomCenter
    ld a, b
    ld [wBuffer + wPFacCorTX], a
    ld a, c
    ld [wBuffer + wPFacCorTY], a
.hLeg
    call PFacCorStampCell
    ld a, [wBuffer + wPFacCurX]
    ld hl, wBuffer + wPFacCorTX
    cp [hl]
    jr z, .vLeg
    jr c, .hInc
    dec a
    ld [wBuffer + wPFacCurX], a
    jr .hLeg
.hInc
    inc a
    ld [wBuffer + wPFacCurX], a
    jr .hLeg
.vLeg
    call PFacCorStampCell
    ld a, [wBuffer + wPFacCurY]
    ld hl, wBuffer + wPFacCorTY
    cp [hl]
    ret z
    jr c, .vInc
    dec a
    ld [wBuffer + wPFacCurY], a
    jr .vLeg
.vInc
    inc a
    ld [wBuffer + wPFacCurY], a
    jr .vLeg

; Primary cell: carve UNTOUCHED -> CORRIDOR. Existing room floors and corridors
; remain unchanged, but never stop the walk: every mandatory corridor must reach
; its recorded parent center so incidental room contacts cannot form a
; disconnected cycle.
PFacCorStampCell:
    call PFacReadBlock
    cp PFAC_UNTOUCHED
    jr z, .carve
    call PFacTryCutPremadeSocket
    ret nc
.carve
    ld a, PFAC_CORRIDOR
    jp PFacWriteBlock

; Carry set if the cell the corridor wants is one of a stamped premade's four
; canonical sockets, which may therefore be re-cut through the template's wall.
;
; Sockets sit on the footprint perimeter at the room's own center row/column -
; the same cells PFacRoomCenter aims corridors at, and the same cells
; tools/check_facility_premades.py proves cuttable through to the hub.
; PFacPremadePerimeterClear already refused the template outright if any OTHER
; perimeter cell had been crossed, so nothing else is ever re-cuttable here.
PFacTryCutPremadeSocket:
    ld b, 1
.room
    push bc
    ld a, b
    call PFacRoomRecordAddr
    ld a, [hli]
    ld d, a                     ; d = interior X
    ld a, [hli]
    ld e, a                     ; e = interior Y
    ld a, [hli]
    ld b, a                     ; b = interior W
    ld a, [hli]
    ld c, a                     ; c = interior H
    inc hl                      ; hl -> record +5 (Type)
    bit 7, [hl]
    jr z, .next                 ; generic room, or an unplaced slot

    ; --- north / south: column X + W/2, one row outside the interior ---
    ld a, b
    srl a
    add a, d
    ld h, a                     ; socket column
    ld a, [wBuffer + wPFacCurX]
    cp h
    jr nz, .horizontal
    ld a, e
    dec a                       ; Y - 1
    ld h, a
    ld a, [wBuffer + wPFacCurY]
    cp h
    jr z, .yes
    ld a, e
    add a, c                    ; Y + H
    ld h, a
    ld a, [wBuffer + wPFacCurY]
    cp h
    jr z, .yes

.horizontal
    ; --- west / east: row Y + H/2, one column outside the interior ---
    ld a, c
    srl a
    add a, e
    ld h, a                     ; socket row
    ld a, [wBuffer + wPFacCurY]
    cp h
    jr nz, .next
    ld a, d
    dec a                       ; X - 1
    ld h, a
    ld a, [wBuffer + wPFacCurX]
    cp h
    jr z, .yes
    ld a, d
    add a, b                    ; X + W
    ld h, a
    ld a, [wBuffer + wPFacCurX]
    cp h
    jr z, .yes

.next
    pop bc
    inc b
    ld a, b
    cp 11
    jr nz, .room
    and a
    ret
.yes
    pop bc
    scf
    ret
; ============================================================
; PFacCarveEdgeOpenings
; Stamp the fixed south entrance socket, then open the selected exit boundary
; and its room wall. Exit sockets are $08 north, $05 west, and $04 east.
; Runs AFTER PFacEncloseRooms (so it overwrites the ring wall) and writes real
; PFAC_CORRIDOR so the boundary pass encloses it before floor conversion.
; ============================================================
PFacCarveEdgeOpenings:
    ld a, 9
    ld [wBuffer + wPFacCurX], a
    ld a, 19
    ld [wBuffer + wPFacCurY], a
    ld a, $2C
    call PFacWriteBlock

    ld a, [sProcFacilityExitEdge]
    and a
    jr z, .north
    dec a
    jr z, .west
.east
    ld a, 19
    ld [wBuffer + wPFacCurX], a
    ld a, [sProcFacilityExitI]
    ld [wBuffer + wPFacCurY], a
    ld a, PFAC_EXIT_E
    call PFacWriteBlock
    ld a, 18
    ld [wBuffer + wPFacCurX], a
    ld a, PFAC_CORRIDOR
    call PFacWriteBlock
    ld a, 18
    ld [wBuffer + wPFacDX], a
    ld a, [sProcFacilityExitI]
    ld [wBuffer + wPFacDY], a
    ld a, PFAC_W_RIGHT
    ld [wBuffer + wPFacFlankExpect], a
    ld a, PFAC_J_RIGHT_N
    ld [wBuffer + wPFacFlankFirst], a
    ld a, PFAC_J_RIGHT_S
    ld [wBuffer + wPFacFlankSecond], a
    jp PFacRewriteVerticalFlanks
.west
    xor a
    ld [wBuffer + wPFacCurX], a
    ld a, [sProcFacilityExitI]
    ld [wBuffer + wPFacCurY], a
    ld a, PFAC_EXIT_W
    call PFacWriteBlock
    ld a, 1
    ld [wBuffer + wPFacCurX], a
    ld a, PFAC_CORRIDOR
    call PFacWriteBlock
    ld a, 1
    ld [wBuffer + wPFacDX], a
    ld a, [sProcFacilityExitI]
    ld [wBuffer + wPFacDY], a
    ld a, PFAC_W_LEFT
    ld [wBuffer + wPFacFlankExpect], a
    ld a, PFAC_J_LEFT_N
    ld [wBuffer + wPFacFlankFirst], a
    ld a, PFAC_J_LEFT_S
    ld [wBuffer + wPFacFlankSecond], a
    jp PFacRewriteVerticalFlanks
.north
    ld a, [sProcFacilityExitI]
    ld [wBuffer + wPFacCurX], a
    xor a
    ld [wBuffer + wPFacCurY], a
    ld a, PFAC_EXIT_N
    call PFacWriteBlock
    ld a, 1
    ld [wBuffer + wPFacCurY], a
    ld a, PFAC_CORRIDOR
    call PFacWriteBlock
    ; The row-1 opening pierces the exit room's top wall. Give it the same
    ; guarded west/east jambs as ordinary north-facing room doorways.
    ld a, [sProcFacilityExitI]
    ld [wBuffer + wPFacDX], a
    ld a, 1
    ld [wBuffer + wPFacDY], a
    ld a, PFAC_W_TOP
    ld [wBuffer + wPFacFlankExpect], a
    ld a, PFAC_J_TOP_W
    ld [wBuffer + wPFacFlankFirst], a
    ld a, PFAC_J_TOP_E
    ld [wBuffer + wPFacFlankSecond], a
    jp PFacRewriteHorizontalFlanks

; ============================================================
; PFacAbs - a = |a| (two's complement). Port of PFAbs.
; ============================================================
PFacAbs:
    bit 7, a
    ret z
    cpl
    inc a
    ret

; ============================================================
; PFacRollMonClass
; Duplicate of PCRollMonClass/PFRollMonClass (takes rarity bump in B, so it
; can't be farcall'd - Bankswitch clobbers B). INPUT: b = rarity bump.
; OUTPUT: c = class 1-4. Clobbers a, d (b preserved).
; ============================================================
PFacRollMonClass:
    ld a, [wBattleCount]
    cp 90
    jr c, .noClamp
    ld a, 89
.noClamp
    ld d, 0
.divLoop
    cp 10
    jr c, .gotRound
    sub 10
    inc d
    jr .divLoop
.gotRound
    ld a, d
    add a, a
    add a, a
    add a, a            ; round * 8
    add a, b
    jr nc, .noShiftClamp
    ld a, 255
.noShiftClamp
    ld d, a
    call Random
    add a, d
    jr nc, .noEffClamp
    ld a, 255
.noEffClamp
    ld c, 1
    cp 205
    jr c, .done
    inc c
    cp 243
    jr c, .done
    inc c
    cp 253
    jr c, .done
    inc c
.done
    ret

; Reassert facility SRAM ownership after a farcall. Shared item/species helpers
; may disable SRAM or leave another bank selected.
PFacRestoreSRAMBank:
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    ld a, BMODE_ADVANCED
    ld [rBMODE], a
    ld a, BANK(sProcFacilityStagingBuffer)
    ld [rRAMB], a
    ret

; ============================================================
; PFacRollBoss
; Rolls the facility boss species + OW sprite category, stores both to SRAM.
; Called from PFacPreload while SRAM is open. Same farcall rules as PFRollBoss.
; ============================================================
PFacRollBoss:
    farcall PCGetBossLevel           ; sets wCurEnemyLevel
    ld b, 60                         ; boss rarity bump (matches cave/forest)
    call PFacRollMonClass            ; c = rarity class (same-bank call)
    ld e, c                          ; the class can only cross a farcall in e
    farcall Random_Pokemon_Selection_Far ; -> d = species, e = form
    call PFacRestoreSRAMBank
    ld a, d
    ld [wRoguePokemon1], a
    ld [sProcFacilityBossSpecies], a
    ld a, e
    ld [wRoguePokemonForm1], a
    ; Preserve the boss form in sign-variant bits 1-7. Bit 0 remains the
    ; independently rolled sign text selector.
    add a, a
    ld [sProcFacilitySignVariant], a
    farcall PFacStoreBossOWSpriteToSRAM  ; stores SPRITE_* to sProcFacilityBossSprite
    ret

; ============================================================
; PFacPreload::
; Called when Facility is assigned at the lobby. Resets bake flag + per-generation
; SRAM state, rolls the
; palette variant and sign variant, and sets the wild budget.
; ============================================================
PFacPreload::
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    ld a, BMODE_ADVANCED
    ld [rBMODE], a
    ld a, BANK(sProcFacilityStagingBuffer)  ; facility SRAM is bank 1, NOT 0
    ld [rRAMB], a
    xor a
    ld [sProcFacilityBaked], a       ; 0 = needs fresh generation
    ld [sProcFacilityItemGot], a     ; clear ball-collected bits
    ld a, [wBattleCount]
    ld [sProcFacilityEntryBattleCount], a

    ; Select and persist the exit edge: 0=N, 1=W, 2=E.
    ld c, 3
    call Rangerandom
    ld [sProcFacilityExitEdge], a

    ; Roll the facility's own boss (species + OW sprite -> SRAM).
    ld a, [wBattleCount]
    push af
    call PFacRollBoss
    ; Species selection borrows broad generation scratch. Keep stage progress
    ; authoritative across the preload regardless of the selected species/form.
    pop af
    ld [wBattleCount], a
    ld [sProcFacilityEntryBattleCount], a

    ; Roll palette variant: 0 = PowerPlant (green), 1 = Mansion (red). Cosmetic
    ; only now - read by SetPal_Overworld's FACILITY case, no longer branches
    ; generation.
    call Random
    and 1
    ld [sProcFacilityPalette], a

    ; Roll sign variant: 0 = items text, 1 = boss text.
    call Random
    and 1
    ld b, a
    ld a, [sProcFacilitySignVariant]
    and $fe
    or b
    ld [sProcFacilitySignVariant], a

    ; Wild-battle budget: 10 + wBattleCount/5, saturating at 255 (cave formula).
    ld a, [wBattleCount]
    ld b, 0
.budgetDivLoop
    cp 5
    jr c, .budgetGotQuotient
    sub 5
    inc b
    jr .budgetDivLoop
.budgetGotQuotient
    ld a, b
    add a, 10
    jr nc, .budgetNoClamp
    ld a, 255
.budgetNoClamp
    ld [wProcFacilityWildBudget], a

    ; Reset reused run events (shared cave events; facility never concurrent).
    ResetEvent EVENT_BEAT_PC_BOSS
    ResetEvent EVENT_PC_BOSS_OFFERED
    ResetEvent EVENT_PC_BUDGET_ENDED
    ResetEvent EVENT_PC_CALMED_SHOWN
    ResetEvent EVENT_BEAT_FACILITY_FAKE_BALL_1
    ResetEvent EVENT_BEAT_FACILITY_FAKE_BALL_2
    ResetEvent EVENT_BEAT_FACILITY_FAKE_BALL_3
    ResetEvent EVENT_BEAT_FACILITY_FAKE_BALL_4

    ld a, BMODE_SIMPLE
    ld [rBMODE], a
    ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
    ld [rRAMG], a
    ret

; ============================================================
; PFacFinalize::
; Called at PROCEDURAL_FACILITY warp-in.
;   First visit (sProcFacilityBaked=0): generate, bake to SRAM.
;   Re-entry (sProcFacilityBaked=1): fast-blit the staging buffer back.
;   Both paths then patch the exit warp entries and (re)place the boss + 4 ball
;     sprites from SRAM.
; SRAM is kept open through generation (RAMG/BMODE/RAMB only gate $A000-$BFFF,
; not WRAM), so sProcFacilityGenScratch is reachable during the carve.
; ============================================================
PFacFinalize::
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    ld a, BMODE_ADVANCED
    ld [rBMODE], a
    ld a, BANK(sProcFacilityStagingBuffer)  ; facility SRAM is bank 1, NOT 0
    ld [rRAMB], a

    ld a, [sProcFacilityBaked]
    and a
    jp nz, .fastBlit

    ld a, [wBattleCount]
    ld [sProcFacilityEntryBattleCount], a

    ; === First visit: generate directly into wOverworldMap ===
    ld a, LOW(wOverworldMap + PFAC_BASE)
    ld [wBuffer + wPFacTargetBaseLo], a
    ld a, HIGH(wOverworldMap + PFAC_BASE)
    ld [wBuffer + wPFacTargetBaseHi], a

    ; Seed the whole player area with the untouched sentinel, then run the
    ; room-tree pipeline. On return the map holds only real block IDs and
    ; sProcFacilityGenScratch[0..7] / wPFacItemTemp hold the ball coords + items.
    call PFacFillUntouched
    call PFacGenerateFacility

    ; Save 4 ball positions as tile coords (Y,X order) to sProcFacilityBallXY.
    ; sProcFacilityGenScratch holds X0,Y0,X1,Y1,... block coords from the scan.
    ld hl, sProcFacilityBallXY
    ld de, sProcFacilityGenScratch
    ld b, 4
.ballSave
    ld a, [de]                      ; block X
    inc de
    add a, a
    add a, 4                        ; tile X = block*2+4
    ld c, a
    ld a, [de]                      ; block Y
    inc de
    add a, a
    add a, 4                        ; tile Y = block*2+4
    ld [hli], a                     ; store tile Y first
    ld a, c
    ld [hli], a                     ; then tile X
    dec b
    jr nz, .ballSave

    ; Save 4 rolled items (wPFacItemTemp) to sProcFacilityBallItems.
    ld hl, wBuffer + wPFacItemTemp
    ld de, sProcFacilityBallItems
    ld b, 4
.itemSave
    ld a, [hli]
    ld [de], a
    inc de
    dec b
    jr nz, .itemSave

    ; === Bake: copy wOverworldMap -> sProcFacilityStagingBuffer ===
    ld hl, wOverworldMap + PFAC_BASE
    ld de, sProcFacilityStagingBuffer + PFAC_BASE
    ld b, PFAC_SIZE
.bakeRowLoop
    push bc
    ld c, PFAC_SIZE
.bakeColLoop
    ld a, [hli]
    ld [de], a
    inc de
    dec c
    jr nz, .bakeColLoop
    ld a, l
    add a, PFAC_STRIDE - PFAC_SIZE
    ld l, a
    jr nc, .bakeNoCarryHL
    inc h
.bakeNoCarryHL
    ld a, e
    add a, PFAC_STRIDE - PFAC_SIZE
    ld e, a
    jr nc, .bakeNoCarryDE
    inc d
.bakeNoCarryDE
    pop bc
    dec b
    jr nz, .bakeRowLoop

    ld a, 1
    ld [sProcFacilityBaked], a
    jr .placeSprites

.fastBlit
    ; === Re-entry: blit SRAM staging buffer -> wOverworldMap ===
    ld hl, sProcFacilityStagingBuffer + PFAC_BASE
    ld de, wOverworldMap + PFAC_BASE
    ld b, PFAC_SIZE
.blitRowLoop
    push bc
    ld c, PFAC_SIZE
.blitColLoop
    ld a, [hli]
    ld [de], a
    inc de
    dec c
    jr nz, .blitColLoop
    ld a, l
    add a, PFAC_STRIDE - PFAC_SIZE
    ld l, a
    jr nc, .blitNoCarryHL
    inc h
.blitNoCarryHL
    ld a, e
    add a, PFAC_STRIDE - PFAC_SIZE
    ld e, a
    jr nc, .blitNoCarryDE
    inc d
.blitNoCarryDE
    pop bc
    dec b
    jr nz, .blitRowLoop

.placeSprites
    ; --- Patch the south entrance and the selected two-tile exit ---
    ld hl, wWarpEntries
    ld a, 38
    ld [hli], a
    ld a, 19
    ld [hl], a

    ; sProcFacilityExitI is a block column for north or row for west/east.
    ; wWarpEntries+4 = entry 1 (Y,X,..), +8 = entry 2.
    ld a, [sProcFacilityExitI]
    add a, a
    ld c, a
    ld hl, wWarpEntries + 4
    ld a, [sProcFacilityExitEdge]
    and a
    jr z, .warpsNorth
    dec a
    jr z, .warpsWest
.warpsEast
    ld a, c
    ld [hli], a
    ld a, PFAC_SIZE * 2 - 1
    ld [hli], a
    inc hl
    inc hl
    ld a, c
    inc a
    ld [hli], a
    ld a, PFAC_SIZE * 2 - 1
    ld [hl], a
    jr .restoreBoss
.warpsWest
    ld a, c
    ld [hli], a
    xor a
    ld [hli], a
    inc hl
    inc hl
    ld a, c
    inc a
    ld [hli], a
    xor a
    ld [hl], a
    jr .restoreBoss
.warpsNorth
    xor a
    ld [hli], a
    ld a, c
    ld [hli], a
    inc hl
    inc hl
    xor a
    ld [hli], a
    ld a, c
    inc a
    ld [hl], a

    ; --- Restore boss species and place its sprite (slot 1) ---
.restoreBoss
    ld a, [sProcFacilityBossSpecies]
    ld [wRoguePokemon1], a
    ld a, [sProcFacilitySignVariant]
    srl a
    ld [wRoguePokemonForm1], a

    ld a, [sProcFacilityExitEdge]
    and a
    jr z, .bossNorth
    dec a
    jr z, .bossWest
.bossEast
    ld a, 18 * 2 + 4
    ld [wSprite01StateData2MapX], a
    ld a, [sProcFacilityExitI]
    add a, a
    add a, 4
    ld [wSprite01StateData2MapY], a
    ld bc, (LEFT << 8) | SPRITE_FACING_LEFT
    jr .bossFacing
.bossWest
    ld a, 1 * 2 + 4
    ld [wSprite01StateData2MapX], a
    ld a, [sProcFacilityExitI]
    add a, a
    add a, 4
    ld [wSprite01StateData2MapY], a
    ld bc, (RIGHT << 8) | SPRITE_FACING_RIGHT
    jr .bossFacing
.bossNorth
    ld a, [sProcFacilityExitI]
    add a, a
    add a, 4                        ; tile X = exitX*2+4
    ld [wSprite01StateData2MapX], a
    ld a, 1 * 2 + 4                 ; block Y=1 -> tile Y = 6
    ld [wSprite01StateData2MapY], a
    ld bc, (DOWN << 8) | SPRITE_FACING_DOWN
.bossFacing
    ; c = SPRITESTATEDATA1_FACINGDIRECTION, b = the object's movement byte 2.
    ; Writing the facing byte alone is NOT enough. UpdateNPCSprite re-reads
    ; movement byte 2 out of wMapSpriteData every tick, and for a STAY sprite
    ; with a fixed direction .determineDirection falls into .moveDown /
    ; .moveUp / .moveLeft / .moveRight, whose TryWalking unconditionally
    ; rewrites SPRITESTATEDATA1_FACINGDIRECTION from that constant. The
    ; authored object direction is DOWN, so a west/east boss snapped back to
    ; DOWN on the first frame after generation. Patch the source of truth too.
    ; Slot 1's entry is wMapSpriteData + (slot - 1) * 2 = offset 0.
    ld a, c
    ld [wSprite01StateData1FacingDirection], a
    ld a, b
    ld [wMapSpriteData], a

    ; Boss species/level into wMapSpriteExtraData slot 1 (offset 0).
    farcall PCGetBossLevel          ; wCurEnemyLevel from wBattleCount (bank 7)
    call PFacRestoreSRAMBank
    ld hl, wMapSpriteExtraData + 0
    ld a, [wRoguePokemon1]
    ld [hli], a
    ld a, [wCurEnemyLevel]
    set 7, a                        ; OW_POKEMON bit
    ld [hl], a

    ; --- Restore the 4 pokeball sprites (slots 2-5) from SRAM ---
    ld hl, sProcFacilityBallXY      ; Y0,X0,Y1,X1,...
    ld de, wSprite01StateData2MapY + 16
    ld b, 4
.ballRestoreXY
    ld a, [hli]                     ; tile Y
    ld [de], a
    inc de
    ld a, [hli]                     ; tile X
    ld [de], a
    ld a, e
    add a, 15                       ; advance to next slot's MapY (+16 total)
    ld e, a
    jr nc, .ballNoCarry
    inc d
.ballNoCarry
    dec b
    jr nz, .ballRestoreXY

    ; Ball items -> wRogueItem..+6 (2 bytes/slot, low byte = ID)
    ld hl, sProcFacilityBallItems
    ld de, wRogueItem
    ld b, 4
.itemRestore
    ld a, [hli]
    ld [de], a
    inc de
    inc de
    dec b
    jr nz, .itemRestore

    ; Fake encounter balls (slots 6-9) use the four persistent Y/X pairs in
    ; scratch bytes 72-79. All four share the first-entry battle-count snapshot.
    ld hl, sProcFacilityGenScratch + 72
    ld de, wSprite01StateData2MapY + 16 * 5
    ld b, 4
.fakeRestoreXY
    ld a, [hli]
    ld [de], a
    inc de
    ld a, [hli]
    ld [de], a
    ld a, e
    add a, 15
    ld e, a
    jr nc, .fakeNoCarry
    inc d
.fakeNoCarry
    dec b
    jr nz, .fakeRestoreXY

    ; Byte 80 stores the one ordinary-wild level rolled during generation.
    ld a, [sProcFacilityGenScratch + 80]
    set 7, a
    ld c, a
    ld a, [sProcFacilityEntryBattleCount]
    cp 60
    ld a, VOLTORB
    jr c, .fakeSpeciesReady
    ld a, ELECTRODE
.fakeSpeciesReady
    ld d, a
    ld hl, wMapSpriteExtraData + 10
    ld b, 4
.fakeExtra
    ld a, d
    ld [hli], a
    ld a, c
    ld [hli], a
    dec b
    jr nz, .fakeExtra

    ld a, BMODE_SIMPLE
    ld [rBMODE], a
    ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
    ld [rRAMG], a
    ret
