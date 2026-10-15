; custom_functions/cave_subroom.asm
;
; The cave's subroom (PROCEDURAL_SUBROOMS_PLAN Phase 4). Two ladders down,
; placed at generation on fixed sites (constants/cave_ladder_site_constants.asm)
; at least CAVE_LADDER_MIN_DISTANCE apart, lead into PROCEDURAL_CAVE_SUBROOM;
; each of its two ladders up climbs back onto its own. When only one site fits,
; that one ladder serves both of the subroom's.
;
; Opens its own section, pinned to $3F in layout.link; farcall-only.

SECTION "Cave Subroom", ROMX

; State: CAVESUB_* in constants/cave_ladder_site_constants.asm.

DEF CAVESUB_STRIDE EQU 26           ; PC_STRIDE (procedural_cave_gen.asm)
DEF CAVESUB_BASE   EQU 81           ; PC_BASE
DEF CAVESUB_FLOOR  EQU 1            ; PC_BLOCK_FLOOR

ASSERT CAVE_FIRST_LADDER_WARP + NUM_CAVE_LADDER_SITES <= MAX_WARP_EVENTS
ASSERT NUM_CAVE_LADDER_SITES < CAVE_LADDER_NONE

; Two bytes per site: block X, block Y. Every site keeps its E/S/SE neighbours on
; the map (X, Y <= 18).
CaveLadderSiteTable:
FOR n, NUM_CAVE_LADDER_SITES
	ASSERT CAVE_LADDER_SITE_{d:n}_X >= 1 && CAVE_LADDER_SITE_{d:n}_X <= 18
	ASSERT CAVE_LADDER_SITE_{d:n}_Y >= 1 && CAVE_LADDER_SITE_{d:n}_Y <= 18
	db CAVE_LADDER_SITE_{d:n}_X, CAVE_LADDER_SITE_{d:n}_Y
ENDR

INCLUDE "data/tilesets/cavern_quad_masks.asm"

CaveSubOpenSRAM:
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK(sProcCaveStagingBuffer) == 0
	xor a
	ld [rRAMB], a
	ret

CaveSubCloseSRAM:
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ret

; ------------------------------------------------------------
; PCFinalizeCave's first visit, after every block-changing pass (PCPlaceDropIn)
; and before the bake, so the ladders are baked with the cave. wOverworldMap
; holds the finished cave. Clobbers everything; leaves SRAM closed.
; ------------------------------------------------------------
CaveSubroomPlaceLadders::
	; Fresh cave: objects not shown yet, nobody beaten, and the coin flip for
	; the subroom's resident (the Gambler or the Super Nerd).
	call Random
	and 1 << BIT_CAVESUB_SUPER_NERD
	ld b, a
	call CaveSubOpenSRAM
	ld a, b
	ld [CAVESUB_STATE], a
	ld a, CAVE_LADDER_NONE
	ld [CAVESUB_LADDER_A], a
	ld [CAVESUB_LADDER_B], a
	ld bc, CAVE_LADDER_NONE         ; b = 0: count; c = no partner
	call CaveLadderWalk
	and a
	jr z, .fallback                 ; no site at all: no subroom this cave
	ld c, a
	call Rangerandom
	inc a
	ld b, a
	ld c, CAVE_LADDER_NONE
	call CaveLadderWalk             ; a = the first ladder's site
	ld [CAVESUB_LADDER_A], a
	call CaveLadderSiteXY
	ld a, d
	ld [CAVESUB_TMP_X], a
	ld a, e
	ld [CAVESUB_TMP_Y], a
	ld a, [CAVESUB_LADDER_A]
	ld c, a
	ld b, 0
	call CaveLadderWalk             ; sites far enough from it
	and a
	jr z, .stamp                    ; none: one ladder serves both
	ld c, a
	call Rangerandom
	inc a
	ld b, a
	ld a, [CAVESUB_LADDER_A]
	ld c, a
	call CaveLadderWalk
	ld [CAVESUB_LADDER_B], a
.stamp
	ld a, [CAVESUB_LADDER_A]
	call .stampSite
	ld a, [CAVESUB_LADDER_B]
	call .stampSite
.done
	jp CaveSubCloseSRAM

.fallback
	; The resident stands in the cave instead: a block picked uniformly from
	; every one passing the ladder rule (rows/columns 1-18).
	call CaveFallbackScan           ; b = how many
	ld a, b
	and a
	jr z, .done                     ; nowhere at all: no resident this cave
	ld c, a
	call Rangerandom
	inc a
	ld b, a
	call CaveFallbackScan.from      ; d/e = that block
	ld a, d
	or CAVESUB_FALLBACK
	ld [CAVESUB_LADDER_A], a
	ld a, e
	or CAVESUB_FALLBACK_ROW
	ld [CAVESUB_LADDER_B], a
	jr .done

.stampSite
	cp NUM_CAVE_LADDER_SITES
	ret nc
	call CaveLadderSiteXY
	call CaveLadderBlockAddr
	ld [hl], CAVE_LADDER_BLOCK
	ret

; Walks the sites that pass CaveLadderSiteValid and, when c names a partner
; site (its block in CAVESUB_TMP_X/Y), lie at least CAVE_LADDER_MIN_DISTANCE
; blocks from it. In: b = k >= 1: stop on the k-th, a = its site; b = 0: count,
; a = how many. SRAM bank 0 open. Clobbers a/de/hl, keeps bc.
CaveLadderWalk:
	ld hl, 0                        ; h = site, l = passes so far
.site
	ld a, h
	cp NUM_CAVE_LADDER_SITES
	jr nc, .end
	push hl
	push bc
	call CaveLadderSiteXY
	call CaveLadderSiteValid        ; carry = a ladder may go here; keeps de
	pop bc
	pop hl
	jr nc, .next
	ld a, c
	cp CAVE_LADDER_NONE
	jr z, .take
	ld a, [CAVESUB_TMP_X]
	sub d
	jr nc, .dx
	cpl
	inc a
.dx
	ld d, a
	ld a, [CAVESUB_TMP_Y]
	sub e
	jr nc, .dy
	cpl
	inc a
.dy
	add d
	cp CAVE_LADDER_MIN_DISTANCE
	jr c, .next                     ; also rejects the partner itself
.take
	inc l
	ld a, l
	cp b
	jr nz, .next
	ld a, h
	ret
.next
	inc h
	jr .site
.end
	ld a, l
	ret

; Walks every block (rows/columns 1-18) in row order through the ladder rule.
; Counting: out b = how many pass. .from, b = k >= 1: stops on the k-th, d/e =
; its block. SRAM bank 0 open. Clobbers a/c/hl.
CaveFallbackScan:
	ld b, $ff                       ; never reached: far fewer blocks pass
.from
	ld e, 1
	ld c, 0
.row
	ld d, 1
.block
	push bc
	call CaveLadderSiteValid        ; keeps de
	pop bc
	jr nc, .next
	inc c
	ld a, c
	cp b
	ret z
.next
	inc d
	ld a, d
	cp 19
	jr c, .block
	inc e
	ld a, e
	cp 19
	jr c, .row
	ld b, c
	ret

; Out: carry = this cave uses the resident's fallback; d/e = its block.
; SRAM bank 0 open. Clobbers a.
CaveFallbackSpot:
	ld a, [CAVESUB_LADDER_A]
	cp CAVESUB_FALLBACK
	ccf
	ret nc
	cp CAVESUB_FALLBACK | 19
	ret nc
	and ~CAVESUB_FALLBACK & $ff
	ld d, a
	ld a, [CAVESUB_LADDER_B]
	sub CAVESUB_FALLBACK_ROW
	ccf
	ret nc
	cp 19
	ret nc
	ld e, a
	ret                             ; carry from the cp: in range

; ProcBossPatchStageSprite, every cave load before InitMapSprites: objects 8
; and 9 get their pictures only when this cave uses the fallback, and then only
; the rolled one; a zero picture allocates no VRAM slot. Clobbers everything.
CaveFallbackPatchSprites::
	call CaveSubOpenSRAM
	call CaveFallbackSpot
	ld b, 0
	ld c, 0
	jr nc, .write
	ld a, [CAVESUB_STATE]
	bit BIT_CAVESUB_SUPER_NERD, a
	ld b, SPRITE_GAMBLER
	jr z, .write
	ld b, 0
	ld c, SPRITE_SUPER_NERD
.write
	call CaveSubCloseSRAM
	ld a, b
	ld [wSprite{02d:CAVE_GAMBLER}StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ld a, c
	ld [wSprite{02d:CAVE_SUPER_NERD}StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ret

; In: a = site. Out: d = block X, e = block Y. Keeps bc. Clobbers a/hl.
CaveLadderSiteXY:
	add a
	ld l, a
	ld h, 0
	push bc
	ld bc, CaveLadderSiteTable
	add hl, bc
	pop bc
	ld a, [hli]
	ld d, a
	ld e, [hl]
	ret

; In: d/e = block X/Y. Out: hl = that block in wOverworldMap. Keeps bc/de.
CaveLadderBlockAddr:
	push bc
	ld hl, wOverworldMap + CAVESUB_BASE
	ld b, 0
	ld c, d
	add hl, bc
	ld c, CAVESUB_STRIDE
	ld a, e
	and a
	jr z, .done
.row
	add hl, bc
	dec a
	jr nz, .row
.done
	pop bc
	ret

; In: d/e = block X/Y. Out: carry = a ladder may go here. The ladder is block
; CAVE_LADDER_BLOCK, whose only ladder quadrant is the bottom-right one, and
; stepping on it leaves the cave, so for walking that quadrant is a wall. If the
; 8 quadrants around it are walkable, every route through it can go round:
; three are the site's own (floor), five are the E block's left column, the S
; block's top row and the SE block's top-left. Nothing may stand within a block
; (balls, the exit and its boss, the entrance), nor the stage-event hideout
; within two.
; tools/pyboy_smoke/audit_cave_ladder_sites.py applies this same rule, and its
; flood found it never strands anything. SRAM bank 0 open. Keeps de.
CaveLadderSiteValid:
	call CaveLadderBlockAddr
	ld a, [hl]
	cp CAVESUB_FLOOR
	jr nz, .no
	inc hl                          ; E
	ld a, [hl]
	call CaveQuadMask
	and %0101
	cp %0101                        ; TL and BL
	jr nz, .no
	ld bc, CAVESUB_STRIDE - 1
	add hl, bc                      ; S
	ld a, [hli]
	call CaveQuadMask
	and %0011
	cp %0011                        ; TL and TR
	jr nz, .no
	ld a, [hl]                      ; SE
	call CaveQuadMask
	bit 0, a                        ; TL
	jr z, .no
	; The balls: (Y, X) tile pairs, map border included (+4).
	ld hl, sProcCaveBallXY
	ld b, 4
.ball
	ld a, [hli]
	sub 4
	srl a
	ld c, a                         ; block Y
	ld a, [hli]
	sub 4
	srl a                           ; block X
	push hl
	call .near
	pop hl
	jr c, .no
	dec b
	jr nz, .ball
	; The exit (where the boss stands) and the entrance: blocks.
	ld a, [sProcCaveStagingExitY]
	ld c, a
	ld a, [sProcCaveStagingExitX]
	call .near
	jr c, .no
	ld a, [sProcCaveStagingEntranceY]
	ld c, a
	ld a, [sProcCaveStagingEntranceX]
	call .near
	jr c, .no
	; The stage-event hideout (blocks; same SRAM bank): two blocks, not one.
	; The event NPCs stand there and the villains see 4 tiles; a ladder two
	; blocks off is at least 5 tiles away, so nobody can spot the player
	; arriving on it (a battle started on a warp tile takes the warp after).
	ld a, [sStageEventHideoutX]
	cp STAGE_EVENT_NO_HIDEOUT
	jr z, .yes
	sub d
	add 2                           ; -2..2 -> 0..4
	cp 5
	jr nc, .yes
	ld a, [sStageEventHideoutY]
	sub e
	add 2
	cp 5
	jr c, .no
.yes
	scf
	ret
.no
	and a
	ret

; In: a = object block X, c = its block Y; d/e = the site. Out: carry = within
; one block of it. Clobbers a.
.near
	sub d
	inc a                           ; -1..1 -> 0..2
	cp 3
	jr nc, .far                     ; too far in X
	ld a, c
	sub e
	inc a
	cp 3
	ret                             ; carry = 0..2: near
.far
	and a
	ret

; In: a = block id. Out: a = its walkable-quadrant mask, 0 past the table.
; Keeps bc/de/hl.
CaveQuadMask:
	cp NUM_CAVERN_QUAD_MASKS
	jr nc, .none
	push hl
	push de
	ld e, a
	ld d, 0
	ld hl, CavernQuadWalkMasks
	add hl, de
	ld a, [hl]
	pop de
	pop hl
	ret
.none
	xor a
	ret

; ------------------------------------------------------------
; Every cave load (PCFinalizeCave's two paths, after wWarpEntries is loaded and
; the map is final). Disarms every site warp (Y = $FF matches no player
; position), then arms the stored ladders into the subroom: A at its ladder 0,
; B at its ladder 1. Clobbers everything; leaves SRAM closed.
; ------------------------------------------------------------
CaveSubroomArm::
	ld hl, wWarpEntries + CAVE_FIRST_LADDER_WARP * 4
	ld b, NUM_CAVE_LADDER_SITES
	ld de, 4
.disarm
	ld [hl], CAVE_LADDER_NONE
	add hl, de
	dec b
	jr nz, .disarm
	call CaveSubOpenSRAM
	call CaveFallbackSpot           ; the resident's fallback: stand him there
	jr nc, .noFallback
	ld a, e
	add a
	add 4 + 1                       ; bottom-right quadrant, map border included
	ld [wSprite{02d:CAVE_GAMBLER}StateData2MapY], a
	ld [wSprite{02d:CAVE_SUPER_NERD}StateData2MapY], a
	ld a, d
	add a
	add 4 + 1
	ld [wSprite{02d:CAVE_GAMBLER}StateData2MapX], a
	ld [wSprite{02d:CAVE_SUPER_NERD}StateData2MapX], a
.noFallback
	ld a, [CAVESUB_LADDER_A]
	ld b, a
	ld a, [CAVESUB_LADDER_B]
	ld c, a
	call CaveSubCloseSRAM
	push bc
	ld a, b
	ld c, 0                         ; the subroom's ladder 0
	call .arm
	pop bc
	ld a, c
	ld c, 1                         ; the subroom's ladder 1
	; fall through

; In: a = site (or NONE / an old save's fill byte), c = the subroom ladder.
.arm
	cp NUM_CAVE_LADDER_SITES
	ret nc
	ld b, a
	call CaveLadderSiteXY
	call CaveLadderBlockAddr
	ld a, [hl]
	cp CAVE_LADDER_BLOCK
	ret nz                          ; the ladder is not drawn there (an old save)
	ld a, b
	add CAVE_FIRST_LADDER_WARP
	add a
	add a                           ; entry * 4 (at most 124)
	ld l, a
	ld h, 0
	push de
	ld de, wWarpEntries
	add hl, de
	pop de
	ld a, e
	add a
	inc a
	ld [hli], a                     ; Y = 2 * blockY + 1
	ld a, d
	add a
	inc a
	ld [hli], a                     ; X = 2 * blockX + 1
	ld a, c
	ld [hli], a                     ; destination warp (0-based): that ladder
	ld [hl], PROCEDURAL_CAVE_SUBROOM
	ret

; ------------------------------------------------------------
; ProcStageLoadDispatch, every load of the subroom: its ladder 0 climbs back
; onto ladder A, its ladder 1 onto ladder B (or A when there is only one).
; Without any (an old save) the ROM destinations, the cave entrance, stay.
; ------------------------------------------------------------
CaveSubroomLoad::
	call CaveSubOpenSRAM
	ld a, [CAVESUB_LADDER_A]
	ld b, a
	ld a, [CAVESUB_LADDER_B]
	ld c, a
	call CaveSubCloseSRAM
	ld a, b
	cp NUM_CAVE_LADDER_SITES
	ret nc
	ld a, c
	cp NUM_CAVE_LADDER_SITES
	jr c, .two
	ld c, b                         ; one ladder serves both
.two
	ld a, b
	add CAVE_FIRST_LADDER_WARP
	ld [wWarpEntries + 2], a        ; ladder 0's destination warp
	ld a, c
	add CAVE_FIRST_LADDER_WARP
	ld [wWarpEntries + 4 + 2], a    ; ladder 1's
	ret

; Out: carry = this cave's subroom resident is the Super Nerd (else the
; Gambler). Clobbers a.
CaveSubroomResidentIsNerd::
	call CaveSubOpenSRAM
	ld a, [CAVESUB_STATE]
	push af
	call CaveSubCloseSRAM
	pop af
	bit BIT_CAVESUB_SUPER_NERD, a
	jr z, .gambler
	scf
	ret
.gambler
	and a                           ; carry clear (bit leaves carry alone)
	ret

; ------------------------------------------------------------
; ProceduralCave1_Script's fresh-entry block, after it set EVENT_ENTER_ROOM. Out:
; carry = this is the cave's first entry, so its objects should be shown; the
; flag is then set. Re-entries (the subroom's ladders) leave the toggles as
; they are, or a collected ball would come back (Phase 1's item dupe).
; Clobbers a/hl.
; ------------------------------------------------------------
CaveStageFirstEntry::
	call CaveSubOpenSRAM
	ld hl, CAVESUB_STATE
	ld a, [hl]
	set BIT_CAVESUB_OBJECTS_SHOWN, [hl]
	ld l, a
	call CaveSubCloseSRAM
	bit BIT_CAVESUB_OBJECTS_SHOWN, l
	jr z, .first
	and a
	ret
.first
	; The subroom's resident for this cave: the rolled one shown, the other
	; hidden (its map is not loaded, so the flags are written directly).
	ld a, l
	push af
	ld c, TOGGLE_CAVESUB_GAMBLER
	ld b, FLAG_SET                  ; hidden
	bit BIT_CAVESUB_SUPER_NERD, a
	jr nz, .gambler
	ld b, FLAG_RESET
.gambler
	ld hl, wToggleableObjectFlags
	predef FlagActionPredef
	pop af
	push af
	ld c, TOGGLE_CAVESUB_SUPER_NERD
	ld b, FLAG_RESET                ; shown
	bit BIT_CAVESUB_SUPER_NERD, a
	jr nz, .nerd
	ld b, FLAG_SET
.nerd
	ld hl, wToggleableObjectFlags
	predef FlagActionPredef
	; And the subroom's item ball comes back for the new cave.
	ld c, TOGGLE_CAVESUB_BALL
	ld b, FLAG_RESET
	ld hl, wToggleableObjectFlags
	predef FlagActionPredef
	; The resident's fallback, in this map: shown only when the cave uses it,
	; and only the rolled one (toggle bits outlive the cave, so always write).
	pop af
	push af
	call CaveFallbackShowOne
	pop af
	scf
	ret

; In: a = CAVESUB_STATE. Shows the rolled resident's fallback object if this
; cave uses the fallback, hides both otherwise. Clobbers everything.
CaveFallbackShowOne:
	ld b, a
	push bc
	call CaveSubOpenSRAM
	call CaveFallbackSpot
	push af
	call CaveSubCloseSRAM
	pop af
	pop bc
	ld c, FLAG_SET                  ; c = Gambler hidden?
	ld e, FLAG_SET                  ; e = Super Nerd hidden?
	jr nc, .write
	bit BIT_CAVESUB_SUPER_NERD, b
	jr nz, .nerd
	ld c, FLAG_RESET
	jr .write
.nerd
	ld e, FLAG_RESET
.write
	push de
	ld b, c
	ld c, TOGGLE_CAVE_GAMBLER
	ld hl, wToggleableObjectFlags
	predef FlagActionPredef
	pop de
	ld b, e
	ld c, TOGGLE_CAVE_SUPER_NERD
	ld hl, wToggleableObjectFlags
	predef_jump FlagActionPredef
