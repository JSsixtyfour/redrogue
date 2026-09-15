; custom_functions/final_sequence.asm
;
; Final sequence: Victory Road (mandatory Rival mini-boss) -> Elite Four
; (randomized order, no repeats) -> Champion (RIVAL3). Reached once all 8
; badges are obtained.
;
; PHASE 7: the 24-row Elite4OrderTable and its wElite4Order 0-23 index are
; GONE. This run's Elite Four is wRunElite4 (ram/wram.asm), four TRAINER CLASS
; ids in room order, drawn by RollElite4AndChampion below. A class id is one
; OPP_ID_OFFSET below its OPP_ constant, so every consumer here that compares
; against an OPP_ class converts at the boundary and nowhere else.
;
; Storing class ids rather than OPP_ ids is not a free choice: wRunElite4 is
; already covered by the save/load round-trip in tools/pyboy_smoke/test_smoke.py,
; whose expected bytes are class ids.
;
; The pool grew from 4 fixed members to 7 selectable ones, and the three Johto
; members are gated on the Johto species group:
;
;   Johto off: Lorelei, Bruno, Agatha, Lance          -> 4 candidates, draw 4
;   Johto on:  + Koga, Will, Karen                    -> 7 candidates, draw 4
;
; so a Kanto-only run still gets exactly today's Elite Four in a random order.
; Koga is dropped on top of that if he or Janine stood in a gym this run.
;
; The tables below stay in THIS bank on purpose. Elite4OrderTable used to live
; in data/trainers/parties.asm (a different bank) and was read with a plain
; ld a,[hl] from here; the cross-bank read returned garbage, every room resolved
; to Lance, and Lance looped to himself. See project_cross_bank_call_bugs.

; The Elite Four candidate pool, as trainer class ids. ORDER IS SIGNIFICANT:
; the Johto members must be contiguous at the END so the pool size alone
; (NUM_E4_POOL_KANTO or NUM_E4_POOL_ALL) expresses the group gate, and Koga's
; index is named because his gym-leader exclusion pre-marks that one bit.
Elite4Pool:
	db LORELEI       ; 0
	db BRUNO         ; 1
	db AGATHA        ; 2
	db LANCE         ; 3
	db KOGA_E4       ; 4  Johto only. A SEPARATE class from the gym KOGA.
	db WILL          ; 5  Johto only
	db KAREN         ; 6  Johto only
DEF NUM_E4_POOL_KANTO EQU 4
DEF NUM_E4_POOL_ALL   EQU 7
DEF E4_POOL_IDX_KOGA  EQU 4
ASSERT NUM_E4_POOL_ALL <= 8, "the used-slot mask in RollElite4 is one byte"

; OPP_ class -> that member's room map. Replaces the old cp/jr chain, which
; fell through to LANCES_ROOM for any unmatched byte - the silent default that
; made the 2026-07 cross-bank bug look like a routing bug for days. A miss here
; now answers the Lobby, which is visibly wrong rather than plausibly wrong.
;
; The Lobby is only a SAFE answer where the player can walk away from it, which
; is true of the neighbour path (a room the player should not be in still gets
; two working exits) and false of the lobby-door path, where it would point a
; door at its own map. ForceElite4Doors therefore does not rely on this at all:
; it self-heals an unrolled lineup instead. Do not add a caller that feeds this
; result into wLobbyDoor*StageMap without doing the same.
Elite4RoomMaps:
	db OPP_LORELEI, LORELEIS_ROOM
	db OPP_BRUNO,   BRUNOS_ROOM
	db OPP_AGATHA,  AGATHAS_ROOM
	db OPP_LANCE,   LANCES_ROOM
	db OPP_KOGA_E4, KOGAS_ROOM
	db OPP_WILL,    WILLS_ROOM
	db OPP_KAREN,   KARENS_ROOM
	db -1

; The Champion candidate pool, as trainer class ids, in availability order.
; RIVAL3 is always available; LANCE needs Johto AND to have missed the Elite
; Four draw; PROF_OAK needs the Kanto Time Warp group.
ChampionPool:
	db RIVAL3        ; 0
	db LANCE         ; 1
	db PROF_OAK      ; 2
DEF NUM_CHAMPION_POOL EQU 3
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
	; Self-heal an unrolled lineup rather than letting Elite4FirstRoomMap fall
	; back. This is the ONE caller whose result becomes both lobby doors, so a
	; fallback here is a dead end by construction: a door pointing at the lobby
	; leaves the player in the lobby with nowhere to walk. Rolling instead makes
	; "unrolled" impossible at the doors rather than something a fallback has to
	; survive. 0 is not a valid trainer class, so it is an unambiguous sentinel,
	; and RollElite4AndChampion is idempotent enough to call twice.
	ld a, [wRunElite4]
	and a
	call z, RollElite4AndChampion
	call Elite4FirstRoomMap
	ld [wLobbyDoor1StageMap], a
	ld [wLobbyDoor2StageMap], a
	ret

; ============================================================
; RollElite4AndChampion  -- farcall entry point
; Rolls this run's Elite Four (wRunElite4, 4 trainer class ids in room order)
; and Champion (wRunChampion, 1 trainer class id). Called once, when the
; Victory Road Rival is defeated. Replaces the three `ld [wElite4Order], a`
; sites that used to roll a 0-23 permutation index.
; INPUT:  none
; OUTPUT: none (farcall destroys every return register anyway)
; CLOBBERS: a, bc, de, hl
; ============================================================
RollElite4AndChampion::
	call RollElite4
	; fall through

; ============================================================
; RollChampion  (same-bank call only)
; Picks wRunChampion. MUST run after RollElite4: Lance is only a Champion
; candidate if he did NOT land in the Elite Four, and that is read off
; wRunElite4.
;
; The plan called for two "first clear" flags in SRAM beside
; sRogueSpeciesGroupsEnabled. They are not needed: RogueGetActiveGroupMask
; already DERIVES unlock state from wNumHoFTeams (0 clears = Kanto only, 1
; unlocks Johto, 2 unlocks Time Warp), so "forced until the first Johto clear"
; is exactly wNumHoFTeams == 1 and "until the first KEP clear" is exactly
; wNumHoFTeams == 2. That avoids two new SRAM fields and the explicit
; new-game clear each one would have required (SRAM powers up $ff, and
; ClearAllSRAMBanks FILLS $ff - see project_sram_new_field_needs_explicit_clear),
; and keeps one source of truth for progression.
; CLOBBERS: a, bc, de, hl
; ============================================================
RollChampion:
	farcall RogueGetActiveGroupMaskFar  ; e = active group mask (d preserved)

	; b = availability mask over ChampionPool. RIVAL3 is unconditional.
	ld b, 1 << 0

	bit BIT_GROUP_JOHTO, e
	jr z, .noLance
	; Lance is a candidate only if he missed the Elite Four draw.
	ld a, LANCE
	call Elite4Contains                 ; Z = present in wRunElite4
	jr z, .noLance
	set 1, b
.noLance

	bit BIT_GROUP_WARP, e
	jr z, .noOak
	set 2, b
.noOak

	; Forced first-clear champions, in unlock order. Each only fires if that
	; candidate is actually available, so a player who has switched the group
	; back off in the PC still gets a reachable Champion.
	ld a, [wNumHoFTeams]
	cp 1
	jr nz, .notFirstJohto
	bit 1, b
	jr z, .randomChampion
	ld a, LANCE
	jr .storeChampion
.notFirstJohto
	cp 2
	jr nz, .randomChampion
	bit 2, b
	jr z, .randomChampion
	ld a, PROF_OAK
	jr .storeChampion

.randomChampion
	; Count the available candidates, draw one, then walk the mask to it.
	ld c, 0
	ld e, b
	ld d, NUM_CHAMPION_POOL
.countLoop
	bit 0, e
	jr z, .countSkip
	inc c
.countSkip
	srl e
	dec d
	jr nz, .countLoop

	call Rangerandom                    ; a = 0 .. c-1; preserves bc, de, hl
	ld c, a                             ; c = how many available to skip
	ld hl, ChampionPool
.selectLoop
	bit 0, b
	jr z, .selectSkip
	ld a, c
	and a
	jr z, .selectFound
	dec c
.selectSkip
	srl b
	inc hl
	jr .selectLoop
.selectFound
	ld a, [hl]
.storeChampion
	ld [wRunChampion], a
	ret

; ============================================================
; RollElite4  (same-bank call only)
; Draws 4 distinct trainer class ids into wRunElite4.
;
; Distinctness is a used-slot bitmask over the pool rather than a scan of the
; slots already written, because the mask also carries the Koga exclusion: a
; leader who must not be drawn is simply pre-marked as already used. With Koga
; excluded from the 7-member pool that is 6 candidates for 4 slots; in a
; Kanto-only run it is 4 for 4, which converges in ~8 draws.
; CLOBBERS: a, bc, de, hl
; ============================================================
RollElite4:
	farcall RogueGetActiveGroupMaskFar  ; e = active group mask
	ld c, NUM_E4_POOL_KANTO
	bit BIT_GROUP_JOHTO, e
	jr z, .poolSized
	ld c, NUM_E4_POOL_ALL
.poolSized

	ld b, 0                             ; b = used-slot mask
	call GymLineupHasKogaOrJanine       ; Z = neither stood in a gym this run
	jr z, .kogaEligible
	ld b, 1 << E4_POOL_IDX_KOGA         ; pre-mark Koga as already drawn
.kogaEligible

	ld hl, wRunElite4
	ld d, 4                             ; d = slots still to fill
.slotLoop
	call Rangerandom                    ; a = 0 .. c-1; preserves bc, de, hl
	push af                             ; the index, needed again after the test
	call PoolBitForIndex                ; a = 1 << index; preserves de
	ld e, a                             ; e = that slot's bit
	and b
	jr nz, .retry                       ; that pool slot is already spoken for
	ld a, e
	or b
	ld b, a                             ; mark it used
	pop af                              ; a = the drawn index again

	push hl                             ; save the wRunElite4 write pointer
	ld hl, Elite4Pool
	add a, l
	ld l, a
	jr nc, .noCarry
	inc h
.noCarry
	ld a, [hl]                          ; a = that candidate's class id
	pop hl
	ld [hli], a
	dec d
	jr nz, .slotLoop
	ret
.retry
	pop af
	jr .slotLoop

; ============================================================
; PoolBitForIndex  (same-bank call only)
; INPUT:  a = pool index 0-7
; OUTPUT: a = 1 << index
; CLOBBERS: a only. bc/de/hl are all live across this in RollElite4.
; ============================================================
PoolBitForIndex:
	inc a                               ; so index 0 exits after one dec
	push de
	ld e, a
	ld a, 1
.shift
	dec e
	jr z, .done
	add a, a
	jr .shift
.done
	pop de
	ret

; ============================================================
; Elite4Contains  (same-bank call only)
; INPUT:  a = a trainer CLASS id (not an OPP_ id)
; OUTPUT: Z set if that class is one of this run's four Elite Four members.
; CLOBBERS: a, hl. bc/de preserved - RollChampion holds its mask in b.
; ============================================================
Elite4Contains:
	push de
	ld e, a
	ld d, 4
	ld hl, wRunElite4
.scan
	ld a, [hli]
	cp e
	jr z, .found
	dec d
	jr nz, .scan
	inc d                               ; d was 0, so force NZ on the way out
.found
	pop de
	ret

; ============================================================
; GymLineupHasKogaOrJanine  (same-bank call only)
; OUTPUT: Z set (a = 0) if NEITHER Koga nor Janine is in wRunGymLineup this
;         run, i.e. Koga is still eligible for the Elite Four.
; CLOBBERS: a, hl. bc/de preserved.
;
; wRunGymLineup is all zeroes until Phase 7a's roller fills it, and 0 is not a
; valid trainer class, so this correctly reports "eligible" before then.
; ============================================================
GymLineupHasKogaOrJanine:
	push de
	ld hl, wRunGymLineup
	ld d, 8
.scan
	ld a, [hli]
	cp KOGA
	jr z, .found
	cp JANINE
	jr z, .found
	dec d
	jr nz, .scan
	xor a                               ; Z, and a = 0
	pop de
	ret
.found
	ld a, 1
	and a                               ; NZ
	pop de
	ret

; ============================================================
; Elite4FirstRoomMap  (same-bank call only)
; OUTPUT: a = the map constant of wRunElite4[0]'s room.
; CLOBBERS: a, bc, de, hl
; ============================================================
Elite4FirstRoomMap:
	ld a, [wRunElite4]
	add OPP_ID_OFFSET
	jp Elite4MemberRoomMapForOPP

; ============================================================
; Elite4MemberRoomMapForOPP  (same-bank call only)
; INPUT:  a = any of the seven Elite Four members' OPP_ classes
; OUTPUT: a = that member's room map constant, or INDIGO_PLATEAU_LOBBY on a miss
; CLOBBERS: none besides a (bc and hl are saved; callers rely on both)
; ============================================================
Elite4MemberRoomMapForOPP:
	push bc
	push hl
	ld c, a
	ld hl, Elite4RoomMaps
.scan
	ld a, [hli]
	cp -1
	jr z, .notFound
	cp c
	ld a, [hli]                  ; the map byte; ld does not disturb cp's flags
	jr nz, .scan
	pop hl
	pop bc
	ret
.notFound
	; No row for this class. The old cp/jr chain silently answered LANCES_ROOM
	; here, which is exactly what disguised the 2026-07 cross-bank read as a
	; routing bug. Answer with the Lobby instead: still wrong, but unmistakably.
	ld a, INDIGO_PLATEAU_LOBBY
	pop hl
	pop bc
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
	sub OPP_ID_OFFSET
	ld e, a                      ; e = target trainer CLASS to find
	ld hl, wRunElite4
	xor a
	ld d, a                      ; d = index i (0-3)
.scan
	ld a, [hl]
	cp e
	jr z, .found
	inc hl
	inc d
	ld a, d
	cp 4
	jr c, .scan
	; Not one of this run's four. Only reachable if wRunElite4 is corrupt or a
	; room was entered outside the final sequence; the old code walked off the
	; end of its 4-byte row instead. Fail safe: south to the Lobby, north to the
	; Champion, and return NZ so the caller does not arm the Champion room.
	ld b, INDIGO_PLATEAU_LOBBY
	ld c, CHAMPIONS_ROOM
	ld a, 4
	cp 3
	ret
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
	add OPP_ID_OFFSET            ; wRunElite4 holds CLASS ids, not OPP_ ids
	push hl
	call Elite4MemberRoomMapForOPP
	pop hl
	ld b, a
	inc hl                       ; hl back to wRunElite4[i]
.prevDone
	; Resolve "next" (index i+1, or champion if i==3)
	ld a, d
	cp 3
	jr z, .nextIsChampion
	inc hl
	ld a, [hl]
	add OPP_ID_OFFSET            ; wRunElite4 holds CLASS ids, not OPP_ ids
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
	ld a, [wRunElite4 + 3]
	add OPP_ID_OFFSET            ; wRunElite4 holds CLASS ids, not OPP_ ids
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
; Phase 7 rooms. These y values are NOT copied from the rooms above: Koga's and
; Will's maps are 7 blocks tall (14 steps, south row 13) and Karen's is 8 (16
; steps, south row 15), against the 6 blocks (south row 11) the three original
; rooms use. Measured off each .blk, see PHASE_7_SPEC.md.
	db OPP_KOGA_E4, 13,4, 13,5, 0,4, 0,5
	db OPP_WILL,    13,4, 13,5, 0,4, 0,5
	db OPP_KAREN,   15,4, 15,5, 0,4, 0,5
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
