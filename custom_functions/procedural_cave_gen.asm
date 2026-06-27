; custom_functions/procedural_cave_gen.asm
;
; Runtime procedural cave generator for ProceduralCave1.
;
; Called once per map load via homecall from LoadMapData (home/overworld.asm,
; verified bank 00/HOME), right after LoadTileBlockMap has copied the static
; 20x20 template (Prototype B border kit + top_level_fill interior, see
; maps/ProceduralCave1.blk) into wOverworldMap, and before LoadCurrentMapView
; converts wOverworldMap into the visible VRAM tilemap.
;
; wOverworldMap stores one byte per block, row-major, with a MAP_BORDER=3
; block pad on every side (see home/overworld.asm LoadTileBlockMap). So cell
; (x,y) for this fixed 20x20 map lives at:
;   wOverworldMap + MAP_BORDER + x + (y + MAP_BORDER) * (PC_SIZE + MAP_BORDER*2)
;   = wOverworldMap + 3 + x + (y+3)*26 = wOverworldMap + 81 + x + y*26
;
; Design (see Red Rogue Files/cavern-blockset-classification.md for the full
; block catalog this draws from):
;   - entrance: random point on one of the 4 edges
;   - 5 target points on the other 3 edges; exactly one is the exit
;   - decorate interior fill cells with obstacle blocks before carving, so
;     carving always overwrites any obstacle that lands on the path
;   - wobble-walk from entrance to each target, carving floor as it goes
;   - entrance/exit get a boundary opening + their wWarpEntries Y/X patched;
;     the other 4 targets dead-end against the inside face of the wall

SECTION "ProceduralCaveGen", ROMX

DEF PC_SIZE    EQU 20  ; map width/height in blocks
DEF PC_STRIDE  EQU 26  ; PC_SIZE + MAP_BORDER*2
DEF PC_BASE    EQU 81  ; MAP_BORDER + MAP_BORDER*PC_STRIDE

DEF PC_BLOCK_FLOOR    EQU 1
DEF PC_BLOCK_ENTRANCE EQU 36  ; distinct floor variant used for the entrance cell only
DEF PC_BLOCK_WATER    EQU 118 ; river obstacle (PCCarveRiver) - confirmed impassable
                               ; (raw tile $14, not in Cavern_Coll) via direct .bst
                               ; decode, see PCCarveRiver's header comment
; Temporary sentinel used ONLY during PCAutotilePass's peninsula fix (see
; the comment there) - confirmed via a real before/after memory dump
; (2026-06-25) that writing PC_BLOCK_FLOOR directly during the main sweep
; let later-scanned cells mistake a JUST-converted cell for genuine
; pre-existing floor, cascading false peninsula triggers down a row. This
; value is never floor-like to PCClassifyCell during the main sweep, so it
; can't cascade; a cleanup pass at the end converts every leftover sentinel
; to real floor once the whole sweep (which can no longer see it) is done.
DEF PC_BLOCK_PENDING_FLOOR EQU 255

DEF PC_EDGE_TOP    EQU 0    ; procedural cave edge top of map, ect
DEF PC_EDGE_BOTTOM EQU 1
DEF PC_EDGE_LEFT   EQU 2
DEF PC_EDGE_RIGHT  EQU 3

DEF NUM_PC_OBSTACLES EQU 2  ; PCObstacleTable - 117 moved to its own pass, see PCDecorateLast
DEF NUM_PC_ROCKS     EQU 7  ; PCRockTable - stray-corner fallback decoration
DEF NUM_PC_LADDER_IDS EQU 3 ; PCLadderTable - exit warp ladder tile, 35 deliberately excluded

; Scratch storage: WRAM0 has no free bytes left for a new dedicated section
; (confirmed via the linker map), so this borrows wBuffer (ram/wram.asm,
; generic 30-byte scratch already reused by many unrelated one-off systems).
; Safe here because the whole generator runs as one atomic, non-reentrant
; pass between LoadTileBlockMap and LoadCurrentMapView - nothing else touches
; wBuffer during that window.
;
; WATCH ITEM: if something unrelated misbehaves right after a map load (a
; naming screen, trade animation, or anything else that also borrows
; wBuffer), suspect this reuse first. These are plain numeric offsets, NOT
; addresses - every use site below references them as [wBuffer + offset],
; since wBuffer's actual address isn't known until link time and DEF/EQU
; can't fold a cross-file link-time symbol into a constant.
DEF wProcCaveEntranceX    EQU 0
DEF wProcCaveEntranceY    EQU 1
DEF wProcCaveEntranceEdge EQU 2
DEF wProcCaveExitX        EQU 3
DEF wProcCaveExitY        EQU 4
DEF wProcCaveExitIndex    EQU 5
DEF wProcCaveTargetX      EQU 6
DEF wProcCaveTargetY      EQU 7
; PCRecheckNeighbors reuses these same two offsets (6/7) as its own
; save-slot for "which cell just got escalated to floor" - safe because
; by the time PCAutotilePass's Pass B runs, carving (the only other user
; of TargetX/Y) is long finished, and nothing after Pass B reads
; TargetX/Y again (confirmed: PCPlaceWildAreaItems was redesigned to
; sample fresh floor cells instead of using these). NOT safe to also
; reuse DX/DY here, despite them looking "free" the same way - PCRecheck-
; Neighbors calls PCClassifyCell/PCVerifyCorner per neighbor, and BOTH of
; those use DX/DY as THEIR OWN scratch, which would clobber an outer
; loop's saved position if it also lived in DX/DY.
DEF wProcCaveRecheckX     EQU 6
DEF wProcCaveRecheckY     EQU 7
DEF wProcCaveCurX         EQU 8
DEF wProcCaveCurY         EQU 9
DEF wProcCaveMaxSteps     EQU 10
DEF wProcCaveEdge         EQU 11
DEF wProcCaveOffset       EQU 12
DEF wProcCaveDX           EQU 13
DEF wProcCaveDY           EQU 14
DEF wProcCaveLoopI        EQU 15
DEF wProcCaveLoopX        EQU 16
DEF wProcCaveLoopY        EQU 17
; offsets 19/20/21 (SaveY, BulgeX/Y) were used by an earlier live-during-
; carving autotiling design, now removed - see the note above
; PCAutotilePass for why. Free again; reuse before adding new offsets.
DEF wProcCaveLadderOffset EQU 19  ; 0 or 1 - sub-tile remainder for the exit ladder's
                                  ; wWarpEntries position, set by PCPlaceExitLadder
                                  ; based on which ID got picked - see that function.
DEF wProcCaveItemCounter  EQU 20  ; PCPlaceWildAreaItems: 0-3, which of the 4 wild
                                  ; area pokeballs (sprite slots 1-4, wRogueItem/2/3/4)
                                  ; is currently being placed.
DEF wProcCaveBallPos      EQU 10  ; PCPlaceWildAreaItems: 8 bytes, X/Y interleaved for
                                  ; each of the 4 already-placed balls (offset+i*2 = X,
                                  ; +i*2+1 = Y) - used to reject new candidates that
                                  ; land too close to one already placed. Reuses
                                  ; MaxSteps/Edge/Offset/DX/DY/LoopI/LoopX/LoopY
                                  ; (offsets 10-17) - all carving-phase-only scratch,
                                  ; long finished by the time this runs (last thing
                                  ; GenerateProceduralCave does).
DEF PC_ITEM_MIN_DIST      EQU 4   ; PCPlaceWildAreaItems: minimum Chebyshev distance
                                  ; (max(|dx|,|dy|)) a candidate must keep from the
                                  ; entrance and from every already-placed ball.
DEF wProcCaveIncludeRocks EQU 18  ; toggle read by PCClassifyCell's floor-check -
                                  ; see PCIsFloorLike. 0 (default) = only real
                                  ; floor/entrance count; set to 1 only during
                                  ; PCAutotilePass's Pass C, which treats
                                  ; PCRockTable IDs as floor-like too, purely
                                  ; for cosmetic edge placement around rocks -
                                  ; rocks are NOT passable, so this must never
                                  ; be allowed to trigger the peninsula rule's
                                  ; floor escalation (Pass C's caller guards
                                  ; against that explicitly, see its comment).
                                  ; ALSO reused (long after autotiling is done) by
                                  ; PCPlaceWildAreaItems as a spacing-retry budget -
                                  ; counts down attempts to find a well-spaced
                                  ; candidate before giving up and accepting a
                                  ; closer-than-ideal (but still real-floor) one.
DEF wProcCaveFlags        EQU 22  ; PCClassifyCell's own scratch - must NOT reuse
                                  ; LoopI, which is live across PCCarveOne in the
                                  ; outer target loop in GenerateProceduralCave.
                                  ; ALSO safely reused by PCVerifyCorner (called
                                  ; only after PCClassifyCell has fully returned).
DEF wProcCaveIncludeWater EQU 26  ; toggle read by PCIsFloorLike, same pattern as
                                  ; wProcCaveIncludeRocks but for PC_BLOCK_WATER -
                                  ; 0 (default) = water never counts as floor-like;
                                  ; set to 1 only during PCAutotileRiverEdges, which
                                  ; gives water the same edge/corner treatment
                                  ; PCAutotilePass gives floor, reusing the exact
                                  ; same IDs (21/24/26/29/22/20/30/28) per the
                                  ; user's explicit instruction.
DEF wProcCaveCount        EQU 23  ; PCCountFloorNeighbors' running tally
DEF wProcCaveCountX       EQU 24  ; PCCountFloorNeighbors' own save slots - must
DEF wProcCaveCountY       EQU 25  ; NOT reuse DX/DY, which PCVerifyCorner (its
                                  ; only caller) is using for its OWN save at the
                                  ; same time

; PCPlaceDropIn scratch - runs absolute LAST in GenerateProceduralCave, so
; every offset below is long finished with by every earlier phase; freely
; reuses EntranceX/Y/Edge/ExitX/Y/Index/TargetX/Y (0-7) and Edge/Offset/DX/
; DY/LoopI (11-15), same "reuse, don't grow" discipline as wProcCaveBallPos.
DEF wProcCaveDropInIdx        EQU 0
DEF wProcCaveDropInW          EQU 1
DEF wProcCaveDropInH          EQU 2
DEF wProcCaveDropInBG         EQU 3
DEF wProcCaveDropInBuf        EQU 4
DEF wProcCaveDropInTotalW     EQU 5
DEF wProcCaveDropInTotalH     EQU 6
DEF wProcCaveDropInMaxOXRange EQU 7
DEF wProcCaveDropInMaxOYRange EQU 11
DEF wProcCaveDropInOX         EQU 12
DEF wProcCaveDropInOY         EQU 13
DEF wProcCaveDropInRow        EQU 14
DEF wProcCaveDropInCol        EQU 15

; ============================================================
; GenerateProceduralCave
; Entry point. See header comment for the hook site and call convention.
; ============================================================
GenerateProceduralCave::
	; --- entrance: PINNED to a hardcoded interior block for now (2026-06-25) ---
	; Was: random edge + offset via two Rangerandom calls (see git history /
	; the [[redrogue-procedural-cave]] memory for the exact original lines -
	; not reproduced here since this is a bigger structural change than the
	; earlier pin, not a simple value swap).
	;
	; Earlier pin attempts (top edge, then bottom edge) kept the ENTIRE
	; runtime-patching approach: dynamically computing wYCoord/wXCoord,
	; wSpritePlayerStateData2MapY/MapX, and wCurrentTileBlockMapViewPointer
	; from a generator-chosen block position, mirroring the build tool's
	; own event_displacement formula by hand. Bottom edge (block Y=19, the
	; map's last row) broke badly (camera showed nothing but the border-fill
	; block everywhere, player couldn't move at all) and top edge worked
	; only for collision/logical-position - a separate parity-bit cache
	; (wYBlockCoord/wXBlockCoord, see engine/overworld/tilesets.asm) gets
	; derived from wYCoord/wXCoord BEFORE this generator runs and was never
	; re-synced by any of the hand-rolled patches, which may also explain
	; some of the inconsistent behavior. Rather than keep hand-mirroring
	; (and debugging) the engine's own position-setup logic, the entrance is
	; now a genuinely static warp_event (data/maps/objects/ProceduralCave1.asm,
	; tile coords 36,76 = block (9,19) - on the bottom boundary row itself,
	; same spot as the broken bottom-edge attempt, but now via the SAME
	; build-time mechanism already proven correct for every vanilla warp in
	; the game (confirmed via the Red's House 1F live test this session),
	; which computes wYCoord/wXCoord, the sprite-state pair, the view-
	; pointer, AND the parity-bit pair correctly with zero runtime patching.
	; If this position still doesn't work, that's real evidence the last
	; row specifically has some other issue (insufficient padding margin?
	; not yet root-caused), since this rules out a hand-rolled-formula bug
	; as the cause. Only the EXIT still needs a runtime wWarpEntries patch
	; below, since its position is still chosen by the generator.
	;
	; wProcCaveEntranceEdge is set to PC_EDGE_BOTTOM since the entrance
	; really is on the bottom edge again - PCOtherEdgesTable picks the 3
	; OTHER edges for targets, same as the original random-entrance design.
	ld a, PC_EDGE_BOTTOM
	ld [wBuffer + wProcCaveEntranceEdge], a
	ld a, 9
	ld [wBuffer + wProcCaveEntranceX], a
	ld a, 19
	ld [wBuffer + wProcCaveEntranceY], a

	; --- which of the 5 targets is the exit ---
	ld c, 5
	call Rangerandom
	ld [wBuffer + wProcCaveExitIndex], a

	; --- stamp the entrance cell with its own distinct floor variant ---
	ld a, [wBuffer + wProcCaveEntranceX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveEntranceY]
	ld [wBuffer + wProcCaveCurY], a
	ld a, PC_BLOCK_ENTRANCE
	call PCWriteCell

	; --- 5 target points, each walked from the entrance ---
	xor a
	ld [wBuffer + wProcCaveLoopI], a
.targetLoop
	; pick target edge: one of the 3 NOT equal to the entrance edge
	ld c, 3
	call Rangerandom
	ld b, a                        ; b = sub-index 0-2 (Rangerandom preserves b)
	ld a, [wBuffer + wProcCaveEntranceEdge]
	ld c, a
	add a, a                       ; a = edge*2
	add a, c                       ; a = edge*3
	add a, b                       ; + sub-index = table row*3 + col
	ld hl, PCOtherEdgesTable
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hl]
	ld [wBuffer + wProcCaveEdge], a

	ld c, 18
	call Rangerandom
	inc a
	ld [wBuffer + wProcCaveOffset], a
	call PCEdgePoint
	ld a, [wBuffer + wProcCaveCurX]
	ld [wBuffer + wProcCaveTargetX], a
	ld a, [wBuffer + wProcCaveCurY]
	ld [wBuffer + wProcCaveTargetY], a

	; is this target the exit?
	ld a, [wBuffer + wProcCaveLoopI]
	ld b, a
	ld a, [wBuffer + wProcCaveExitIndex]
	cp b
	jr nz, .notExit
	ld a, [wBuffer + wProcCaveTargetX]
	ld [wBuffer + wProcCaveExitX], a
	ld a, [wBuffer + wProcCaveTargetY]
	ld [wBuffer + wProcCaveExitY], a
	ld a, [wBuffer + wProcCaveTargetX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveTargetY]
	ld [wBuffer + wProcCaveCurY], a
	ld a, PC_BLOCK_FLOOR
	call PCWriteCell                ; punch the exit boundary opening
.notExit

	call PCCarveOne

	ld a, [wBuffer + wProcCaveLoopI]
	inc a
	ld [wBuffer + wProcCaveLoopI], a
	cp 5
	jp nz, .targetLoop  ; jr out of range now that the loop body is bigger

	; --- re-stamp the entrance: every walk above starts by resetting to the
	; entrance position and immediately overwrites it with plain floor on
	; its first loop iteration, so PC_BLOCK_ENTRANCE never survives carving
	; without this - just set it again now that all carving is done ---
	ld a, [wBuffer + wProcCaveEntranceX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveEntranceY]
	ld [wBuffer + wProcCaveCurY], a
	ld a, PC_BLOCK_ENTRANCE
	call PCWriteCell

	; --- one final autotiling sweep over the whole map, now that all floor
	; is in its final position - see PCAutotilePass. Doing this once at the
	; end instead of live during carving avoids redundant re-classification
	; (the same wall cell could get reclassified repeatedly as different
	; walks/bulges carve floor near it over time) and removes the need for
	; the early-termination ambiguity that broke reachability - see
	; [[redrogue-procedural-cave]] memory for the full story. ---
	call PCAutotilePass

	; --- decoration, now that the cave's final shape is fully settled ---
	; Moved to run here (after carving + autotiling) instead of before
	; carving, on purpose: placing decoration BEFORE the cave's shape was
	; known meant a decoration could end up on the carved path (overwritten,
	; harmless) or immediately adjacent to it (NOT harmless - it would get
	; swept into the autotile pass's floor-adjacency rules like any other
	; fill cell, which is how a decoration like 117 ended up only ever
	; making visual sense as a north-wall edge in one observed case). Doing
	; it last means 60/61 only ever land on cells PCAutotilePass left alone
	; entirely (genuinely zero real floor neighbors - guaranteed isolated),
	; and 117 is reframed as a rare decorative variant of an ALREADY-PLACED
	; 21, never placed as loose fill at all. See PCDecorateLast below.
	call PCDecorateLast

	; --- river: impassable water obstacle, connectivity-safe by
	; construction (see PCCarveRiver's header comment) since it never
	; overwrites real floor. TESTING OVERRIDE: called unconditionally
	; (100%) right now - the real design is ~25% of caves get a river.
	; To restore that: ld c, 4 / call Rangerandom / and a / jr nz, .skipRiver
	; / call PCCarveRiver / .skipRiver (and delete the line below).
	call PCCarveRiver
	call PCAutotileRiverEdges

	; --- exit ladder tile: pick BEFORE patching wWarpEntries, since which ID
	; gets picked determines the sub-tile remainder needed below ---
	ld a, [wBuffer + wProcCaveExitX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveExitY]
	ld [wBuffer + wProcCaveCurY], a
	call PCPlaceExitLadder

	; --- patch the exit warp (wWarpEntries entry 1) to its chosen position ---
	; The entrance is now a genuinely static warp_event (see the comment at
	; the top of this function), so it needs no runtime patching at all -
	; wWarpEntries entry 0, wYCoord/wXCoord, the sprite-state pair, the
	; view-pointer, and the parity-bit pair are all set correctly by the
	; normal map-load process before this generator even runs. Only the
	; exit's position is still chosen here at runtime, and only its
	; wWarpEntries entry needs patching - the player never initially lands
	; on it, so none of the position-cache machinery above applies to it.
	;
	; wWarpEntries stores TILE coordinates (same units as wYCoord/wXCoord) -
	; convert block -> tile by *2, NOT *4. A PC block is 4x4 RAW tiles for
	; rendering (PC_BASE/PC_STRIDE addressing into wOverworldMap, confirmed
	; correct against the real .blk file), but wYCoord/wXCoord's "tile" unit
	; is a 2x2-raw-tile movement step, i.e. a PC block = exactly 2x2
	; movement-tile units. *4 was the same mistake the entrance's position
	; made early on (tried tile=block*4, e.g. (36,76) for block (9,19) -
	; wrong, see [[redrogue-procedural-cave]]) before being corrected to
	; ~block*2 (19,38) by hand. Confirmed against EVERY real warp_event in
	; data/maps/objects/SeafoamIslandsB1F.asm cross-referenced against
	; maps/SeafoamIslandsB1F.blk: tile = block*2 lands exactly on a sensible
	; ladder-style block ID for all 7 real warps; tile = block*4 lands on
	; garbage (border/plain floor) for all 7. Not in doubt.
	;
	; PLUS a per-ID sub-tile remainder (0 or 1, SAME value added to both axes -
	; confirmed not independent per-axis below) - the engine's warp-tile-
	; recognition check (CheckWarpsNoCollision -> ExtraWarpCheck ->
	; IsWarpTileInFrontOfPlayer, home/overworld.asm + engine/overworld/
	; player_state.asm) requires either the player's resting raw tile or the
	; tile ahead of them (depending on approach direction) to match a
	; recognized ID for the Cavern tileset - a bare position match alone is
	; NOT enough (verified: every reachable approach direction at a plain
	; block*2 position fired nothing). Checking all 7 real SeafoamIslandsB1F
	; warps' (tile%2) against their block IDs showed block 39 always uses
	; remainder (0,0), while blocks 40/60/62/124 always use remainder (1,1) -
	; tied to which corner each block's distinctive icon graphic sits in
	; (39's icon is top-left; 40/60/62/124's is bottom-right).
	; PCPlaceExitLadder sets wProcCaveLadderOffset to the correct value (0 or
	; 1) for whichever ID it just picked - apply it here.
	ld hl, wWarpEntries + 4
	ld a, [wBuffer + wProcCaveExitY]
	add a, a
	ld b, a
	ld a, [wBuffer + wProcCaveLadderOffset]
	add a, b
	ld [hli], a
	ld a, [wBuffer + wProcCaveExitX]
	add a, a
	ld b, a
	ld a, [wBuffer + wProcCaveLadderOffset]
	add a, b
	ld [hl], a

	; --- wild area pokeballs: 4 independent items, placed LAST, after
	; everything else (carving/autotile/decoration/exit ladder) has
	; permanently settled. Originally tried positioning these at each
	; dead-end target's walk endpoint, but that needed careful bookkeeping
	; for a case that turned out not to matter - just pick straight from
	; the real, final floor layout instead. See PCPlaceWildAreaItems.
	call PCPlaceWildAreaItems
	call PCPlaceBoss
	call PCSprinkleFloorDecor
	call PCPlaceDropIn
	ret

; ============================================================
; PCPlaceBoss
; Rolls a random species (reusing the EXISTING reward-pokemon machinery -
; GetRewardMonLevel + Random_Pokemon_Selection, same calls
; rogue_pokemon_randomized_batch already makes for wRoguePokemon1-3 - and
; reusing wRoguePokemon1 itself as scratch, per explicit user instruction,
; rather than adding a new WRAM variable) and patches it into the boss
; object_event's compiled data (data/maps/objects/ProceduralCave1.asm,
; the 5th declared object - sprite slot 5). No position patch needed -
; the boss is declared at a fixed tile (18,38), right in front of the
; static entrance warp, same reasoning as why the entrance itself needs
; no runtime position patch. See that object_event's comment for the
; OW_POKEMON/EngageMapTrainer mechanism this relies on.
; ============================================================
PCPlaceBoss:
	farcall GetRewardMonLevel       ; sets wCurEnemyLevel
	call Random
	ld c, 0                         ; auto-determine class via rarity odds
	; Random_Pokemon_Selection lives in bank 06 (confirmed via .sym), this
	; generator's own code is bank 07 - MUST be farcall, not call. A plain
	; call here silently executed bank 07's own bytes at that address
	; instead (the cross-bank call gotcha), corrupting the stack/control
	; flow enough that PCSprinkleFloorDecor's call right after PCPlaceBoss
	; in GenerateProceduralCave never ran - confirmed via a PyBoy execution
	; hook showing zero hits on PCSprinkleFloorDecor despite the call
	; being right there in the disassembly. The earlier "boss species/level
	; data looks correct" PyBoy confirmation this session was real but
	; lucky - whatever bank-07 garbage sat at Random_Pokemon_Selection's
	; address apparently left a plausible-looking d/wCurEnemyLevel by
	; coincidence often enough to not look broken.
	farcall Random_Pokemon_Selection ; -> d = species (possibly evolved)
	ld a, d
	ld [wRoguePokemon1], a

	; wMapSpriteExtraData is 2 bytes/slot, (slot-1)*2 offset - slot 5
	; (the boss, 5th declared object_event) = offset 8
	ld hl, wMapSpriteExtraData + 8
	ld a, [wRoguePokemon1]
	ld [hli], a                     ; "trainer class" slot = species
	ld a, [wCurEnemyLevel]
	set 7, a                        ; OW_POKEMON ($80) - confirmed this is
	ld [hl], a                      ; the bit EngageMapTrainer checks to
	ret                             ; treat this as a wild mon, not a trainer

; ============================================================
; PCPlaceWildAreaItems
; Places the 4 wild area pokeballs by picking straight from the cave's
; REAL, FINAL floor layout - not by tracking any particular carve walk's
; endpoint. Each candidate must (a) be real floor (PC_BLOCK_FLOOR) right
; now, and (b) keep at least PC_ITEM_MIN_DIST (Chebyshev) away from the
; entrance and from every already-placed ball, with a bounded retry
; budget that gives up on (b) - never on (a) - if the map doesn't have
; enough room to satisfy it. Run LAST in GenerateProceduralCave, after
; carving/autotiling/decoration/exit-ladder have all permanently settled,
; so "is this cell floor" can never go stale afterward.
; ============================================================
PCPlaceWildAreaItems:
	xor a
	ld [wBuffer + wProcCaveItemCounter], a
.placeLoop
	ld a, 80
	ld [wBuffer + wProcCaveIncludeRocks], a   ; spacing-retry budget, see its DEF
.spacingRetry
	; --- find ANY real floor cell first - never skipped, generously
	; bounded only as a safety net against a pathological map ---
	ld b, 200
.floorRetry
	ld c, PC_SIZE
	call Rangerandom
	ld [wBuffer + wProcCaveCurX], a
	ld c, PC_SIZE
	call Rangerandom
	ld [wBuffer + wProcCaveCurY], a
	push bc
	call PCReadCell                ; clobbers b - preserve our retry counter
	pop bc
	cp PC_BLOCK_FLOOR
	jr z, .gotFloor
	dec b
	jr nz, .floorRetry
	ret                             ; couldn't find ANY floor cell - bail out
	                                ; rather than hang (should never happen -
	                                ; the cave always has well over 100)
.gotFloor

	; --- must be far enough from the entrance ---
	ld a, [wBuffer + wProcCaveCurX]
	ld c, a
	ld a, [wBuffer + wProcCaveEntranceX]
	sub c
	call PCAbs
	ld c, a
	ld a, [wBuffer + wProcCaveCurY]
	ld d, a
	ld a, [wBuffer + wProcCaveEntranceY]
	sub d
	call PCAbs
	cp c
	jr nc, .haveMaxEnt
	ld a, c
.haveMaxEnt                        ; a = max(|dx|,|dy|) to entrance
	cp PC_ITEM_MIN_DIST
	jr c, .spaceFail

	; --- must be far enough from each already-placed ball ---
	ld a, [wBuffer + wProcCaveItemCounter]
	and a
	jr z, .distOK                  ; no balls placed yet
	ld b, a
	ld hl, wBuffer + wProcCaveBallPos
.checkBallLoop
	ld a, [wBuffer + wProcCaveCurX]
	ld c, a
	ld a, [hli]                    ; placed ball's X
	sub c
	call PCAbs
	ld c, a
	ld a, [wBuffer + wProcCaveCurY]
	ld e, a
	ld a, [hli]                    ; placed ball's Y
	sub e
	call PCAbs
	cp c
	jr nc, .haveMaxBall
	ld a, c
.haveMaxBall
	cp PC_ITEM_MIN_DIST
	jr c, .spaceFail
	dec b
	jr nz, .checkBallLoop
.distOK
	jr .accept
.spaceFail
	ld a, [wBuffer + wProcCaveIncludeRocks]
	dec a
	ld [wBuffer + wProcCaveIncludeRocks], a
	jr nz, .spacingRetry
	; budget exhausted - accept this candidate anyway (it's still
	; confirmed real floor, just closer than ideal to something)
.accept
	; remember this ball's position for future spacing checks
	ld a, [wBuffer + wProcCaveItemCounter]
	add a, a                       ; *2 (X,Y pair)
	ld c, a
	ld b, 0
	ld hl, wBuffer + wProcCaveBallPos
	add hl, bc
	ld a, [wBuffer + wProcCaveCurX]
	ld [hli], a
	ld a, [wBuffer + wProcCaveCurY]
	ld [hl], a

	; position the matching sprite slot (itemCounter+1, 1-indexed -
	; sprite slots 1-4, see data/maps/objects/ProceduralCave1.asm)
	ld a, [wBuffer + wProcCaveItemCounter]
	add a, a
	add a, a
	add a, a
	add a, a                       ; *16
	ld hl, wSprite01StateData2MapY
	add a, l
	ld l, a
	jr nc, .noCarrySpriteSlot
	inc h
.noCarrySpriteSlot
	ld a, [wBuffer + wProcCaveCurY]
	add a, a                       ; block -> tile, *2 (no sub-tile remainder
	ld [hli], a                    ; needed here - that was specifically about
	ld a, [wBuffer + wProcCaveCurX] ; satisfying the warp-tile-recognition
	add a, a                       ; check, irrelevant to plain object/NPC
	ld [hl], a                     ; collision - see [[redrogue-procedural-cave]]

	; roll an independent item for this slot. Random_Item_Selection reads
	; wRogueDoorSelection to pick its class (HEALING=0/STAT=1/TM=2/MONEY=3,
	; see engine/items/item_rarity.asm) - we never set it before this, so
	; it just held whatever stale value the last unrelated write left
	; there (0 on a fresh debug game, since nothing else had touched it
	; yet), which is why every wild-area item rolled as a healing item.
	; Roll our own random class here instead.
	ld c, 4
	call Rangerandom
	ld [wRogueDoorSelection], a
	farcall Random_Item_Selection   ; always writes its result to wRogueItem
	ld a, [wBuffer + wProcCaveItemCounter]
	and a
	jr z, .afterItemCopy            ; slot 0 (ball 1) - wRogueItem already correct
	add a, a                        ; *2 - wRogueItem/2/3/4 are 4 consecutive dw's
	ld c, a
	ld b, 0
	ld hl, wRogueItem
	add hl, bc
	ld a, [wRogueItem]
	ld [hl], a
.afterItemCopy

	ld a, [wBuffer + wProcCaveItemCounter]
	inc a
	ld [wBuffer + wProcCaveItemCounter], a
	cp 4
	jp nz, .placeLoop
	ret

; ============================================================
; PCSprinkleFloorDecor
; Places NUM_PC_FLOOR_DECOR floor-obstacle decals (IDs 12-19 - 4 distinct
; corner-decal motifs, each duplicated under two IDs, confirmed via
; direct .bst decode: every one of the 8 is 12/16 raw tiles
; Cavern_Coll-passable, with the other 4 forming a single 2x2
; impassable corner in a different corner per ID) onto random
; already-real-floor cells (PC_BLOCK_FLOOR, never the entrance/exit/
; item cells - those no longer read as plain floor by this point).
;
; A single decal alone can never block its own cell - it only takes one
; of the cell's 4 movement-tile quadrants, leaving the other 3 open, and
; every direction crosses via 2 parallel tiles so removing 1 still
; leaves the other available. BUT two decals on ADJACENT cells CAN
; combine into a real, total blockage if they block DIFFERENT rows/
; columns on their facing sides ("crossed" alignment) - e.g. one cell
; blocking its bottom-right while its north neighbor blocks its
; top-right: the top crossing fails because the north cell's side is
; blocked, AND the bottom crossing fails because the south cell's side
; is blocked - neither of the 2 parallel routes has both ends open.
; Confirmed for real with a labeled debug screenshot: ID 17 directly
; north of ID 18 is exactly this case (17 blocks its own bottom-left,
; 18 blocks its own top-right) and is genuinely impassable - not a
; theoretical worry, an actual case the user found and verified.
; PCNearFloorDecor below rejects any candidate adjacent to an existing
; decal, which fully prevents this (a lone decal is always safe per the
; first paragraph, so "never adjacent to another decal" is sufficient,
; not just risk-reducing).
; ============================================================
DEF NUM_PC_FLOOR_DECOR EQU 3
DEF wProcCaveFloorDecorCount EQU 0  ; reused offset, same numeric slot
                                    ; PCPlaceDropIn later reuses for its
                                    ; own counter - this function always
                                    ; finishes before that one starts

PCFloorDecorTable:
	db 12, 13, 14, 15, 16, 17, 18, 19

; ============================================================
; PCNearFloorDecor
; INPUT: wProcCaveCurX/Y = cell to check. OUTPUT: carry SET if any of
; the 4 orthogonal neighbors already holds a placed floor-decor ID
; (12-19) - see PCSprinkleFloorDecor's header comment for why two
; adjacent decals (even though each is individually harmless alone) can
; combine into a real blockage, and must never be allowed to be
; neighbors. Same save/restore-DX/DY structure as PCNearClaimed - safe
; here for the identical reason (long past the carving phase).
; ============================================================
PCNearFloorDecor:
	ld a, [wBuffer + wProcCaveCurX]
	ld [wBuffer + wProcCaveDX], a
	ld a, [wBuffer + wProcCaveCurY]
	ld [wBuffer + wProcCaveDY], a

	dec a
	ld [wBuffer + wProcCaveCurY], a
	call PCReadCell
	call PCIsFloorDecorCarry
	jr c, .restore

	ld a, [wBuffer + wProcCaveDY]
	inc a
	ld [wBuffer + wProcCaveCurY], a
	ld a, [wBuffer + wProcCaveDX]
	ld [wBuffer + wProcCaveCurX], a
	call PCReadCell
	call PCIsFloorDecorCarry
	jr c, .restore

	ld a, [wBuffer + wProcCaveDY]
	ld [wBuffer + wProcCaveCurY], a
	ld a, [wBuffer + wProcCaveDX]
	dec a
	ld [wBuffer + wProcCaveCurX], a
	call PCReadCell
	call PCIsFloorDecorCarry
	jr c, .restore

	ld a, [wBuffer + wProcCaveDX]
	inc a
	ld [wBuffer + wProcCaveCurX], a
	call PCReadCell
	call PCIsFloorDecorCarry
.restore
	push af
	ld a, [wBuffer + wProcCaveDX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveDY]
	ld [wBuffer + wProcCaveCurY], a
	pop af
	ret

; INPUT: a = a cell's current block ID. OUTPUT: carry SET if it's in
; the floor-decor ID range (12-19 inclusive).
PCIsFloorDecorCarry:
	cp 12
	jr c, .no
	cp 20
	jr nc, .no
	scf
	ret
.no
	and a
	ret

PCSprinkleFloorDecor:
	xor a
	ld [wBuffer + wProcCaveFloorDecorCount], a
.sprinkleLoop
	ld b, 200
.retry
	ld c, PC_SIZE
	call Rangerandom
	ld [wBuffer + wProcCaveCurX], a
	ld c, PC_SIZE
	call Rangerandom
	ld [wBuffer + wProcCaveCurY], a
	push bc
	call PCReadCell                ; clobbers b - preserve our retry counter
	pop bc
	cp PC_BLOCK_FLOOR
	jr nz, .notFloor
	push bc
	call PCNearFloorDecor           ; reject anything next to an existing
	pop bc                          ; decal - see header comment for why
	jr nc, .gotFloor
.notFloor
	dec b
	jr nz, .retry
	ret                             ; couldn't find a valid cell - bail out, harmless
.gotFloor
	ld c, 8
	call Rangerandom
	ld c, a
	ld hl, PCFloorDecorTable
	ld b, 0
	add hl, bc
	ld a, [hl]
	call PCWriteCell

	ld a, [wBuffer + wProcCaveFloorDecorCount]
	inc a
	ld [wBuffer + wProcCaveFloorDecorCount], a
	cp NUM_PC_FLOOR_DECOR
	jr nz, .sprinkleLoop
	ret

; ============================================================
; Drop-in stamps (DRAFT 5, IMPLEMENTED 2026-06-26): small hand-authored
; .blk files, dropped onto a verified-clear rectangle of the finished
; cave. User-authored, not extracted from existing maps. Two backing
; types, named by file prefix:
; - "1tile*": backed by real floor (PC_BLOCK_FLOOR). The file holds ONLY
;   the stamp's own interior (confirmed by decoding 1tilepooldrop.blk -
;   4 bytes, all raw value 96, no edge variation at all - floor needs no
;   edge transition, matching PCSprinkleFloorDecor's same reasoning).
;   Needs a SEPARATE, runtime-checked-but-never-written 1-cell buffer
;   ring of real floor around its own footprint, so nothing else (an
;   item, the boss, floor decor, another stamp) ends up jammed directly
;   against it. Matches the user's own example exactly: "for the 2x2
;   pool [1tilepooldrop.blk] a 4x4 space would be required to drop in" -
;   2x2 footprint + 1-cell buffer on all 4 sides = 4x4 checked, only the
;   inner 2x2 actually written.
; - "25tile*": backed by plain fill (25, the same "untouched" cells
;   PCDecorateLast targets). The file BAKES ITS OWN buffer/edge-ring
;   directly into its data (confirmed by decoding 25tilepooldrop.blk - a
;   4x4 block whose outer ring is real autotile edge IDs, 21/24/26/29,
;   the exact same N/S/E/W-alone IDs PCAutotilePass itself uses, framing
;   a 2x2 pool-texture interior - not generic fill). So the file's own
;   declared width/height IS the full required space already; no extra
;   runtime buffer on top of it (PC_DROPIN_BUF_FILL = 0).
;
; Picks one random stamp, rejection-samples a valid top-left corner for
; its full checked rectangle (footprint + 2*buffer on each axis), then
; writes only the stamp's own inner W x H bytes - the buffer ring (if
; any) is read-only, never modified. Gives up gracefully (no stamp this
; generation) if no valid spot is found in budget - same idiom as
; PCPlaceWildAreaItems's spacing retry.
; ============================================================
DEF PC_DROPIN_BUF_FLOOR EQU 1   ; 1-tile runtime-checked buffer, floor-backed
DEF PC_DROPIN_BUF_FILL  EQU 0   ; fill-backed stamps bake their own buffer/edges
DEF NUM_PC_DROPINS      EQU 4

PCDropIn1tilePoolData:     INCBIN "maps/1tilepooldrop.blk"
PCDropIn1tileTallRockData: INCBIN "maps/1tiletallrockdrop.blk"
PCDropIn1tileWideRockData: INCBIN "maps/1tilewiderockdrop.blk"
PCDropIn25tilePoolData:    INCBIN "maps/25tilepooldrop.blk"

; one row per stamp: width, height, background value, buffer
PCDropInTable:
	db 2, 2, PC_BLOCK_FLOOR, PC_DROPIN_BUF_FLOOR  ; 1tilepooldrop
	db 1, 3, PC_BLOCK_FLOOR, PC_DROPIN_BUF_FLOOR  ; 1tiletallrockdrop
	db 3, 1, PC_BLOCK_FLOOR, PC_DROPIN_BUF_FLOOR  ; 1tilewiderockdrop
	db 4, 4, 25,             PC_DROPIN_BUF_FILL   ; 25tilepooldrop
PCDropInPtrTable:
	dw PCDropIn1tilePoolData
	dw PCDropIn1tileTallRockData
	dw PCDropIn1tileWideRockData
	dw PCDropIn25tilePoolData

; ============================================================
; PCDropInCheckRect
; Checks whether the wProcCaveDropInTotalW x TotalH rectangle starting
; at (DropInOX, DropInOY) is ENTIRELY background value DropInBG.
; OUTPUT: carry SET if so.
; ============================================================
PCDropInCheckRect:
	xor a
	ld [wBuffer + wProcCaveDropInRow], a
.rowLoop
	xor a
	ld [wBuffer + wProcCaveDropInCol], a
.colLoop
	ld a, [wBuffer + wProcCaveDropInOX]
	ld b, a
	ld a, [wBuffer + wProcCaveDropInCol]
	add a, b
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveDropInOY]
	ld b, a
	ld a, [wBuffer + wProcCaveDropInRow]
	add a, b
	ld [wBuffer + wProcCaveCurY], a
	call PCReadCell
	ld b, a
	ld a, [wBuffer + wProcCaveDropInBG]
	cp b
	jr nz, .fail

	ld a, [wBuffer + wProcCaveDropInCol]
	inc a
	ld [wBuffer + wProcCaveDropInCol], a
	ld b, a
	ld a, [wBuffer + wProcCaveDropInTotalW]
	cp b
	jr nz, .colLoop

	ld a, [wBuffer + wProcCaveDropInRow]
	inc a
	ld [wBuffer + wProcCaveDropInRow], a
	ld b, a
	ld a, [wBuffer + wProcCaveDropInTotalH]
	cp b
	jr nz, .rowLoop

	scf
	ret
.fail
	and a       ; clear carry
	ret

; ============================================================
; PCDropInWriteRect
; Writes the chosen stamp's own W x H bytes - INPUT: de = stamp data
; pointer - starting at (DropInOX+DropInBuf, DropInOY+DropInBuf). The
; buffer ring, if any, is left completely untouched.
; ============================================================
PCDropInWriteRect:
	xor a
	ld [wBuffer + wProcCaveDropInRow], a
.rowLoop
	xor a
	ld [wBuffer + wProcCaveDropInCol], a
.colLoop
	ld a, [wBuffer + wProcCaveDropInOX]
	ld b, a
	ld a, [wBuffer + wProcCaveDropInBuf]
	add a, b
	ld b, a
	ld a, [wBuffer + wProcCaveDropInCol]
	add a, b
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveDropInOY]
	ld b, a
	ld a, [wBuffer + wProcCaveDropInBuf]
	add a, b
	ld b, a
	ld a, [wBuffer + wProcCaveDropInRow]
	add a, b
	ld [wBuffer + wProcCaveCurY], a

	ld a, [de]
	inc de
	call PCWriteCell

	ld a, [wBuffer + wProcCaveDropInCol]
	inc a
	ld [wBuffer + wProcCaveDropInCol], a
	ld b, a
	ld a, [wBuffer + wProcCaveDropInW]
	cp b
	jr nz, .colLoop

	ld a, [wBuffer + wProcCaveDropInRow]
	inc a
	ld [wBuffer + wProcCaveDropInRow], a
	ld b, a
	ld a, [wBuffer + wProcCaveDropInH]
	cp b
	jr nz, .rowLoop
	ret

; ============================================================
; PCDropInOverlapsSprite
; Checks the 4 wild-area-item sprite slots (1-4) and the boss (slot 5)
; against the FULL checked rectangle [DropInOX, DropInOX+DropInTotalW) x
; [DropInOY, DropInOY+DropInTotalH) - not just the inner write rectangle,
; to stay safely clear of the buffer too. OUTPUT: carry SET if any
; sprite's block position falls inside that rectangle.
;
; Found via real testing: PCPlaceDropIn ran with zero awareness of where
; PCPlaceWildAreaItems/PCPlaceBoss had already positioned their sprites,
; so a stamp could (and did, in a real run) land directly on top of an
; already-placed item, overwriting its floor tile underneath it.
; ============================================================
PCDropInOverlapsSprite:
	ld c, 0                         ; slot index 0-3 = items 1-4, 4 = boss
.slotLoop
	ld a, c
	add a, a
	add a, a
	add a, a
	add a, a                        ; *16
	ld hl, wSprite01StateData2MapY
	add a, l
	ld l, a
	jr nc, .noCarrySlot
	inc h
.noCarrySlot
	ld a, [hli]                     ; tile Y
	srl a                           ; tile -> block, /2
	ld b, a                         ; b = sprite's block Y
	ld a, [hl]                      ; tile X (MapX immediately follows MapY)
	srl a
	ld d, a                         ; d = sprite's block X

	ld a, b
	ld e, a
	ld a, [wBuffer + wProcCaveDropInOY]
	ld b, a
	ld a, e
	sub b                           ; a = spriteBlockY - OY (wraps if negative)
	ld b, a
	ld a, [wBuffer + wProcCaveDropInTotalH]
	cp b
	jr c, .next                     ; TotalH <= b -> outside this axis
	jr z, .next

	ld a, d
	ld e, a
	ld a, [wBuffer + wProcCaveDropInOX]
	ld b, a
	ld a, e
	sub b
	ld b, a
	ld a, [wBuffer + wProcCaveDropInTotalW]
	cp b
	jr c, .next
	jr z, .next

	scf                              ; inside on both axes - overlap
	ret
.next
	inc c
	ld a, c
	cp 5
	jr nz, .slotLoop
	and a
	ret

PCPlaceDropIn:
	ld c, NUM_PC_DROPINS
	call Rangerandom
	ld [wBuffer + wProcCaveDropInIdx], a

	; row = idx*4 into PCDropInTable (W,H,BG,Buf per stamp)
	add a, a
	add a, a
	ld c, a
	ld b, 0
	ld hl, PCDropInTable
	add hl, bc
	ld a, [hli]
	ld [wBuffer + wProcCaveDropInW], a
	ld a, [hli]
	ld [wBuffer + wProcCaveDropInH], a
	ld a, [hli]
	ld [wBuffer + wProcCaveDropInBG], a
	ld a, [hl]
	ld [wBuffer + wProcCaveDropInBuf], a

	; totalW/H = W/H + 2*Buf
	ld a, [wBuffer + wProcCaveDropInBuf]
	add a, a
	ld b, a
	ld a, [wBuffer + wProcCaveDropInW]
	add a, b
	ld [wBuffer + wProcCaveDropInTotalW], a
	ld a, [wBuffer + wProcCaveDropInBuf]
	add a, a
	ld b, a
	ld a, [wBuffer + wProcCaveDropInH]
	add a, b
	ld [wBuffer + wProcCaveDropInTotalH], a

	; valid OX/OY range size = PC_SIZE - totalW/H + 1 (assumes
	; totalW/H <= PC_SIZE - true for every stamp currently authored;
	; not defended against a hypothetically oversized future stamp)
	ld a, [wBuffer + wProcCaveDropInTotalW]
	ld b, a
	ld a, PC_SIZE
	sub b
	inc a
	ld [wBuffer + wProcCaveDropInMaxOXRange], a
	ld a, [wBuffer + wProcCaveDropInTotalH]
	ld b, a
	ld a, PC_SIZE
	sub b
	inc a
	ld [wBuffer + wProcCaveDropInMaxOYRange], a

	ld b, 100
.retry
	ld a, [wBuffer + wProcCaveDropInMaxOXRange]
	ld c, a
	call Rangerandom
	ld [wBuffer + wProcCaveDropInOX], a
	ld a, [wBuffer + wProcCaveDropInMaxOYRange]
	ld c, a
	call Rangerandom
	ld [wBuffer + wProcCaveDropInOY], a

	push bc
	call PCDropInCheckRect
	pop bc
	jr nc, .failed
	push bc
	call PCDropInOverlapsSprite     ; don't land on an already-placed item/boss
	pop bc
	jr c, .failed
	jr .found
.failed
	dec b
	jr nz, .retry
	ret                              ; gave up - no drop-in this generation
.found
	ld a, [wBuffer + wProcCaveDropInIdx]
	add a, a
	ld c, a
	ld b, 0
	ld hl, PCDropInPtrTable
	add hl, bc
	ld e, [hl]
	inc hl
	ld d, [hl]
	call PCDropInWriteRect
	ret

; ============================================================
; PCPlaceExitLadder
; Stamps a random ladder-pool tile onto the exit's block position
; (wProcCaveCurX/Y must already be set to the exit position by the caller).
; No neighbor/direction logic needed - confirmed safe to place on any
; floor tile. Pool is {40, 39, 62}; 35 deliberately excluded ("to be
; safe" per user instruction), 98 dropped after decoding gfx/blocksets/
; cavern.bst: 98 is 15/16 impassable raw tiles (almost entirely a wall
; graphic), unlike 39/40/62 which are mostly open floor with the ladder
; icon tucked into just one corner - confirmed via real PyBoy collision
; test that 98 specifically blocked movement, see
; [[redrogue-procedural-cave]].
; ============================================================
PCLadderTable:
	db 40, 39, 62
; Parallel table (same index) - sub-tile remainder needed for that ID's
; wWarpEntries position to land on its recognized raw tile, see the long
; comment above the wWarpEntries patch in GenerateProceduralCave. Derived
; from every real warp_event in SeafoamIslandsB1F: 39 always uses
; remainder 0 (icon is top-left), 40/62 always use remainder 1 (icon is
; bottom-right).
PCLadderOffsetTable:
	db 1, 0, 1

PCPlaceExitLadder:
	ld c, NUM_PC_LADDER_IDS
	call Rangerandom
	ld c, a
	ld hl, PCLadderTable
	ld b, 0
	add hl, bc
	ld a, [hl]
	call PCWriteCell
	ld hl, PCLadderOffsetTable
	ld b, 0
	add hl, bc
	ld a, [hl]
	ld [wBuffer + wProcCaveLadderOffset], a
	ret

; ============================================================
; PCEntranceViewPointer
; Computes the build-time-equivalent view pointer for the generator's
; chosen entrance tile and writes it to wCurrentTileBlockMapViewPointer.
; Mirrors the event_displacement macro's formula (macros/scripts/maps.asm):
;   ptr = wOverworldMap + 7 + width + (width+6)*(tileY>>1) + (tileX>>1)
; tileY/tileX = entrance block coords * 4 (block -> tile), so
; tileY>>1 = entranceY*2 and tileX>>1 = entranceX*2. width = PC_SIZE, so
; width+6 = PC_STRIDE (26) - same numeric stride as PCWriteCell uses, but
; this is a DIFFERENT addressing scheme (base 7+width vs PC_BASE=81); see
; the comment at the call site.
; ============================================================
PCEntranceViewPointer:
	ld a, [wBuffer + wProcCaveEntranceY]
	add a, a            ; blockY*2 = (blockY*4)>>1 = tileY>>1
	ld b, a
	ld hl, wOverworldMap + 7 + PC_SIZE
	and a
	jr z, .doneRows
.rowLoop
	ld a, l
	add a, PC_STRIDE
	ld l, a
	jr nc, .noCarryRow
	inc h
.noCarryRow
	dec b
	jr nz, .rowLoop
.doneRows
	ld a, [wBuffer + wProcCaveEntranceX]
	add a, a            ; blockX*2 = tileX>>1
	add a, l
	ld l, a
	jr nc, .noCarryCol
	inc h
.noCarryCol
	ld a, l
	ld [wCurrentTileBlockMapViewPointer], a
	ld a, h
	ld [wCurrentTileBlockMapViewPointer + 1], a
	ret

; ============================================================
; PCEdgePoint
; INPUT: wProcCaveEdge (0-3), wProcCaveOffset (1-18)
; OUTPUT: wProcCaveCurX, wProcCaveCurY
; ============================================================
PCEdgePoint:
	ld a, [wBuffer + wProcCaveEdge]
	and a
	jr z, .top
	dec a
	jr z, .bottom
	dec a
	jr z, .left
	; right
	ld a, PC_SIZE - 1
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveOffset]
	ld [wBuffer + wProcCaveCurY], a
	ret
.left
	xor a
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveOffset]
	ld [wBuffer + wProcCaveCurY], a
	ret
.bottom
	ld a, [wBuffer + wProcCaveOffset]
	ld [wBuffer + wProcCaveCurX], a
	ld a, PC_SIZE - 1
	ld [wBuffer + wProcCaveCurY], a
	ret
.top
	ld a, [wBuffer + wProcCaveOffset]
	ld [wBuffer + wProcCaveCurX], a
	xor a
	ld [wBuffer + wProcCaveCurY], a
	ret

PCOtherEdgesTable:
	db PC_EDGE_BOTTOM, PC_EDGE_LEFT,   PC_EDGE_RIGHT  ; entrance = TOP
	db PC_EDGE_TOP,    PC_EDGE_LEFT,   PC_EDGE_RIGHT  ; entrance = BOTTOM
	db PC_EDGE_TOP,    PC_EDGE_BOTTOM, PC_EDGE_RIGHT  ; entrance = LEFT
	db PC_EDGE_TOP,    PC_EDGE_BOTTOM, PC_EDGE_LEFT   ; entrance = RIGHT

; ============================================================
; PCWriteCell
; INPUT: a = block ID to write, wProcCaveCurX/Y = cell coords (0-19)
; ============================================================
PCWriteCell:
	push af
	ld hl, wOverworldMap + PC_BASE
	ld a, [wBuffer + wProcCaveCurX]
	add a, l
	ld l, a
	jr nc, .noCarryX
	inc h
.noCarryX
	ld a, [wBuffer + wProcCaveCurY]
	and a
	jr z, .doneY
	ld b, a
.yLoop
	ld a, l
	add a, PC_STRIDE
	ld l, a
	jr nc, .noCarryY
	inc h
.noCarryY
	dec b
	jr nz, .yLoop
.doneY
	pop af
	ld [hl], a
	ret

; ============================================================
; PCReadCell
; Read-only mirror of PCWriteCell, same addressing.
; INPUT: wProcCaveCurX/Y = cell coords (0-19). OUTPUT: a = current block ID.
; ============================================================
PCReadCell:
	ld hl, wOverworldMap + PC_BASE
	ld a, [wBuffer + wProcCaveCurX]
	add a, l
	ld l, a
	jr nc, .noCarryX
	inc h
.noCarryX
	ld a, [wBuffer + wProcCaveCurY]
	and a
	jr z, .doneY
	ld b, a
.yLoop
	ld a, l
	add a, PC_STRIDE
	ld l, a
	jr nc, .noCarryY
	inc h
.noCarryY
	dec b
	jr nz, .yLoop
.doneY
	ld a, [hl]
	ret

; ============================================================
; PCIsConvertible
; INPUT: a = a cell's current block ID.
; OUTPUT: carry SET if this is fill/decoration/a straight edge (eligible to
;   be (re)classified by PCClassifyCell); carry CLEAR for floor, entrance,
;   an already-finalized corner, or anything else (e.g. the border-fill
;   block, though that never appears inside the 0-19 range anyway).
; Edge IDs (21/29/26/24) are included so a cell already classified as a
; straight edge can later be upgraded to a corner once a second floor
; neighbor appears - see PCRecomputeNeighbors.
; ============================================================
PCIsConvertible:
	cp 25
	jr z, .yes
	cp 60
	jr z, .yes
	cp 61
	jr z, .yes
	cp 117
	jr z, .yes
	cp 21
	jr z, .yes
	cp 29
	jr z, .yes
	cp 26
	jr z, .yes
	cp 24
	jr z, .yes
	and a
	ret
.yes
	scf
	ret

; ============================================================
; PCIsFloorLike
; INPUT: a = a cell's current block ID.
; OUTPUT: carry SET if floor-like for adjacency purposes - always true for
;   PC_BLOCK_FLOOR/PC_BLOCK_ENTRANCE. ALSO true for any PCRockTable ID, but
;   ONLY when wProcCaveIncludeRocks is set (see that flag's comment - this
;   must stay off except during PCAutotilePass's Pass C, since rocks are
;   not passable and must never be allowed to trigger the peninsula rule's
;   floor escalation in PCClassifyCell).
; ============================================================
PCIsFloorLike:
	cp PC_BLOCK_FLOOR
	jr z, .yes
	cp PC_BLOCK_ENTRANCE
	jr z, .yes
	ld b, a
	ld a, [wBuffer + wProcCaveIncludeWater]
	and a
	ld a, b
	jr z, .checkRocks
	cp PC_BLOCK_WATER
	jr z, .yes
.checkRocks
	ld b, a
	ld a, [wBuffer + wProcCaveIncludeRocks]
	and a
	ld a, b
	jr z, .no
	cp 2
	jr z, .yes
	cp 77
	jr z, .yes
	cp 78
	jr z, .yes
	cp 79
	jr z, .yes
	cp 81
	jr z, .yes
	cp 82
	jr z, .yes
	cp 83
	jr z, .yes
.no
	and a
	ret
.yes
	scf
	ret

; ============================================================
; PCClassifyCell
; INPUT: wProcCaveCurX/Y = the cell to classify (must not itself be floor).
; OUTPUT: if at least one orthogonal neighbor is floor-like (PC_BLOCK_FLOOR
;   or PC_BLOCK_ENTRANCE), carry SET and a = the correct block ID for this
;   cell (a corner if two adjacent sides are floor, else a straight edge).
;   If no neighbor is floor-like, carry CLEAR and a is undefined - caller
;   must leave the cell untouched.
; wProcCaveCurX/Y is restored to its input value before returning.
; Clobbers: wProcCaveDX/DY (used as save slots), wProcCaveFlags (used as a
;   4-bit neighbor-floor flags byte: bit0=north,1=south,2=east,3=west), b.
; Deliberately does NOT touch wProcCaveLoopI - that's the live target-loop
; counter in GenerateProceduralCave, which calls PCCarveOne (and so this,
; transitively) before re-reading it.
; ============================================================
PCClassifyCell:
	ld a, [wBuffer + wProcCaveCurX]
	ld [wBuffer + wProcCaveDX], a
	ld a, [wBuffer + wProcCaveCurY]
	ld [wBuffer + wProcCaveDY], a
	xor a
	ld [wBuffer + wProcCaveFlags], a

	; north (y-1)
	ld a, [wBuffer + wProcCaveDY]
	and a
	jr z, .skipNorth
	dec a
	ld [wBuffer + wProcCaveCurY], a
	ld a, [wBuffer + wProcCaveDX]
	ld [wBuffer + wProcCaveCurX], a
	call PCReadCell
	call PCIsFloorLike
	jr nc, .skipNorth
	ld a, [wBuffer + wProcCaveFlags]
	or 1
	ld [wBuffer + wProcCaveFlags], a
.skipNorth
	; south (y+1)
	ld a, [wBuffer + wProcCaveDY]
	cp PC_SIZE - 1
	jr z, .skipSouth
	inc a
	ld [wBuffer + wProcCaveCurY], a
	ld a, [wBuffer + wProcCaveDX]
	ld [wBuffer + wProcCaveCurX], a
	call PCReadCell
	call PCIsFloorLike
	jr nc, .skipSouth
	ld a, [wBuffer + wProcCaveFlags]
	or 2
	ld [wBuffer + wProcCaveFlags], a
.skipSouth
	; east (x+1)
	ld a, [wBuffer + wProcCaveDX]
	cp PC_SIZE - 1
	jr z, .skipEast
	inc a
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveDY]
	ld [wBuffer + wProcCaveCurY], a
	call PCReadCell
	call PCIsFloorLike
	jr nc, .skipEast
	ld a, [wBuffer + wProcCaveFlags]
	or 4
	ld [wBuffer + wProcCaveFlags], a
.skipEast
	; west (x-1)
	ld a, [wBuffer + wProcCaveDX]
	and a
	jr z, .skipWest
	dec a
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveDY]
	ld [wBuffer + wProcCaveCurY], a
	call PCReadCell
	call PCIsFloorLike
	jr nc, .skipWest
	ld a, [wBuffer + wProcCaveFlags]
	or 8
	ld [wBuffer + wProcCaveFlags], a
.skipWest

	ld a, [wBuffer + wProcCaveDX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveDY]
	ld [wBuffer + wProcCaveCurY], a

	ld a, [wBuffer + wProcCaveFlags]
	and a
	jr z, .noFloorNeighbor
	ld b, a

	; if 3 or 4 sides are floor, this cell is almost surrounded already -
	; no 2-sided corner ID can represent that correctly (the priority check
	; below only ever looks at 2 of the 4 bits, so a 3rd floor side was
	; silently ignored before this check existed, leaving a "peninsula" of
	; solid material poking into open floor - confirmed by an actual
	; in-game screenshot, e.g. a 22/20 with floor ALSO to its south, or a
	; 28/30 with floor ALSO to its north). Just make it floor too.
	xor a
	ld c, a
	bit 0, b
	jr z, .skipCountN
	inc c
.skipCountN
	bit 1, b
	jr z, .skipCountS
	inc c
.skipCountS
	bit 2, b
	jr z, .skipCountE
	inc c
.skipCountE
	bit 3, b
	jr z, .skipCountW
	inc c
.skipCountW
	ld a, c
	cp 3
	jr c, .twoOrFewerSides
	; PC_BLOCK_PENDING_FLOOR, NOT PC_BLOCK_FLOOR - see the constant's comment.
	; Writing real floor here would let a cell scanned moments later mistake
	; this just-converted cell for genuine pre-existing floor, cascading
	; false peninsula triggers down a row - confirmed via a real before/after
	; memory dump, not theorized. PCAutotilePass's cleanup pass converts this
	; to real floor only after the whole sweep (which can't see it) is done.
	ld a, PC_BLOCK_PENDING_FLOOR
	scf
	ret
.twoOrFewerSides

	; opposite-sides exception: floor on both north+south, or both east+west
	; (a wall cell sandwiched between two parallel corridors) isn't a corner
	; pattern either - no 2-sided corner ID represents "open on two opposite
	; sides", and picking one side via the priority chain below would hide
	; the other (confirmed by an actual report: a "24" with floor genuinely
	; on its east too). Resolve it the same way as the 3+ case: just open
	; it into floor, merging the two corridors at that point - a wider
	; merge point reads as a natural cave feature, and it needs no tile a
	; clean 9-slice kit doesn't have. Same PC_BLOCK_PENDING_FLOOR sentinel,
	; same reasoning, so this is automatically cascade-safe too.
	ld a, b
	cp %0011                ; exactly north+south, nothing else
	jr z, .openOppositeSides
	cp %1100                ; exactly east+west, nothing else
	jr nz, .notOppositeSides
.openOppositeSides
	ld a, PC_BLOCK_PENDING_FLOOR
	scf
	ret
.notOppositeSides

	; IDs confirmed 2026-06-25 against the user's hand-drawn Polished Map
	; intersection reference (ground truth - the static border template
	; used for the EARLIER, wrong derivation has no actual carved floor
	; anywhere, so it couldn't prove a real floor-adjacency rule). Every
	; single direction is mirrored from the previous attempt: north<->south
	; AND east<->west both flipped, so corners flip too.
	ld a, b
	and %0101              ; north+east
	cp %0101
	jr nz, .notNE
	ld a, 22
	jr .haveResult
.notNE
	ld a, b
	and %1001              ; north+west
	cp %1001
	jr nz, .notNW
	ld a, 20
	jr .haveResult
.notNW
	ld a, b
	and %0110              ; south+east
	cp %0110
	jr nz, .notSE
	ld a, 30
	jr .haveResult
.notSE
	ld a, b
	and %1010              ; south+west
	cp %1010
	jr nz, .notSW
	ld a, 28
	jr .haveResult
.notSW
	bit 0, b                ; north
	jr z, .notN2
	ld a, 21
	jr .haveResult
.notN2
	bit 1, b                ; south
	jr z, .notS2
	ld a, 29
	jr .haveResult
.notS2
	bit 3, b                ; west
	jr z, .notW2
	ld a, 24
	jr .haveResult
.notW2
	ld a, 26                ; only east left
.haveResult
	scf
	ret
.noFloorNeighbor
	and a
	ret

; ============================================================
; PCCountFloorNeighbors
; INPUT: wProcCaveCurX/Y = a cell (typically a known floor cell).
; OUTPUT: a = count of its orthogonal neighbors that are floor-like (0-4).
; wProcCaveCurX/Y restored to its input value before returning.
; Clobbers: wProcCaveCount/CountX/CountY. Deliberately does NOT use DX/DY -
;   PCVerifyCorner (its only caller) needs those to survive across this call.
; ============================================================
PCCountFloorNeighbors:
	ld a, [wBuffer + wProcCaveCurX]
	ld [wBuffer + wProcCaveCountX], a
	ld a, [wBuffer + wProcCaveCurY]
	ld [wBuffer + wProcCaveCountY], a
	xor a
	ld [wBuffer + wProcCaveCount], a

	; north
	ld a, [wBuffer + wProcCaveCountY]
	and a
	jr z, .skipN
	dec a
	ld [wBuffer + wProcCaveCurY], a
	ld a, [wBuffer + wProcCaveCountX]
	ld [wBuffer + wProcCaveCurX], a
	call PCReadCell
	cp PC_BLOCK_FLOOR
	jr z, .nFloor
	cp PC_BLOCK_ENTRANCE
	jr nz, .skipN
.nFloor
	ld a, [wBuffer + wProcCaveCount]
	inc a
	ld [wBuffer + wProcCaveCount], a
.skipN
	; south
	ld a, [wBuffer + wProcCaveCountY]
	cp PC_SIZE - 1
	jr z, .skipS
	inc a
	ld [wBuffer + wProcCaveCurY], a
	ld a, [wBuffer + wProcCaveCountX]
	ld [wBuffer + wProcCaveCurX], a
	call PCReadCell
	cp PC_BLOCK_FLOOR
	jr z, .sFloor
	cp PC_BLOCK_ENTRANCE
	jr nz, .skipS
.sFloor
	ld a, [wBuffer + wProcCaveCount]
	inc a
	ld [wBuffer + wProcCaveCount], a
.skipS
	; east
	ld a, [wBuffer + wProcCaveCountX]
	cp PC_SIZE - 1
	jr z, .skipE
	inc a
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveCountY]
	ld [wBuffer + wProcCaveCurY], a
	call PCReadCell
	cp PC_BLOCK_FLOOR
	jr z, .eFloor
	cp PC_BLOCK_ENTRANCE
	jr nz, .skipE
.eFloor
	ld a, [wBuffer + wProcCaveCount]
	inc a
	ld [wBuffer + wProcCaveCount], a
.skipE
	; west
	ld a, [wBuffer + wProcCaveCountX]
	and a
	jr z, .skipW
	dec a
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveCountY]
	ld [wBuffer + wProcCaveCurY], a
	call PCReadCell
	cp PC_BLOCK_FLOOR
	jr z, .wFloor
	cp PC_BLOCK_ENTRANCE
	jr nz, .skipW
.wFloor
	ld a, [wBuffer + wProcCaveCount]
	inc a
	ld [wBuffer + wProcCaveCount], a
.skipW
	ld a, [wBuffer + wProcCaveCountX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveCountY]
	ld [wBuffer + wProcCaveCurY], a
	ld a, [wBuffer + wProcCaveCount]
	ret

; ============================================================
; PCVerifyCorner
; INPUT: a = a proposed corner ID (22/20/30/28), wProcCaveCurX/Y = the wall
;   cell that would receive it.
; OUTPUT: a = the SAME corner ID if both contributing floor neighbors have
;   2+ floor neighbors of their own (a genuine corridor turn); otherwise a
;   randomly-picked PCRockTable ID instead. A corner caused by two dead-end
;   nubs (most likely a PCBulge poke, which by construction has exactly 1
;   floor neighbor) coincidentally meeting at a right angle isn't a real
;   turn and shouldn't be drawn like one.
; wProcCaveCurX/Y restored to its input value before returning. Safe to
; reuse wProcCaveDX/DY and wProcCaveFlags here - PCClassifyCell (their only
; other owner) has always already returned by the time this runs.
; ============================================================
PCVerifyCorner:
	ld [wBuffer + wProcCaveFlags], a      ; stash the proposed ID
	ld a, [wBuffer + wProcCaveCurX]
	ld [wBuffer + wProcCaveDX], a
	ld a, [wBuffer + wProcCaveCurY]
	ld [wBuffer + wProcCaveDY], a

	; first contributing neighbor: north for 22/20, south for 30/28
	ld a, [wBuffer + wProcCaveFlags]
	cp 22
	jr z, .firstIsNorth
	cp 20
	jr z, .firstIsNorth
	ld a, [wBuffer + wProcCaveDY]
	inc a
	ld [wBuffer + wProcCaveCurY], a
	ld a, [wBuffer + wProcCaveDX]
	ld [wBuffer + wProcCaveCurX], a
	jr .haveFirst
.firstIsNorth
	ld a, [wBuffer + wProcCaveDY]
	dec a
	ld [wBuffer + wProcCaveCurY], a
	ld a, [wBuffer + wProcCaveDX]
	ld [wBuffer + wProcCaveCurX], a
.haveFirst
	call PCCountFloorNeighbors
	cp 2
	jr c, .notReal

	; second contributing neighbor: east for 22/30, west for 20/28
	ld a, [wBuffer + wProcCaveFlags]
	cp 22
	jr z, .secondIsEast
	cp 30
	jr z, .secondIsEast
	ld a, [wBuffer + wProcCaveDX]
	dec a
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveDY]
	ld [wBuffer + wProcCaveCurY], a
	jr .haveSecond
.secondIsEast
	ld a, [wBuffer + wProcCaveDX]
	inc a
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveDY]
	ld [wBuffer + wProcCaveCurY], a
.haveSecond
	call PCCountFloorNeighbors
	cp 2
	jr c, .notReal

	ld a, [wBuffer + wProcCaveDX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveDY]
	ld [wBuffer + wProcCaveCurY], a
	ld a, [wBuffer + wProcCaveFlags]
	ret
.notReal
	ld a, [wBuffer + wProcCaveDX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveDY]
	ld [wBuffer + wProcCaveCurY], a
	ld c, NUM_PC_ROCKS
	call Rangerandom
	ld hl, PCRockTable
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hl]
	ret

; stray-corner fallback decoration - generic rocks/boulders that look fine
; regardless of orientation, used in place of a directional corner piece
; when PCVerifyCorner determines the "corner" is just two dead-end nubs
; (almost always a PCBulge poke) meeting by coincidence, not a real turn.
PCRockTable:
	db 2, 77, 78, 79, 81, 82, 83

; ============================================================
; NOTE ON AN EARLIER, ABANDONED APPROACH (2026-06-25)
;
; PCAutotilePass below replaced a live/during-carving design: every floor
; write (in GenerateProceduralCave's entrance stamp and exit punch, and in
; PCCarveOne's walk loop/done-stamp, and in PCBulge) was immediately
; followed by a call to a PCRecomputeNeighbors routine, which reclassified
; the 4 orthogonal neighbors of whatever cell had just become floor via
; PCClassifyCell (same classify logic that still exists below) and a
; PCRecomputeOne helper that gated the write on PCIsConvertible.
;
; Two real problems killed it, both confirmed by an actual test, not
; theorized:
; 1. CPU cost: the same wall/edge cell can get reclassified many times
;    over the course of generation, once per nearby floor write from any
;    walk or bulge - redundant work that scales with how much gets carved,
;    not with the fixed size of the map.
; 2. Correctness: it came with an early-termination feature (stop a walk
;    early if it stepped onto a cell some OTHER walk had already carved,
;    so paths could branch into each other). But all 5 walks start from
;    the SAME entrance, so "touched already-floor" couldn't distinguish a
;    genuine connection to a distant walk from just touching the shared
;    starting area near the entrance - walks 2-5 could (and did, in
;    testing) terminate within their first couple of steps, never
;    reaching their actual targets. The test screenshot showed exactly
;    this: most of the map never got carved at all.
;
; PCAutotilePass fixes both: one pass, fixed cost, no live connectivity
; detection needed (and so no early-termination ambiguity), since by the
; time it runs every walk has already unconditionally reached its own
; target the simple way (like before any of this existed).
;
; If live-during-carving ever comes back (e.g. for some effect a one-shot
; final pass genuinely can't do), the early-termination design needs a way
; to tell "this walk's own already-carved cells" apart from "a different
; walk's" - a per-cell "which walk carved this" tag, or a minimum-step
; count before allowing termination, would both need building first; don't
; just resurrect the old call sites as-is.
; ============================================================
; PCAutotilePass
; One full sweep over every cell in the map (0-19 x 0-19, boundary ring
; included), run once after all carving (all 5 walks, plus the entrance
; re-stamp) is finished. For each cell still convertible (plain fill or a
; decoration obstacle - never a cell carving already turned to floor),
; classify it from its neighbors' CURRENT (final) floor state and write
; the result. Since all floor placement is already final by the time this
; runs, a single pass is enough - no need to revisit a cell once it's been
; classified, unlike a live-during-carving approach would.
; ============================================================
; ============================================================
; PCAutotilePass
; Two genuinely separate passes over the whole map, not one combined sweep.
;
; Pass A resolves ALL peninsula-driven floor first (a cell with 3+ real
; floor neighbors becomes floor itself), using the same pending-sentinel
; trick to stop false cascades WITHIN this pass. Only after Pass A's own
; cleanup runs is the floor layout for the WHOLE map fully and finally
; settled - both originally-carved floor AND peninsula-created floor.
;
; Pass B then does edge/corner classification using that complete, final
; floor layout. This is necessary, not just tidier: even with Pass A's
; anti-cascade fix, a single combined sweep can still legitimately produce
; a cell that becomes new floor via the peninsula rule (using only ITS OWN
; real original neighbors - not a cascade, a perfectly correct conversion)
; AFTER an EARLIER-SCANNED neighbor has already been finalized as a plain
; edge. That earlier neighbor never gets a chance to learn it now also
; borders real floor. Confirmed via real before/after dumps: a `26` cell
; with floor genuinely to its south too (which should have made it a `30`
; corner) - the south neighbor only became floor moments later in the
; same sweep, after the `26` was already written and never revisited.
; Splitting into two passes removes the order-dependency entirely instead
; of patching around it - by the time Pass B runs, ALL floor is fixed, so
; it doesn't matter what order Pass B itself visits cells in.
; ============================================================

; ============================================================
; PCRecheckNeighbors / PCRecheckOne
; See the long comment inside Pass B (below) at the one call site for
; the full story - Pass B's own rare "shouldn't happen" floor-escalation
; fallback has the exact same cascade bug Pass A already had, just one
; level deeper. This re-examines the 4 immediate neighbors of
; wProcCaveCurX/Y (which must already BE the just-escalated floor cell,
; already written) and corrects any that need it - including
; OVERWRITING an already-finalized edge/corner, which nothing else in
; this file ever does (PCIsConvertible deliberately excludes them
; everywhere else). Only one level deep, not recursive - see the call
; site for why that's an acceptable, deliberate tradeoff and what the
; more thorough (more expensive) alternative would look like.
;
; REMAINING KNOWN RISK, confirmed via real automated scanning (not just
; theorized): this cuts real violations from ~8 per 100 generations down
; to ~1 per 100 - a big improvement, but NOT a full fix. A genuine
; second-order cascade (a neighbor-of-a-neighbor needing escalation,
; one hop past what this one-level recheck reaches) can still produce
; an occasional awkward/wrong edge or corner tile somewhere on the map.
; User's explicit call: this residual rate is acceptable, given the cost
; of fully closing it (see the more-extreme-alternative note above).
; Revisit only if real testing shows this is more common or more
; visually disruptive than this scan suggested.
; ============================================================
PCRecheckNeighbors:
	ld a, [wBuffer + wProcCaveCurX]
	ld [wBuffer + wProcCaveRecheckX], a
	ld a, [wBuffer + wProcCaveCurY]
	ld [wBuffer + wProcCaveRecheckY], a

	; north
	ld a, [wBuffer + wProcCaveRecheckY]
	and a
	jr z, .skipN
	dec a
	ld [wBuffer + wProcCaveCurY], a
	ld a, [wBuffer + wProcCaveRecheckX]
	ld [wBuffer + wProcCaveCurX], a
	call PCRecheckOne
.skipN
	; south
	ld a, [wBuffer + wProcCaveRecheckY]
	cp PC_SIZE - 1
	jr z, .skipS
	inc a
	ld [wBuffer + wProcCaveCurY], a
	ld a, [wBuffer + wProcCaveRecheckX]
	ld [wBuffer + wProcCaveCurX], a
	call PCRecheckOne
.skipS
	; east
	ld a, [wBuffer + wProcCaveRecheckX]
	cp PC_SIZE - 1
	jr z, .skipE
	inc a
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveRecheckY]
	ld [wBuffer + wProcCaveCurY], a
	call PCRecheckOne
.skipE
	; west
	ld a, [wBuffer + wProcCaveRecheckX]
	and a
	jr z, .skipW
	dec a
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveRecheckY]
	ld [wBuffer + wProcCaveCurY], a
	call PCRecheckOne
.skipW
	ld a, [wBuffer + wProcCaveRecheckX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveRecheckY]
	ld [wBuffer + wProcCaveCurY], a
	ret

; INPUT: wProcCaveCurX/Y = neighbor to recheck.
PCRecheckOne:
	call PCReadCell
	cp PC_BLOCK_FLOOR
	ret z                   ; already real floor - nothing to upgrade
	cp PC_BLOCK_ENTRANCE
	ret z
	call PCClassifyCell
	ret nc                  ; no floor-like neighbor at all - leave as is
	cp PC_BLOCK_PENDING_FLOOR
	jr nz, .notPendingRecheck
	ld a, PC_BLOCK_FLOOR
	jr .writeRecheck
.notPendingRecheck
	cp 22
	jr z, .cornerRecheck
	cp 20
	jr z, .cornerRecheck
	cp 30
	jr z, .cornerRecheck
	cp 28
	jr z, .cornerRecheck
	jr .writeRecheck
.cornerRecheck
	call PCVerifyCorner
.writeRecheck
	call PCWriteCell
	ret

PCAutotilePass:
	; --- Pass A: peninsula resolution only ---
	xor a
	ld [wBuffer + wProcCaveLoopY], a
.aYLoop
	xor a
	ld [wBuffer + wProcCaveLoopX], a
.aXLoop
	ld a, [wBuffer + wProcCaveLoopX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveLoopY]
	ld [wBuffer + wProcCaveCurY], a

	call PCReadCell
	call PCIsConvertible
	jr nc, .aSkipCell
	call PCClassifyCell
	jr nc, .aSkipCell
	cp PC_BLOCK_PENDING_FLOOR
	jr nz, .aSkipCell           ; an edge/corner result - leave it for Pass B
	call PCWriteCell
.aSkipCell
	ld a, [wBuffer + wProcCaveLoopX]
	inc a
	ld [wBuffer + wProcCaveLoopX], a
	cp PC_SIZE
	jr nz, .aXLoop
	ld a, [wBuffer + wProcCaveLoopY]
	inc a
	ld [wBuffer + wProcCaveLoopY], a
	cp PC_SIZE
	jr nz, .aYLoop

	; Pass A cleanup: convert this pass's own pending-floor sentinels to
	; real floor now that Pass A's own sweep is fully finished.
	xor a
	ld [wBuffer + wProcCaveLoopY], a
.cleanYLoop
	xor a
	ld [wBuffer + wProcCaveLoopX], a
.cleanXLoop
	ld a, [wBuffer + wProcCaveLoopX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveLoopY]
	ld [wBuffer + wProcCaveCurY], a
	call PCReadCell
	cp PC_BLOCK_PENDING_FLOOR
	jr nz, .cleanSkip
	ld a, PC_BLOCK_FLOOR
	call PCWriteCell
.cleanSkip
	ld a, [wBuffer + wProcCaveLoopX]
	inc a
	ld [wBuffer + wProcCaveLoopX], a
	cp PC_SIZE
	jr nz, .cleanXLoop
	ld a, [wBuffer + wProcCaveLoopY]
	inc a
	ld [wBuffer + wProcCaveLoopY], a
	cp PC_SIZE
	jr nz, .cleanYLoop

	; --- Pass B: edge/corner classification, floor layout now fully fixed ---
	xor a
	ld [wBuffer + wProcCaveLoopY], a
.yLoop
	xor a
	ld [wBuffer + wProcCaveLoopX], a
.xLoop
	ld a, [wBuffer + wProcCaveLoopX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveLoopY]
	ld [wBuffer + wProcCaveCurY], a

	call PCReadCell
	call PCIsConvertible
	jr nc, .skipCell
	call PCClassifyCell
	jr nc, .skipCell

	; CORRECTED 2026-06-26: this WAS commented "no cascade risk: this is
	; the last pass, nothing left to read it as a false signal" - that was
	; wrong, confirmed via real before/after dumps (same methodology that
	; found the original Pass A/B cascade bugs). Pass B can ALSO create
	; new real floor mid-sweep (this exact fallback), and a neighbor
	; scanned EARLIER in this SAME Pass B sweep can already have been
	; permanently finalized as an edge/corner using stale, pre-escalation
	; neighbor data - and since corners/edges are excluded from
	; PCIsConvertible, nothing would ever revisit and fix it. Confirmed
	; for real: a "20" corner with ALL 4 neighbors genuinely real floor,
	; traced via phase-boundary breakpoints to appearing exactly here,
	; inside Pass B's own sweep.
	;
	; Fix: after writing this escalation, immediately recheck just this
	; cell's 4 immediate neighbors (PCRecheckNeighbors below) and correct
	; any that need it - including overwriting an already-finalized edge/
	; corner, which nothing else in this file ever does. Deliberately only
	; one level deep, not a recursive worklist - this fallback firing at
	; all is already rare, so a second-order cascade from it is rarer
	; still, and one-level recheck is enough to fix every case found so
	; far. The MORE EXTREME alternative - give this whole pass the same
	; sentinel+cleanup treatment as Pass A, then run a full additional
	; reclassification sweep willing to revisit existing corners too -
	; would be more rigorous (catches multi-level cascades) but costs a
	; full extra pass or two over all 400 cells (~15-25 more frames on
	; top of this function's already-dominant load-time share, see
	; Red Rogue Files/procedural-cave-performance-plan.md) for a benefit
	; that's only theoretical until real testing shows the scoped
	; one-level version actually missing something.
	cp PC_BLOCK_PENDING_FLOOR
	jr nz, .notPending
	ld a, PC_BLOCK_FLOOR
	call PCWriteCell
	call PCRecheckNeighbors
	jr .skipCell
.notPending
	; if the result is a corner, verify it's a real turn and not just two
	; dead-end nubs (almost always a PCBulge poke) meeting by coincidence
	cp 22
	jr z, .checkCorner
	cp 20
	jr z, .checkCorner
	cp 30
	jr z, .checkCorner
	cp 28
	jr z, .checkCorner
	jr .haveValue
.checkCorner
	call PCVerifyCorner
.haveValue
	call PCWriteCell
.skipCell

	ld a, [wBuffer + wProcCaveLoopX]
	inc a
	ld [wBuffer + wProcCaveLoopX], a
	cp PC_SIZE
	jr nz, .xLoop

	ld a, [wBuffer + wProcCaveLoopY]
	inc a
	ld [wBuffer + wProcCaveLoopY], a
	cp PC_SIZE
	jr nz, .yLoop

	; --- Pass C: cosmetic edges around rocks ---
	; Rocks (PCRockTable) only exist after Pass B places them, so this has
	; to run as its own pass afterward - same order-dependency reasoning as
	; the Pass A/B split. wProcCaveIncludeRocks makes PCIsFloorLike (used
	; inside PCClassifyCell) treat rocks as floor-like for this pass only.
	;
	; Touches plain fill (25) AND any already-placed straight edge
	; (21/29/26/24) - NOT existing corners (22/20/30/28), which are already
	; the maximal 2-sided representation and have no further upgrade path.
	; Revisiting straight edges matters: Pass B classifies purely from real
	; floor, so an edge that's ALSO rock-adjacent on a second, adjacent side
	; (e.g. a "26" with a rock to its north) was finalized before Pass C
	; could ever see the rock - confirmed via an actual report ("26 north
	; of a 2"). Reclassifying it here can upgrade it to the correct corner.
	;
	; A PC_BLOCK_PENDING_FLOOR result is deliberately discarded (cell is
	; left exactly as it was, whether that's 25 or its prior edge ID), not
	; written - rocks are NOT passable, so rock-adjacency must never open a
	; cell into real floor, unlike a genuine 3-real-floor-sides peninsula.
	; Corners produced here skip PCVerifyCorner too - that check is about
	; real-path continuity, which doesn't apply when triggered by
	; rock-adjacency.
	ld a, 1
	ld [wBuffer + wProcCaveIncludeRocks], a
	xor a
	ld [wBuffer + wProcCaveLoopY], a
.cYLoop
	xor a
	ld [wBuffer + wProcCaveLoopX], a
.cXLoop
	ld a, [wBuffer + wProcCaveLoopX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveLoopY]
	ld [wBuffer + wProcCaveCurY], a

	call PCReadCell
	cp 25
	jr z, .cEligible
	cp 21
	jr z, .cEligible
	cp 29
	jr z, .cEligible
	cp 26
	jr z, .cEligible
	cp 24
	jr z, .cEligible
	jr .cSkipCell
.cEligible
	call PCClassifyCell
	jr nc, .cSkipCell
	cp PC_BLOCK_PENDING_FLOOR
	jr z, .cSkipCell
	call PCWriteCell
.cSkipCell
	ld a, [wBuffer + wProcCaveLoopX]
	inc a
	ld [wBuffer + wProcCaveLoopX], a
	cp PC_SIZE
	jr nz, .cXLoop
	ld a, [wBuffer + wProcCaveLoopY]
	inc a
	ld [wBuffer + wProcCaveLoopY], a
	cp PC_SIZE
	jr nz, .cYLoop

	xor a
	ld [wBuffer + wProcCaveIncludeRocks], a
	ret

; ============================================================
; PCAbs
; INPUT: a = signed byte. OUTPUT: a = absolute value. Only touches a/flags.
; ============================================================
PCAbs:
	bit 7, a
	ret z
	cpl
	inc a
	ret

; ============================================================
; PCDecorateLast
; Two decoration passes over the 18x18 interior, run AFTER carving and the
; full PCAutotilePass sweep (see the call site comment in
; GenerateProceduralCave for why this moved here instead of running
; before carving, like the original PCDecorate did).
;
; Pass 1: 60/61 (~1-in-40 chance) on any cell STILL plain fill (25) at this
; point. PCAutotilePass would already have converted anything with a real
; floor neighbor, so anything still 25 here is guaranteed genuinely
; isolated - these can never end up adjacent to the cave structure at all.
;
; Pass 2: 117 (~1-in-40 chance) replacing an ALREADY-PLACED 21. Reframed as
; a decorative variant of that one wall type specifically, never placed as
; loose fill - 117 only ever made visual sense in a 21-adjacent context
; (confirmed by an actual in-game screenshot report).
; ============================================================
PCDecorateLast:
	ld a, 1
	ld [wBuffer + wProcCaveLoopY], a
.fillYLoop
	ld a, 1
	ld [wBuffer + wProcCaveLoopX], a
.fillXLoop
	ld a, [wBuffer + wProcCaveLoopX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveLoopY]
	ld [wBuffer + wProcCaveCurY], a
	call PCReadCell
	cp 25
	jr nz, .fillSkipCell

	ld c, 40
	call Rangerandom
	and a
	jr nz, .fillSkipCell

	ld c, NUM_PC_OBSTACLES
	call Rangerandom
	ld hl, PCObstacleTable
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hl]
	call PCWriteCell
.fillSkipCell
	ld a, [wBuffer + wProcCaveLoopX]
	inc a
	ld [wBuffer + wProcCaveLoopX], a
	cp PC_SIZE - 1
	jr nz, .fillXLoop
	ld a, [wBuffer + wProcCaveLoopY]
	inc a
	ld [wBuffer + wProcCaveLoopY], a
	cp PC_SIZE - 1
	jr nz, .fillYLoop

	; Pass 2: 117 as a rare decorative variant of existing 21s
	ld a, 1
	ld [wBuffer + wProcCaveLoopY], a
.wallYLoop
	ld a, 1
	ld [wBuffer + wProcCaveLoopX], a
.wallXLoop
	ld a, [wBuffer + wProcCaveLoopX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveLoopY]
	ld [wBuffer + wProcCaveCurY], a
	call PCReadCell
	cp 21
	jr nz, .wallSkipCell

	ld c, 40
	call Rangerandom
	and a
	jr nz, .wallSkipCell

	ld a, 117
	call PCWriteCell
.wallSkipCell
	ld a, [wBuffer + wProcCaveLoopX]
	inc a
	ld [wBuffer + wProcCaveLoopX], a
	cp PC_SIZE - 1
	jr nz, .wallXLoop
	ld a, [wBuffer + wProcCaveLoopY]
	inc a
	ld [wBuffer + wProcCaveLoopY], a
	cp PC_SIZE - 1
	jr nz, .wallYLoop
	ret

; obstacle block IDs for PCDecorateLast's fill pass. 60/61 are classified as
; warp_ladder in the catalog, but confirmed safe here - warp behavior is
; driven entirely by wWarpEntries entries, not tile ID, and nothing ever
; creates a warp_event at a random decoration position, so these are
; purely cosmetic when sprinkled. 117 is handled separately (see
; PCDecorateLast's second pass), not part of this table anymore.
PCObstacleTable:
	db 60, 61

; ============================================================
; PCCarveOne
; Wobble-walks from the entrance to wProcCaveTargetX/Y, writing floor along
; the way, then force-stamps the exact target cell regardless of how the
; walk ended (guarantees the breach/dead-end point is always connected).
; ============================================================
PCCarveOne:
	ld a, [wBuffer + wProcCaveEntranceX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveEntranceY]
	ld [wBuffer + wProcCaveCurY], a

	call PCManhattan          ; a = manhattan distance, entrance to target
	ld b, a
	add a, b
	add a, b                 ; a = distance * 3
	and a
	jr nz, .haveMax
	inc a                     ; avoid a zero step budget if already on target
.haveMax
	ld [wBuffer + wProcCaveMaxSteps], a

.walkLoop
	ld a, PC_BLOCK_FLOOR
	call PCWriteCell

	ld c, 20
	call Rangerandom
	cp 3
	call c, PCBulge            ; ~15% chance: also carve one random neighbor

	ld a, [wBuffer + wProcCaveCurX]
	ld b, a
	ld a, [wBuffer + wProcCaveTargetX]
	cp b
	jr nz, .notAtTarget
	ld a, [wBuffer + wProcCaveCurY]
	ld b, a
	ld a, [wBuffer + wProcCaveTargetY]
	cp b
	jr z, .done
.notAtTarget
	ld a, [wBuffer + wProcCaveMaxSteps]
	and a
	jr z, .done
	dec a
	ld [wBuffer + wProcCaveMaxSteps], a

	call PCStep
	jr .walkLoop

.done
	ld a, [wBuffer + wProcCaveTargetX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveTargetY]
	ld [wBuffer + wProcCaveCurY], a
	ld a, PC_BLOCK_FLOOR
	call PCWriteCell
	ret

; ============================================================
; PCManhattan
; OUTPUT: a = |targetX-curX| + |targetY-curY|
; ============================================================
PCManhattan:
	ld a, [wBuffer + wProcCaveTargetX]
	ld b, a
	ld a, [wBuffer + wProcCaveCurX]
	ld c, a
	ld a, b
	sub c
	ld [wBuffer + wProcCaveDX], a
	ld a, [wBuffer + wProcCaveTargetY]
	ld b, a
	ld a, [wBuffer + wProcCaveCurY]
	ld c, a
	ld a, b
	sub c
	ld [wBuffer + wProcCaveDY], a

	ld a, [wBuffer + wProcCaveDX]
	call PCAbs
	ld b, a
	ld a, [wBuffer + wProcCaveDY]
	call PCAbs
	add a, b
	ret

; ============================================================
; PCStep
; Moves wProcCaveCurX/Y one step toward wProcCaveTargetX/Y: 70% along
; whichever axis has the larger remaining distance, 30% a random nudge on
; the other axis. Clamped to the 1-18 interior (never steps onto the
; boundary ring itself; the exact target cell is force-stamped separately).
; ============================================================
PCStep:
	ld a, [wBuffer + wProcCaveTargetX]
	ld b, a
	ld a, [wBuffer + wProcCaveCurX]
	ld c, a
	ld a, b
	sub c
	ld [wBuffer + wProcCaveDX], a
	ld a, [wBuffer + wProcCaveTargetY]
	ld b, a
	ld a, [wBuffer + wProcCaveCurY]
	ld c, a
	ld a, b
	sub c
	ld [wBuffer + wProcCaveDY], a

	ld a, [wBuffer + wProcCaveDX]
	call PCAbs
	ld b, a
	ld a, [wBuffer + wProcCaveDY]
	call PCAbs
	ld c, a
	ld a, b
	cp c
	jr c, .yDominant

.xDominant
	ld c, 10
	call Rangerandom
	cp 7
	jr nc, .wobbleY
	ld a, [wBuffer + wProcCaveDX]
	bit 7, a
	jr nz, .moveXDec
	jr .moveXInc

.yDominant
	ld c, 10
	call Rangerandom
	cp 7
	jr nc, .wobbleX
	ld a, [wBuffer + wProcCaveDY]
	bit 7, a
	jr nz, .moveYDec
	jr .moveYInc

.wobbleY
	ld c, 2
	call Rangerandom
	and a
	jr z, .moveYDec
	jr .moveYInc

.wobbleX
	ld c, 2
	call Rangerandom
	and a
	jr z, .moveXDec
	jr .moveXInc

; NOTE: these clamps use >=/<= checks (cp + ret nc/ret c), not exact-match
; (cp + ret z). The entrance is hardcoded on the boundary ring (Y=19), so a
; walk can legitimately START at 19 - one off from PC_SIZE-2's exact-match
; check, which only blocked incrementing FROM exactly 18, not from 19 or
; beyond. The wobble mechanic picks a direction independent of the target,
; so it could roll "increment Y" while still sitting at 19 and push to 20 -
; carving directly into the border-fill padding ring (block 46) and
; corrupting it, confirmed by an actual in-game crash when walking into the
; resulting hole. Exact-match clamps are only safe if the starting position
; is already known to be within range; >=/<= clamps are safe regardless.
.moveXInc
	ld a, [wBuffer + wProcCaveCurX]
	cp PC_SIZE - 2
	ret nc
	inc a
	ld [wBuffer + wProcCaveCurX], a
	ret
.moveXDec
	ld a, [wBuffer + wProcCaveCurX]
	cp 2
	ret c
	dec a
	ld [wBuffer + wProcCaveCurX], a
	ret
.moveYInc
	ld a, [wBuffer + wProcCaveCurY]
	cp PC_SIZE - 2
	ret nc
	inc a
	ld [wBuffer + wProcCaveCurY], a
	ret
.moveYDec
	ld a, [wBuffer + wProcCaveCurY]
	cp 2
	ret c
	dec a
	ld [wBuffer + wProcCaveCurY], a
	ret

; ============================================================
; PCBulge
; Carves one random orthogonal neighbor of the current cell, clamped to the
; 1-18 interior. Saves and restores wProcCaveCurX/Y around the write.
; ============================================================
PCBulge:
	ld a, [wBuffer + wProcCaveCurX]
	ld [wBuffer + wProcCaveDX], a
	ld a, [wBuffer + wProcCaveCurY]
	ld [wBuffer + wProcCaveDY], a

	; same >=/<= clamp fix as PCStep - exact-match (cp+jr z) checks are only
	; safe if the starting position is known in-range; the entrance starts
	; AT the boundary (Y=19), so this must tolerate an out-of-the-usual-
	; range starting value too, not just block the one exact value below it
	ld c, 4
	call Rangerandom
	and a
	jr nz, .notN
	ld a, [wBuffer + wProcCaveCurY]
	cp 2
	jr c, .skip
	dec a
	ld [wBuffer + wProcCaveCurY], a
	jr .doWrite
.notN
	cp 1
	jr nz, .notS
	ld a, [wBuffer + wProcCaveCurY]
	cp PC_SIZE - 2
	jr nc, .skip
	inc a
	ld [wBuffer + wProcCaveCurY], a
	jr .doWrite
.notS
	cp 2
	jr nz, .isW
	ld a, [wBuffer + wProcCaveCurX]
	cp PC_SIZE - 2
	jr nc, .skip
	inc a
	ld [wBuffer + wProcCaveCurX], a
	jr .doWrite
.isW
	ld a, [wBuffer + wProcCaveCurX]
	cp 2
	jr c, .skip
	dec a
	ld [wBuffer + wProcCaveCurX], a
.doWrite
	ld a, PC_BLOCK_FLOOR
	call PCWriteCell
.skip
	ld a, [wBuffer + wProcCaveDX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveDY]
	ld [wBuffer + wProcCaveCurY], a
	ret

; ============================================================================
; DRAFT SKETCHES, 2026-06-25/26 - NOT WIRED IN, NOT TESTED, NOT ACTIVE.
;
; Everything below is commented out and not called from anywhere. Priority
; order for implementing these (user's explicit order): exit warp ladder
; tile [IMPLEMENTED 2026-06-26, see PCPlaceExitLadder above] -> random
; items in dead-ends -> rivers -> floor decor -> copy/paste feature
; stamps. Pick up each one at a time, build+test before starting the
; next - that discipline is what got the autotiling system working after
; several rounds of "fixed it" that weren't.
; ============================================================================

; ----------------------------------------------------------------------
; DRAFT 2: random items in the 4 non-exit dead-ends
; [IMPLEMENTED 2026-06-26] - see the "wild area pokeball" block inside
; GenerateProceduralCave's target loop (.notExit branch, above), plus:
; - ram/wram.asm: wRogueItem2/3/4 (3 new dw's, consecutive after wRogueItem)
; - constants/toggle_constants.asm: TOGGLE_WILD_AREA_POKEBALL_1-4
; - custom_functions/random_stage_selection.asm: WildAreaStageMapTable /
;   IsWildAreaStageMap (deliberately SEPARATE from RogueStageMapTable /
;   IsRogueStageMap, to avoid colliding with Route1-style maps' existing
;   slot 6-10 usage - reward pokeballs / trade NPC)
; - engine/overworld/toggleable_objects.asm: IsObjectHidden extended for
;   slots 1-4 on wild-area maps
; - engine/events/pick_up_item.asm: RandomPickUpItem extended for slots 1-4
;   on wild-area maps (indexes wRogueItem/2/3/4 and the 4 toggle consts
;   arithmetically, not via branching - both are 4 consecutive
;   words/consts)
; - data/maps/objects/ProceduralCave1.asm: 4 placeholder object_events
;   (SPRITE_POKE_BALL), become sprite slots 1-4
; - scripts/ProceduralCave1.asm: EVENT_ENTER_ROOM-gated ShowObject reset
;   for all 4 (toggle flags are persistent WRAM state, need resetting to
;   visible on every fresh entry, same reasoning as Route1's RogueRefresh)
; Object position patching uses wSprite01StateData2MapY (and the 3 slots
; after it, 16 bytes apart - confirmed via .sym) - this table is the
; proven analogue to wWarpEntries for object_events specifically, traced
; this session (see [[redrogue-procedural-cave]]). No sub-tile remainder
; needed here (unlike the exit ladder) - that was specifically about
; satisfying the warp-tile-recognition check, irrelevant to plain
; object/NPC collision.

; ----------------------------------------------------------------------
; DRAFT 3: rivers [ACTIVATED 2026-06-26 for in-game testing, called at
; 100% instead of the eventual ~25% - see the call site comment above
; PCCarveRiver's call in GenerateProceduralCave]
; CHECKED, NOT GUESSED (2026-06-26): decoded block 118 directly from
; gfx/blocksets/cavern.bst - all 16 raw tiles are $14, uniformly. $14 is
; NOT in Cavern_Coll's passable set ({5,15,18,1a,20,21,22,2a,2d,30}, see
; data/tilesets/collision_tile_ids.asm). So 118 is CURRENTLY IMPASSABLE -
; the original "would function like a floor 1" assumption was wrong. This
; is a real design decision to make before activating this draft, not
; just an implementation detail:
;   (a) keep 118 impassable and treat rivers as a routing OBSTACLE (valid,
;       common Pokemon pattern - "you need Surf/another way around");
;   (b) find/author a different water-style block ID that IS in
;       Cavern_Coll, or add $14 to Cavern_Coll if that's acceptable
;       (global, affects EVERY map using Cavern, not just ours - check
;       whether anything else relies on $14 staying solid before doing
;       this).
; Sketch below assumes (a) (impassable obstacle) since it requires zero
; engine-side changes - swap to (b) by adding $14 to Cavern_Coll once a
; choice is made, no carving-logic change needed either way.
;
; Run AFTER the main 5-target carving + autotile + decoration are fully
; done (PCAutotilePass/PCDecorateLast don't know about 118 at all - 118
; isn't in PCIsConvertible's eligible set, so running rivers first would
; just get silently skipped by every later pass, which is actually fine
; and arguably the safer order: river tiles land on TOP of whatever
; autotiling decided, never the reverse).
;
; CONNECTIVITY GUARANTEE (the user's explicit concern - confirmed safe by
; construction, not just hoped): rivers run LAST, after the entrance,
; exit, and all 4 dead-end items' cells are already permanently real
; floor (1/36). The walk below NEVER overwrites a cell that reads as real
; floor at the moment it steps onto it - it just skips past, leaving that
; cell exactly as it was. Since every tile on every already-carved path
; (entrance to exit, entrance to each item) is real floor, and floor cells
; are categorically never touched by this pass, the floor-to-floor
; adjacency graph - which is ALL that "is there a path" depends on - is
; completely unchanged by adding a river anywhere. A river can run directly
; alongside a corridor, or cross it (effectively "tunnel under" that one
; tile, since the floor tile itself is skipped, not paved over) without
; ever being able to disconnect anything. This only fails if some LATER
; pass were added that runs AFTER rivers and overwrites floor cells with
; something river-blind - don't add such a pass without re-checking this.
;
; Rough shape: pick a random start edge point (reuse PCEdgePoint) and a
; random end edge point on a DIFFERENT edge (reuse PCOtherEdgesTable, same
; selection style as the main target loop), wobble-walk between them
; similar to PCCarveOne/PCStep but writing 118 instead of PC_BLOCK_FLOOR,
; and SKIP the write (move on without overwriting) whenever the current
; cell already reads as real floor (1/36) or the entrance (36 again, same
; check) - "doesn't interfere with paths," guaranteed per above. Needs its
; own visual-transition
; consideration too - does water need its own edge/corner kit where it
; meets plain fill, the way floor does via PCAutotilePass? Not researched -
; the sketch below just stamps plain 118 with no edge variants, which will
; likely look like a hard-edged rectangle/blob rather than a natural
; shoreline; revisit once the impassable-vs-passable decision above is
; made, since that affects whether a shoreline transition even matters
; gameplay-wise (purely cosmetic for an obstacle; matters more if walkable).
;
; ACTIVATED 2026-06-26 for in-game testing - called unconditionally from
; GenerateProceduralCave right now (100%) instead of the eventual ~25%
; chance, see the call site comment there.
;
; ============================================================
; PCNearClaimed
; INPUT: wProcCaveCurX/Y = cell to check (the cell itself is NOT checked -
; callers already handle that separately)
; OUTPUT: carry SET if any of the 4 orthogonal neighbors is "claimed" -
; anything other than still-plain-fill (25) or already-placed water
; (PC_BLOCK_WATER). This is deliberately NOT "is this real floor" - real
; floor's own edge tile (21/24/26/29 etc, placed by the main
; PCAutotilePass long before the river runs) is ALSO claimed, and so are
; rocks/decorations. Per the user's correction: a floor/rock area and a
; river each need their OWN edge tile, which means TWO full cells of
; separation from real floor, not one - one cell for the floor/rock's
; existing edge tile (already non-25, so automatically caught by this
; check), and a SECOND cell that's still plain fill at this point, so
; PCAutotileRiverEdges has a real, unclaimed cell left to convert into
; the river's own facing edge afterward. The old, narrower "real floor
; only" version of this check let water land directly against an
; existing floor-edge tile with zero cells of plain fill left for the
; river's own edge to be carved into - confirmed from a real screenshot
; of exactly this happening.
; Reuses DX/DY as save/restore scratch - safe here, PCCarveRiver's walk
; loop (this function's only caller) never needs DX/DY once walking starts.
; ============================================================
PCNearClaimed:
	ld a, [wBuffer + wProcCaveCurX]
	ld [wBuffer + wProcCaveDX], a
	ld a, [wBuffer + wProcCaveCurY]
	ld [wBuffer + wProcCaveDY], a

	; north
	dec a
	ld [wBuffer + wProcCaveCurY], a
	call PCReadCell
	call PCIsClaimedCarry
	jr c, .restore

	; south
	ld a, [wBuffer + wProcCaveDY]
	inc a
	ld [wBuffer + wProcCaveCurY], a
	ld a, [wBuffer + wProcCaveDX]
	ld [wBuffer + wProcCaveCurX], a
	call PCReadCell
	call PCIsClaimedCarry
	jr c, .restore

	; west
	ld a, [wBuffer + wProcCaveDY]
	ld [wBuffer + wProcCaveCurY], a
	ld a, [wBuffer + wProcCaveDX]
	dec a
	ld [wBuffer + wProcCaveCurX], a
	call PCReadCell
	call PCIsClaimedCarry
	jr c, .restore

	; east
	ld a, [wBuffer + wProcCaveDX]
	inc a
	ld [wBuffer + wProcCaveCurX], a
	call PCReadCell
	call PCIsClaimedCarry
.restore
	push af
	ld a, [wBuffer + wProcCaveDX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveDY]
	ld [wBuffer + wProcCaveCurY], a
	pop af
	ret

; INPUT: a = a cell's current block ID. OUTPUT: carry SET if it's
; "claimed" (anything other than plain fill 25 or PC_BLOCK_WATER).
PCIsClaimedCarry:
	cp 25
	jr z, .no
	cp PC_BLOCK_WATER
	jr z, .no
	scf
	ret
.no
	and a       ; clears carry
	ret

PCCarveRiver:
	; pick start point (any edge)
	ld c, 4
	call Rangerandom
	ld [wBuffer + wProcCaveEdge], a
	ld c, 18
	call Rangerandom
	inc a
	ld [wBuffer + wProcCaveOffset], a
	call PCEdgePoint
	ld a, [wBuffer + wProcCaveCurX]
	ld [wBuffer + wProcCaveDX], a   ; reuse DX/DY as start-point save slots
	ld a, [wBuffer + wProcCaveCurY]
	ld [wBuffer + wProcCaveDY], a

	; pick end point on one of the 3 OTHER edges (same table/pattern the
	; main target loop uses for entrance-vs-target edge selection)
	ld c, 3
	call Rangerandom
	ld b, a
	ld a, [wBuffer + wProcCaveEdge]
	ld c, a
	add a, a
	add a, c
	add a, b
	ld hl, PCOtherEdgesTable
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hl]
	ld [wBuffer + wProcCaveEdge], a
	ld c, 18
	call Rangerandom
	inc a
	ld [wBuffer + wProcCaveOffset], a
	call PCEdgePoint
	ld a, [wBuffer + wProcCaveCurX]
	ld [wBuffer + wProcCaveTargetX], a
	ld a, [wBuffer + wProcCaveCurY]
	ld [wBuffer + wProcCaveTargetY], a

	; restore start point into CurX/Y, walk toward TargetX/Y
	ld a, [wBuffer + wProcCaveDX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveDY]
	ld [wBuffer + wProcCaveCurY], a
	call PCManhattan
	ld b, a
	add a, b
	add a, b
	and a
	jr nz, .haveMax
	inc a
.haveMax
	ld [wBuffer + wProcCaveMaxSteps], a
.walkLoop
	call PCReadCell
	; die the moment this step would land on, or next to, anything already
	; claimed (real floor, an existing floor/rock edge tile, a decoration,
	; etc.) - not just real floor itself. See PCNearClaimed's header
	; comment for why this needs to be a full 2-cell buffer (one cell for
	; whatever's already there's own edge tile, one more left over, still
	; plain fill, for the river's own edge tile to be carved into
	; afterward) rather than just "don't touch real floor."
	call PCIsClaimedCarry
	jr c, .done               ; hit a real path/edge/rock/decoration - die
	call PCNearClaimed         ; here, permanently (used to skip past it and
	jr c, .done                ; keep wobbling, which could fragment the
	                            ; river into multiple disconnected blobs)
	ld a, PC_BLOCK_WATER
	call PCWriteCell
	ld a, [wBuffer + wProcCaveCurX]
	ld b, a
	ld a, [wBuffer + wProcCaveTargetX]
	cp b
	jr nz, .notAtTarget
	ld a, [wBuffer + wProcCaveCurY]
	ld b, a
	ld a, [wBuffer + wProcCaveTargetY]
	cp b
	jr z, .done
.notAtTarget
	ld a, [wBuffer + wProcCaveMaxSteps]
	and a
	jr z, .done
	dec a
	ld [wBuffer + wProcCaveMaxSteps], a
	call PCStep               ; same wobble-walk helper PCCarveOne uses
	jr .walkLoop
.done
	ret

; ============================================================
; PCAutotileRiverEdges
; Runs right after PCCarveRiver. Gives water (118) the SAME edge/corner
; treatment PCAutotilePass already gives floor, reusing the exact same
; ID convention (21/24/26/29 straight edges, 22/20/30/28 corners) - per
; the user's explicit instruction: "Rivers can use the exact same edges
; that the floors do." Only touches cells still reading as plain fill
; (25); an already-classified floor edge/corner that's ALSO water-
; adjacent on another side is left untouched in this version (no mixed
; floor+water corner upgrade yet - would need re-running something
; closer to the full PCAutotilePass rather than this scoped pass).
;
; Same two-phase anti-cascade structure as PCAutotilePass's Pass A/B,
; for the identical reason: a fill cell that becomes "peninsula floor"
; via 3+ water-adjacent sides must not be mistaken for genuine
; pre-existing floor by a neighbor scanned later in the SAME sweep.
; Toggles wProcCaveIncludeWater so PCIsFloorLike (used inside
; PCClassifyCell) treats water as floor-like for this pass only.
;
; Deliberately does NOT call PCVerifyCorner (unlike PCAutotilePass's
; Pass B) - that check validates corner legitimacy via
; PCCountFloorNeighbors, which hardcodes PC_BLOCK_FLOOR/PC_BLOCK_ENTRANCE
; directly (not PCIsFloorLike), so it's blind to water entirely and
; would reject every real water corner as a false "dead-end nub".
;
; Cost note: a second close-to-full 400-cell sweep (two sub-passes + a
; cleanup pass, no Pass C) - real added load time, see Red Rogue Files/
; procedural-cave-performance-plan.md. A cheaper, position-tracked
; version (only visiting actual water cells' neighbors, via a list built
; during PCCarveRiver's walk instead of rescanning the whole grid) was
; considered but doesn't fit in wBuffer's remaining free bytes for a
; river of unbounded length - revisit if this pass's cost matters.
; ============================================================
PCAutotileRiverEdges:
	ld a, 1
	ld [wBuffer + wProcCaveIncludeWater], a

	; --- Pass A': peninsula resolution only, plain fill (25) only ---
	xor a
	ld [wBuffer + wProcCaveLoopY], a
.aYLoop
	xor a
	ld [wBuffer + wProcCaveLoopX], a
.aXLoop
	ld a, [wBuffer + wProcCaveLoopX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveLoopY]
	ld [wBuffer + wProcCaveCurY], a

	call PCReadCell
	cp 25
	jr nz, .aSkipCell
	call PCClassifyCell
	jr nc, .aSkipCell
	cp PC_BLOCK_PENDING_FLOOR
	jr nz, .aSkipCell           ; an edge/corner result - leave it for Pass B'
	call PCWriteCell
.aSkipCell
	ld a, [wBuffer + wProcCaveLoopX]
	inc a
	ld [wBuffer + wProcCaveLoopX], a
	cp PC_SIZE
	jr nz, .aXLoop
	ld a, [wBuffer + wProcCaveLoopY]
	inc a
	ld [wBuffer + wProcCaveLoopY], a
	cp PC_SIZE
	jr nz, .aYLoop

	; cleanup: convert this pass's own pending-floor sentinels to real
	; floor now that Pass A's own sweep is fully finished
	xor a
	ld [wBuffer + wProcCaveLoopY], a
.cleanYLoop
	xor a
	ld [wBuffer + wProcCaveLoopX], a
.cleanXLoop
	ld a, [wBuffer + wProcCaveLoopX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveLoopY]
	ld [wBuffer + wProcCaveCurY], a
	call PCReadCell
	cp PC_BLOCK_PENDING_FLOOR
	jr nz, .cleanSkip
	ld a, PC_BLOCK_FLOOR
	call PCWriteCell
.cleanSkip
	ld a, [wBuffer + wProcCaveLoopX]
	inc a
	ld [wBuffer + wProcCaveLoopX], a
	cp PC_SIZE
	jr nz, .cleanXLoop
	ld a, [wBuffer + wProcCaveLoopY]
	inc a
	ld [wBuffer + wProcCaveLoopY], a
	cp PC_SIZE
	jr nz, .cleanYLoop

	; --- Pass B': edge/corner classification, layout now fully fixed ---
	xor a
	ld [wBuffer + wProcCaveLoopY], a
.bYLoop
	xor a
	ld [wBuffer + wProcCaveLoopX], a
.bXLoop
	ld a, [wBuffer + wProcCaveLoopX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveLoopY]
	ld [wBuffer + wProcCaveCurY], a

	call PCReadCell
	cp 25
	jr nz, .bSkipCell
	call PCClassifyCell
	jr nc, .bSkipCell
	cp PC_BLOCK_PENDING_FLOOR
	jr nz, .bHaveValue
	ld a, PC_BLOCK_FLOOR        ; shouldn't fire - Pass A' already resolved
.bHaveValue                     ; every real peninsula case
	call PCWriteCell
.bSkipCell
	ld a, [wBuffer + wProcCaveLoopX]
	inc a
	ld [wBuffer + wProcCaveLoopX], a
	cp PC_SIZE
	jr nz, .bXLoop
	ld a, [wBuffer + wProcCaveLoopY]
	inc a
	ld [wBuffer + wProcCaveLoopY], a
	cp PC_SIZE
	jr nz, .bYLoop

	xor a
	ld [wBuffer + wProcCaveIncludeWater], a
	ret

; ----------------------------------------------------------------------
; DRAFT 4: floor decor (12-19) [IMPLEMENTED 2026-06-26, see
; PCSprinkleFloorDecor above]. Resolved the open question below by direct
; .bst decode: 12-19 are NOT fully passable (12/16 raw tiles pass, one
; corner is a 2x2 wall decal). Originally limited to one decal,
; "accepting a small risk" of it walling off a forced corridor - later
; proven (not just estimated) that this can't actually happen at all,
; given every PC-block is 2 tiles wide and a single decal only ever
; blocks one of 4 sub-tile quadrants, never a full side - see
; PCSprinkleFloorDecor's header comment for the full reasoning. No
; per-cell connectivity check needed at any decal count.

; ----------------------------------------------------------------------
; DRAFT 5: copy/paste feature stamps (e.g. pools)
; User's plan: hand-author small .bin block-grids (not extracted from
; existing ROM maps), then randomly stamp one into a procedurally
; "acceptable" spot. Most open-ended item on the list, lowest priority,
; deliberately not sketched in code yet - needs a design conversation
; first: how is a stamp's size/shape declared (fixed NxM, or with its own
; embedded width/height header), how is an "acceptable spot" defined
; (probably: an NxM block of cells that are ALL still plain 25 - reuses
; the same "still untouched fill" guarantee PCDecorateLast already relies
; on), and how does the stamp get loaded into ROM (INCBIN per stamp file,
; with a lookup table of pointers + dimensions). Come back to this only
; after drafts 1-4 are real and tested.
	ret
