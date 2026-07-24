; custom_functions/final_sequence.asm
;
; Final sequence: Victory Road (mandatory Rival mini-boss) -> Elite Four
; (randomized order, no repeats) -> Champion (RIVAL3). Reached once all 8
; badges are obtained.
;
; Elite4OrderTable (24 x 4 bytes, all permutations of the 4 Elite Four
; members' OPP_* classes) is defined below, in THIS bank, so the routines
; here can read it with a plain ld a,[hl]. wElite4Order (ram/wram.asm) is a
; 0-23 index into it, rolled once when the Victory Road Rival is defeated
; (scripts/VictoryRoad1F.asm). (It used to live in data/trainers/parties.asm,
; which compiles into a different bank - the cross-bank read returned garbage
; and made every room resolve to Lance.)

; All 24 permutations of Lorelei(0), Bruno(1), Agatha(2), Lance(3). Each row
; = 4 bytes, one OPP_* constant per Elite Four member position.
Elite4OrderTable:
	db OPP_LORELEI, OPP_BRUNO, OPP_AGATHA, OPP_LANCE
	db OPP_LORELEI, OPP_BRUNO, OPP_LANCE, OPP_AGATHA
	db OPP_LORELEI, OPP_AGATHA, OPP_BRUNO, OPP_LANCE
	db OPP_LORELEI, OPP_AGATHA, OPP_LANCE, OPP_BRUNO
	db OPP_LORELEI, OPP_LANCE, OPP_BRUNO, OPP_AGATHA
	db OPP_LORELEI, OPP_LANCE, OPP_AGATHA, OPP_BRUNO
	db OPP_BRUNO, OPP_LORELEI, OPP_AGATHA, OPP_LANCE
	db OPP_BRUNO, OPP_LORELEI, OPP_LANCE, OPP_AGATHA
	db OPP_BRUNO, OPP_AGATHA, OPP_LORELEI, OPP_LANCE
	db OPP_BRUNO, OPP_AGATHA, OPP_LANCE, OPP_LORELEI
	db OPP_BRUNO, OPP_LANCE, OPP_LORELEI, OPP_AGATHA
	db OPP_BRUNO, OPP_LANCE, OPP_AGATHA, OPP_LORELEI
	db OPP_AGATHA, OPP_LORELEI, OPP_BRUNO, OPP_LANCE
	db OPP_AGATHA, OPP_LORELEI, OPP_LANCE, OPP_BRUNO
	db OPP_AGATHA, OPP_BRUNO, OPP_LORELEI, OPP_LANCE
	db OPP_AGATHA, OPP_BRUNO, OPP_LANCE, OPP_LORELEI
	db OPP_AGATHA, OPP_LANCE, OPP_LORELEI, OPP_BRUNO
	db OPP_AGATHA, OPP_LANCE, OPP_BRUNO, OPP_LORELEI
	db OPP_LANCE, OPP_LORELEI, OPP_BRUNO, OPP_AGATHA
	db OPP_LANCE, OPP_LORELEI, OPP_AGATHA, OPP_BRUNO
	db OPP_LANCE, OPP_BRUNO, OPP_LORELEI, OPP_AGATHA
	db OPP_LANCE, OPP_BRUNO, OPP_AGATHA, OPP_LORELEI
	db OPP_LANCE, OPP_AGATHA, OPP_LORELEI, OPP_BRUNO
	db OPP_LANCE, OPP_AGATHA, OPP_BRUNO, OPP_LORELEI
;
; CALLING CONVENTION: every entry point below marked "farcall entry point"
; is reached via `farcall` from a script file in a different bank. `farcall`
; goes through Bankswitch (home/bankswitch.asm), which clobbers a/b/c AND
; flags both on entry (its first instruction is `ldh a,[hLoadedROMBank]`)
; and again on return (its .Return epilogue pops/overwrites b/c/a) - only
; d/e survive as farcall INPUT, and nothing survives as farcall OUTPUT.
; (Same convention already used by InitGymBattle/InitElite4Battle: take
; input in d, do all the work internally, return nothing.) Helpers below
; that are only ever reached via a same-bank `call` (never farcalled
; directly) are free to use normal register returns.

; ============================================================
; ForceVictoryRoadDoors
; Forces both Lobby exit doors to Victory Road, the mandatory stage reached
; once all 8 badges are obtained (before it has been cleared this run).
; Victory Road's Rival is a STATIC map object (see VictoryRoad1F.asm object
; data) - not the roll-based mini-boss framework - so this only clears any
; leftover transient mini-boss bits (mirroring the top of
; MiniBossRollAndAssign) rather than rolling a new one.
; Called via plain `call` from SelectAndPatchLobbyExit (same bank).
; CLOBBERS: a, hl
; ============================================================
ForceVictoryRoadDoors::
	ld hl, wRogueFlagsBitfield
	res BIT_MINIBOSS_DOOR, [hl]
	res BIT_MINIBOSS_ACTIVE, [hl]
	ld a, [hl]
	and %11001111 ; clear the offered-type field (bits 4-5), keep the rest
	ld [hl], a
	ld a, VICTORY_ROAD_1F
	ld [wRogueMap], a
	ld [wLobbyDoor1StageMap], a
	ld [wLobbyDoor2StageMap], a
	ret

; ============================================================
; ForceElite4Doors
; Once Victory Road is cleared, forces both Lobby exit doors to the first
; (order[0]) Elite Four member's room. If that member (and any after it)
; has already been beaten this run - e.g. the player returned to the Lobby
; after losing to a later member or to the Champion - walking into that
; room is harmless: its exit is already unlocked and its own on-load warp
; patch (Elite4PatchRoomWarps, farcalled from each room's script) forwards
; the player on to the next unbeaten room automatically.
; Called via plain `call` from SelectAndPatchLobbyExit (same bank).
; CLOBBERS: a, bc, de, hl
; ============================================================
ForceElite4Doors::
	ld hl, wRogueFlagsBitfield
	res BIT_MINIBOSS_DOOR, [hl]
	res BIT_MINIBOSS_ACTIVE, [hl]
	ld a, [hl]
	and %11001111
	ld [hl], a
	ld hl, wElite4Flags
	set BIT_STARTED_ELITE_4, [hl] ; order-independent now; was set in LoreleisRoom (assumed Lorelei was always first)
	call Elite4FirstRoomMap
	ld [wLobbyDoor1StageMap], a
	ld [wLobbyDoor2StageMap], a
	ret

; ============================================================
; Elite4FirstRoomMap  (same-bank call only)
; OUTPUT: a = the map constant of the order[0] Elite Four member's room.
; CLOBBERS: a, bc, de, hl
; ============================================================
Elite4FirstRoomMap:
	ld a, [wElite4Order]
	ld d, 0
	add a, a
	add a, a
	ld e, a
	ld hl, Elite4OrderTable
	add hl, de
	ld a, [hl]                   ; a = order[0]'s OPP_* class
	jp Elite4MemberRoomMapForOPP

; ============================================================
; Elite4MemberRoomMapForOPP  (same-bank call only)
; INPUT:  a = OPP_LORELEI / OPP_BRUNO / OPP_AGATHA / OPP_LANCE
; OUTPUT: a = that member's room map constant
; CLOBBERS: none besides a
; ============================================================
Elite4MemberRoomMapForOPP:
	cp OPP_LORELEI
	jr nz, .notLorelei
	ld a, LORELEIS_ROOM
	ret
.notLorelei
	cp OPP_BRUNO
	jr nz, .notBruno
	ld a, BRUNOS_ROOM
	ret
.notBruno
	cp OPP_AGATHA
	jr nz, .notAgatha
	ld a, AGATHAS_ROOM
	ret
.notAgatha
	; must be OPP_LANCE
	ld a, LANCES_ROOM
	ret

; ============================================================
; Elite4ResolveNeighborMaps  (same-bank call only)
; Determines an Elite Four room's neighbors in this run's shuffled order.
; INPUT:  a = this room's OPP_* member constant
; OUTPUT: b = map for this room's SOUTH warp(s): the previous room, or
;             INDIGO_PLATEAU_LOBBY if this is the first (order[0]) member
;         c = map for this room's NORTH warp(s): the next room, or
;             CHAMPIONS_ROOM if this is the last (order[3]) member
;         Z set if this is the last (4th) member
; CLOBBERS: a, d, e, hl
; ============================================================
Elite4ResolveNeighborMaps:
	ld e, a                      ; e = target OPP class to find
	ld a, [wElite4Order]
	ld d, 0
	add a, a
	add a, a                     ; a = wElite4Order * 4
	ld l, a
	ld h, d
	ld bc, Elite4OrderTable
	add hl, bc                   ; hl = &Elite4OrderTable[wElite4Order*4]
	; Scan the 4 bytes for e (target OPP class), tracking index in d
	xor a
	ld d, a                      ; d = index i (0-3)
.scan
	ld a, [hl]
	cp e
	jr z, .found
	inc hl
	inc d
	jr .scan
.found
	; Resolve "previous" (index i-1, or lobby if i==0)
	ld a, d
	and a
	jr nz, .havePrevIndex
	ld b, INDIGO_PLATEAU_LOBBY
	jr .prevDone
.havePrevIndex
	dec hl
	ld a, [hl]
	push hl
	call Elite4MemberRoomMapForOPP
	pop hl
	ld b, a
	inc hl                       ; hl back to order[i]
.prevDone
	; Resolve "next" (index i+1, or champion if i==3)
	ld a, d
	cp 3
	jr z, .nextIsChampion
	inc hl
	ld a, [hl]
	call Elite4MemberRoomMapForOPP
	ld c, a
	jr .nextDone
.nextIsChampion
	ld c, CHAMPIONS_ROOM
.nextDone
	ld a, d
	cp 3
	ret                           ; Z set if this was the last (4th) member

; ============================================================
; Elite4ResolveChampionNeighbor  (same-bank call only)
; The Champion's room isn't itself an Elite4OrderTable entry, so it needs
; its own lookup: its south warp(s) always lead back to the LAST (order[3])
; Elite Four member's room.
; OUTPUT: a = order[3]'s room map constant
; CLOBBERS: a, bc, de, hl
; ============================================================
Elite4ResolveChampionNeighbor:
	ld a, [wElite4Order]
	ld d, 0
	add a, a
	add a, a
	ld e, a
	ld hl, Elite4OrderTable
	add hl, de
	ld bc, 3
	add hl, bc                   ; hl = &order[3]
	ld a, [hl]
	jp Elite4MemberRoomMapForOPP

; Per-room warp-tile coordinates, read directly from each room's own
; data/maps/objects/*.asm (not guessed). Fixed 9-byte stride so
; Elite4PatchRoomWarps can scan by class byte:
;   OPP_class, southY1,southX1, southY2,southX2, northY1,northX1, northY2,northX2
; Lance has only ONE south tile - southY2/southX2 duplicate southY1/southX1,
; which just means PatchWarpEntry's second call for that tile is a harmless
; redundant match.
Elite4RoomWarpTiles:
	db OPP_LORELEI, 11,4, 11,5, 0,4, 0,5
	db OPP_BRUNO,   11,4, 11,5, 0,4, 0,5
	db OPP_AGATHA,  11,4, 11,5, 0,4, 0,5
	db OPP_LANCE,   16,24, 16,24, 0,5, 0,6
	db -1

; ============================================================
; Elite4PatchRoomWarps  -- farcall entry point
; Patches an Elite Four room's south AND north warp tiles to match this
; run's shuffled order, and arms the Champion room if this is the last
; (4th) member. Without this, a room's ROM-authored (vanilla fixed-order)
; warps would send the player to the wrong room when backtracking, since
; the order is now randomized. Idempotent - safe to call on every map load.
; INPUT: d = this room's OPP_* member constant
; CLOBBERS: a, bc, de, hl
; ============================================================
Elite4PatchRoomWarps::
	ld hl, Elite4RoomWarpTiles
.findRoom
	ld a, [hl]
	cp d
	jr z, .found
	ld bc, 9
	add hl, bc
	jr .findRoom
.found
	push hl                        ; [tileRowPtr] (-> class byte)
	ld a, d
	call Elite4ResolveNeighborMaps ; b = south map, c = north map, Z = last
	jr nz, .notLast
	ld a, SCRIPT_CHAMPIONSROOM_PLAYER_ENTERS
	ld [wChampionsRoomCurScript], a
.notLast
	push bc                        ; b=south, c=north
	pop de                         ; d = south map, e = north map
	pop hl                         ; hl -> tileRowPtr (class byte)
	inc hl                         ; hl -> southY1
	; South tile 1
	ld a, [hli]
	ld b, a
	ld a, [hli]
	ld c, a
	push hl
	push de
	ld a, d
	call PatchWarpEntry
	pop de
	pop hl
	; South tile 2
	ld a, [hli]
	ld b, a
	ld a, [hli]
	ld c, a
	push hl
	push de
	ld a, d
	call PatchWarpEntry
	pop de
	pop hl
	; North tile 1
	ld a, [hli]
	ld b, a
	ld a, [hli]
	ld c, a
	push hl
	push de
	ld a, e
	call PatchWarpEntry
	pop de
	pop hl
	; North tile 2
	ld a, [hli]
	ld b, a
	ld a, [hl]
	ld c, a
	push de
	ld a, e
	call PatchWarpEntry
	pop de
	ret

; ============================================================
; Elite4PatchChampionRoomWarps  -- farcall entry point
; The Champion room isn't in Elite4OrderTable and only ever has ONE
; instance, so it needs no input. Patches its south warp tiles to lead
; back to whichever room ended up last (order[3]) in this run's shuffle.
; Its north warps (to Hall of Fame) are never reordered and are untouched.
; CLOBBERS: a, bc, de, hl
; ============================================================
Elite4PatchChampionRoomWarps::
	call Elite4ResolveChampionNeighbor  ; a = order[3]'s room map
	ld d, a
	ld b, 7
	ld c, 3
	call PatchWarpEntry
	ld a, d
	ld b, 7
	ld c, 4
	call PatchWarpEntry
	ret
