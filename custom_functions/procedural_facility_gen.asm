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
                             ; PFacCarveOneCorridor). Converted to PFAC_FLOOR
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

; Fully solid (0/4 walkable) corner caps, used ONLY by
; PFacClassifyCorridorDiagonal. A plain corner is 1/4 walkable, and its single
; open quadrant sits on the corner OPPOSITE the solid one - which touches the
; block to the N and the block to the E (for C_BL), never the NE diagonal. The
; diagonal branch fires precisely when no CARDINAL neighbour is a corridor, so
; the cap's opening can never face the corridor that justified placing it. When
; the two cardinal neighbours then happen to be solid as well, that quadrant is
; walkable floor the player can see and can never reach, because the overworld
; has no diagonal movement. Measured: seed (57,241,59,183) stranded quadrant
; (11,18) exactly this way.
;
; Sealing the cap is what the branch's own comment always intended ("so the
; walkable half of the adjacent straight wall cannot open directly onto $2E").
; $68/$69 already existed; $80/$81 are appended to facility.bst by the same
; mechanical recipe (plain corner + the 53 54 / 36 26 object filling its open
; quadrant). The art in $80/$81 is placeholder and may be redrawn freely - the
; ONLY contract is that tile offsets 5, 7, 13 and 15 stay out of the walkable
; set, which tools/check_facility_diagonal_splits.py and the C0a corpus
; assertion both verify.
DEF PFAC_C_TL_SOLID EQU $68
DEF PFAC_C_TR_SOLID EQU $69
DEF PFAC_C_BL_SOLID EQU $80
DEF PFAC_C_BR_SOLID EQU $81

; Doorway jamb/end pieces. Names describe the flank's position around the gap.
DEF PFAC_J_TOP_W    EQU $63
DEF PFAC_J_TOP_E    EQU $67
DEF PFAC_J_BOTTOM_W EQU $58
DEF PFAC_J_BOTTOM_E EQU $57
DEF PFAC_J_LEFT_N   EQU $55
DEF PFAC_J_LEFT_S   EQU $59
DEF PFAC_J_RIGHT_N  EQU $56
DEF PFAC_J_RIGHT_S  EQU $5A

; Authored premade counterparts. These are art, not generator output: $2A is
; the right half of a $6B/$2A pair a premade payload draws, and $2B is its
; mirror. They are listed here only so PFacRemoveStrandedJambs can apply the
; same lost-arm rule to them that it applies to $58/$57.
DEF PFAC_J_AUTHORED_W EQU $2A
DEF PFAC_J_AUTHORED_E EQU $2B

; Ring-corner end caps, three per corner: arm 1 alone, arm 2 alone, both.
; GENERATED into facility.bst from the corner plus the matching straight-wall
; cap tiles, never drawn by hand. See PFacApplyCornerCaps for the arm pairing
; and ROM_BIBLE.md for the recipe.
DEF PFAC_CC_TL_E  EQU $82
DEF PFAC_CC_TL_S  EQU $83
DEF PFAC_CC_TL_ES EQU $84
DEF PFAC_CC_TR_W  EQU $85
DEF PFAC_CC_TR_S  EQU $86
DEF PFAC_CC_TR_WS EQU $87
DEF PFAC_CC_BL_N  EQU $88
DEF PFAC_CC_BL_E  EQU $89
DEF PFAC_CC_BL_NE EQU $8A
DEF PFAC_CC_BR_N  EQU $8B
DEF PFAC_CC_BR_W  EQU $8C
DEF PFAC_CC_BR_NW EQU $8D

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

; Wall-decoration compatibility catalog, consumed by PFacDecorateCorridorWalls
; (C6b). Decoded from facility.bst by tools/decode_facility_wall_decor.py
; (PROCEDURAL_FACILITY_CONTENT_PLAN.md, C6a) - every one is fully solid, so
; none may be applied by a blind whole-map substitution, only through that
; pass's redundancy proof.
;
; The decode also found corner variants ($40 -> $68, $42 -> $69, $4A -> $0C,
; with $48 having no art at all), but corners are NOT decorated: a corner has
; a single walkable quadrant hanging off two flanking walls, and placing them
; safely needs real quadrant-occupancy data rather than a block-id test.
DEF PFAC_DECOR_WALL_LEFT     EQU $5C  ; replaces PFAC_W_LEFT   ($44)
DEF PFAC_DECOR_WALL_RIGHT    EQU $5D  ; replaces PFAC_W_RIGHT  ($46)
DEF PFAC_DECOR_WALL_TOP      EQU $61  ; replaces PFAC_W_TOP    ($41)
DEF PFAC_DECOR_WALL_BOTTOM_A EQU $33  ; replaces PFAC_W_BOTTOM ($49), variant A
DEF PFAC_DECOR_WALL_BOTTOM_B EQU $28  ; replaces PFAC_W_BOTTOM ($49), variant B

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

; C1: interior caps for the two rooms that are placed unconditionally.
;
; Entry and exit never retry, so they keep whatever PFacRollRoomDim gives them
; while every middle room gets whittled down by rejection and by
; PFacForceItemRoom's fallback. Measured over 64 layouts that made them the two
; LARGEST rooms on the map (mean footprint 4.9x5.1 and 4.9x4.9, against ~4.2x4.2
; for item rooms) - and they are also the only two rooms no content pass touches,
; so the biggest rooms were reliably the empty ones.
;
; The clamp is applied INLINE at each of the four roll sites rather than through
; a shared PFacRollRoomDimCapped helper. That is deliberate and load-bearing: a
; helper adds a call level, and the PyBoy harness decides an injected routine has
; returned by matching SP at Bankswitch.Return, which nested farcalls pass
; through ~20 times per PFacPreload. The extra depth shifted that match and made
; test_facility_regeneration_resets_objects_and_uses_count_60_threshold read a
; corrupted wBattleCount. Layout and cycle-count controls both ruled themselves
; out; only the added call depth reproduced it. Keep these inline.
;
; Clamping AFTER the roll leaves the RNG draw count unchanged, so only the
; stored value differs. Both caps are one-line tunables.
;
; EXIT raised 4 -> 5 on 2026-09-16 as part of C9. Measured on the OLD placement
; code, raising the caps alone made the map worse, not better: rooms placed per
; layout fell 6.70 -> 6.50 and forced item rooms rose 48% -> 66%, because entry
; and exit are placed first and a bigger pair simply ate the space the other ten
; rooms were already failing to reach. With C9 able to route around them it is a
; gain instead.
;
; ENTRY STAYS AT 3, and this is a safety limit, not a tuning choice. It was
; briefly raised to 4 in C9 and that produced a HARD SOFTLOCK: interior 4 admits
; 6-wide entry footprints, room 0 drew ProceduralFacility_6x5-shaped premade art
; whose bottom interior cell above the entrance column is solid $06, and the
; player spawned sealed into the single entrance block with all 529 other
; walkable quadrants unreachable (audit seed D8 E9 4D 8C, 1 layout in 400).
;
; The root cause is NOT this constant: _spawn_safe in
; tools/check_facility_premades.py measures PFAC_TPL_SPAWN with all four
; canonical sockets held open, so a payload passes by borrowing a path through a
; socket that is still solid art at runtime (the same defect described at
; PFacCarveEdgeOpenings). Raising this cap merely widened the pool until a
; payload with that property became reachable. Do not raise it again until that
; measurement is corrected.
;
; The cap costs nothing anyway. Measured over 3000 simulated layouts, entry 3
; with exit 5 beats entry 4 with exit 5 on both room count (7.50 vs 7.46) and
; interiors 5x5 or larger (0.43 vs 0.41), for slightly less mean area.
DEF PFAC_ENTRY_MAX_DIM EQU 3   ; interior; footprint up to 5x5
DEF PFAC_EXIT_MAX_DIM  EQU 5   ; interior; footprint up to 7x7, the boss room
                               ; stays the grander of the two

; C4. Consecutive placement failures before the candidate shrinks by one on each
; axis. Item rooms have a 40-retry budget, so 8 gives five size steps; explore
; rooms have 32, so 4 gives eight.
;
; The point is that the SIZE is now rolled once per room and survives a
; collision. Previously every retry re-rolled size and position together, so a
; big room that lost one coin-flip against an occupied cell simply became a
; small room and its roll was discarded - which is the main reason big rooms
; were rare, independent of the size distribution itself. Now a big room gets
; first refusal on the empty space and only gives ground when it has genuinely
; failed K times.
;
; Second win, for free: a retry after the first drops from 7 Rangerandom draws
; to 3, and PFacRollRoomDim was 43% of placement.
; Shrinking stops here rather than at 1. Measured: a floor of 1 drove 31% of all
; placed rooms to a 1x1 interior and pulled the mean interior area down to 3.20,
; because shrinking makes placement SUCCEED more often, so the extra rooms C4
; wins are all tiny ones. C4 is supposed to raise mean size, not trade it for
; count. Raised 2 -> 3 alongside C9: once PFacRollCandidate can actually reach a
; legal cell, shrinking is no longer the only way an attempt ever succeeds, so
; the floor can afford to protect size instead of rescuing placement.
DEF PFAC_SHRINK_FLOOR   EQU 3
DEF PFAC_SHRINK_ITEM    EQU 8
DEF PFAC_SHRINK_EXPLORE EQU 4

; C9. Geometry of a beside-the-parent placement roll (see PFacRollCandidate).
;
; PFAC_ROOM_GAP is the distance from a parent edge to the nearest candidate edge
; that PFacCandOverlaps will accept. That test separates when
; parentX + parentW + 2 < candX, so the closest legal candX is
; parentX + parentW + 3. Keep this in step with the +2 there: a smaller value
; makes every roll overlap, a larger one wastes floor space.
DEF PFAC_ROOM_GAP  EQU 3
; Hall-anchor sample band for real pokeballs (PFacTryHallAnchor). Derived, not
; written out, so it tracks the entry-room cap: the entry rect is bottom
; aligned at Y = 19 - H, so its top ring sits at row 18 - PFAC_ENTRY_MAX_DIM in
; the worst case and the band must stop one row short of it.
DEF PFAC_HALL_ANCHOR_Y_MIN  EQU 3
DEF PFAC_HALL_ANCHOR_Y_SPAN EQU 15 - PFAC_ENTRY_MAX_DIM
ASSERT PFAC_HALL_ANCHOR_Y_MIN + PFAC_HALL_ANCHOR_Y_SPAN - 1 < 18 - PFAC_ENTRY_MAX_DIM
ASSERT PFAC_HALL_ANCHOR_Y_SPAN > 0
; Slide along the axis the candidate did NOT leave by, as rand(0..SPAN-1) - BIAS,
; so SPAN 7 / BIAS 3 gives -3..3. Widening it finds more distinct layouts but
; misses more often, since a slid candidate can clip a third room.
DEF PFAC_SLIDE_SPAN EQU 7
DEF PFAC_SLIDE_BIAS EQU 3
ASSERT PFAC_SLIDE_BIAS * 2 < PFAC_SLIDE_SPAN
DEF PFAC_ROOM_NONE   EQU $FF  ; Parent sentinel for room 0
DEF PFAC_TEMPLATE_FLAG EQU $80
DEF BIT_PFAC_FAKE_ROOM EQU 4
; Bit 6 (set by PFacPlaceLargeDecor's .stamp) records authored large-decor
; ownership of a room's interior. Combined with bit 7 (PFAC_TEMPLATE_FLAG),
; this mask picks out every room whose walls must NOT be touched by C7 room
; wall decor: a template's ring is part of its own art, and a large-decor
; room's ring may be load-bearing for a solid authored interior the same way
; a premade's is (PROCEDURAL_FACILITY_CONTENT_PLAN.md, C7).
DEF PFAC_ROOM_DECORATED_MASK EQU $C0
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
;      the hub specifically is what matters; PFAC_TPL_EXIT_N/W/E = the payload is
;      safe as the exit room against that map edge; PFAC_TPL_SPAWN = it is safe
;      as the entry room)
;   +4/+5 payload pointer, footprint W*H block ids, row-major
DEF PFAC_TPL_STRIDE EQU 6
DEF PFAC_TPL_ITEM   EQU 1 << 0

; C2. Exit-room safety, one bit per map edge the exit can face. MEASURED by
; tools/check_facility_premades.py exactly like the socket mask, never authored.
;
; A bit is set only if EVERY opening position along that edge leaves the opening
; connected to the payload's socket component. Testing every position rather
; than the one that will be used is what makes the bit position-independent:
; sProcFacilityExitI is rolled in PFacPlaceExitRoom, long before any template is
; chosen, and lands on an arbitrary interior column (north) or row (west/east),
; NOT the canonical centre socket that the socket mask describes. So selection
; needs no ExitI arithmetic at all, just this bit.
;
; Note what is deliberately NOT tested: the cell the boss stands on.
; PFacCarveEdgeOpenings writes PFAC_CORRIDOR over it AFTER the premade stamp, so
; it is walkable whatever the payload holds. The hazard was never the boss cell,
; it is REACHING it: a payload that seals the interior beside the opening, on a
; ring whose baseboard is severed there, strands the boss and both exit warp
; tiles and the stage cannot be finished.
;
; There is no south bit by construction: the south edge carries the fixed player
; entrance at (9,19) and never the exit.
DEF PFAC_TPL_EXIT_N EQU 1 << 1
DEF PFAC_TPL_EXIT_W EQU 1 << 2
DEF PFAC_TPL_EXIT_E EQU 1 << 3

; C3. Entry-room (slot 0) safety. MEASURED the same way, and position-independent
; for the same reason: PFacPlaceEntryRoom bottom-aligns room 0 at Y = 19 - H and
; picks X = 9 - rand(W), so in footprint coordinates the reserved block (9,17)
; sits at row H_fp - 3 - a row fixed per template - and at a column that sweeps
; the whole interior as X takes its range. The bit holds for every one of those
; columns, so selection needs no arithmetic here either.
;
; THREE cells matter here and they are three different cells. Measured
; 2026-09-16 by warping in and reading wYCoord/wXCoord:
;
;   (9,19) is where the player ACTUALLY arrives, standing on the south warp tile
;          itself, which is the ordinary pokered behaviour - nothing in this
;          file, procedural_stage_hooks.asm or scripts/ProceduralFacility.asm
;          ever writes the player's coordinates. It is the footprint's bottom
;          RING row, and PFacCarveEdgeOpenings overwrites it with $2C after the
;          stamp, so its payload art is irrelevant. Only REACHING the room
;          through it matters, exactly as for the C2 exit. This is the cell the
;          reachability flood starts from.
;   (9,18) is the first interior row, the cell the player steps onto. Covered
;          transitively: the flood runs from (9,19) and must arrive at (9,17),
;          which cannot happen without crossing it.
;   (9,17) no longer matters at all. It was reserved as plain floor and kept out
;          of fake-ball anchors because ONE dead branch, the defensive fallback
;          in PFacPlaceItems, dropped a pokeball there. That branch now scans for
;          a real room, the map's vestigial sign bg_event is gone, and the corpus
;          assertion that pinned the cell to $0E is retired with them.
;
; So this flag is now exactly the C2 exit test applied to the SOUTH edge:
; nothing about the entry room needs the payload's art, only that the player can
; get out of the doorway they arrive in. Requiring it at every column is what
; keeps it position-independent.
DEF PFAC_TPL_SPAWN  EQU 1 << 4

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
    db 3, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E
    dw PFacTplData3x3BedRoom
    db 3, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E
    dw PFacTplData3x3BlockRoom
    db 3, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E
    dw PFacTplData3x3RockRoom
    db 3, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E
    dw PFacTplData3x3RockRoom2
    db 3, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E
    dw PFacTplData3x3ServerRoom
    db 3, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E
    dw PFacTplData3x3TableRoom
    db 3, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E
    dw PFacTplData3x3TreeRoom
    db 3, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E
    dw PFacTplData3x3TreeRoom2
PFacTpl3x3End:

PFacTpl3x4:
    db 3, 4, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData3x4ServerRoom
    db 3, 4, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData3x4ServerblockRoom
    db 3, 4, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData3x4ServerrockRoom
    db 3, 4, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData3x4ServertableRoom
    db 3, 4, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData3x4TreerockRoom
PFacTpl3x4End:

PFacTpl3x5:
    db 3, 5, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData3x5BedrockRoom
    db 3, 5, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData3x5BlockRoom
    db 3, 5, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData3x5RockRoom
    db 3, 5, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData3x5ServerrockRoom
    db 3, 5, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData3x5TablerockRoom
PFacTpl3x5End:

PFacTpl3x6:
    db 3, 6, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData3x6TableserverRoom
PFacTpl3x6End:

PFacTpl3x7:
    db 3, 7, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData3x7BlockRoom
    db 3, 7, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData3x7BlockrockRoom
    db 3, 7, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData3x7BlocktreeRoom
    db 3, 7, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData3x7LongtableRoom
    db 3, 7, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData3x7RockRoom
PFacTpl3x7End:

PFacTpl4x3:
    db 4, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E
    dw PFacTplData4x3BedRoom
    db 4, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E
    dw PFacTplData4x3RockRoom
    db 4, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E
    dw PFacTplData4x3TabletreeRoom
PFacTpl4x3End:

PFacTpl4x4:
    db 4, 4, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData4x4ServerRoom
    db 4, 4, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData4x4ServerRoom2
PFacTpl4x4End:

PFacTpl4x5:
    db 4, 5, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData4x5BlockRoom
    db 4, 5, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData4x5DoubletableRoom
    db 4, 5, PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData4x5RockRoom
    db 4, 5, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData4x5TableserverRoom
PFacTpl4x5End:

PFacTpl4x6:
    db 4, 6, PFAC_SOCKET_N | PFAC_SOCKET_S, PFAC_TPL_EXIT_N | PFAC_TPL_SPAWN
    dw PFacTplData4x6RockCombinedroom
PFacTpl4x6End:

PFacTpl4x7:
    db 4, 7, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData4x7DoubletableTreeCombinedroom
    db 4, 7, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData4x7ServerTableCombinedroom
PFacTpl4x7End:

PFacTpl5x3:
    db 5, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E
    dw PFacTplData5x3BedRoom
    db 5, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E
    dw PFacTplData5x3RockserverRoom
    db 5, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E
    dw PFacTplData5x3ServerRoom
PFacTpl5x3End:

PFacTpl5x4:
    db 5, 4, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData5x4DoubletabletreeRoom
    db 5, 4, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData5x4ServerTableRoom
PFacTpl5x4End:

PFacTpl5x5:
    db 5, 5, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData5x5PooltreeRoom
    db 5, 5, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData5x5RockRoom
    db 5, 5, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData5x5TableBedRoom
    db 5, 5, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData5x5BlockRoom
    db 5, 5, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData5x5LongtableRoom
    db 5, 5, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData5x5TableRockRoom
    db 5, 5, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData5x5TableRoom
    db 5, 5, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData5x5TreeRoom
PFacTpl5x5End:

PFacTpl5x6:
    db 5, 6, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData5x6TableserverRoom
    db 5, 6, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData5x6TablestatueRoom
PFacTpl5x6End:

PFacTpl5x7:
    db 5, 7, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData5x7DoublebigtableserverRoom
PFacTpl5x7End:

PFacTpl6x3:
    db 6, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E
    dw PFacTplData6x3BedRoom
    db 6, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E
    dw PFacTplData6x3ServerRoom
PFacTpl6x3End:

PFacTpl6x4:
    db 6, 4, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData6x4BlockRoom
    db 6, 4, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData6x4TabletreeRoom
    db 6, 4, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData6x4TripletableRockRoom
PFacTpl6x4End:

PFacTpl6x5:
    db 6, 5, PFAC_SOCKET_N | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_W | PFAC_TPL_SPAWN
    dw PFacTplData6x5TableRockRoom
PFacTpl6x5End:

PFacTpl6x6:
    db 6, 6, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData6x6BlockRoom
    db 6, 6, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData6x6WaterRoom
    db 6, 6, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData6x6WaterRoom2
PFacTpl6x6End:

PFacTpl6x7:
    db 6, 7, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData6x7TripletableTreeCombinedroom
PFacTpl6x7End:

PFacTpl7x4:
    db 7, 4, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData7x4BlockrockRoom
    db 7, 4, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData7x4RockRoom
PFacTpl7x4End:

PFacTpl7x7:
    db 7, 7, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData7x7BlockrockRoom
    db 7, 7, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData7x7DoublebigtabletreeRoom
    db 7, 7, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData7x7DoubletableServerCombinedroom
    db 7, 7, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData7x7Pool
    db 7, 7, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData7x7TreerockCombinedroom
PFacTpl7x7End:

PFacTpl8x3:
    db 8, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E
    dw PFacTplData8x3BlockRoom
    db 8, 3, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E
    dw PFacTplData8x3ServerRoom
    db 8, 3, PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E
    dw PFacTplData8x3ServerrockRoom
PFacTpl8x3End:

PFacTpl8x4:
    db 8, 4, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData8x4BlockserverCombinedroom
    db 8, 4, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData8x4TableservertreeRoom
PFacTpl8x4End:

PFacTpl8x5:
    db 8, 5, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData8x5CombinedtableRockRoom
PFacTpl8x5End:

PFacTpl8x6:
    db 8, 6, PFAC_SOCKET_N | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_W | PFAC_TPL_SPAWN
    dw PFacTplData8x6RockCombinedroom
PFacTpl8x6End:

PFacTpl8x7:
    db 8, 7, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData8x7PoolRoom
PFacTpl8x7End:

PFacTpl9x5:
    db 9, 5, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData9x5BlockrockRoom
PFacTpl9x5End:

PFacTpl9x7:
    db 9, 7, PFAC_SOCKET_N | PFAC_SOCKET_E | PFAC_SOCKET_S | PFAC_SOCKET_W, PFAC_TPL_ITEM | PFAC_TPL_EXIT_N | PFAC_TPL_EXIT_W | PFAC_TPL_EXIT_E | PFAC_TPL_SPAWN
    dw PFacTplData9x7TreerockCombinedroom
PFacTpl9x7End:

PFacRoomDescriptorsEnd:
DEF PFAC_TPL_TOTAL EQU (PFacRoomDescriptorsEnd - PFacRoomDescriptors) / PFAC_TPL_STRIDE
ASSERT PFAC_TPL_TOTAL == 79

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
    pfac_tpl_group PFacTpl3x4, PFacTpl3x4End ; 3x4, 5
    pfac_tpl_group PFacTpl3x5, PFacTpl3x5End ; 3x5, 5
    pfac_tpl_group PFacTpl3x6, PFacTpl3x6End ; 3x6, 1
    pfac_tpl_group PFacTpl3x7, PFacTpl3x7End ; 3x7, 5
    pfac_tpl_no_group ; 3x8
    pfac_tpl_no_group ; 3x9
    ; footprint width 4
    pfac_tpl_group PFacTpl4x3, PFacTpl4x3End ; 4x3, 3
    pfac_tpl_group PFacTpl4x4, PFacTpl4x4End ; 4x4, 2
    pfac_tpl_group PFacTpl4x5, PFacTpl4x5End ; 4x5, 4
    pfac_tpl_group PFacTpl4x6, PFacTpl4x6End ; 4x6, 1
    pfac_tpl_group PFacTpl4x7, PFacTpl4x7End ; 4x7, 2
    pfac_tpl_no_group ; 4x8
    pfac_tpl_no_group ; 4x9
    ; footprint width 5
    pfac_tpl_group PFacTpl5x3, PFacTpl5x3End ; 5x3, 3
    pfac_tpl_group PFacTpl5x4, PFacTpl5x4End ; 5x4, 2
    pfac_tpl_group PFacTpl5x5, PFacTpl5x5End ; 5x5, 8
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
    pfac_tpl_group PFacTpl7x4, PFacTpl7x4End ; 7x4, 2
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
PFacTplData3x4ServerRoom:
    INCBIN "maps/ProceduralFacility_3x4_server_room.blk"
ASSERT @ - PFacTplData3x4ServerRoom == 12
PFacTplData3x4ServerblockRoom:
    INCBIN "maps/ProceduralFacility_3x4_serverblock_room.blk"
ASSERT @ - PFacTplData3x4ServerblockRoom == 12
PFacTplData3x4ServerrockRoom:
    INCBIN "maps/ProceduralFacility_3x4_serverrock_room.blk"
ASSERT @ - PFacTplData3x4ServerrockRoom == 12
PFacTplData3x4ServertableRoom:
    INCBIN "maps/ProceduralFacility_3x4_servertable_room.blk"
ASSERT @ - PFacTplData3x4ServertableRoom == 12
PFacTplData3x4TreerockRoom:
    INCBIN "maps/ProceduralFacility_3x4_treerock_room.blk"
ASSERT @ - PFacTplData3x4TreerockRoom == 12
PFacTplData3x5BedrockRoom:
    INCBIN "maps/ProceduralFacility_3x5_bedrock_room.blk"
ASSERT @ - PFacTplData3x5BedrockRoom == 15
PFacTplData3x5BlockRoom:
    INCBIN "maps/ProceduralFacility_3x5_block_room.blk"
ASSERT @ - PFacTplData3x5BlockRoom == 15
PFacTplData3x5RockRoom:
    INCBIN "maps/ProceduralFacility_3x5_rock_room.blk"
ASSERT @ - PFacTplData3x5RockRoom == 15
PFacTplData3x5ServerrockRoom:
    INCBIN "maps/ProceduralFacility_3x5_serverrock_room.blk"
ASSERT @ - PFacTplData3x5ServerrockRoom == 15
PFacTplData3x5TablerockRoom:
    INCBIN "maps/ProceduralFacility_3x5_tablerock_room.blk"
ASSERT @ - PFacTplData3x5TablerockRoom == 15
PFacTplData3x6TableserverRoom:
    INCBIN "maps/ProceduralFacility_3x6_tableserver_room.blk"
ASSERT @ - PFacTplData3x6TableserverRoom == 18
PFacTplData3x7BlockRoom:
    INCBIN "maps/ProceduralFacility_3x7_block_room.blk"
ASSERT @ - PFacTplData3x7BlockRoom == 21
PFacTplData3x7BlockrockRoom:
    INCBIN "maps/ProceduralFacility_3x7_blockrock_room.blk"
ASSERT @ - PFacTplData3x7BlockrockRoom == 21
PFacTplData3x7BlocktreeRoom:
    INCBIN "maps/ProceduralFacility_3x7_blocktree_room.blk"
ASSERT @ - PFacTplData3x7BlocktreeRoom == 21
PFacTplData3x7LongtableRoom:
    INCBIN "maps/ProceduralFacility_3x7_longtable_room.blk"
ASSERT @ - PFacTplData3x7LongtableRoom == 21
PFacTplData3x7RockRoom:
    INCBIN "maps/ProceduralFacility_3x7_rock_room.blk"
ASSERT @ - PFacTplData3x7RockRoom == 21
PFacTplData4x3BedRoom:
    INCBIN "maps/ProceduralFacility_4x3_bed_room.blk"
ASSERT @ - PFacTplData4x3BedRoom == 12
PFacTplData4x3RockRoom:
    INCBIN "maps/ProceduralFacility_4x3_rock_room.blk"
ASSERT @ - PFacTplData4x3RockRoom == 12
PFacTplData4x3TabletreeRoom:
    INCBIN "maps/ProceduralFacility_4x3_tabletree_room.blk"
ASSERT @ - PFacTplData4x3TabletreeRoom == 12
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
PFacTplData5x5PooltreeRoom:
    INCBIN "maps/ProceduralFacility_5x5__pooltree_room.blk"
ASSERT @ - PFacTplData5x5PooltreeRoom == 25
PFacTplData5x5RockRoom:
    INCBIN "maps/ProceduralFacility_5x5__rock_room.blk"
ASSERT @ - PFacTplData5x5RockRoom == 25
PFacTplData5x5TableBedRoom:
    INCBIN "maps/ProceduralFacility_5x5__table_bed_room.blk"
ASSERT @ - PFacTplData5x5TableBedRoom == 25
PFacTplData5x5BlockRoom:
    INCBIN "maps/ProceduralFacility_5x5_block_room.blk"
ASSERT @ - PFacTplData5x5BlockRoom == 25
PFacTplData5x5LongtableRoom:
    INCBIN "maps/ProceduralFacility_5x5_longtable_room.blk"
ASSERT @ - PFacTplData5x5LongtableRoom == 25
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
PFacTplData7x4BlockrockRoom:
    INCBIN "maps/ProceduralFacility_7x4_blockrock_room.blk"
ASSERT @ - PFacTplData7x4BlockrockRoom == 28
PFacTplData7x4RockRoom:
    INCBIN "maps/ProceduralFacility_7x4_rock_room.blk"
ASSERT @ - PFacTplData7x4RockRoom == 28
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

; generated by tools/gen_facility_room_table.py from tools/check_facility_premades.py


DEF PFAC_LARGE_DECOR_COUNT EQU 16
; Interior-only large-decor descriptors: width, height, payload pointer.
; These may be placed in any larger compatible middle-room interior. They do
; not own or replace the room's surrounding wall ring.
PFacLargeDecorDescriptors:
    db 1, 3
    dw PFacLargeDecor1x3Doubletabletree
    db 2, 1
    dw PFacLargeDecor2x1Doubletable
    db 2, 1
    dw PFacLargeDecor2x1RockBlock
    db 2, 2
    dw PFacLargeDecor2x2Block
    db 2, 2
    dw PFacLargeDecor2x2Blocktree
    db 2, 2
    dw PFacLargeDecor2x2Rocktree
    db 2, 3
    dw PFacLargeDecor2x3Bed
    db 2, 3
    dw PFacLargeDecor2x3Block
    db 3, 2
    dw PFacLargeDecor3x2Rock
    db 3, 2
    dw PFacLargeDecor3x2Tree
    db 3, 3
    dw PFacLargeDecor3x3Block
    db 3, 3
    dw PFacLargeDecor3x3Blockrock
    db 3, 3
    dw PFacLargeDecor3x3Rock
    db 3, 3
    dw PFacLargeDecor3x3Rocktree
    db 3, 3
    dw PFacLargeDecor3x3Tabletree
    db 3, 3
    dw PFacLargeDecor3x3Triplebigtable
PFacLargeDecor1x3Doubletabletree:
    INCBIN "maps/ProceduralFacility_1x3_doubletabletree_decor.blk"
ASSERT @ - PFacLargeDecor1x3Doubletabletree == 3
PFacLargeDecor2x1Doubletable:
    INCBIN "maps/ProceduralFacility_2x1_doubletable_decor.blk"
ASSERT @ - PFacLargeDecor2x1Doubletable == 2
PFacLargeDecor2x1RockBlock:
    INCBIN "maps/ProceduralFacility_2x1_rockblock_decor.blk"
ASSERT @ - PFacLargeDecor2x1RockBlock == 2
PFacLargeDecor2x2Block:
    INCBIN "maps/ProceduralFacility_2x2_block_decor.blk"
ASSERT @ - PFacLargeDecor2x2Block == 4
PFacLargeDecor2x2Blocktree:
    INCBIN "maps/ProceduralFacility_2x2_blocktree_decor.blk"
ASSERT @ - PFacLargeDecor2x2Blocktree == 4
PFacLargeDecor2x2Rocktree:
    INCBIN "maps/ProceduralFacility_2x2_rocktree_decor.blk"
ASSERT @ - PFacLargeDecor2x2Rocktree == 4
PFacLargeDecor2x3Bed:
    INCBIN "maps/ProceduralFacility_2x3_bed_decor.blk"
ASSERT @ - PFacLargeDecor2x3Bed == 6
PFacLargeDecor2x3Block:
    INCBIN "maps/ProceduralFacility_2x3_block_decor.blk"
ASSERT @ - PFacLargeDecor2x3Block == 6
PFacLargeDecor3x2Rock:
    INCBIN "maps/ProceduralFacility_3x2_rock_decor.blk"
ASSERT @ - PFacLargeDecor3x2Rock == 6
PFacLargeDecor3x2Tree:
    INCBIN "maps/ProceduralFacility_3x2_tree_decor.blk"
ASSERT @ - PFacLargeDecor3x2Tree == 6
PFacLargeDecor3x3Block:
    INCBIN "maps/ProceduralFacility_3x3_block_decor.blk"
ASSERT @ - PFacLargeDecor3x3Block == 9
PFacLargeDecor3x3Blockrock:
    INCBIN "maps/ProceduralFacility_3x3_blockrock_decor.blk"
ASSERT @ - PFacLargeDecor3x3Blockrock == 9
PFacLargeDecor3x3Rock:
    INCBIN "maps/ProceduralFacility_3x3_rock_decor.blk"
ASSERT @ - PFacLargeDecor3x3Rock == 9
PFacLargeDecor3x3Rocktree:
    INCBIN "maps/ProceduralFacility_3x3_rocktree_decor.blk"
ASSERT @ - PFacLargeDecor3x3Rocktree == 9
PFacLargeDecor3x3Tabletree:
    INCBIN "maps/ProceduralFacility_3x3_tabletree_decor.blk"
ASSERT @ - PFacLargeDecor3x3Tabletree == 9
PFacLargeDecor3x3Triplebigtable:
    INCBIN "maps/ProceduralFacility_3x3_triplebigtable_decor.blk"
ASSERT @ - PFacLargeDecor3x3Triplebigtable == 9

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
DEF wPFacFakeReusePass EQU 20 ; C8 pass: 0 = rooms holding neither a fake nor
                              ; a real ball, 1 = any fake-free room, 2 = reuse
DEF wPFacFakeRowsLeft EQU 21  ; rows left in the wrapped hall sweep (C8)

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
; PFacApplyWallEndCaps runs after the doorway pass, so wPFacDX is dead by then
; and this reuses that slot. LoopX/LoopY stay the authoritative sweep position
; because CurX/CurY are scratch for the neighbour probe.
DEF wPFacCapWall      EQU 19

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
DEF wPFacCandSumX     EQU 16  ; candX + candW + 2, hoisted out of the overlap scan
DEF wPFacCandSumY     EQU 17  ; candY + candH + 2
DEF wPFacShrinkIn     EQU 18  ; C4: failures left before the candidate shrinks
ASSERT wPFacShrinkIn < wPFacRoomCount

ASSERT wPFacItemTemp + 3 < 30
ASSERT wPFacFlankSecond < 30
ASSERT wPFacRoomCount < 30
; Corridor phase (PFacCarveCorridors/PFacCarveOneCorridor). Same 4-12 window,
; different names (placement is finished by the time corridors run).
DEF wPFacCorId        EQU 4   ; source room whose corridor we're carving
DEF wPFacCorTX        EQU 5   ; target center X
DEF wPFacCorTY        EQU 6   ; target center Y
DEF wPFacCorSX        EQU 7   ; source center X
DEF wPFacCorSY        EQU 8   ; source center Y
DEF wPFacCorElbow     EQU 9   ; column the route turns down (PFacCarveOneCorridor)
DEF wPFacCorPX        EQU 10  ; ring corner under test by PFacRouteClipsCorner
DEF wPFacCorPY        EQU 11
DEF wPFacCorScan      EQU 12  ; room index while testing a candidate route
ASSERT wPFacCorScan < wPFacRoomCount

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
DEF wPFacTplExitNeed  EQU 23  ; C2/C3: flag bit this room requires, 0 for 1-10
ASSERT wPFacTplExitNeed < wPFacRoomCount

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

; INPUT: a = block ID; [wBuffer+wPFacCurX/Y] = logical coords (0-19).
; Preserves AF and BC; clobbers DE and HL.
; Invalid coordinates are ignored so a failed placement cannot index past the
; row table and corrupt unrelated WRAM.
;
; R6 rewrite. These two are the generator's hottest primitive by a wide margin,
; so the address math is now built once straight into HL. The original read
; CurX and CurY twice each, reloaded the target base through a spare `push hl`
; / `pop hl` pair around the row lookup, and pushed BC it did not need to. The
; body is deliberately duplicated rather than shared as a subroutine: a
; `call`/`ret` pair costs 10 cycles, which is a fifth of what the whole
; calculation now takes.
PFacWriteBlock:
    push af
    ld a, [wBuffer + wPFacCurY]
    cp PFAC_SIZE
    jr nc, .skip
    add a, a
    ld e, a
    ld d, 0
    ld hl, PFacRowOffsetTable
    add hl, de
    ld a, [hli]
    ld d, [hl]
    ld e, a                 ; de = Y * PFAC_STRIDE
    ld a, [wBuffer + wPFacCurX]
    cp PFAC_SIZE
    jr nc, .skip
    add a, e
    ld e, a
    jr nc, .noCarry
    inc d
.noCarry
    ld hl, wBuffer + wPFacTargetBaseLo
    ld a, [hli]
    ld h, [hl]
    ld l, a
    add hl, de
    pop af
    ld [hl], a
    ret
.skip
    pop af
    ret

; INPUT: [wBuffer+wPFacCurX/Y] = logical coords. OUTPUT: a = block value.
; Preserves BC; clobbers DE and HL.
; Invalid coordinates read as a solid wall instead of reading outside the map.
PFacReadBlock:
    ld a, [wBuffer + wPFacCurY]
    cp PFAC_SIZE
    jr nc, .oob
    add a, a
    ld e, a
    ld d, 0
    ld hl, PFacRowOffsetTable
    add hl, de
    ld a, [hli]
    ld d, [hl]
    ld e, a                 ; de = Y * PFAC_STRIDE
    ld a, [wBuffer + wPFacCurX]
    cp PFAC_SIZE
    jr nc, .oob
    add a, e
    ld e, a
    jr nc, .noCarry
    inc d
.noCarry
    ld hl, wBuffer + wPFacTargetBaseLo
    ld a, [hli]
    ld h, [hl]
    ld l, a
    add hl, de
    ld a, [hl]
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
; Selects AND stamps full-room premades for every room: middle rooms 1-10, the
; exit room 11 (C2) and the entry room 0 (C3).
;
; Rooms 0 and 11 each differ from a middle room in one way only. Their map-edge
; opening is carved later, by PFacCarveEdgeOpenings, so no corridor crosses that
; side of the footprint yet and PFacPremadePerimeterClear cannot see the
; requirement. It is supplied instead as wPFacTplExitNeed, a flag bit the payload
; must carry: PFAC_TPL_EXIT_N/W/E for room 11's chosen edge, PFAC_TPL_SPAWN for
; room 0.
;
; The two predicates never collide. Room 11 is never an item room, so its
; wPFacTplItemOnly is 0. Room 0 falls on the item side of the same `cp 5` test,
; which is exactly what C3 wants: requiring PFAC_TPL_ITEM guarantees the payload
; has a usable interior rather than a solid centre the player spawns beside.
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
    ld b, 0                     ; C3: room 0 (entry) is included
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
    jp z, .next                 ; unplaced slot (jp: C2 pushed .next out of jr range)
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

    ; C2/C3. Rooms 11 and 0 additionally need a payload proven safe against the
    ; map edge they touch. Every other room needs nothing here.
    ld a, b
    and a
    ld a, PFAC_TPL_SPAWN
    jr z, .exitNeedStored       ; C3: room 0, the entry room
    ld a, b
    cp 11
    jr nz, .noExitNeed
    ld a, [sProcFacilityExitEdge]
    and a
    ld a, PFAC_TPL_EXIT_N
    jr z, .exitNeedStored
    ld a, [sProcFacilityExitEdge]
    dec a
    ld a, PFAC_TPL_EXIT_W
    jr z, .exitNeedStored
    ld a, PFAC_TPL_EXIT_E
    jr .exitNeedStored
.noExitNeed
    xor a
.exitNeedStored
    ld [wBuffer + wPFacTplExitNeed], a

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
    cp 12                       ; C2: 11 is the exit room, included since C2
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
; INPUT: wPFacTplFirst, wPFacTplCount, wPFacTplNeed, wPFacTplItemOnly,
;        wPFacTplExitNeed.
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
    ld a, [wBuffer + wPFacTplExitNeed]
    and a
    jr z, .exitOK               ; not the exit room, no edge requirement
    ld d, a
    ld a, [hl]                  ; +3 flags
    and d
    jr z, .reject               ; payload is not safe against this map edge
.exitOK
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
; carved by PFacCarveCorridors/PFacCarveOneCorridor, or another room's floor)
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
    ld a, PFAC_C_BR_SOLID
    jr .restore
.useBL
    ld a, PFAC_C_BL_SOLID
    jr .restore
.useTR
    ld a, PFAC_C_TR_SOLID
    jr .restore
.useTL
    ld a, PFAC_C_TL_SOLID
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
    call PFacTryHallAnchor        ; C8: one real ball in four goes in a hall
    jp z, .positionOK
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
    ; Defensive fallback, unreachable in every corpus layout: rule e guarantees
    ; item rooms 1-4 always place. It used to default to block (9,17), which is
    ; INSIDE THE ENTRY ROOM, and that single dead branch was the only reason
    ; (9,17) had to stay plain floor and be excluded from fake-ball anchors.
    ; No item or fake item may spawn in the entry room (user decision
    ; 2026-09-16), so scan for any other placed room instead. Rooms 0 and 11
    ; always place, so starting at 1 and ending at 11 always finds one, and
    ; room 0 is never reached. PFacRoomRecordAddr clobbers only de, so b
    ; survives as the scan counter.
    ld b, 1
.fallbackScan
    ld a, b
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
    inc b
    ld a, b
    cp 12
    jr c, .fallbackScan
    ; Doubly unreachable (room 11 always places). Keep the rect non-degenerate
    ; so Rangerandom is never handed a zero range.
    ld a, 1
    ld [wBuffer + wPFacRmW], a
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

; ============================================================
; PFacTryHallAnchor (C8)
; One real pokeball in four is offered a corridor ("hall") anchor instead of
; its own item room. Z with CurX/CurY on an accepted hall cell; NZ to fall
; through to the untouched in-room anchor search.
;
; Why a roll and not a fallback: the plan specified C8 as a fallback for when
; a room anchor cannot be found, but PFacPlaceItems' room fallback is
; unreachable (rule e guarantees rooms 1-4 place), so a fallback-shaped C8
; would be dead code and would never put a ball in a hall. The roll is the
; only form that ships.
;
; Random sampling rather than PFacFindFakeCorridorAnchor's sweep, so real
; balls are not pinned to whichever corridor cell the sweep reaches first.
;
; The Y band stops below the entry room on purpose. Ball baking overwrites
; room 0's record in place (sProcFacilityGenScratch 0-7), so from ball 1 onward
; the rect PFacCorridorAnchorValid tests for room 0 is garbage and can no longer
; keep a ball out of the entry room. Entry Y is 19 - H with H at most
; PFAC_ENTRY_MAX_DIM, so the entry room and its top ring never reach above row
; 18 - PFAC_ENTRY_MAX_DIM; banding one row below that enforces "no item in the
; entry room" (user decision 2026-09-16) structurally instead of trusting that
; record. Room 1 needs no such guard: its X/Y bytes are written by ball 3, the
; last ball, so its rect is still intact for every attempt made here.
;
; The band is DERIVED from PFAC_ENTRY_MAX_DIM rather than written as a literal.
; It used to be a hardcoded 14, correct only while that cap happened to be 3.
; C9 raised the cap to 4, which moved the entry ring up to row 14 and put a real
; ball inside the entry footprint (caught by test_procedural_facility_generation);
; the cap was then put back to 3 for an unrelated safety reason, so the band is
; numerically 3-14 again. It stays derived so the next person to touch that cap
; does not have to rediscover this.
;
; Clobbers a, b, c, de, hl. CurX/CurY are meaningful only when Z.
; ============================================================
PFacTryHallAnchor:
    ld c, 4
    call Rangerandom
    and a
    jr nz, .decline
    ld a, 24
    ld [wBuffer + wPFacRmIdx], a  ; sample budget; RmIdx is dead until the
                                  ; caller loads this ball's room record
.sample
    ld c, 16
    call Rangerandom
    add a, 2                      ; X 2-17, the same band fake halls use
    ld [wBuffer + wPFacCurX], a
    ld c, PFAC_HALL_ANCHOR_Y_SPAN
    call Rangerandom
    add a, PFAC_HALL_ANCHOR_Y_MIN ; see the entry-room note above
    ld [wBuffer + wPFacCurY], a
    call PFacCorridorAnchorValid
    jr nz, .nextSample
    ld b, 0                       ; no fake ball exists yet
    ld a, [wBuffer + wPFacBallIdx]
    ld c, a                       ; real balls placed so far
    call PFacBallSpacingOK
    jr nz, .nextSample
    xor a
    ret
.nextSample
    ld hl, wBuffer + wPFacRmIdx
    dec [hl]
    jr nz, .sample
.decline
    or 1
    ret

; INPUT: c = real balls to test (0-4), b = fake balls to test (0-4).
; Z when CurX/CurY is two or more cells away on at least one axis from every
; one of those balls. That is stricter than "not the same cell" on purpose: a
; hall is one cell wide, so two balls parked beside each other read as a single
; clump and, for real items, gate the same corridor twice in a row. Only balls
; actually placed are tested, because the unwritten slots still hold room
; record bytes rather than coordinates.
; Real coords are block coords (sProcFacilityGenScratch 0-7, X then Y). Fake
; coords are tile coords (+72, Y then X) and convert back with the same
; sub 4 / srl pattern PFacFakeAnchorUnused uses. Preserves CurX/CurY.
; Clobbers a, b, c, de, hl.
PFacBallSpacingOK:
    ld a, c
    and a
    jr z, .fakes
    ld hl, sProcFacilityGenScratch
.realLoop
    ld a, [hli]
    ld d, a                       ; ball X
    ld a, [hli]
    ld e, a                       ; ball Y
    call PFacBallSpacingTest
    jr z, .tooClose
    dec c
    jr nz, .realLoop
.fakes
    ld a, b
    and a
    jr z, .clear
    ld hl, sProcFacilityGenScratch + 72
.fakeLoop
    ld a, [hli]                   ; Y (tile coord)
    sub 4
    srl a
    ld e, a
    ld a, [hli]                   ; X (tile coord)
    sub 4
    srl a
    ld d, a
    call PFacBallSpacingTest
    jr z, .tooClose
    dec b
    jr nz, .fakeLoop
.clear
    xor a
    ret
.tooClose
    or 1
    ret

; INPUT: d/e = a placed ball's block X/Y. Z when CurX/CurY is within one cell
; of it on BOTH axes. Preserves b, c, d, e, hl and CurX/CurY. Clobbers a.
PFacBallSpacingTest:
    ld a, [wBuffer + wPFacCurX]
    sub d
    jr nc, .absX
    cpl
    inc a
.absX
    cp 2
    jr nc, .apart
    ld a, [wBuffer + wPFacCurY]
    sub e
    jr nc, .absY
    cpl
    inc a
.absY
    cp 2
    jr nc, .apart
    xor a
    ret
.apart
    or 1
    ret

; Z when one of the four real pokeballs sits inside the room rect currently
; loaded in wPFacRmX/RmY/RmW/RmH. Every real ball is placed by the time the
; fake pass runs, so all four slots hold coordinates here. Preserves the rect
; and CurX/CurY. Clobbers a, b, de, hl.
PFacRoomHoldsRealBall:
    ld hl, sProcFacilityGenScratch
    ld b, 4
.loop
    ld a, [hli]
    ld d, a                       ; ball X
    ld a, [hli]
    ld e, a                       ; ball Y
    push hl
    call PFacRectHoldsPoint
    pop hl
    jr z, .holds
    dec b
    jr nz, .loop
    or 1
    ret
.holds
    xor a
    ret

; INPUT: d/e = a point's block X/Y; wPFacRmX/RmY/RmW/RmH = the rect.
; Z when the point lies inside the rect. Preserves b, c, d, e. Clobbers a, hl.
PFacRectHoldsPoint:
    ld a, d
    ld hl, wBuffer + wPFacRmX
    sub [hl]
    jr c, .outside
    ld hl, wBuffer + wPFacRmW
    cp [hl]
    jr nc, .outside
    ld a, e
    ld hl, wBuffer + wPFacRmY
    sub [hl]
    jr c, .outside
    ld hl, wBuffer + wPFacRmH
    cp [hl]
    jr nc, .outside
    xor a
    ret
.outside
    or 1
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
    cp 2
    jr nc, .loadRoom              ; pass 2 is the reuse pass
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
    ; C8: on pass 0 a room that already displays a real item is skipped, so
    ; fakes fill the bare rooms first. Before C8 the pool was rooms 2-10, of
    ; which 2/3/4 always place and always hold a real ball while 5-10
    ; contributed only ~0.9 rooms, forcing 3 of 4 fakes to double up: 72.3%
    ; of fakes shared a real item's room over 64 seeds.
    ld a, [wBuffer + wPFacFakeReusePass]
    and a
    jr nz, .scan
    call PFacRoomHoldsRealBall
    jp z, .nextRoom
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
    jp nz, .roomLoop
    ; Halls are tried once pass 0 is exhausted, before any pass that lets a
    ; fake share a room. Safe one-wide straightaways only: never a socket, a
    ; turn or a branch (PFacCorridorAnchorValid). C8 moved this ahead of the
    ; fake-free-room pass, which is what takes the sharing rate down rather
    ; than merely reordering which room gets doubled up.
    ld a, [wBuffer + wPFacFakeReusePass]
    and a
    jr nz, .passAdvance
    call PFacFindFakeCorridorAnchor
    jr z, .save
.passAdvance
    ld hl, wBuffer + wPFacFakeReusePass
    inc [hl]
    ld a, [hl]
    cp 3
    jp c, .roomPass
    jr .globalFallback
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
    ; C8: begin the sweep on a random row and wrap, rather than always at row
    ; 3. Now that halls are tried before any room-sharing pass, a fixed start
    ; would pack all four encounters into the top-left-most corridor run.
    ld c, 14
    call Rangerandom
    add a, 3
    ld [wBuffer + wPFacCurY], a
    ld a, 14
    ld [wBuffer + wPFacFakeRowsLeft], a
.row
    ld a, 2
    ld [wBuffer + wPFacCurX], a
.column
    call PFacCorridorAnchorValid
    jr nz, .advance
    call PFacFakeAnchorUnused
    jr nz, .advance
    ld a, [wBuffer + wPFacBallIdx]
    ld b, a                       ; fakes placed so far
    ld c, 4                       ; every real ball is already placed
    call PFacBallSpacingOK
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
    jr c, .rowReady
    ld [hl], 3                    ; wrap to the top of the band
.rowReady
    ld hl, wBuffer + wPFacFakeRowsLeft
    dec [hl]
    jp nz, .row
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
; PFacDecorateCorridorWalls (C6b, extended to room walls by C7)
; Cosmetic pass over EVERY finalized straight wall block on the map, corridor
; or room ring alike, replacing a fraction of them with their fully-solid
; decorated variant (PROCEDURAL_FACILITY_CONTENT_PLAN.md, C6a's decode). The
; scan is block-id driven and never distinguished corridor from room wall, so
; C7 needed no new scan: a room's ring is just another straight-wall run, and
; a generic room's OPEN INTERIOR (not its baseboard) carries connectivity, so
; losing a ring quadrant there is exactly as safe as losing one in a corridor.
; The one gap C7 closed is PFacWallInsideDecorated: it used to exclude only
; premade footprints, which left a large-decor room's ring eligible even
; though that room's authored interior can be just as solid as a premade's.
; It now excludes any room with PFAC_ROOM_DECORATED_MASK set (template bit 7
; OR large-decor bit 6) - i.e. decorates only rooms with no template and no
; large decor, the C7 additional rule.
;
; MUST run after PFacPlaceItems and PFacPlaceFakeBalls: R3's actual failure
; was stranding a ball's interaction quadrant, so every ball position must be
; known before any decoration decision. Must also run after PFacPlaceLargeDecor
; so PFAC_ROOM_DECORATED_MASK is fully populated before this pass reads it.
;
; The safety rule is REDUNDANCY, not reachability. A decorated block loses its
; walkable quadrants entirely, so the pass only fires where those quadrants are
; provably surplus: a cell decorates only in the interior of a run of three
; identical straight wall blocks whose open sides are all plain PFAC_FLOOR.
; The removed quadrants then have exactly three walkable edge-neighbours - the
; floor cell on the open side, and the run neighbours above and below - and
; every one of them keeps its own independent link into that continuous floor
; lane. Nothing can be cut off, without consulting quadrant occupancy at all.
;
; Two properties fall out of the same test and are load-bearing:
;   - A wall cell next to a CORNER never decorates, because the corner is not
;     the same block id as the run. That is what protects the 1/4-walkable
;     corners, whose single quadrant hangs off exactly two flanking walls.
;   - Two decorated cells can never be adjacent along the run, because the
;     first write replaces the plain id the second one's test requires. So the
;     pass is order-safe and produces no runs.
; The first attempt at this phase decorated unconditionally on C6a's finding 2
; (measured corridor WIDTH, not connectivity) and broke both cases; see the
; C6b record in the plan.
;
; Corners are never decorated. $48 has no decorated art at all, and the other
; three would need real quadrant-occupancy data to place safely.
;
; Reuses wBuffer offsets 4-19: room placement, item and fake-ball state have
; already been copied out to sProcFacilityGenScratch/SRAM by this point, and
; wPFacRoomCount (offset 25) is never touched.
; ============================================================
DEF wPFacWallX      EQU 4   ; scan column
DEF wPFacWallY      EQU 5   ; scan row
DEF wPFacWallScan   EQU 6   ; room-record scan index (premade-footprint test)
DEF wPFacWallRX     EQU 7   ; scanned room/ball X
DEF wPFacWallRY     EQU 8   ; scanned room/ball Y
DEF wPFacWallRW     EQU 9   ; scanned room W (premade-footprint test only)
DEF wPFacWallRH     EQU 10  ; scanned room H (premade-footprint test only)
DEF wPFacWallSaveX  EQU 11  ; base cell X, restored after each lane probe
DEF wPFacWallSaveY  EQU 12  ; base cell Y, restored after each lane probe
DEF wPFacWallType   EQU 13  ; plain wall id the run must repeat
DEF wPFacWallDecorA EQU 14  ; decorated replacement, variant A
DEF wPFacWallDecorB EQU 15  ; decorated replacement, variant B
DEF wPFacWallRunDX  EQU 16  ; one step ALONG the wall
DEF wPFacWallRunDY  EQU 17
DEF wPFacWallOpenDX EQU 18  ; one step toward the wall's walkable side
DEF wPFacWallOpenDY EQU 19
ASSERT wPFacWallOpenDY < wPFacRoomCount

; Decorable straight walls. Run is the axis the wall repeats along; open is the
; side its walkable quadrants face, named by each block's own doc comment
; above. Only PFAC_W_BOTTOM has two decorated variants; the others repeat one
; so the variant roll can stay branch-free.
DEF PFAC_WALL_RUN_STRIDE EQU 7
PFacWallRunTable:
    ;  plain wall,    run dx, run dy, open dx, open dy, decor A, decor B
    db PFAC_W_LEFT,        0,     -1,       1,       0, PFAC_DECOR_WALL_LEFT,     PFAC_DECOR_WALL_LEFT
    db PFAC_W_RIGHT,       0,     -1,      -1,       0, PFAC_DECOR_WALL_RIGHT,    PFAC_DECOR_WALL_RIGHT
    db PFAC_W_TOP,        -1,      0,       0,       1, PFAC_DECOR_WALL_TOP,      PFAC_DECOR_WALL_TOP
    db PFAC_W_BOTTOM,     -1,      0,       0,      -1, PFAC_DECOR_WALL_BOTTOM_A, PFAC_DECOR_WALL_BOTTOM_B
PFacWallRunTableEnd:
ASSERT PFacWallRunTableEnd - PFacWallRunTable == 4 * PFAC_WALL_RUN_STRIDE

PFacDecorateCorridorWalls:
    xor a
    ld [wBuffer + wPFacWallY], a
.row
    xor a
    ld [wBuffer + wPFacWallX], a
.col
    ld a, [wBuffer + wPFacWallX]
    ld [wBuffer + wPFacCurX], a
    ld [wBuffer + wPFacWallSaveX], a
    ld a, [wBuffer + wPFacWallY]
    ld [wBuffer + wPFacCurY], a
    ld [wBuffer + wPFacWallSaveY], a

    call PFacReadBlock
    ld [wBuffer + wPFacWallType], a
    ld hl, PFacWallRunTable
    ld b, 4
.scanType
    cp [hl]
    jr z, .foundType
    ld de, PFAC_WALL_RUN_STRIDE
    add hl, de
    dec b
    jr nz, .scanType
    jr .next                    ; corners and everything else: never decorated
.foundType
    inc hl
    ld a, [hli]
    ld [wBuffer + wPFacWallRunDX], a
    ld a, [hli]
    ld [wBuffer + wPFacWallRunDY], a
    ld a, [hli]
    ld [wBuffer + wPFacWallOpenDX], a
    ld a, [hli]
    ld [wBuffer + wPFacWallOpenDY], a
    ld a, [hli]
    ld [wBuffer + wPFacWallDecorA], a
    ld a, [hl]
    ld [wBuffer + wPFacWallDecorB], a

    call PFacWallRunRedundant
    jr z, .next
    call PFacWallSiteBlocked
    jr z, .next
    call PFacWallGateRoll
    jr z, .next

    call Random
    bit 0, a
    ld a, [wBuffer + wPFacWallDecorA]
    jr z, .write
    ld a, [wBuffer + wPFacWallDecorB]
.write
    call PFacWriteBlock
.next
    ld a, [wBuffer + wPFacWallX]
    inc a
    ld [wBuffer + wPFacWallX], a
    cp PFAC_SIZE
    jp nz, .col
    ld a, [wBuffer + wPFacWallY]
    inc a
    ld [wBuffer + wPFacWallY], a
    cp PFAC_SIZE
    jp nz, .row
    ret

; NZ set with 1-in-4 probability (the C6b scatter gate), Z otherwise.
; Clobbers a, bc (Rangerandom's contract).
PFacWallGateRoll:
    ld c, 4
    call Rangerandom
    and a
    jr nz, .miss
    or 1
    ret
.miss
    xor a
    ret

; Z when CurX/CurY must NOT be decorated for structural reasons: inside a
; premade or large-decor room's footprint, or cardinally adjacent to a placed
; ball (real or fake). NZ when neither applies. Preserves CurX/CurY.
PFacWallSiteBlocked:
    call PFacWallInsideDecorated
    ret z
    jp PFacWallNearBall

; Z when CurX/CurY lies inside some premade OR large-decor room's full
; footprint (its interior rect grown by one on every side, matching the ring
; PFacEncloseRooms skips for a "complete premade owns its perimeter" room -
; see C6b rule 5/6: an uncut template socket only ever exists inside that same
; footprint, so excluding the footprint wholesale also excludes every socket
; cell). A large-decor room's authored interior can be just as solid as a
; premade's (C7's additional rule: only rooms with no template and no large
; decor are bare enough for wall decor). NZ when outside every excluded
; footprint. Preserves CurX/CurY. Clobbers a, b, c, de, hl.
PFacWallInsideDecorated:
    xor a
    ld [wBuffer + wPFacWallScan], a
.room
    ld a, [wBuffer + wPFacWallScan]
    cp PFAC_ROOM_MAX
    jr nc, .safe
    call PFacRoomRecordAddr
    ld a, [hli]
    ld [wBuffer + wPFacWallRX], a
    ld a, [hli]
    ld [wBuffer + wPFacWallRY], a
    ld a, [hli]
    and a
    jr z, .nextRoom
    ld [wBuffer + wPFacWallRW], a
    ld a, [hli]
    ld [wBuffer + wPFacWallRH], a
    inc hl
    ld a, [hl]
    and PFAC_ROOM_DECORATED_MASK
    jr z, .nextRoom

    ld a, [wBuffer + wPFacWallRX]
    dec a
    ld b, a
    ld a, [wBuffer + wPFacCurX]
    cp b
    jr c, .nextRoom
    sub b
    ld c, a
    ld a, [wBuffer + wPFacWallRW]
    add a, 2
    cp c
    jr c, .nextRoom
    jr z, .nextRoom

    ld a, [wBuffer + wPFacWallRY]
    dec a
    ld b, a
    ld a, [wBuffer + wPFacCurY]
    cp b
    jr c, .nextRoom
    sub b
    ld c, a
    ld a, [wBuffer + wPFacWallRH]
    add a, 2
    cp c
    jr c, .nextRoom
    jr z, .nextRoom

    xor a
    ret
.nextRoom
    ld hl, wBuffer + wPFacWallScan
    inc [hl]
    jr .room
.safe
    or 1
    ret

; Z when CurX/CurY is cardinally adjacent (Manhattan distance 1) to a placed
; ball, real or fake. Real coordinates are already block coords
; (sProcFacilityGenScratch 0-7, X/Y pairs for balls 0-3). Fake coordinates are
; tile coords (sProcFacilityGenScratch+72, Y/X pairs) and are converted back
; with the same sub 4 / srl pattern PFacFakeAnchorUnused uses. NZ when no
; ball is adjacent. Preserves CurX/CurY. Clobbers a, b, c, hl.
PFacWallNearBall:
    ld hl, sProcFacilityGenScratch
    ld b, 4
.realLoop
    ld a, [hli]
    ld [wBuffer + wPFacWallRX], a
    ld a, [hli]
    ld [wBuffer + wPFacWallRY], a
    push bc
    push hl
    call PFacWallAdjacentTest
    pop hl
    pop bc
    jr z, .near
    dec b
    jr nz, .realLoop

    ld hl, sProcFacilityGenScratch + 72
    ld b, 4
.fakeLoop
    ld a, [hli]                 ; Y (tile coord)
    sub 4
    srl a
    ld [wBuffer + wPFacWallRY], a
    ld a, [hli]                 ; X (tile coord)
    sub 4
    srl a
    ld [wBuffer + wPFacWallRX], a
    push bc
    push hl
    call PFacWallAdjacentTest
    pop hl
    pop bc
    jr z, .near
    dec b
    jr nz, .fakeLoop

    or 1
    ret
.near
    xor a
    ret

; INPUT: wPFacWallRX/RY = a ball's block coords. Z when CurX/CurY is exactly
; one cardinal step away (Manhattan distance 1). Clobbers a, b, c.
PFacWallAdjacentTest:
    ld a, [wBuffer + wPFacCurX]
    ld b, a
    ld a, [wBuffer + wPFacWallRX]
    sub b
    call PFacAbs
    ld c, a
    ld a, [wBuffer + wPFacCurY]
    ld b, a
    ld a, [wBuffer + wPFacWallRY]
    sub b
    call PFacAbs
    add a, c
    cp 1
    ret

; NZ when the base cell (wPFacWallSaveX/Y) sits in the INTERIOR of a run of
; three identical wPFacWallType blocks whose open sides are all plain
; PFAC_FLOOR, which is the redundancy proof described in the header. Z
; otherwise. Reads five cells: the base cell's open neighbour, and each run
; neighbour plus its own open neighbour. Off-map probes read as PFAC_WALL and
; therefore reject, so the map edge needs no special case. CurX/CurY are
; restored to the base cell on both paths. Clobbers a, hl.
PFacWallRunRedundant:
    call .openSideIsFloor
    jr z, .reject

    ld a, [wBuffer + wPFacWallSaveX]
    ld hl, wBuffer + wPFacWallRunDX
    sub [hl]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacWallSaveY]
    ld hl, wBuffer + wPFacWallRunDY
    sub [hl]
    ld [wBuffer + wPFacCurY], a
    call .runNeighbourOK
    jr z, .reject

    ld a, [wBuffer + wPFacWallSaveX]
    ld hl, wBuffer + wPFacWallRunDX
    add a, [hl]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacWallSaveY]
    ld hl, wBuffer + wPFacWallRunDY
    add a, [hl]
    ld [wBuffer + wPFacCurY], a
    call .runNeighbourOK
    jr z, .reject

    call .restoreBase
    or 1
    ret
.reject
    call .restoreBase
    xor a
    ret

; CurX/CurY = a run-neighbour cell. NZ when it repeats the run's wall type and
; its own open side is plain floor. Falls through by design.
.runNeighbourOK
    call PFacReadBlock
    ld hl, wBuffer + wPFacWallType
    cp [hl]
    jr nz, .fail
.openSideIsFloor
    ld a, [wBuffer + wPFacCurX]
    ld hl, wBuffer + wPFacWallOpenDX
    add a, [hl]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacCurY]
    ld hl, wBuffer + wPFacWallOpenDY
    add a, [hl]
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_FLOOR
    jr nz, .fail
    or 1                        ; PFAC_FLOOR is nonzero, so this only sets NZ
    ret
.fail
    xor a
    ret
.restoreBase
    ld a, [wBuffer + wPFacWallSaveX]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacWallSaveY]
    ld [wBuffer + wPFacCurY], a
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
    call PFacApplyWallEndCaps
    call PFacApplyCornerCaps
    call PFacRemoveStrandedJambs
    call PFacPlaceLargeDecor
    call PFacPlaceItems
    call PFacDecorateExploreRooms
    call PFacPlaceFakeBalls
    call PFacDecorateCorridorWalls
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
; PFacApplyWallEndCaps
; PFacApplyDoorJambs only fires where a corridor sentinel sits directly beside
; ROOM FLOOR, so it caps room doorways and nothing else. Every other way a wall
; run can end against open floor - a corridor wall reaching a junction, a
; premade socket carve, a corner deleted by PFacRemoveIsolatedGeneratedCorners -
; leaves the run terminating on a plain straight wall block, which draws as a
; flat cut edge hanging in the floor. User-reported from screenshots.
;
; The eight jamb blocks are already the right art for this: each differs from
; its straight wall in exactly the two tiles that cap ONE edge, so "which jamb"
; is fully determined by which side the floor is on.
;
;   $44 W_LEFT   caps top    -> $59, caps bottom -> $55   (run is N-S)
;   $46 W_RIGHT  caps top    -> $5A, caps bottom -> $56   (run is N-S)
;   $41 W_TOP    caps west   -> $67, caps east   -> $63   (run is E-W)
;   $49 W_BOTTOM caps west   -> $57, caps east   -> $58   (run is E-W)
;
; Verified against gfx/blocksets/facility.bst, 2026-09-16: $55 differs from $44
; at tile offsets 12-13 (bottom row) and $59 at 0-1 (top row), $63 from $41 at
; 3/7 (east column) and $67 at 0/4 (west column), and so on for all eight.
;
; Safe for the reachability and stranded-quadrant assertions WITHOUT a
; connectivity argument about any particular layout: every jamb carries the
; same walkable-quadrant mask as the wall it replaces, measured at block offsets
; 5/7/13/15 - $44/$55/$59 are all .1.1 and $46/$56/$5A are all 1.1. - so the
; substitution changes art only. That also leaves the premade socket masks in
; tools/check_facility_premades.py valid, since they describe connectivity.
;
; Runs BEFORE PFacRemoveStrandedJambs so that a one-block wall island, floor on
; both ends, is capped toward one side and then deleted by that pass rather than
; left as a stub. No such island occurs in the 128-layout corpus; the ordering
; is defensive. Runs BEFORE PFacDecorateCorridorWalls so decoration only ever
; considers the plain middle of a run, never a cap.
; ============================================================
PFacApplyWallEndCaps:
    xor a
    ld [wBuffer + wPFacLoopY], a
.row
    xor a
    ld [wBuffer + wPFacLoopX], a
.column
    ld a, [wBuffer + wPFacLoopX]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacLoopY]
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    ld [wBuffer + wPFacCapWall], a
    ld hl, PFacWallEndCapTable
    ld b, PFAC_WALL_END_CAP_COUNT
.entry
    ld a, [wBuffer + wPFacCapWall]
    cp [hl]
    jr nz, .nextEntry
    push hl
    inc hl
    ld a, [wBuffer + wPFacLoopX]
    add a, [hl]                   ; + probe dx, $FF reads as -1
    ld [wBuffer + wPFacCurX], a
    inc hl
    ld a, [wBuffer + wPFacLoopY]
    add a, [hl]                   ; + probe dy
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock            ; out of range reads as solid wall
    pop hl
    cp PFAC_FLOOR
    jr nz, .nextEntry
    ld a, [wBuffer + wPFacLoopX]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacLoopY]
    ld [wBuffer + wPFacCurY], a
    ld de, 3
    add hl, de
    ld a, [hl]
    call PFacWriteBlock
    jr .advance
.nextEntry
    ld de, PFAC_WALL_END_CAP_STRIDE
    add hl, de
    dec b
    jr nz, .entry
.advance
    ld hl, wBuffer + wPFacLoopX
    inc [hl]
    ld a, [hl]
    cp PFAC_SIZE
    jp c, .column
    ld hl, wBuffer + wPFacLoopY
    inc [hl]
    ld a, [hl]
    cp PFAC_SIZE
    jp c, .row
    ret

; wall block, probe dx, probe dy, capped replacement. First match wins, so a
; one-block island with floor on both ends takes the earlier row here and is
; then removed by PFacRemoveStrandedJambs.
DEF PFAC_WALL_END_CAP_STRIDE EQU 4
PFacWallEndCapTable:
    db PFAC_W_LEFT,   0, -1, PFAC_J_LEFT_S    ; floor N, run ends at the top
    db PFAC_W_LEFT,   0,  1, PFAC_J_LEFT_N    ; floor S, run ends at the bottom
    db PFAC_W_RIGHT,  0, -1, PFAC_J_RIGHT_S
    db PFAC_W_RIGHT,  0,  1, PFAC_J_RIGHT_N
    db PFAC_W_TOP,   -1,  0, PFAC_J_TOP_E     ; floor W, run ends at the west
    db PFAC_W_TOP,    1,  0, PFAC_J_TOP_W     ; floor E, run ends at the east
    db PFAC_W_BOTTOM, -1, 0, PFAC_J_BOTTOM_E
    db PFAC_W_BOTTOM,  1, 0, PFAC_J_BOTTOM_W
DEF PFAC_WALL_END_CAP_COUNT EQU 8

; ============================================================
; PFacApplyCornerCaps
; The straight-wall half of this problem is PFacApplyWallEndCaps. A ring corner
; has the same defect but needs three variants rather than two, because it
; carries TWO wall arms and either or both can end against floor:
;
;   $40 C_TL arms E and S    $42 C_TR arms W and S
;   $48 C_BL arms N and E    $4A C_BR arms N and W
;
; The 12 replacements were generated mechanically, not drawn: each is its ring
; corner with the SAME cap-tile substitution the matching straight-wall jamb
; uses, so the whole set needed no new tile art. That mattered because
; facility.2bpp is exactly $600 bytes and LoadTilesetTilePatternData copies
; exactly $600, so the tileset is full at 96 tiles with only 2 unreferenced
; slots, while block ids $82-$FF were free. Generated by the recipe recorded in
; ROM_BIBLE.md; the cap alphabet is $2D top-left, $2E top-right, $3B
; bottom-left, $3C bottom-right, which the ring corners were already built from.
;
; Connectivity-neutral for the same reason the straight caps are: none of the
; substituted tile offsets is one of the quadrant offsets 5/7/13/15, so every
; variant keeps its corner's walkable mask exactly ($82-$84 are ...1 like $40,
; $85-$87 are ..1. like $42, $88-$8A are .1.. like $48, $8B-$8D are 1... like
; $4A). Verified by the generator, which refuses to emit a block whose mask
; moved.
; ============================================================
PFacApplyCornerCaps:
    xor a
    ld [wBuffer + wPFacLoopY], a
.row
    xor a
    ld [wBuffer + wPFacLoopX], a
.column
    ld a, [wBuffer + wPFacLoopX]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacLoopY]
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    ld [wBuffer + wPFacCapWall], a
    ld hl, PFacCornerCapTable
    ld b, PFAC_CORNER_CAP_COUNT
.entry
    ld a, [wBuffer + wPFacCapWall]
    cp [hl]
    jr z, .found
    ld de, PFAC_CORNER_CAP_STRIDE
    add hl, de
    dec b
    jr nz, .entry
    jr .advance
.found
    ld c, 0                       ; bit 0 = arm 1 ends, bit 1 = arm 2 ends
    push hl
    inc hl                        ; -> arm 1 dx
    call PFacCornerArmIsFloor     ; leaves hl -> arm 2 dx
    jr nz, .arm2
    set 0, c
.arm2
    call PFacCornerArmIsFloor     ; leaves hl -> the replacement triple
    jr nz, .pick
    set 1, c
.pick
    pop hl
    ld a, c
    and a
    jr z, .advance                ; both arms continue, the corner is fine
    dec a                         ; 0 = arm 1 only, 1 = arm 2 only, 2 = both
    ld e, a
    ld d, 0
    add hl, de
    ld de, 5
    add hl, de
    ld a, [wBuffer + wPFacLoopX]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacLoopY]
    ld [wBuffer + wPFacCurY], a
    ld a, [hl]
    call PFacWriteBlock
.advance
    ld hl, wBuffer + wPFacLoopX
    inc [hl]
    ld a, [hl]
    cp PFAC_SIZE
    jp c, .column
    ld hl, wBuffer + wPFacLoopY
    inc [hl]
    ld a, [hl]
    cp PFAC_SIZE
    jp c, .row
    ret

; INPUT hl -> a [dx, dy] pair, with the sweep cell in LoopX/LoopY.
; OUTPUT Z when that neighbour is plain floor. Advances hl past the pair and
; preserves c, which carries the caller's arm flags. Out-of-range coordinates
; read as solid wall, so the map edges need no guard.
PFacCornerArmIsFloor:
    ld a, [wBuffer + wPFacLoopX]
    add a, [hl]
    ld [wBuffer + wPFacCurX], a
    inc hl
    ld a, [wBuffer + wPFacLoopY]
    add a, [hl]
    ld [wBuffer + wPFacCurY], a
    inc hl
    push hl
    call PFacReadBlock            ; preserves bc
    pop hl
    cp PFAC_FLOOR
    ret

; corner id, arm 1 dx/dy, arm 2 dx/dy, then the replacement for arm 1 alone,
; arm 2 alone, and both. Arm order matches the block ids, which run
; arm1 / arm2 / both per corner from $82.
DEF PFAC_CORNER_CAP_STRIDE EQU 8
PFacCornerCapTable:
    db PFAC_C_TL,  1,  0,  0,  1, PFAC_CC_TL_E, PFAC_CC_TL_S, PFAC_CC_TL_ES
    db PFAC_C_TR, -1,  0,  0,  1, PFAC_CC_TR_W, PFAC_CC_TR_S, PFAC_CC_TR_WS
    db PFAC_C_BL,  0, -1,  1,  0, PFAC_CC_BL_N, PFAC_CC_BL_E, PFAC_CC_BL_NE
    db PFAC_C_BR,  0, -1, -1,  0, PFAC_CC_BR_N, PFAC_CC_BR_W, PFAC_CC_BR_NW
DEF PFAC_CORNER_CAP_COUNT EQU 4

; ============================================================
; PFacRemoveStrandedJambs
; A doorway jamb draws a wall "arm" on the side AWAY from its gap: $58 and the
; authored $2A extend west, $57 and the authored $2B extend east. Three ways
; that arm goes missing, all of which leave the jamb standing alone in open
; floor, which reads in game as a short wall stub floating in the middle of a
; room. Measured over the 128-layout smoke corpus, 2026-09-16:
;
;   Two doorways through one wall with a single block between them. The flank
;   rewrite only touches blocks that are STILL the plain straight wall, so the
;   shared block keeps the first doorway's jamb and the second doorway's
;   corridor eats the floor on its other side. 3 of the 103 $57 placed; seeds
;   (92,96,180,132) at (12,8) and (12,13), (166,82,114,90) at (8,4).
;
;   A premade's west socket carve removing the $6B half of the authored $6B/$2A
;   pair. This is the common case: 7 of the 22 $2A placed. Every $2A in the
;   corpus sits against either $6B or floor, never anything else, which is what
;   makes "floor to the west" an unambiguous defect rather than a style.
;
;   PFacRemoveIsolatedGeneratedCorners writing floor over a ring corner that a
;   jamb was leaning on. Not observed, but it runs before this pass precisely so
;   that it cannot hide one.
;
; Repair is to delete the stub, replacing it with plain floor. That direction is
; safe by construction for the reachability and stranded-quadrant assertions:
; PFAC_FLOOR is walkable in all four quadrants, so overwriting ANY block with it
; can only add walkable cells, never remove one. It cannot expose a void either
; in the measured corpus - all 10 offenders had a wall or floor on every
; cardinal side, never $2E.
;
; A single forward sweep is enough. Two same-id jambs cannot end up adjacent:
; the flank rewrite skips a block that already holds a jamb, so the only
; neighbouring pair it can produce is $57 beside $58, which is a genuine
; two-block wall segment between two doorways and is deliberately left alone.
; PFacReadBlock reads out of range as solid wall, so the map edges need no
; guard of their own.
; ============================================================
PFacRemoveStrandedJambs:
    xor a
    ld [wBuffer + wPFacCurY], a
.row
    xor a
    ld [wBuffer + wPFacCurX], a
.column
    call PFacReadBlock
    ld c, $FF                     ; arm lies to the WEST
    cp PFAC_J_BOTTOM_W
    jr z, .probe
    cp PFAC_J_AUTHORED_W
    jr z, .probe
    ld c, 1                       ; arm lies to the EAST
    cp PFAC_J_BOTTOM_E
    jr z, .probe
    cp PFAC_J_AUTHORED_E
    jr nz, .advance
.probe
    ld a, [wBuffer + wPFacCurX]
    ld b, a                       ; column to come back to
    add a, c
    ld [wBuffer + wPFacCurX], a
    call PFacReadBlock            ; preserves bc
    ld c, a
    ld a, b
    ld [wBuffer + wPFacCurX], a
    ld a, c
    cp PFAC_FLOOR
    jr nz, .advance
    ld a, PFAC_FLOOR
    call PFacWriteBlock
.advance
    ld hl, wBuffer + wPFacCurX
    inc [hl]
    ld a, [hl]
    cp PFAC_SIZE
    jr c, .column
    ld hl, wBuffer + wPFacCurY
    inc [hl]
    ld a, [hl]
    cp PFAC_SIZE
    jr c, .row
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
; 1-cell wall ring is added). One Random draw masked to 5 bits indexes a
; 32-byte table, so this is exactly one draw with no rejection loop - cheaper
; than the Rangerandom(7)-twice-take-the-min it replaced (that averaged 1.14
; draws each, 2.28 total), and it decouples speed from shape: the curve is now
; 32 bytes to hand-edit, not code. Table and rationale are
; PROCEDURAL_FACILITY_CONTENT_PLAN.md section 1 (C5). Clobbers a, d, e, hl.
; ============================================================
PFacRollRoomDim:
    call Random
    and %00011111               ; 0..31
    ld hl, PFacRoomDimTable
    ld d, 0
    ld e, a
    add hl, de
    ld a, [hl]                  ; 1..7
    ret

; 32-entry size curve, indexed 0-31 by 5 random bits. Humped on 3-5 rather than
; uniform: a plain uniform draw over-produces the 8x8/9x9 footprints, which
; saturate the grid fastest and whose templates (6x7/7x7/8x7/9x5/9x7) were
; measured as never occurring even once under the old distribution.
PFacRoomDimTable:
    db 1, 1, 1
    db 2, 2, 2, 2
    db 3, 3, 3, 3, 3, 3
    db 4, 4, 4, 4, 4, 4, 4
    db 5, 5, 5, 5, 5, 5
    db 6, 6, 6, 6
    db 7, 7
PFacRoomDimTableEnd:
ASSERT PFacRoomDimTableEnd - PFacRoomDimTable == 32

; ============================================================
; PFacPlaceEntryRoom  (room 0)
; Small floor rect, bottom-aligned (floor bottom = row 18, wall ring at row 19),
; positioned so the reserved block (9,17) is inside it. Always succeeds.
;
; (9,17) was called "the fixed spawn block" here until 2026-09-16, when warping
; in and reading wYCoord/wXCoord measured the player arriving at (9,19) instead,
; standing on the south warp tile, which is the ordinary pokered behaviour -
; nothing in this file, procedural_stage_hooks.asm or scripts/
; ProceduralFacility.asm ever writes the player's coordinates. The block is no
; longer reserved for anything; see PFAC_TPL_SPAWN. The H floor of 2 is kept
; because the entry room wants a real interior to arrive into, not because any
; particular block is special.
; ============================================================
PFacPlaceEntryRoom:
    xor a
    ld [wBuffer + wPFacPlaceId], a
    call PFacRollRoomDim
    cp PFAC_ENTRY_MAX_DIM + 1
    jr c, .widthCapped
    ld a, PFAC_ENTRY_MAX_DIM
.widthCapped
    ld [wBuffer + wPFacCandW], a  ; floor W 1-PFAC_ENTRY_MAX_DIM, biased small
    call PFacRollRoomDim
    cp PFAC_ENTRY_MAX_DIM + 1
    jr c, .heightCapped
    ld a, PFAC_ENTRY_MAX_DIM
.heightCapped
    cp 2
    jr nc, .heightOK
    inc a
.heightOK
    ld [wBuffer + wPFacCandH], a  ; floor H 2-PFAC_ENTRY_MAX_DIM; the player
                                  ; arrives into a real interior, not a slot
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
    cp PFAC_EXIT_MAX_DIM + 1
    jr c, .widthCapped
    ld a, PFAC_EXIT_MAX_DIM
.widthCapped
    ld [wBuffer + wPFacCandW], a
    call PFacRollRoomDim
    cp PFAC_EXIT_MAX_DIM + 1
    jr c, .heightCapped
    ld a, PFAC_EXIT_MAX_DIM
.heightCapped
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
    ld [wBuffer + wPFacRetry], a
    ld a, PFAC_SHRINK_ITEM
    jr .setRetries
.exploreRetries
    ld a, 32
    ld [wBuffer + wPFacRetry], a
    ld a, PFAC_SHRINK_EXPLORE
.setRetries
    ld [wBuffer + wPFacShrinkIn], a

    ; C4: roll the size ONCE for this room. Retries below re-roll only the
    ; parent and position, and shrink this size rather than discarding it.
    call PFacRollRoomDim
    ld [wBuffer + wPFacCandW], a
    call PFacRollRoomDim
    ld [wBuffer + wPFacCandH], a
.attempt
    call PFacRollCandidate        ; a=0 accept, a=1 reject
    and a
    jr z, .accepted

    ; C4: K consecutive failures shrink the candidate one step, floored at
    ; PFAC_SHRINK_FLOOR, then the counter reloads for the next step.
    ld hl, wBuffer + wPFacShrinkIn
    dec [hl]
    jr nz, .noShrink
    ld a, [wBuffer + wPFacPlaceId]
    cp 5
    ld a, PFAC_SHRINK_EXPLORE
    jr nc, .reloadShrink
    ld a, PFAC_SHRINK_ITEM
.reloadShrink
    ld [hl], a
    ; Shrink the LARGER axis only. Taking both every step loses area twice as
    ; fast and drives rooms toward the floor on both sides; taking the larger one
    ; pulls them toward square instead, which is what keeps corridor junctions
    ; alive (measured: both-axes lost the junction block entirely in 7 of 128
    ; layouts, where the baseline lost it in none).
    ld hl, wBuffer + wPFacCandH
    ld a, [wBuffer + wPFacCandW]
    cp [hl]
    jr c, .shrinkChosen           ; W < H, so hl already points at H
    ld hl, wBuffer + wPFacCandW
.shrinkChosen
    ld a, [hl]
    cp PFAC_SHRINK_FLOOR + 1
    jr c, .noShrink
    dec [hl]
.noShrink
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

; Roll one placement POSITION for the current candidate size, beside a chosen
; parent. OUT a=0 accept, a=1 reject.
;
; C4: this used to roll wPFacCandW/H as well, so every retry threw away the size
; along with the position. The caller now rolls the size once per room and
; shrinks it on sustained failure, which is what lets a big room compete for
; space.
;
; C9 (2026-09-16): the position used to be the parent's CENTER plus an offset of
; rand(-5..5) on each axis, which could not reach a legal cell. PFacCandOverlaps
; wants a 2-cell gap, so clearing a parent needs an offset of
; parentW + 2 - parentW/2 + candW/2. That passes 5 as soon as
; parent interior + candidate interior >= 6, and then NO offset on that axis can
; ever separate the two rects. Measured consequences on the old code, 128
; layouts: an interior of 5 or more on both axes occurred 0.00 times per layout
; (it is arithmetically impossible against any parent, including a 1x1 one),
; 674 of 768 explore rooms never placed, and 49% of item rooms fell through to
; PFacForceItemRoom's top-left linear scan, which is why so many rooms were 3x3
; and huddled in a corner. The shrink schedule was never the binding constraint:
; simulating a floor of 1 still yielded 0.00 big rooms.
;
; So the candidate is now placed BESIDE the parent instead of on top of it: roll
; a side, sit exactly PFAC_ROOM_GAP clear of the parent on that axis (the
; closest cell the +2 rule permits, so no space is wasted), and slide along the
; other axis by rand(-3..3) for variety. Every roll is now a geometrically legal
; position with respect to the parent, and only the OTHER placed rooms and the
; map bounds can reject it. Corridors get shorter too, since PFacCarveCorridors
; routes each room to this same parent.
;
; Two random draws per attempt, one fewer than the version it replaces, and
; an attempt now covers TWO candidate positions (see C9b at .flip).
;
; Register contract: Random preserves bc/de/hl and Rangerandom preserves de/hl
; (both documented in home/random.asm), so the side and slide survive in d and e
; without touching wBuffer. PFacRoomRecordAddr clobbers de, so the parent rect
; is copied out BEFORE those two rolls, not after.
PFacRollCandidate:
    call PFacPickParent           ; -> wPFacParent (a placed id < placeId)
    ; Copy the parent rect into the B temps. The branch below needs all four
    ; bytes and only b stays free once the side and slide are rolled. These
    ; slots are dead here: R6 moved PFacCandOverlaps' scanned rect into
    ; registers, and PFacAssignExitParent runs in a later phase.
    ld a, [wBuffer + wPFacParent]
    call PFacRoomRecordAddr       ; hl -> parent X
    ld a, [hli]
    ld [wBuffer + wPFacBX], a
    ld a, [hli]
    ld [wBuffer + wPFacBY], a
    ld a, [hli]
    ld [wBuffer + wPFacBW], a
    ld a, [hl]
    ld [wBuffer + wPFacBH], a
    ld c, PFAC_SLIDE_SPAN
    call Rangerandom              ; 0..PFAC_SLIDE_SPAN-1
    sub PFAC_SLIDE_BIAS
    ld e, a                       ; e = slide, -3..3 as a signed byte
    call Random
    and 3
    ld d, a                       ; d = side: 0 N, 1 S, 2 W, 3 E
                                  ; bit 0 = which end of the axis
                                  ; bit 1 = axis (0 vertical, 1 horizontal)
                                  ; bit 2 = "already flipped", see .flip
.recompute
    bit 1, d
    jr nz, .horizontal

    ; Leaving north or south: clear the parent on Y, centre on X plus the slide.
    ld a, [wBuffer + wPFacBW]
    srl a
    ld hl, wBuffer + wPFacBX
    add a, [hl]                   ; parent center X
    ld hl, wBuffer + wPFacCandW
    ld b, [hl]
    srl b
    sub b                         ; - candW/2
    add a, e
    ld [wBuffer + wPFacCandX], a
    bit 0, d
    jr nz, .south
    ; North: Y = parentY - candH - PFAC_ROOM_GAP. Underflow wraps high and
    ; PFacCandInBounds rejects it on the `cp 19` test.
    ld a, [wBuffer + wPFacBY]
    ld hl, wBuffer + wPFacCandH
    sub [hl]
    sub PFAC_ROOM_GAP
    jr .storeY
.south
    ld a, [wBuffer + wPFacBY]
    ld hl, wBuffer + wPFacBH
    add a, [hl]
    add a, PFAC_ROOM_GAP
.storeY
    ld [wBuffer + wPFacCandY], a
    jr .bounds

.horizontal
    ; Leaving west or east: clear the parent on X, centre on Y plus the slide.
    ld a, [wBuffer + wPFacBH]
    srl a
    ld hl, wBuffer + wPFacBY
    add a, [hl]                   ; parent center Y
    ld hl, wBuffer + wPFacCandH
    ld b, [hl]
    srl b
    sub b                         ; - candH/2
    add a, e
    ld [wBuffer + wPFacCandY], a
    bit 0, d
    jr nz, .east
    ; West: X = parentX - candW - PFAC_ROOM_GAP.
    ld a, [wBuffer + wPFacBX]
    ld hl, wBuffer + wPFacCandW
    sub [hl]
    sub PFAC_ROOM_GAP
    jr .storeX
.east
    ld a, [wBuffer + wPFacBX]
    ld hl, wBuffer + wPFacBW
    add a, [hl]
    add a, PFAC_ROOM_GAP
.storeX
    ld [wBuffer + wPFacCandX], a

.bounds
    call PFacCandInBounds         ; preserves de, touches only a and hl
    and a
    jr nz, .flip
    push de                       ; PFacCandOverlaps uses d/e for the scanned
    call PFacCandOverlaps         ; rect, so the side and slide must be saved
    pop de
    and a
    ret z                         ; accepted

    ; C9b: the first side failed. Try the OPPOSITE one before spending the
    ; attempt, which costs one more geometry pass and NO extra random draw.
    ;
    ; Measured: 53.5% of all rejected rolls were out of bounds rather than
    ; collisions, because the side is rolled uniformly over four even when the
    ; parent hugs a map edge, where two of the four can never fit. Flipping is
    ; exactly `side XOR 1` (N<->S, W<->E), so the axis bit survives untouched
    ; and the slide stays meaningful for that axis.
    ;
    ; Simulated over 2500 layouts: rooms placed 7.52 -> 7.63, mean interior
    ; 10.38 -> 10.75, interiors 5x5 or larger 0.40 -> 0.47, footprint coverage
    ; 51.0% -> 52.8%.
    ;
    ; Bit 2 of d is the "already flipped" latch, which is why every dispatch
    ; above tests bit 0 / bit 1 rather than comparing d against a constant.
.flip
    bit 2, d
    jr nz, .reject
    set 2, d
    ld a, d
    xor 1
    ld d, a
    jr .recompute
.reject
    ld a, 1
    ret

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
;
; The +2 before each comparison is deliberate: a >=1 gap lets two rooms' wall
; rings (each 1 cell wide) land on the same shared cell, so whichever room's
; PFacEncloseRooms pass runs later silently overwrites the other's corner/edge
; there. A >=2 gap gives every room's ring its own dedicated cell; the second
; increment prevents those two dedicated ring cells from touching one another.
;
; R6: this is the inner loop of the generator's most expensive phase, so it now
; walks the record array with hl instead of recomputing id*6 through
; PFacRoomRecordAddr for all twelve slots, keeps the scanned rect in registers
; instead of copying it through four wBuffer bytes, and hoists the two
; candidate edge sums out of the loop. BC is preserved because
; PFacForceItemRoom holds its scan bound in b across the call.
PFacCandOverlaps:
    push bc
    ld a, [wBuffer + wPFacCandX]
    ld hl, wBuffer + wPFacCandW
    add a, [hl]
    add a, 2
    ld [wBuffer + wPFacCandSumX], a
    ld a, [wBuffer + wPFacCandY]
    ld hl, wBuffer + wPFacCandH
    add a, [hl]
    add a, 2
    ld [wBuffer + wPFacCandSumY], a

    ld a, PFAC_ROOM_MAX
    ld [wBuffer + wPFacScanId], a
    ld hl, sProcFacilityGenScratch
.loop
    ld a, [hli]
    ld d, a                      ; d = scanned room X
    ld a, [hli]
    ld e, a                      ; e = scanned room Y
    ld a, [hli]
    and a
    jr z, .next                  ; unplaced slot; hl now points at its H byte
    ld b, a                      ; b = scanned room W
    ld c, [hl]                   ; c = scanned room H
    push hl

    ld hl, wBuffer + wPFacCandSumX
    ld a, [hl]
    cp d
    jr c, .separated             ; candX + candW + 2 < roomX
    ld a, d
    add a, b
    add a, 2
    ld hl, wBuffer + wPFacCandX
    cp [hl]
    jr c, .separated             ; roomX + roomW + 2 < candX
    ld hl, wBuffer + wPFacCandSumY
    ld a, [hl]
    cp e
    jr c, .separated             ; candY + candH + 2 < roomY
    ld a, e
    add a, c
    add a, 2
    ld hl, wBuffer + wPFacCandY
    cp [hl]
    jr c, .separated             ; roomY + roomH + 2 < candY

    pop hl
    pop bc
    ld a, 1                      ; no axis separated them -> overlap
    ret
.separated
    pop hl
.next
    inc hl
    inc hl
    inc hl                       ; H byte -> the next record
    ld a, [wBuffer + wPFacScanId]
    dec a
    ld [wBuffer + wPFacScanId], a
    jr nz, .loop
    pop bc
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

; Z set (a=0) if room wPFacCorId is unplaced (W=0); else NZ.
PFacCorRoomPlaced:
    ld a, [wBuffer + wPFacCorId]
    call PFacRoomRecordAddr
    inc hl
    inc hl
    ld a, [hl]
    and a
    ret

; ============================================================
; PFacCarveOneCorridor
; INPUT a = target room id; wPFacCorId = source room id. Carves a 1-wide
; manhattan corridor of PFAC_CORRIDOR from the source center all the way to the
; target center. Crossing another room or corridor does not stop the walk,
; preserving the recorded parent-tree connectivity contract.
;
; R6: the route is no longer fixed. Every path here is described by a single
; number, the ELBOW column, and is walked in three legs: along row SY from SX to
; the elbow, down column elbow from SY to TY, then along row TY to TX. An elbow
; of TX collapses leg 3 and reproduces the original horizontal-leg-first L
; exactly; an elbow of SX collapses leg 1 and gives the vertical-first L; any
; column between them gives a Z with one extra turn. All three shapes leave the
; source along its center row and arrive at the target along a center row or
; column, so every one of them still enters and leaves through canonical
; sockets.
;
; Why this exists. PFacValidateGeneratedCorners is the ONLY gate that can throw
; a layout away, and measurement showed every single rejection was one corridor
; clipping one room's footprint ring corner - the cell PFacRingWrite then
; refuses to overwrite, leaving the corner wrong. A rejection costs a full
; pipeline re-roll, and the worst measured seed paid for eighteen of them.
; Choosing an elbow that misses every corner rescues about 84% of those
; layouts (tools/pyboy_smoke/simulate_facility_corridor_policy.py). TX is tried
; first, so any layout that is accepted today carves exactly the path it always
; did.
; ============================================================
PFacCarveOneCorridor:
    push af
    ld a, [wBuffer + wPFacCorId]
    call PFacRoomCenter
    ld a, b
    ld [wBuffer + wPFacCorSX], a
    ld a, c
    ld [wBuffer + wPFacCorSY], a
    pop af
    call PFacRoomCenter
    ld a, b
    ld [wBuffer + wPFacCorTX], a
    ld a, c
    ld [wBuffer + wPFacCorTY], a
    call PFacChooseCorridorRoute

    ld a, [wBuffer + wPFacCorSX]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacCorSY]
    ld [wBuffer + wPFacCurY], a
.leg1                            ; row SY, walk X to the elbow
    call PFacCorStampCell
    ld a, [wBuffer + wPFacCurX]
    ld hl, wBuffer + wPFacCorElbow
    cp [hl]
    jr z, .leg2
    jr c, .leg1Inc
    dec a
    ld [wBuffer + wPFacCurX], a
    jr .leg1
.leg1Inc
    inc a
    ld [wBuffer + wPFacCurX], a
    jr .leg1
.leg2                            ; column elbow, walk Y to TY
    call PFacCorStampCell
    ld a, [wBuffer + wPFacCurY]
    ld hl, wBuffer + wPFacCorTY
    cp [hl]
    jr z, .leg3
    jr c, .leg2Inc
    dec a
    ld [wBuffer + wPFacCurY], a
    jr .leg2
.leg2Inc
    inc a
    ld [wBuffer + wPFacCurY], a
    jr .leg2
.leg3                            ; row TY, walk X to TX
    call PFacCorStampCell
    ld a, [wBuffer + wPFacCurX]
    ld hl, wBuffer + wPFacCorTX
    cp [hl]
    ret z
    jr c, .leg3Inc
    dec a
    ld [wBuffer + wPFacCurX], a
    jr .leg3
.leg3Inc
    inc a
    ld [wBuffer + wPFacCurX], a
    jr .leg3

; Pick the elbow column for the route described by wPFacCorSX/SY and
; wPFacCorTX/TY, and leave it in wPFacCorElbow. TX is tried first so an already
; clean layout is carved exactly as before, then SX, then every column between
; them. If no candidate is clean the original TX shape is restored and the
; layout is rejected downstream exactly as it is today.
PFacChooseCorridorRoute:
    ld a, [wBuffer + wPFacCorTX]
    ld [wBuffer + wPFacCorElbow], a
    call PFacRouteClipsCorner
    ret nc
    ld a, [wBuffer + wPFacCorSX]
    ld [wBuffer + wPFacCorElbow], a
    call PFacRouteClipsCorner
    ret nc
.span
    ld a, [wBuffer + wPFacCorElbow]
    ld hl, wBuffer + wPFacCorTX
    cp [hl]
    jr z, .exhausted
    jr c, .spanInc
    dec a
    jr .spanStore
.spanInc
    inc a
.spanStore
    ld [wBuffer + wPFacCorElbow], a
    ld hl, wBuffer + wPFacCorTX
    cp [hl]
    jr z, .exhausted             ; walked back to TX, which was candidate one
    call PFacRouteClipsCorner
    ret nc
    jr .span
.exhausted
    ld a, [wBuffer + wPFacCorTX]
    ld [wBuffer + wPFacCorElbow], a
    ret

; Carry set when the candidate route passes through any placed room's footprint
; ring corner - the exact condition PFacValidateGeneratedCorners rejects on.
;
; Every placed room is tested, including ones that will later be replaced by a
; premade, because PFacCarveCorridors runs once BEFORE premade selection and
; once after, and both passes must choose the same elbow or the second pass
; would carve a different corridor than the first. That costs nothing in
; practice: PFacPremadePerimeterClear scans the full top and bottom footprint
; rows, so a room whose ring corner a corridor crossed is refused a template
; anyway and is validated as a generic room.
PFacRouteClipsCorner:
    xor a
    ld [wBuffer + wPFacCorScan], a
.room
    ld a, [wBuffer + wPFacCorScan]
    cp PFAC_ROOM_MAX
    jr nc, .clean
    call PFacRoomRecordAddr
    ld a, [hli]
    ld d, a                      ; d = interior X
    ld a, [hli]
    ld e, a                      ; e = interior Y
    ld a, [hli]
    and a
    jr z, .next                  ; unplaced slot
    ld b, a                      ; b = interior W
    ld c, [hl]                   ; c = interior H

    ; Cheap per-room rejection before the four per-corner tests. The route only
    ; ever occupies row SY, row TY and column elbow, so a corner of this room
    ; can only be on it if one of the room's two ring ROWS is SY or TY, or one
    ; of its two ring COLUMNS is the elbow. Most rooms fail all six compares and
    ; never pay for a single PFacRouteHitsPoint call. hl is free here: the
    ; record pointer has already been fully consumed.
    ld a, e
    dec a                        ; top ring row
    ld hl, wBuffer + wPFacCorSY
    cp [hl]
    jr z, .candidate
    ld hl, wBuffer + wPFacCorTY
    cp [hl]
    jr z, .candidate
    ld a, e
    add a, c                     ; bottom ring row
    ld hl, wBuffer + wPFacCorSY
    cp [hl]
    jr z, .candidate
    ld hl, wBuffer + wPFacCorTY
    cp [hl]
    jr z, .candidate
    ld hl, wBuffer + wPFacCorElbow
    ld a, d
    dec a                        ; left ring column
    cp [hl]
    jr z, .candidate
    ld a, d
    add a, b                     ; right ring column
    cp [hl]
    jr nz, .next

.candidate
    ld a, d
    dec a
    ld [wBuffer + wPFacCorPX], a ; left ring column
    ld a, e
    dec a
    ld [wBuffer + wPFacCorPY], a ; top ring row
    call PFacRouteHitsPoint
    ret c
    ld a, d
    add a, b
    ld [wBuffer + wPFacCorPX], a ; right ring column
    call PFacRouteHitsPoint
    ret c
    ld a, e
    add a, c
    ld [wBuffer + wPFacCorPY], a ; bottom ring row
    call PFacRouteHitsPoint
    ret c
    ld a, d
    dec a
    ld [wBuffer + wPFacCorPX], a
    call PFacRouteHitsPoint
    ret c
.next
    ld hl, wBuffer + wPFacCorScan
    inc [hl]
    jr .room
.clean
    and a
    ret

; Carry set if the candidate route passes through (wPFacCorPX, wPFacCorPY).
; Preserves BC and DE so PFacRouteClipsCorner keeps the room rect it loaded.
PFacRouteHitsPoint:
    push bc
    push de
    ld a, [wBuffer + wPFacCorPY]
    ld hl, wBuffer + wPFacCorSY
    cp [hl]
    jr nz, .leg2                 ; not on the source row
    ld a, [wBuffer + wPFacCorSX]
    ld b, a
    ld a, [wBuffer + wPFacCorElbow]
    ld c, a
    ld a, [wBuffer + wPFacCorPX]
    call PFacWithinSpan
    jr c, .hit
.leg2
    ld a, [wBuffer + wPFacCorPX]
    ld hl, wBuffer + wPFacCorElbow
    cp [hl]
    jr nz, .leg3                 ; not on the elbow column
    ld a, [wBuffer + wPFacCorSY]
    ld b, a
    ld a, [wBuffer + wPFacCorTY]
    ld c, a
    ld a, [wBuffer + wPFacCorPY]
    call PFacWithinSpan
    jr c, .hit
.leg3
    ld a, [wBuffer + wPFacCorPY]
    ld hl, wBuffer + wPFacCorTY
    cp [hl]
    jr nz, .miss                 ; not on the target row
    ld a, [wBuffer + wPFacCorElbow]
    ld b, a
    ld a, [wBuffer + wPFacCorTX]
    ld c, a
    ld a, [wBuffer + wPFacCorPX]
    call PFacWithinSpan
    jr c, .hit
.miss
    pop de
    pop bc
    and a
    ret
.hit
    pop de
    pop bc
    scf
    ret

; Carry set when a lies in the inclusive span between b and c, given in either
; order. Clobbers a, b, c and d.
PFacWithinSpan:
    ld d, a
    ld a, b
    cp c
    jr c, .ordered
    jr z, .ordered
    ld a, b
    ld b, c
    ld c, a                      ; swap so b is the low end
.ordered
    ld a, d
    cp b
    jr c, .outside
    ld a, c
    cp d
    jr c, .outside
    scf
    ret
.outside
    and a
    ret

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
    ld b, 0                     ; C3: room 0 is stamped too (see C2's bug)
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
    cp 12                       ; C2: room 11 is stamped too, so its socket must be cuttable
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

    ; C9: a PREMADE exit room must be opened at its CANONICAL socket.
    ;
    ; sProcFacilityExitI is rolled in PFacPlaceExitRoom, long before any
    ; template is chosen, and names an arbitrary interior row (west/east) or
    ; column (north). For a plain room that is harmless, every interior cell
    ; being floor. For a premade it is not: the payload owns its ring AND its
    ; interior art, so an opening can land against a cell that is solid on the
    ; exit side, and then the boss, both exit warp tiles and the whole room
    ; beyond are unreachable.
    ;
    ; Measured 2026-09-16 on ProceduralFacility_5x5__rock_room, whose west ring
    ; is 68 5C 5C 44 48 and whose first interior column is 41 38 0E 0E 49: an
    ; opening on its first interior row meets $38, solid on its west half, and
    ; stranded 8 quadrants including the exit itself.
    ;
    ; The canonical socket is the one position that carries a guarantee. The
    ; socket mask in PFacRoomDescriptors is measured by
    ; tools/check_facility_premades.py as "cutting THIS cell to floor connects
    ; to the interior without leaking", so aligning the opening with it is
    ; exactly the case that was verified. Its coordinate is the room centre,
    ; matching _hub_and_sockets in that tool and PFacRoomCenter here.
    ;
    ; NOTE the PFAC_TPL_EXIT_N/W/E bits do NOT cover this. They are measured
    ; with all four canonical sockets held open at once, but at runtime
    ; PFacCarveCorridors reopens only the sockets a corridor actually traversed,
    ; so a payload can pass that check by borrowing a path through a socket that
    ; is still solid art on the real map. Correcting that measurement moves
    ; exit bits on 24 of 83 payloads and spawn bits on 9, so it is left alone
    ; here and this aligns the opening instead.
    ;
    ; Plain and large-decor exit rooms keep their rolled position, which is what
    ; preserves variety in where the exit sits along its edge.
    ld a, 11
    call PFacRoomRecordAddr
    ld de, 5
    add hl, de
    bit 7, [hl]                   ; PFAC_TEMPLATE_FLAG
    jr z, .exitIndexKept
    ld a, 11
    call PFacRoomCenter           ; b = centre X, c = centre Y
    ld a, [sProcFacilityExitEdge]
    and a
    ld a, c                       ; west/east: the socket is a ROW
    jr nz, .exitIndexStore
    ld a, b                       ; north: the socket is a COLUMN
.exitIndexStore
    ld [sProcFacilityExitI], a
.exitIndexKept

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
    ; Phase 7: the stage-event NPCs need the same per-preload reset the boss
    ; gets. They are run-scoped events, so without this a run whose SECOND
    ; wild area also rolls an event would find the flag already set by the
    ; first, and that villain could never be engaged.
    ResetEvent EVENT_BEAT_STAGE_EVENT_NPC_1
    ResetEvent EVENT_BEAT_STAGE_EVENT_NPC_2
    ResetEvent EVENT_BEAT_FACILITY_STAGE_NPC_1
    ResetEvent EVENT_BEAT_FACILITY_STAGE_NPC_2
    ResetEvent EVENT_PC_BOSS_OFFERED
    ResetEvent EVENT_PC_BUDGET_ENDED
    ResetEvent EVENT_PC_CALMED_SHOWN
    ResetEvent EVENT_BEAT_FACILITY_FAKE_BALL_1
    ResetEvent EVENT_BEAT_FACILITY_FAKE_BALL_2
    ResetEvent EVENT_BEAT_FACILITY_FAKE_BALL_3
    ResetEvent EVENT_BEAT_FACILITY_FAKE_BALL_4

    ; Phase 7 rollout: publish the stage-event NPC sprites for this
    ; assignment, same reason and timing as the cave/forest's own preload.
    ; Re-asserts SRAM bank 0 itself (this routine has been on bank 1 -
    ; "facility SRAM" - throughout) and leaves the window open; the close
    ; below does not care which bank was last selected.
    farcall StageEventStageSprites

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

    ; Phase 7 rollout: pick the stage-event hideout. Must run after
    ; PFacGenerateFacility (room records need to be final) and works fine
    ; here despite PFacPlaceItems having already overwritten
    ; sProcFacilityGenScratch bytes 0-7 (room 0's record + room 1's X/Y) -
    ; PFacPickHideout never reads rooms 0 or 1.
    call PFacPickHideout

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
    ; THIS, not the object list, is where the facility's entrance actually
    ; comes from: the literals below overwrite warp entry 0 on every
    ; finalize, so editing data/maps/objects/ProceduralFacility.asm alone
    ; changes nothing the player ever stands on. The two are kept in step
    ; deliberately - the object list is what a reader looks at first.
    ; (39,18) is the BOTTOM-LEFT quadrant of block (9,19), in wWarpEntries'
    ; Y-then-X order; the top two quadrants of that block belong to the
    ; stage-event NPC pair.
    ld hl, wWarpEntries
    ld a, 39
    ld [hli], a
    ld a, 18
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

    ; Phase 7 rollout: stage-event NPC slots 10-11. ONE call site, not two -
    ; both paths already converge at .placeSprites, well before this point.
    ; Each routine opens its own SRAM window (sStageEventHideoutX/Y are bank
    ; 0; everything above this point has been bank 1).
    call PFacPlaceStageEventNpcs
    call PFacApplyStageEventTrainers
    ret

; ============================================================
; PFacPickHideout  (Phase 7 rollout)
; Picks the stage-event hideout from a placed, non-entry, non-exit room.
; Candidates are rooms 2-10 ONLY, never 0 or 1: PFacPlaceItems (already run,
; as part of PFacGenerateFacility above) overwrites sProcFacilityGenScratch
; bytes 0-7 with the four real balls' (X,Y) - room 0's whole record plus room
; 1's X,Y - so those two rooms' records are no longer trustworthy by the time
; this runs. Rooms 2-4 (the other item rooms) are guaranteed placed (rule e
; in this file's own header), so there are always at least 3 real candidates
; and the "no candidates" branch below is unreachable in practice - kept as a
; defined outcome rather than an assumption.
;
; The hideout starts as the room's CENTER cell (X + W/2, Y + H/2) and is then
; nudged onto plain floor by PFacHideoutFindFloor. The center is inside the
; room's stamped interior - PFacEncloseRooms only walls the OUTSIDE perimeter
; - but "interior" is NOT the same as "floor", because the decoration passes
; at the end of PFacGenerateFacility stamp furniture there. That was the
; original claim here and it was wrong; see PFacHideoutFindFloor for the
; measurement that falsified it.
;
; Target ordinal parked in wStageEventScratch, not a register: the room-id
; loop calls PFacRoomRecordAddr repeatedly, which clobbers d/e, and b/c are
; already the loop counter and the room count.
;
; SRAM enters on bank 1 (sProcFacilityGenScratch's bank, already selected by
; the caller) and MUST leave on bank 1 - PFacFinalize's own item-save and
; bake steps immediately after this call assume it.
; Clobbers a/bc/de/hl.
; ============================================================
PFacPickHideout:
    ld b, 2
    ld c, 0
.countLoop
    ld a, b
    call PFacRoomRecordAddr
    ld de, 2
    add hl, de
    ld a, [hl]                      ; W byte (0 = not placed)
    and a
    jr z, .countNext
    inc c
.countNext
    inc b
    ld a, b
    cp 11
    jr c, .countLoop
    ld a, c
    and a
    jr nz, .haveCandidates
    jp .disarm
.haveCandidates
    call Rangerandom                ; a = 0..count-1 (c holds the count)
    ld [wStageEventScratch], a      ; target ordinal
    ld b, 2
.pickLoop
    ld a, b
    call PFacRoomRecordAddr
    push hl
    ld de, 2
    add hl, de
    ld a, [hl]                      ; W byte
    pop hl
    and a
    jr z, .pickNext
    ld a, [wStageEventScratch]
    and a
    jr z, .found
    dec a
    ld [wStageEventScratch], a
.pickNext
    inc b
    jr .pickLoop

; This room's center and all four of its neighbours are decorated or void, so
; try the NEXT placed room rather than giving up. Measured 2026-09-17: probing
; the five cells alone left 2 of 40 layouts with no hideout at all, which is a
; 5% chance of the event simply not happening; walking on to the next room took
; that to 0 of 40. The walk goes b+1..10 and then wraps once through 2..b, so
; every placed room is tried before .disarm - which remains a defined
; outcome, just a much rarer one. Disarming is still the right end state
; when it happens: no event at all beats one standing inside a wall.
.nextRoom
    inc b
    ld a, b
    cp 11
    jr c, .nextRoomHaveId
    ; Past room 10. Go round ONCE from room 2 rather than giving up, so a pick
    ; that happened to land on a high room is not penalised for it -
    ; wStageEventScratch counted the target ordinal down to exactly 0 on the
    ; way into .found, so it is free to reuse here as the "already wrapped"
    ; flag and costs no new state.
    ld a, [wStageEventScratch]
    and a
    jr nz, .disarm
    inc a
    ld [wStageEventScratch], a
    ld b, 2
.nextRoomHaveId
    ld a, b
    call PFacRoomRecordAddr
    push hl
    ld de, 2
    add hl, de
    ld a, [hl]                      ; W byte (0 = not placed)
    pop hl
    and a
    jr z, .nextRoom
    ; fall through with hl = this room's record, exactly as .pickLoop leaves it
.found
    ld a, [hli]
    ld d, a                         ; d = room X
    ld a, [hli]
    ld e, a                         ; e = room Y
    ld a, [hli]                     ; W
    srl a
    add a, d
    ld d, a                         ; d = center X
    ld a, [hl]                      ; H
    srl a
    add a, e
    ld e, a                         ; e = center Y
    ; THE CENTER IS NOT RELIABLY FLOOR, despite this routine's header
    ; having claimed it was. The decoration passes (PFacPlaceLargeDecor,
    ; PFacDecorateExploreRooms) run at the END of PFacGenerateFacility,
    ; after the room interiors are stamped, and a room's center is exactly
    ; where a premade puts its furniture. MEASURED 2026-09-17 over 40
    ; layouts: 9 of them (22.5%) put the pair on a decoration block, and
    ; ONE of those was solid void with no walkable neighbour at all, so the
    ; encounter could not be reached and was simply lost. Block $37 and
    ; $67 are furniture tops - solid above, walkable along the bottom edge,
    ; the ordinary Gen 1 convention - while $47 is a furniture middle and
    ; $5b is solid void.
    ;
    ; So test it, and take a neighbour if it fails. PFAC_FLOOR is the
    ; all-$01 block, which is walkable in all four quadrants - the pair
    ; stands on two of them, so "walkable somewhere in this block" is not
    ; a strong enough test and the exact block id is the right one.
    call PFacHideoutFindFloor
    jr nc, .nextRoom                ; nothing plain-floor at or beside it
    xor a
    ld [rRAMB], a                   ; bank 0: sStageEventHideoutX/Y
    ld a, d
    ld [sStageEventHideoutX], a
    ld a, e
    ld [sStageEventHideoutY], a
    jr .restoreBank
.disarm
    xor a
    ld [rRAMB], a
    ld a, STAGE_EVENT_NO_HIDEOUT
    ld [sStageEventHideoutX], a
    ld [sStageEventHideoutY], a
.restoreBank
    ld a, BANK(sProcFacilityStagingBuffer)
    ld [rRAMB], a
    ret

; ============================================================
; PFacPlaceStageEventNpcs  (Phase 7 rollout)
; Facility's counterpart to the cave's PCPlaceStageEventNpcs, for slots 10-11
; instead of 6-7. The entrance is a FIXED block, (9,19) - see this file's own
; warp_event comment in data/maps/objects/ProceduralFacility.asm ("south
; entry socket at generated block (9,19)") - so, like the forest, no SRAM
; read is needed for it.
;
; "One cell inward" does not carry over from the cave/forest: those hideouts
; are dead-end maze cells with a well-defined single open direction; this one
; is a room CENTER, which has no such direction. Slot 11 is simply one block
; to the right of slot 10 (left if that would leave the grid), which costs
; nothing beyond guaranteeing the pair never shares a cell - the only hard
; requirement (see the cave's own PCPlaceStageEventNpcs header for why
; walkability itself was proven unnecessary to check).
; Clobbers a/bc/de/hl.
; ============================================================
; ============================================================
; PFacHideoutFindFloor  (2026-09-17)
; Nudges a hideout candidate onto a PFAC_FLOOR block.
;
; INPUT:  d,e = candidate block X,Y
; OUTPUT: carry SET  = d,e now name a PFAC_FLOOR block
;         carry CLEAR = neither the candidate nor any of its four
;                       orthogonal neighbours is plain floor; the caller
;                       disarms, which is the right answer - no event at
;                       all beats one standing inside a wall.
;
; The candidate itself is tried first, then SOUTH before the other three.
; That ordering is not arbitrary: the two decoration blocks that actually
; came up in measurement ($37, $67) are furniture TOPS, solid on their top
; half and walkable along the bottom, which is the Gen 1 convention for
; standing in front of an object - so the cell one step south of a piece of
; furniture is the most likely plain floor in the room.
;
; Reads the map through PFacReadBlock, which needs wPFacTargetBaseLo/Hi and
; the final block ids - both true at PFacPickHideout's call site, which
; runs after PFacGenerateFacility has returned. It touches no SRAM, so the
; caller's bank-1 window is unaffected.
;
; PFacReadBlock clobbers a/de/hl and is the reason d/e and the table cursor
; are both stacked across it. Out-of-range coordinates are safe: its own
; .oob path returns something that is not PFAC_FLOOR, so an edge candidate
; rejects rather than reading off the grid.
; Clobbers a/hl; preserves bc.
; ============================================================
PFacHideoutFindFloor:
    ld hl, .offsets
.probe
    ld a, [hl]
    cp $80                          ; table terminator
    jr z, .none
    add a, d
    ld [wBuffer + wPFacCurX], a
    inc hl
    ld a, [hl]
    add a, e
    ld [wBuffer + wPFacCurY], a
    inc hl
    push hl
    push de
    call PFacReadBlock
    pop de
    pop hl
    cp PFAC_FLOOR
    jr nz, .probe
    ld a, [wBuffer + wPFacCurX]
    ld d, a
    ld a, [wBuffer + wPFacCurY]
    ld e, a
    scf
    ret
.none
    and a                           ; carry clear
    ret

.offsets
    db  0,  0                       ; the room center, the usual answer
    db  0,  1                       ; one SOUTH - in front of the furniture
    db  0, -1
    db -1,  0
    db  1,  0
    db $80

PFacPlaceStageEventNpcs:
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    ld a, BMODE_ADVANCED
    ld [rBMODE], a
    xor a
    ld [rRAMB], a                   ; bank 0: sStageEventHideoutX/Y
    ld a, [sStageEventHideoutX]
    ld b, a                         ; b = hideout block X
    ld a, [sStageEventHideoutY]
    ld c, a                         ; c = hideout block Y
    ld a, b
    cp STAGE_EVENT_NO_HIDEOUT
    jr nz, .haveHideout
    ld b, 9                         ; no hideout - park on the entrance block
    ld c, 19
.haveHideout
    ld a, BMODE_SIMPLE
    ld [rBMODE], a
    ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
    ld [rRAMG], a

    ; A GOOD NPC HAS NO ARRIVAL, in any phase. Joy and Jenny are found, not
    ; met: the map script settles them without a greeting, so without this
    ; test the WAITING branch below would stand them in front of the player
    ; for the one frame before that script runs, and they would then never
    ; move - the vanish that repositions a villain is exactly what they skip.
    ; Testing TYPE before PHASE is the whole fix.
    ld a, [wStageEvent]
    and STAGE_EVENT_TYPE_MASK
    cp STAGE_EVENT_JOY
    jr nc, .atHideout
    ld a, [wStageEvent]
    and STAGE_EVENT_PHASE_MASK
    jr nz, .atHideout
    ld d, 9
    ld e, 19
    call PFacPlaceStageEventArrival
    jr .syncPixels
.atHideout
    ld hl, wSprite10StateData2MapY
    ld a, c
    add a, a
    add a, 4
    ld [hli], a
    ld a, b
    add a, a
    add a, 4
    ld [hl], a

    ; --- slot 11 one STEP right, in the same block's top-right quadrant ---
    ; This used to step a whole BLOCK (inc b, or dec b at the right edge),
    ; which stood the pair two tiles apart with a tile of floor between them.
    ; A block is two steps wide, so +1 on the sprite's MapX is all the
    ; "never stack" guarantee needs, and it keeps the partner inside the
    ; hideout's own block instead of gambling on a neighbour - which matters
    ; more here than anywhere else, since a facility hideout sits in a room
    ; and the block beside it can be the room's wall ring. The block is
    ; walkable in all four quadrants because PFacHideoutFindFloor only ever
    ; publishes a PFAC_FLOOR cell; before that existed this was NOT true and
    ; the pair stood in furniture on 22.5% of layouts.
    ; Safe at the right edge too: b = PFAC_SIZE - 1 = 19
    ; gives MapX 43 = tile 39, the last legal column. Same shape as the
    ; cave, forest and cemetery.
    ld hl, wSprite11StateData2MapY
    ld a, c
    add a, a
    add a, 4
    ld [hli], a
    ld a, b
    add a, a
    add a, 5
    ld [hl], a

.syncPixels
    ; Both slots moved in MAP space; their SCREEN PIXEL copies are now stale.
    ; See StageEventSyncPairScreenPos for why that is not self-healing.
    ld d, 10
    farcall StageEventSyncPairScreenPos
    ret

; ============================================================
; PFacPlaceStageEventArrival  (Phase 7 rollout)
; Facility's counterpart to the cave's PCPlaceStageEventArrival.
; INPUT: d = entrance block X, e = entrance block Y. SRAM already closed.
;
; The player warps to the entrance block's BOTTOM-LEFT quadrant
; (warp_event 18,39), so slot 10 takes the TOP-LEFT quadrant of that same
; block and slot 11 the TOP-RIGHT. No floor check is needed or possible to
; get wrong: the player is standing in the block.
;
; THIS WAS WRONG UNTIL 2026-09-17, the same block-vs-step confusion the
; cave and forest had - blockY*2 + 3 is one step above the BLOCK, not above
; the player-in-the-block, so the pair landed in block (9,18) and (10,18).
; Clobbers a/hl.
; ============================================================
PFacPlaceStageEventArrival:
    ld hl, wSprite10StateData2MapY
    ld a, e
    add a, a
    add a, 4                        ; blockY*2 + 4 = the block's TOP row
    ld [hli], a
    ld a, d
    add a, a
    add a, 4                        ; blockX*2 + 4 = top-LEFT, above the player
    ld [hl], a
    ld hl, wSprite11StateData2MapY
    ld a, e
    add a, a
    add a, 4                        ; same row as its partner
    ld [hli], a
    ld a, d
    add a, a
    add a, 5                        ; one STEP right: the same block's top-right
    ld [hl], a
    ret

; ============================================================
; PFacApplyStageEventTrainers  (Phase 7 rollout)
; Thin shim so PFacFinalize reaches the generic trainer patch in the "Stage
; Events" section, with d set to this map's base NPC slot (10 - the facility
; is the one stage that cannot reuse slots 6-7, see procedural_stage_hooks.asm).
; ============================================================
PFacApplyStageEventTrainers:
    ld d, 10
    farcall StageEventApplyTrainers
    ret

; ============================================================
; PFacStageEventVanish  (Phase 7 rollout)
; Facility's counterpart to the cave's PCStageEventVanish.
; Clobbers a/bc/de/hl.
; ============================================================
PFacStageEventVanish::
    call GBFadeOutToBlack
    ld a, [wStageEvent]
    and ~STAGE_EVENT_PHASE_MASK & $ff
    or STAGE_EVENT_PHASE_HIDING << STAGE_EVENT_PHASE_SHIFT
    ld [wStageEvent], a
    call PFacPlaceStageEventNpcs
    call UpdateSprites
    call Delay3
    call GBFadeInFromBlack
    ret

; ============================================================
; PFacShowStageEventNpcs  (Phase 7 rollout)
; Facility's counterpart to the shared StageEventShowCaveNpcs
; (custom_functions/stage_events.asm), duplicated rather than parameterized:
; TOGGLE_FACILITY_NPC_1/2 are genuinely different constants from
; TOGGLE_WILD_AREA_NPC_1/2 (see the toggle_constants.asm note), so this can't
; just reuse the shared routine's slot-6/7 assumption the way the forest does.
; Clobbers a/bc/de/hl.
; ============================================================
PFacShowStageEventNpcs::
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    ld a, BMODE_ADVANCED
    ld [rBMODE], a
    ASSERT BANK("Sprite Buffers") == 0
    xor a
    ld [rRAMB], a
    ld a, [sStageEventSprite6]
    ld d, a
    ld a, [sStageEventSprite7]
    ld e, a
    ld a, BMODE_SIMPLE
    ld [rBMODE], a
    ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
    ld [rRAMG], a
    ld a, d
    and a
    ret z                            ; no event armed - leave both hidden
    push de
    ld a, TOGGLE_FACILITY_NPC_1
    ld [wToggleableObjectIndex], a
    predef ShowObject
    pop de
    ld a, e
    and a
    ret z                            ; single-NPC event
    ld a, TOGGLE_FACILITY_NPC_2
    ld [wToggleableObjectIndex], a
    predef ShowObject
    ret
