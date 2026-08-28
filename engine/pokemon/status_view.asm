; Yume-style START cycling, without changing Red Rogue's mon/page ownership.
; View state lives on the stack while waiting, not in save-backed menu RAM.
; The unused English-font slots $c0-$cd do not overlap either mon picture.
DEF STATUS_EXP_TILE EQU $c0
DEF STATUS_START_TILE EQU STATUS_EXP_TILE + 11

StatusScreenInitView:
	ld de, StatusViewGraphics
	ld hl, vChars1 tile (STATUS_EXP_TILE - $80)
	lb bc, BANK(StatusViewGraphics), 14
	call CopyVideoData
	ld e, STATS_BOX_NORMAL
	jp StatusScreenDrawView

StatusScreenWaitView:
	ld e, STATS_BOX_NORMAL
.wait
	push de
	call DelayFrame
	call Joypad
	pop de
	ldh a, [hJoyPressed]
	and PAD_A | PAD_B
	ret nz ; retain the caller's existing move-page behavior
	ldh a, [hJoyPressed]
	bit B_PAD_START, a
	jr z, .wait
	; Existing enum is NORMAL=0, STAT_EXP=1, DVS=2.
	dec e
	ld a, e
	cp $ff
	jr nz, .draw
	ld e, STATS_BOX_DVS
.draw
	push de
	call StatusScreenDrawView
	pop de
	jr .wait

StatusScreenDrawView:
	push de
	lb de, STATUS_SCREEN_STATS_BOX, STATS_BOX_NORMAL
	farcall PrintStatsBox
	; Restore the actual HP fraction when returning from either alternate view.
	hlcoord 12, 4
	ld de, wLoadedMonHP
	lb bc, 2, 3
	call PrintNumber
	ld a, '/'
	ld [hli], a
	ld de, wLoadedMonMaxHP
	lb bc, 2, 3
	call PrintNumber
	pop de
	push de
	ld a, e
	and a
	jr z, .rendered
	push af
	call StatusViewClearNumbers
	pop af
	cp STATS_BOX_DVS
	jr nz, .bars
	call StatusViewDVs
	jr .rendered
.bars
	call StatusViewStatExp
.rendered
	pop de
	ld a, e
	ld de, .Stats
	and a
	jr z, .label
	ld de, .StatExp
	dec a
	jr z, .label
	ld de, .DVs
.label
	hlcoord 1, 8
	call PlaceString
	hlcoord 13, 8
	ld a, STATUS_START_TILE
	ld [hli], a
	inc a
	ld [hli], a
	inc a
	ld [hl], a
	ret
.Stats
	db "STATS@"
.DVs
	db "DVs@"
.StatExp
	db "STAT.EXP@"

; Yume's direct DV presentation and HP-derived DV. Keep Red Rogue's full
; stat labels and print directly, avoiding the PrintNumber/HRAM alias trap.
StatusViewDVs:
	hlcoord 7, 10
	ld a, [wLoadedMonDVs]
	swap a
	call StatusViewPrintDV
	ld a, [wLoadedMonDVs]
	call StatusViewPrintDV
	ld a, [wLoadedMonDVs + 1]
	swap a
	call StatusViewPrintDV
	ld a, [wLoadedMonDVs + 1]
	call StatusViewPrintDV
	ld hl, wLoadedMonDVs
	ld e, 0
	ld a, [hl]
	swap a
	rrca
	rl e
	ld a, [hli]
	rrca
	rl e
	ld a, [hl]
	swap a
	rrca
	rl e
	ld a, [hl]
	rrca
	rl e
	ld a, e
	hlcoord 17, 4
	; fallthrough
StatusViewPrintDV:
	and $f
	ld b, ' '
	cp 10
	jr c, .ones
	sub 10
	ld b, '1'
.ones
	add '0'
	ld [hl], b
	inc hl
	ld [hl], a
	ld de, SCREEN_WIDTH * 2 - 1
	add hl, de
	ret

StatusViewClearNumbers:
	hlcoord 12, 4
	lb bc, 1, 7
	call ClearScreenArea
	hlcoord 3, 10
	ld b, 4
.row
	push bc
	push hl
	lb bc, 1, 6
	call ClearScreenArea
	pop hl
	ld de, SCREEN_WIDTH * 2
	add hl, de
	pop bc
	dec b
	jr nz, .row
	ret

StatusViewStatExp:
	hlcoord 12, 4
	ld de, wLoadedMonHPExp + 1
	call StatusViewPrintBar
	hlcoord 3, 10
	ld de, wLoadedMonAttackExp + 1
	call StatusViewPrintBar
	ld de, wLoadedMonDefenseExp + 1
	call StatusViewPrintBar
	ld de, wLoadedMonSpeedExp + 1
	call StatusViewPrintBar
	ld de, wLoadedMonSpecialExp + 1
	; fallthrough

; Pinned Yume 35d3bf9 PrintStatBar, remapped from $31-$3b to $c0-$ca.
; Raw stat experience is shown on a 32-pixel scale. Only $ffff is full.
; de = low byte of big-endian stat experience; hl = six-tile destination.
StatusViewPrintBar:
	ld c, 0
	ld a, [de]
	inc a
	dec de
	ld a, [de]
	jr nz, .notFull
	cp $ff
	jr nz, .notFull
	inc c
.notFull
	srl a
	srl a
	srl a
	add c
	ld b, 4
	ld c, a
	ld a, STATUS_EXP_TILE
	ld [hli], a
.fullTile
	ld a, c
	sub 8
	jr c, .partial
	ld c, a
	ld a, STATUS_EXP_TILE + 9
	ld [hli], a
	dec b
	jr nz, .fullTile
	jr .finish
.partial
	add 8 + STATUS_EXP_TILE + 1
	ld [hli], a
	dec b
	jr z, .finish
	ld a, STATUS_EXP_TILE + 1
.empty
	ld [hli], a
	dec b
	jr nz, .empty
.finish
	ld a, STATUS_EXP_TILE + 10
	ld [hl], a
	ld de, SCREEN_WIDTH * 2 - 5
	add hl, de
	ret

StatusViewGraphics:
	INCBIN "gfx/status_screen/stat_exp_bar.2bpp"
	; Yume status tiles $6e-$78: the final three are its START badge.
	INCBIN "gfx/status_screen/status_screen.2bpp", 8 * TILE_SIZE, 3 * TILE_SIZE
StatusViewGraphicsEnd:
	ASSERT StatusViewGraphicsEnd - StatusViewGraphics == 14 * TILE_SIZE

; ============================================================================
; Status Screen page 2 sub-views (Learndex, LEARNDEX_DESIGN.md D-1).
;
; Same START-cycling idiom as StatusScreenWaitView/StatusScreenDrawView
; above, reused rather than a second navigation concept. Two differences from
; page 1's version, both deliberate:
;   - A and B are NOT tested together. B always exits; A exits only on
;     MOVES_BOX_CURRENT and otherwise calls StatusScreen2SelectHook, a bare
;     ret stub until D-5 (a possible per-move detail page) is approved. This
;     keeps a future D-5 a pure addition - replace the one stub - instead of
;     a rewrite of this loop.
;   - UP/DOWN is wired to StatusScreen2MoveCursor, also a bare ret stub until
;     D-2 gives the list views something to scroll.
; View index and cursor position live in de across the wait, not in WRAM -
; same rule status_view.asm's own header comment states for page 1.
; ============================================================================

; Input: de = (d=cursor, e=view). Output: d = updated cursor, clamped to the
; current view's entry count; de otherwise valid for the caller's next loop
; iteration exactly as on entry. Also REDRAWS whatever needs it, so the
; caller (StatusScreen2WaitView) does not call StatusScreen2DrawContent
; itself afterward - see below for why. No-op for views without a cursor yet
; (CURRENT, TMHM, TUTOR - D-3/D-4 add theirs the same way).
;
; If the move does not cross a scroll boundary (the common case - most
; single presses stay within the current 8-row window), only the two
; affected rows' cursor-glyph tiles are flipped, instead of asking for a
; full 8-row content redraw. That distinction is why this function draws at
; all rather than just returning the new cursor: a full redraw on every
; keypress is what was still flickering after StatusScreen2DrawView vs
; StatusScreen2DrawContent was split - the box's rows 9-16 straddle the
; game's own VBlank tile-transfer boundary (AutoBgMapTransfer flushes the
; screen in horizontal thirds, one third per frame - home/vcopy.asm), so
; rewriting all 8 rows on every single press regularly puts half the box on
; one frame and half on the next, and whichever entries happen to land near
; that row-11/row-12 seam during a given scroll position visibly flicker.
; Most presses do not need those 6 unchanged rows touched at all.
; Clobbers af, bc, hl.
StatusScreen2MoveCursor:
	ld a, e
	cp MOVES_BOX_LEVELUP
	ret nz ; only LEVELUP has a cursor so far

	; LearndexPrepareLevelUpWalk calls LearndexLoadRecord, which sets
	; de = wMoveBuffer as part of its own FarCopyData plumbing - de MUST be
	; saved/restored around this, or d (the cursor) is garbage. This was the
	; original crash: MoveCursor read a garbage d, wrote a garbage cursor
	; back, and StatusScreen2DrawView used the garbage e (view) riding along
	; with it to index its own 4-entry jump table out of bounds.
	push de
	call LearndexPrepareLevelUpWalk  ; hl = learnset block start (unused
	                                  ; below, but this leaves wMonHeader
	                                  ; correct for the species count next)
	call LearndexCountLevelUpEntries ; b = N
	pop de

	ld a, d
	call LearndexComputeWindowTop ; a = window_top before the move; N (b)
	ld c, a                        ; is preserved. c = window_top (before).

	push de ; stack: (old cursor, view) - only needed below if the window
	        ; does not end up scrolling; rebalanced on every path out
	ldh a, [hJoyPressed]
	and PAD_UP | PAD_DOWN
	bit B_PAD_UP, a
	jr z, .checkDown
	ld a, d
	and a
	jr z, .noMove ; already at the top
	dec d
	jr .moved
.checkDown
	ld a, d
	inc a
	cp b
	jr nc, .noMove ; already at (or past) the last entry
	ld d, a
.moved
	ld a, d
	call LearndexComputeWindowTop ; a = window_top after the move; b and c
	cp c                           ; (the "before" value) are both preserved
	jr nz, .scrolled

	; Window unchanged: flip just the two rows whose cursor glyph changed.
	; Both row offsets are computed BEFORE either StatusScreen2SetCursorGlyph
	; call below: that call clobbers de (LearndexRowAddress uses it), and d
	; is where the new cursor lives, so reading it AFTER the first call would
	; read garbage - exactly the same bug class as the original crash.
	pop hl ; h = old cursor, l = old view (unused)
	ld a, h
	sub c ; a = old cursor's row offset within the (unchanged) window
	push af ; stash the old row offset
	ld a, d
	sub c ; a = new cursor's row offset
	ld b, a ; stash the new row offset in b (safe - not touched by the
	        ; de-clobbering calls below, and N/b is not needed again)
	pop af ; a = old row offset again; stack now balanced

	; The actual crash: both calls below clobber de (LearndexRowAddress
	; leaves it pointing at .RowAddresses), and this function used to just
	; `ret` straight after, handing the caller garbage instead of
	; (new cursor, view). The caller's loop carries de forward as its own
	; state, so the corrupted e (view) fed MOVES_BOX_LEVELUP's next START
	; press's +1/wrap arithmetic, and the garbage result indexed
	; StatusScreen2DrawView's 4-entry jump table wildly out of bounds - that
	; read two essentially random bytes as a jump address. Preserve de
	; across both calls and restore it before returning, same as .scrolled
	; already does below.
	push de
	push bc ; preserve the new row offset (in b) across this call
	ld b, ' '
	call StatusScreen2SetCursorGlyph ; blank the old row's glyph
	pop bc ; b = new row offset again

	ld a, b
	ld b, '▷' ; same cursor glyph as extra_options.asm ($ec)
	call StatusScreen2SetCursorGlyph ; set the new row's glyph
	pop de ; restore (new cursor, view) for the caller
	ret
.scrolled
	pop hl ; discard the stashed old cursor - unneeded here, just
	       ; rebalancing the push before the move
	push de ; preserve (new cursor, view) across StatusScreen2DrawContent,
	        ; which clobbers de the same way everything else here does
	call StatusScreen2DrawContent
	pop de
	ret
.noMove
	pop hl ; rebalance the push before the move; d/e are already correct,
	       ; untouched since neither branch above ran
	ret

; Input: de = (d=cursor, e=view). Stub until D-5; A currently does nothing on
; any non-CURRENT view.
StatusScreen2SelectHook:
	ret

StatusScreen2WaitView:
	ld d, 0
	ld e, MOVES_BOX_CURRENT
.wait
	push de
	call DelayFrame
	call Joypad
	pop de
	ldh a, [hJoyPressed]
	bit B_PAD_B, a
	ret nz ; B always exits, from every view
	bit B_PAD_A, a
	jr z, .checkStart
	ld a, e
	cp MOVES_BOX_CURRENT
	ret z ; A exits only on the default view, until D-5 changes this
	push de
	call StatusScreen2SelectHook
	pop de
	jr .wait
.checkStart
	ldh a, [hJoyPressed]
	bit B_PAD_START, a
	jr z, .checkUpDown
	ld a, e
	inc a
	cp NUM_MOVES_BOX_VIEWS
	jr nz, .gotNextView
	xor a
.gotNextView
	ld e, a
	ld d, 0 ; each view starts unscrolled, cursor on its first entry
	push de
	call StatusScreen2DrawView
	pop de
	jr .wait
.checkUpDown
	ldh a, [hJoyPressed]
	and PAD_UP | PAD_DOWN
	jr z, .wait
	call StatusScreen2MoveCursor ; a = direction, de = (cursor,view); updates
	                              ; d AND redraws whatever actually needs it
	                              ; itself - see its own comment for why a
	                              ; blanket redraw here on every press is
	                              ; exactly what used to still flicker
	jr .wait

; Full draw: border (which also blanks the interior) + content + view label
; + START badge on row 8. Used on a view switch (START) and page 2's initial
; entry, where the interior's PREVIOUS content is a genuinely different view
; (or nothing yet) and the label needs to change too.
;
; Do NOT call this for a same-view cursor move (UP/DOWN) - StatusScreen2Wait-
; View doesn't, and STOP if you're tempted to add it there. Every visible row
; that isn't changing gets blanked and redrawn regardless, which flickers on
; every single keypress; measured and confirmed against the real thing before
; StatusScreen2DrawContent below was split out. Cursor moves go through
; StatusScreen2DrawContent instead, which touches only the rows that actually
; have new content.
; Input: e = MOVES_BOX_*. Clobbers everything - callers that need their own
; de preserved must push/pop it themselves, exactly as StatusScreen2WaitView
; does above.
StatusScreen2DrawView:
	push de
	hlcoord 0, 8
	ld b, 8
	ld c, 18
	call TextBoxBorder
	pop de

	push de
	call StatusScreen2DrawContent
	pop de

	ld a, e
	add a
	ld c, a
	ld b, 0
	ld hl, .LabelPointers
	add hl, bc
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld d, h
	ld e, l
	hlcoord 2, 8
	call PlaceString
	hlcoord 15, 8
	ld a, STATUS_START_TILE
	ld [hli], a
	inc a
	ld [hli], a
	inc a
	ld [hl], a
	ret

.LabelPointers
	dw .CurrentLabel
	dw .LevelUpLabel
	dw .TMHMLabel
	dw .TutorLabel
.CurrentLabel
	db "MOVES@"
.LevelUpLabel
	db "LEVEL UP@"
.TMHMLabel
	db "TM/HM@"
.TutorLabel
	db "TUTOR@"

; Content-only redraw for the given sub-view: no border, no label/badge -
; both are already correct on screen from the last full draw. The content
; renderer itself (StatusScreen2DrawLevelUp -> .RenderEntryIfVisible for
; LEVELUP) is responsible for clearing whatever it's about to overwrite, one
; row at a time, since there is no blanket border-blank here to fall back on.
; Input: e = MOVES_BOX_*. Clobbers everything.
StatusScreen2DrawContent:
	ld a, e
	add a
	ld c, a
	ld b, 0
	ld hl, .ContentPointers
	add hl, bc
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld bc, .contentDone
	push bc
	jp hl
.contentDone
	ret

.ContentPointers
	dw .DrawCurrent
	dw StatusScreen2DrawLevelUp ; D-2 - ends in ret, needs no wrapper stub
	dw .DrawTMHM
	dw .DrawTutor
.DrawCurrent
	farcall StatusScreen2DrawMovesBoxCurrent
	ret
.DrawTMHM
	ret ; MOVES_BOX_TMHM content - D-3
.DrawTutor
	ret ; MOVES_BOX_TUTOR content - D-4

; ============================================================================
; MOVES_BOX_LEVELUP (LEARNDEX_DESIGN.md D-2): the mon's level-up learnset,
; plus the 4 level-1 moves from wMonHMoves that evos_moves.asm never lists
; explicitly (mirrors the merge PrepareRelearnableMoveList does at
; evos_moves.asm:641-717, but WITHOUT its known-move filtering/deduplication -
; a dex view must show the raw learnset regardless of what the mon already
; knows).
;
; Deliberately reads only the PRIMARY species (wMonHIndex), no fusion merge:
; the real level-up-learning code, LearnMoveFromLevelUp
; (engine/pokemon/evos_moves.asm), only ever reads [wPokedexNum] itself with
; no second-species merge, so a fusion mon's ACTUAL future learnset is the
; primary species' alone - showing anything else here would show the player
; something that will never happen. Same reasoning applies to D-4 (tutor
; moves): PrepareMoveTutorList is equally primary-only.
; ============================================================================

DEF LEARNDEX_RECORD_SIZE  EQU 64 ; bytes copied per LearndexLoadRecord call;
                                  ; measured worst-case real record is 47
                                  ; bytes (PikachuEvosMoves) - see
                                  ; LEARNDEX_DESIGN.md SS3.1
DEF LEARNDEX_MAX_ENTRIES  EQU 30 ; defensive walk cap, NOT a real limit -
                                  ; measured worst-case real learnset is 11
                                  ; entries (VaporeonEvosMoves); this only
                                  ; guards a corrupted/malformed record from
                                  ; ever running the walk off into the weeds
DEF LEARNDEX_VISIBLE_ROWS EQU 8

; Input: a = cursor, b = N (total entry count).
; Output: a = window_top = clamp(cursor - 7, 0, max(0, N - 8)).
; Preserves b, c, d, e, hl.
LearndexComputeWindowTop:
	push bc
	sub LEARNDEX_VISIBLE_ROWS - 1
	jr nc, .gotCandidate
	xor a
.gotCandidate
	ld c, a ; c = candidate = max(0, cursor - 7)
	ld a, b
	sub LEARNDEX_VISIBLE_ROWS
	jr nc, .gotMax
	xor a
.gotMax
	; a = max(0, N - 8)
	cp c
	jr c, .done ; max_allowed < candidate: a already holds the clamped result
	ld a, c ; candidate <= max_allowed: use candidate as-is
.done
	pop bc
	ret

; Input: a = row offset (0-7) within the moves box's 8 visible rows.
; Output: hl = that row's tilemap address, column 1.
; Clobbers af, de.
LearndexRowAddress:
	add a
	ld l, a
	ld h, 0
	ld de, .RowAddresses
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ret
.RowAddresses
	dwcoord 1, 9
	dwcoord 1, 10
	dwcoord 1, 11
	dwcoord 1, 12
	dwcoord 1, 13
	dwcoord 1, 14
	dwcoord 1, 15
	dwcoord 1, 16

; Input: a = row offset (0-7), b = glyph char (' ' or the cursor glyph).
; Writes just that one tile - used by StatusScreen2MoveCursor to flip the
; cursor between two rows without a full content redraw when the visible
; window did not need to scroll (see its own comment for why that matters).
; Clobbers af, hl.
StatusScreen2SetCursorGlyph:
	call LearndexRowAddress
	ld a, b
	ld [hl], a
	ret

; Copies the current species' evos_moves record into wMoveBuffer.
; Input: wCurSpecies = internal species index.
; Output: wMoveBuffer.. = a raw copy of the record (evolutions, then
; learnset, then tutor - whichever blocks the species has). Callers walk past
; whichever leading blocks they do not need themselves.
; Clobbers af, bc, de, hl.
LearndexLoadRecord:
	ld a, [wCurSpecies]
	dec a
	ld c, a
	ld b, 0
	ld hl, EvosMovesPointerTable
	add hl, bc
	add hl, bc
	ld de, wMoveBuffer  ; stage the 2-byte pointer here; overwritten by the
	ld bc, 2            ; record copy below before anything reads it as data
	ld a, BANK(EvosMovesPointerTable)
	call FarCopyData
	ld a, [wMoveBuffer]
	ld l, a
	ld a, [wMoveBuffer + 1]
	ld h, a
	ld de, wMoveBuffer
	ld bc, LEARNDEX_RECORD_SIZE
	ld a, BANK(EvosMovesPointerTable)
	call FarCopyData
	ret

; Sets up wCurSpecies/wMonHeader for the mon shown on the status screen (from
; wMonHIndex, not wCurSpecies - fusion sprite loading may leave wCurSpecies on
; a transient value, but wMonHIndex is documented as left on the primary at
; status_screen.asm:206-210) and loads its evos_moves record, positioning hl
; on the learnset block (past the evolutions block, which every species has
; even if it never evolves - a single db 0).
; Output: hl = wMoveBuffer's learnset block start.
; Clobbers af, bc, de, hl.
LearndexPrepareLevelUpWalk:
	ld a, [wMonHIndex]
	ld [wCurSpecies], a
	call GetMonHeader ; populates wMonHeader (incl. wMonHMoves) fresh, rather
	                  ; than trusting whatever state page 1 left it in
	call LearndexLoadRecord
	ld hl, wMoveBuffer
.skipEvo
	ld a, [hli]
	and a
	jr nz, .skipEvo
	ret

; Input: hl = wMoveBuffer's learnset block start (from
; LearndexPrepareLevelUpWalk). wMonHMoves must already be valid (same call).
; Output: b = total entry count (learnset pairs + up to 4 nonzero
; wMonHMoves), capped defensively at LEARNDEX_MAX_ENTRIES.
; Clobbers af, hl.
LearndexCountLevelUpEntries:
	ld b, 0
.learnsetLoop
	ld a, [hl]
	and a
	jr z, .learnsetDone
	inc hl
	inc hl
	inc b
	ld a, b
	cp LEARNDEX_MAX_ENTRIES
	jr c, .learnsetLoop
.learnsetDone
	ld hl, wMonHMoves
	ld c, 0
.hMovesLoop
	ld a, c
	cp 4
	jr nc, .done
	ld a, [hli]
	and a
	jr z, .done
	inc b
	inc c
	jr .hMovesLoop
.done
	ret

; MOVES_BOX_LEVELUP content renderer, called from StatusScreen2DrawView's
; jump table with e = MOVES_BOX_LEVELUP and d = the cursor position
; (StatusScreen2WaitView's de, untouched since it was pushed before the
; jump-table dispatch - see StatusScreen2DrawView above).
StatusScreen2DrawLevelUp:
	; LearndexPrepareLevelUpWalk -> LearndexLoadRecord sets de = wMoveBuffer
	; as part of its own FarCopyData plumbing, so de (cursor, window_top-to-
	; be) must be saved/restored around it - see the matching note in
	; StatusScreen2MoveCursor above, which had the same bug.
	push de
	call LearndexPrepareLevelUpWalk  ; hl = learnset block start
	pop de
	push hl
	call LearndexCountLevelUpEntries ; b = N
	pop hl

	ld a, d
	call LearndexComputeWindowTop ; a = window_top; b (N) preserved
	ld e, a ; e = window_top. d is untouched and still holds the cursor.

	ld c, 0 ; c = running absolute index
.learnsetRenderLoop
	ld a, [hl]
	and a
	jr z, .learnsetRenderDone
	ld a, c
	cp LEARNDEX_MAX_ENTRIES
	jr nc, .learnsetRenderDone
	ld a, [hl]
	ld b, a ; b = level
	inc hl
	ld a, [hl] ; a = move id
	inc hl
	push hl
	call .RenderEntryIfVisible
	pop hl
	inc c
	jr .learnsetRenderLoop
.learnsetRenderDone
	ld hl, wMonHMoves
.hMovesRenderLoop
	ld a, h
	cp HIGH(wMonHMoves + 4)
	jr nz, .hMovesCheckSlot
	ld a, l
	cp LOW(wMonHMoves + 4)
	jr z, .hMovesRenderDone
.hMovesCheckSlot
	ld a, [hl]
	and a
	jr z, .hMovesRenderDone
	ld b, 1 ; level 1
	push hl
	call .RenderEntryIfVisible ; a still = move id loaded above
	pop hl
	inc hl
	inc c
	jr .hMovesRenderLoop
.hMovesRenderDone
	ret

; Input: b = level, a = move id, c = absolute index, e = window_top,
; d = cursor. Prints the row (cursor glyph, <LV> tile, 2-digit level, move
; name) if c falls in [e, e+7]; no-op otherwise. Preserves b, c, d, e.
; Clobbers af, hl.
.RenderEntryIfVisible:
	push bc
	push de
	; wNamedObjectIndex and wTempByteValue are stacked labels for the SAME
	; byte (ram/wram.asm:1687-88) - staging the move id there now and the
	; level into wTempByteValue two lines below would let the level
	; overwrite the move id before GetMoveName ever reads it (confirmed:
	; this was silently turning "learned move" into "move #<level>", e.g.
	; level 25 printed as move 25's name, MEGA KICK, instead of whatever the
	; level-25 move actually was). Stash the move id in wMoveNum (a separate,
	; unaliased byte) instead, and copy it into wNamedObjectIndex only right
	; before GetMoveName runs, after PrintNumber has already consumed the
	; level from the shared byte.
	ld [wMoveNum], a
	ld a, b
	ld [wTempByteValue], a ; stage the level; b is free to reuse below

	ld a, c
	sub e
	jr c, .done ; c < window_top
	cp LEARNDEX_VISIBLE_ROWS
	jr nc, .done ; c >= window_top + 8
	; a = row offset 0-7

	; Decide the cursor glyph now, while d still holds the real cursor - the
	; row-address lookup below overwrites de, so this must happen first.
	push af
	ld a, c
	cp d
	ld b, ' '
	jr nz, .noCursorHere
	ld b, '▷' ; same cursor glyph as extra_options.asm ($ec)
.noCursorHere
	pop af

	call LearndexRowAddress ; hl = this row's tilemap address, column 1

	; Blank this one row before writing it. StatusScreen2DrawContent (used
	; for a same-view cursor move, see StatusScreen2DrawView's comment) does
	; not blank via a border redraw the way the full draw does, so a shorter
	; new move name would otherwise leave trailing characters behind from
	; whatever was here before.
	push bc ; b = the cursor glyph decided above, must survive this call
	push hl
	lb bc, 1, 18
	call ClearScreenArea
	pop hl
	pop bc

	ld a, b ; the glyph decided above
	ld [hli], a ; column 1
	ld a, '<LV>'
	ld [hli], a ; column 2

	ld de, wTempByteValue
	lb bc, LEADING_ZEROES | 1, 2
	call PrintNumber ; columns 3-4
	ld a, ' '
	ld [hli], a ; column 5

	ld a, [wMoveNum] ; retrieve the move id stashed above - now safe to
	ld [wNamedObjectIndex], a ; write, wTempByteValue's job is done
	call GetMoveName ; de = wNameBuffer, preserves hl
	call PlaceString ; columns 6.. up to 12 chars, '@'-terminated

.done
	pop de
	pop bc
	ret
