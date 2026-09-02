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
; itself afterward - see below for why. No-op for MOVES_BOX_CURRENT, the only
; view without a cursor (it is not a scrollable list).
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
	jr z, .hasCursor
	cp MOVES_BOX_TMHM
	jr z, .hasCursor
	cp MOVES_BOX_TUTOR
	ret nz ; CURRENT has no cursor
.hasCursor
	; LearndexCountEntriesForView's LEVELUP path calls LearndexLoadRecord,
	; which sets de = wMoveBuffer as part of its own FarCopyData plumbing -
	; de MUST be saved/restored around this, or d (the cursor) is garbage.
	; This was the original crash: MoveCursor read a garbage d, wrote a
	; garbage cursor back, and StatusScreen2DrawView used the garbage e
	; (view) riding along with it to index its own 4-entry jump table out
	; of bounds.
	push de
	call LearndexCountEntriesForView ; b = N (dispatches on e itself)
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
	push af ; stash the new row offset before b is overwritten below
	ld b, '▷' ; same cursor glyph as extra_options.asm ($ec)
	call StatusScreen2SetCursorGlyph ; set the new row's glyph

	; D-5 live info strip: the window did not scroll, so the per-row move
	; id cache from the last full render (StatusScreen2DrawLevelUp/TMHM/
	; Tutor's own tail - see their shared comment) is still accurate for
	; every visible row, including this one - no need to re-walk the record
	; just to find "what's under the new cursor."
	pop af ; a = new row offset
	ld l, a
	ld h, 0
	ld a, l
	add LOW(wMoveBuffer + LEARNDEX_RECORD_SIZE)
	ld l, a
	ld a, h
	adc HIGH(wMoveBuffer + LEARNDEX_RECORD_SIZE)
	ld h, a
	ld a, [hl]
	call LearndexDrawInfoStrip

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
	dw StatusScreen2DrawTMHM    ; D-3 - ditto
	dw StatusScreen2DrawTutor   ; D-4 - ditto
.DrawCurrent
	farcall StatusScreen2DrawMovesBoxCurrent
	ret

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
DEF LEARNDEX_VISIBLE_ROWS EQU 7 ; row 16 (the 8th interior row) is the D-5
                                  ; live info strip, not a list row - see
                                  ; LearndexDrawInfoStrip below

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

; D-5 option B: a live info strip on row 16 (the row LEARNDEX_VISIBLE_ROWS'
; shrink to 7 reclaimed from the list), answering "is this move any good"
; for whatever the cursor is on - TYPE, POWER, and ACCURACY, the same fields
; engine/battle/move_info.asm shows in battle, but for a move the mon does
; not know yet (which move_info.asm never has to handle).
; Input: a = move id (0 = no move selected - e.g. an empty list; blanks the
; strip and returns).
; Clobbers af, bc, de, hl.
LearndexDrawInfoStrip:
	push af
	hlcoord 1, 16
	lb bc, 1, 18
	call ClearScreenArea
	pop af
	and a
	ret z

	; Gather power/type/accuracy into wMoveBuffer + 80.. (past both the
	; 64-byte record-copy region and the per-row move id cache at +64..+70 -
	; see each view's own RenderEntryIfVisible) before any PlaceString/
	; PrintNumber call, which would clobber hl/bc mid-walk otherwise.
	;
	; Moves lives in bank $0E (data/moves/moves.asm), not this file's bank
	; $2C - AddNTimes itself is pure arithmetic (safe regardless of the
	; current bank), but the actual byte read MUST go through FarCopyData
	; with BANK(Moves), not a plain [hl] read: this file's own bank is
	; mapped at $4000-$7FFF while it runs, so a raw [hl] here would silently
	; read bank $2C's bytes at that address instead of the real move data -
	; exactly the cross-bank read bug class this project hits repeatedly
	; elsewhere (e.g. LearndexLoadRecord's own EvosMovesPointerTable read,
	; which already goes through FarCopyData for the same reason).
	dec a
	ld hl, Moves
	ld bc, MOVE_LENGTH
	call AddNTimes ; hl -> this move's Moves entry (anim,effect,power,type,acc,pp)
	inc hl
	inc hl ; skip animation, effect - hl -> power
	ld de, wMoveBuffer + 80
	ld bc, 3 ; power, type, accuracy - contiguous in the Moves entry
	ld a, BANK(Moves)
	call FarCopyData

	; type name, columns 1-8. TypeNames (both its pointer table and the
	; string data itself) lives in bank $09, not this file's bank $2C, and
	; PrintType/PrintType_ live there too - reaching them is harder than the
	; usual farcall covers: PrintType's own contract takes its destination
	; in hl via `push hl / jr PrintType_` -> `pop hl`, which only works for
	; a same-bank `call PrintType` (nothing else on the stack in between).
	; farcall's macro clobbers hl for its own jump vector and Bankswitch
	; inserts its own return frame before the target runs, so a farcall
	; would make PrintType_'s pop hl retrieve Bankswitch's bookkeeping
	; instead of the destination. And switching rROMB by hand from inside
	; this ROMX bank doesn't work either - the CPU is still fetching this
	; same code from the region that write just remapped, so the very next
	; instruction fetch reads bank $09's bytes instead of this routine's own
	; (this was tried and confirmed to crash exactly this way; see project
	; memory: never inline a rROMB write in code executing from ROMX).
	;
	; So: skip PrintType entirely and read the string directly via
	; FarCopyData (a HOME routine, safe to call from ROMX), the same
	; "cross-bank pointer, then dereference it" pattern
	; LearndexPrepareTutorWalk already uses for EvosMovesPointerTable. A
	; fixed 9-byte copy (8 chars + '@') covers the longest real type name
	; (FIGHTING/ELECTRIC); PlaceString stops at the first '@' regardless of
	; what follows, so a shorter name just leaves harmless trailing bytes.
	ld a, [wMoveBuffer + 81] ; a = type
	add a
	ld c, a
	ld b, 0
	ld hl, TypeNames
	add hl, bc ; hl -> TypeNames[type], a 2-byte pointer entry (bank $09)
	ld de, wMoveBuffer + 84
	ld bc, 2
	ld a, BANK(TypeNames)
	call FarCopyData ; wMoveBuffer+84/85 = the type name string's ROM address
	ld a, [wMoveBuffer + 84]
	ld l, a
	ld a, [wMoveBuffer + 85]
	ld h, a ; hl = the string's ROM address (bank $09)
	ld de, wMoveBuffer + 86
	ld bc, 9
	ld a, BANK(TypeNames)
	call FarCopyData
	hlcoord 1, 16
	ld de, wMoveBuffer + 86
	call PlaceString

	; power, "Pxxx" at columns 10-13 (right-aligned, space-padded - same
	; PrintNumber convention as move_info.asm's own power field)
	hlcoord 10, 16
	ld a, 'P'
	ld [hli], a
	ld de, wMoveBuffer + 80
	lb bc, 1, 3
	call PrintNumber

	; accuracy, "Axxx" at columns 15-18, converted from the 0-255 scale to a
	; percentage - the exact formula move_info.asm uses for its own accuracy
	; field (100% = 255; add 255 before dividing to round acc*100/256)
	ld a, [wMoveBuffer + 82]
	ld c, a
	ld b, 0
	ld hl, 255
	ld a, 100
	call AddNTimes
	ld a, h
	ld [wMoveBuffer + 83], a
	hlcoord 15, 16
	ld a, 'A'
	ld [hli], a
	ld de, wMoveBuffer + 83
	lb bc, 1, 3
	call PrintNumber
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

; Sets up wCurSpecies/wMonHeader (same source as LearndexPrepareLevelUpWalk:
; wMonHIndex, not wCurSpecies) and loads the record, then walks past BOTH
; the evolutions block and the learnset block to reach the tutor block.
;
; 48 of 190 species have NO tutor block at all, and the record format has
; no explicit marker for this - a tutor entry's own sentinel level (2)
; collides exactly with EVOLVE_ITEM (constants/pokemon_data_constants.asm:
; 80), so a species without a tutor block whose neighbour in the table
; happens to evolve by item would pass a naive "does the next byte look
; like a tutor entry" check. The only reliable signal is structural:
; compare the walked-to position against where the NEXT species' record
; actually starts in EvosMovesPointerTable (confirmed by inspection that
; the table's dw order exactly matches the records' physical declaration
; order in the source file - e.g. RhydonEvosMoves / KangaskhanEvosMoves /
; NidoranMEvosMoves / ClefairyEvosMoves at data/pokemon/evos_moves.asm:221,
; 246, 269, 293, strictly increasing and matching the table's first four
; entries exactly, so there is no gap or reordering to account for).
;
; Output: carry SET = a tutor block exists, hl = its start in wMoveBuffer.
;         carry CLEAR = no tutor block; hl is not meaningful, the caller
;         must render an empty view rather than read it.
; For the very last species in the table (wCurSpecies == NUM_POKEMON_
; INDEXES), there is no "next" pointer to compare against; this falls back
; to always reporting "has a tutor block" and relying on the walk's own
; terminator + LEARNDEX_MAX_ENTRIES cap, the same safety net every species
; had before this routine existed - a narrow, documented residual gap for
; that one species versus the other 189, not a missed check.
; Clobbers af, bc, de, hl.
LearndexPrepareTutorWalk:
	ld a, [wMonHIndex]
	ld [wCurSpecies], a
	call GetMonHeader
	call LearndexLoadRecord

	ld hl, wMoveBuffer
.skipEvo
	ld a, [hli]
	and a
	jr nz, .skipEvo
.skipLearnset
	ld a, [hli]
	and a
	jr nz, .skipLearnset
	; hl = wMoveBuffer + walked (candidate tutor block start)

	ld d, h
	ld e, l ; de = the candidate pointer, saved before hl is reused below
	ld hl, wMoveBuffer
	ld a, e
	sub l
	ld c, a
	ld a, d
	sbc h
	ld b, a ; bc = walked (de - wMoveBuffer)
	push de ; save the candidate WRAM pointer - the real output if a tutor
	        ; block turns out to exist

	; this species' record pointer (ROM address), via a 2-byte cross-bank
	; read. wMoveBuffer's own tail is used as scratch here - safe, since
	; LearndexLoadRecord already finished with the whole buffer before this
	; routine started walking it.
	ld a, [wCurSpecies]
	dec a
	ld l, a
	ld h, 0
	add hl, hl
	ld de, EvosMovesPointerTable
	add hl, de
	push bc ; save "walked" across FarCopyData, which clobbers bc for its
	        ; own byte-count parameter
	ld de, wMoveBuffer + 62
	ld bc, 2
	ld a, BANK(EvosMovesPointerTable)
	call FarCopyData
	pop bc ; bc = walked again
	ld a, [wMoveBuffer + 62]
	ld e, a
	ld a, [wMoveBuffer + 63]
	ld d, a ; de = this species' record pointer (ROM address)

	ld h, d
	ld l, e
	add hl, bc ; hl = record_addr_now (this species' record pointer + walked)

	ld a, [wCurSpecies]
	cp NUM_POKEMON_INDEXES
	jr z, .lastSpecies

	push hl ; save record_addr_now across the next FarCopyData
	ld l, a ; a is still wCurSpecies (1-based); species*2 is the byte
	ld h, 0 ; offset to EvosMovesPointerTable[species] - the (species+1)th
	add hl, hl ; entry, 0-based - no -1 needed here, unlike the read above
	ld de, EvosMovesPointerTable
	add hl, de
	ld de, wMoveBuffer + 62
	ld bc, 2
	ld a, BANK(EvosMovesPointerTable)
	call FarCopyData
	ld a, [wMoveBuffer + 62]
	ld e, a
	ld a, [wMoveBuffer + 63]
	ld d, a ; de = next species' record pointer
	pop hl ; hl = record_addr_now again

	; carry set (hl - de borrows) means hl < de: record_addr_now is still
	; strictly before the next species' record, so a tutor block exists.
	; carry clear covers both "no gap" and "walked past de" - either way,
	; no tutor block.
	ld a, l
	sub e
	ld a, h
	sbc d
	jr c, .hasTutorBlock
	jr .noTutorBlock

.lastSpecies
	; no "next" pointer to compare against - see this routine's own header
	; comment for why this falls back to always reporting a tutor block.
	jr .hasTutorBlock

.hasTutorBlock
	pop hl ; hl = the candidate WRAM pointer, pushed above
	scf
	ret
.noTutorBlock
	pop hl ; rebalance the stack; hl is not meaningful to the caller
	or a
	ret

; Input: hl = tutor block start (from LearndexPrepareTutorWalk, ONLY valid
; when it reported carry SET - callers must check that first).
; Output: b = entry count, capped at LEARNDEX_MAX_ENTRIES.
; Clobbers af, hl.
LearndexCountTutorEntries:
	ld b, 0
.loop
	ld a, [hl]
	and a
	jr z, .done
	inc hl
	inc hl
	inc b
	ld a, b
	cp LEARNDEX_MAX_ENTRIES
	jr c, .loop
.done
	ret

; ============================================================================
; MOVES_BOX_TMHM (LEARNDEX_DESIGN.md D-3): TM/HM compatibility, fusion-aware.
; ============================================================================

; Input: a = 0-based TM/HM index (0..NUM_TM_HM-1).
; Output: Z set = the displayed mon cannot learn it, NZ = it can. Checks
; wMonHIndex (the primary species - see LearndexPrepareLevelUpWalk's own
; comment on why wMonHIndex over wCurSpecies), OR'd with
; wFusionSecondarySpecies too if wLoadedMon is a fusion. Mirrors CanLearnTM's
; own fusion path (engine/items/tms.asm:53-120), which cannot be called
; directly: it derives its fusion check from hWhichPokemon/wPartyMons, which
; assumes a PARTY mon specifically (its own header comment says so), while
; the status screen is also reachable for box mons.
; Leaves wMonHeader populated for wMonHIndex on return either way, matching
; CanLearnTM's own post-condition. Preserves b, c, d, e. Clobbers af, hl.
LearndexTMHMBitSet:
	push bc
	push de
	; mask/offset math, mirrors CanLearnTM's fusion path exactly: byte =
	; index >> 3, mask = 1 << (index & 7), LSB-first.
	ld c, a
	and $07
	inc a
	ld b, $01
.maskLoop
	dec a
	jr z, .maskDone
	sla b
	jr .maskLoop
.maskDone
	ld e, b ; e = bit mask
	ld a, c
	srl a
	srl a
	srl a
	ld d, a ; d = byte offset into the learnset

	ld a, [wMonHIndex]
	ld [wCurSpecies], a
	call GetMonHeader
	ld hl, wMonHLearnset
	ld c, d
	ld b, $00
	add hl, bc
	ld a, [hl]
	and e
	jr nz, .canLearn ; primary already can - no need to check fusion

	push de ; preserve (mask, offset) across the farcall below
	ld de, wLoadedMon
	farcall IsFusionMon
	pop de
	jr z, .cannotLearn ; not a fusion - primary's failed test stands

	ld a, [wFusionSecondarySpecies]
	ld [wCurSpecies], a
	call GetMonHeader
	ld hl, wMonHLearnset
	ld c, d
	ld b, $00
	add hl, bc
	ld a, [hl]
	and e
	push af ; preserve the secondary's test result across the header restore
	ld a, [wMonHIndex]
	ld [wCurSpecies], a
	call GetMonHeader
	pop af
	jr z, .cannotLearn
.canLearn
	pop de
	pop bc
	ret
.cannotLearn
	pop de
	pop bc
	xor a ; force Z - a nonzero AND result must not leak through as "can learn"
	ret

; Input: e = MOVES_BOX_*. Output: b = N (entry count for that view).
; Shared by StatusScreen2MoveCursor (to clamp/scroll the cursor) and each
; view's own draw routine (to compute its window_top the same way).
; Clobbers af, bc, de, hl.
LearndexCountEntriesForView:
	ld a, e
	cp MOVES_BOX_LEVELUP
	jr nz, .notLevelUp
	call LearndexPrepareLevelUpWalk ; hl = learnset block start
	jp LearndexCountLevelUpEntries  ; tail call - b = N, ret
.notLevelUp
	cp MOVES_BOX_TUTOR
	jr nz, .tmhm
	call LearndexPrepareTutorWalk ; carry = has tutor block, hl = start
	jr nc, .noTutorEntries
	jp LearndexCountTutorEntries  ; tail call - b = N, ret
.noTutorEntries
	ld b, 0
	ret
.tmhm
	ld b, 0
	ld c, 0
.countLoop
	ld a, c
	call LearndexTMHMBitSet ; preserves b, c
	jr z, .notLearnable
	inc b
.notLearnable
	inc c
	ld a, c
	cp NUM_TM_HM
	jr nz, .countLoop
	ret

; MOVES_BOX_TMHM content renderer, called from StatusScreen2DrawView's
; jump table with e = MOVES_BOX_TMHM and d = the cursor position (same
; contract as StatusScreen2DrawLevelUp - see its own comment above).
StatusScreen2DrawTMHM:
	call LearndexCountEntriesForView ; b = N (e is already MOVES_BOX_TMHM)

	ld a, d
	call LearndexComputeWindowTop ; a = window_top; b (N) preserved
	ld e, a ; e = window_top. d is untouched and still holds the cursor.
	push bc ; stash N (b) - the render loop below reuses b as the running
	        ; absolute learnable index, so N would not survive to the
	        ; info-strip draw at the end otherwise. Popped back there.

	ld b, 0 ; b = absolute learnable index (N is no longer needed)
	ld c, 0 ; c = raw TM/HM slot index 0..NUM_TM_HM-1
.renderLoop
	ld a, c
	call LearndexTMHMBitSet ; preserves b, c, d, e
	jr z, .notLearnableHere
	ld a, c
	call .RenderEntryIfVisible ; preserves b, c, d, e too
	inc b
.notLearnableHere
	inc c
	ld a, c
	cp NUM_TM_HM
	jr nz, .renderLoop

	pop bc ; b = N again
	; D-5 live info strip for whatever's under the cursor.
	ld a, b
	and a
	jr z, .infoStripEmpty
	ld a, d
	sub e ; a = cursor's row offset within the (already-rendered) window
	ld l, a
	ld h, 0
	ld a, l
	add LOW(wMoveBuffer + LEARNDEX_RECORD_SIZE)
	ld l, a
	ld a, h
	adc HIGH(wMoveBuffer + LEARNDEX_RECORD_SIZE)
	ld h, a
	ld a, [hl]
	jp LearndexDrawInfoStrip ; tail call
.infoStripEmpty
	xor a
	jp LearndexDrawInfoStrip ; tail call

; Input: a = 0-based TM/HM slot index (0..NUM_TM_HM-1), b = absolute
; learnable index, c = the same slot index (re-stashed on entry - the outer
; loop needs c live as ITS OWN slot counter, so this does not trust c to
; survive past its own entry), d = cursor, e = window_top. Prints the row
; (cursor glyph, "TM"/"HM" + 2-digit per-category number, move name) if b
; falls in [e, e+7]; no-op otherwise. Preserves b, c, d, e. Clobbers af, hl.
.RenderEntryIfVisible:
	push bc
	push de
	ld c, a ; c = slot index, safe to hold here - this function's own copy,
	        ; independent of the outer loop's c which is restored via pop

	ld a, b
	sub e
	jr c, .done ; b < window_top
	cp LEARNDEX_VISIBLE_ROWS
	jr nc, .done ; b >= window_top + 7
	; a = row offset 0-6

	; Stash the row offset for the D-5 cache write near the end of this
	; function (once TMToMove has resolved the actual move id) - unlike
	; LevelUp/Tutor's RenderEntryIfVisible, the move id here is not known
	; yet, and b/c/d/e are all still live between here and there (glyph
	; index, slot index, cursor, window_top), leaving no spare register to
	; carry it in. wMoveNum is free here: this function's own use of it
	; (if any) is scoped entirely within this one call, same as LevelUp's.
	ld [wMoveNum], a

	; Decide the cursor glyph now, while d still holds the real cursor - the
	; row-address lookup below overwrites de, so this must happen first.
	push af
	ld a, b
	cp d
	ld b, ' '
	jr nz, .noCursorHere
	ld b, '▷' ; same cursor glyph as extra_options.asm ($ec)
.noCursorHere
	pop af

	call LearndexRowAddress ; hl = this row's tilemap address, column 1

	; Blank this one row before writing it - see StatusScreen2DrawLevelUp's
	; own RenderEntryIfVisible for why (StatusScreen2DrawContent skips the
	; border's blanket blank on a same-view cursor move).
	push bc ; b = the cursor glyph decided above, must survive this call
	push hl
	lb bc, 1, 18
	call ClearScreenArea
	pop hl
	pop bc

	ld a, b ; the glyph decided above
	ld [hli], a ; column 1

	; Compute the unified 1-based TM/HM index (TMToMove's own input) and
	; stash it on the STACK, not in WRAM. wTempTMHM, wTempByteValue,
	; wNamedObjectIndex, wNumSetBits, wTypeEffectiveness, wMoveType, and
	; wPokedexNum are ALL the exact same physical byte (ram/wram.asm:1687-
	; 1696 - a single scratch cell reused by many unrelated routines, not
	; just the wNamedObjectIndex/wTempByteValue pair D-2 already hit). The
	; display-number staging a few lines below writes wTempByteValue for
	; PrintNumber's own input, which silently clobbers wTempTMHM too if the
	; unified index were staged there first - this was invisible for every
	; TM entry (a TM's unified index and display number are numerically
	; identical, both slot+1) and only surfaced on an HM row, where they
	; diverge: HM04's real unified index is 54 but its display number is 4,
	; and the display-number write overwrote the stashed 54 with a 4 before
	; TMToMove ever ran - which is exactly why every HM was silently showing
	; the matching-numbered TM's move instead of its own.
	ld a, c
	inc a ; unified 1-based TM/HM index, TMToMove's own input contract
	push af

	; "TM"/"HM" + the PER-CATEGORY display number (TM01-TM50, HM01-HM05) -
	; NOT the same as the unified index just stashed above.
	ld a, c
	cp NUM_TMS
	jr nc, .isHM
	ld a, 'T'
	ld [hli], a
	ld a, 'M'
	ld [hli], a
	ld a, c
	inc a
	jr .gotDisplayNumber
.isHM
	ld a, 'H'
	ld [hli], a
	ld a, 'M'
	ld [hli], a
	ld a, c
	sub NUM_TMS
	inc a
.gotDisplayNumber
	ld [wTempByteValue], a
	ld de, wTempByteValue
	lb bc, LEADING_ZEROES | 1, 2
	call PrintNumber ; columns 4-5
	ld a, ' '
	ld [hli], a ; column 6

	; wTempByteValue's job (and thus the shared byte's) is done now that
	; PrintNumber has returned, so it is finally safe to write wTempTMHM.
	pop af ; a = unified index, carried past PrintNumber's own use of the
	       ; shared scratch byte via the stack instead
	ld [wTempTMHM], a

	; TMToMove lives in bank 04 (engine/items/tms.asm), not this file's bank
	; $2C - a plain call here executes whatever happens to be mapped at that
	; address in the CURRENTLY active bank instead, which is exactly the
	; cross-bank call bug class this project has hit repeatedly elsewhere.
	; farcall's own macro expansion is `ld hl, TMToMove / ld b, BANK(...) /
	; call Bankswitch` - it uses hl as the jump vector, and TMToMove's own
	; body also uses hl for its TechnicalMachines lookup, so hl is
	; unconditionally garbage on return. hl is this row's write cursor
	; (column 7, about to receive the move name), so it MUST be saved here -
	; without this, GetMoveName below faithfully preserves whatever garbage
	; hl it's handed (its own contract only promises to preserve hl, not to
	; correct it), and PlaceString silently writes the move name somewhere
	; off in unrelated memory instead of onto the visible row. This was the
	; "TM04 shows no move name" bug.
	push hl
	farcall TMToMove ; [wTempTMHM] (already staged above) becomes the move id
	ld a, [wTempTMHM]
	ld [wNamedObjectIndex], a
	pop hl ; hl = this row's write cursor, restored

	; D-5 cache write, now that the move id is finally known - see this
	; row's earlier "stash the row offset" comment for why it waited until
	; here. hl (the row write cursor) is saved/restored around this so the
	; GetMoveName/PlaceString call below still gets the right destination.
	push hl
	ld a, [wMoveNum] ; a = row offset, stashed earlier in this call
	ld l, a
	ld h, 0
	ld a, l
	add LOW(wMoveBuffer + LEARNDEX_RECORD_SIZE)
	ld l, a
	ld a, h
	adc HIGH(wMoveBuffer + LEARNDEX_RECORD_SIZE)
	ld h, a
	ld a, [wNamedObjectIndex] ; the move id, just staged above
	ld [hl], a
	pop hl

	call GetMoveName ; de = wNameBuffer, preserves hl
	call PlaceString ; columns 7.. up to 12 chars, '@'-terminated

.done
	pop de
	pop bc
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
	push bc ; stash N (b) - the render loop below reuses b for each entry's
	        ; level, so N would not survive to the info-strip draw at the end
	        ; otherwise. Popped back there; a plain, locally-balanced nested
	        ; push/pop, safe regardless of what StatusScreen2DrawContent's
	        ; own dispatch put on the stack for this function's return.

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
	pop bc ; b = N again

	; D-5 live info strip for whatever's under the cursor.
	ld a, b
	and a
	jr z, .infoStripEmpty
	ld a, d
	sub e ; a = cursor's row offset within the (already-rendered) window
	ld l, a
	ld h, 0
	ld a, l
	add LOW(wMoveBuffer + LEARNDEX_RECORD_SIZE)
	ld l, a
	ld a, h
	adc HIGH(wMoveBuffer + LEARNDEX_RECORD_SIZE)
	ld h, a
	ld a, [hl]
	jp LearndexDrawInfoStrip ; tail call - its own ret returns to our caller
.infoStripEmpty
	xor a
	jp LearndexDrawInfoStrip ; tail call

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
	jr nc, .done ; c >= window_top + 7
	; a = row offset 0-6

	push af
	; Cache this row's move id at wMoveBuffer + LEARNDEX_RECORD_SIZE + offset
	; (D-5's live info strip): StatusScreen2MoveCursor's cheap glyph-flip
	; path moves the cursor without a full re-render, so it reads this cache
	; instead of re-walking the record to find "what's under the new
	; cursor." hl is not yet live in this function (LearndexRowAddress,
	; the first thing that sets it, runs after this), so it is free to use.
	ld l, a
	ld h, 0
	ld a, l
	add LOW(wMoveBuffer + LEARNDEX_RECORD_SIZE)
	ld l, a
	ld a, h
	adc HIGH(wMoveBuffer + LEARNDEX_RECORD_SIZE)
	ld h, a
	ld a, [wMoveNum] ; the move id, already stashed above
	ld [hl], a

	; Decide the cursor glyph now, while d still holds the real cursor - the
	; row-address lookup below overwrites de, so this must happen first.
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

; ============================================================================
; MOVES_BOX_TUTOR (LEARNDEX_DESIGN.md D-4): the PC Move Tutor's stock for
; this species (Indigo Plateau Lobby, 5000 per use) - Gen 1 tradeback /
; Stadium event moves. 142 of 190 species have one; see
; LearndexPrepareTutorWalk's header comment for how the other 48 are
; detected and rendered as an empty view rather than garbage.
;
; Deliberately reads only the PRIMARY species (wMonHIndex), no fusion merge
; - same reasoning as D-2's own header comment: PrepareMoveTutorList (the
; real in-game tutor list) is equally primary-only, so a fusion mon's
; ACTUAL tutor stock is the primary species' alone.
; ============================================================================

; MOVES_BOX_TUTOR content renderer, called from StatusScreen2DrawView's
; jump table with e = MOVES_BOX_TUTOR and d = the cursor position (same
; contract as StatusScreen2DrawLevelUp/StatusScreen2DrawTMHM above).
StatusScreen2DrawTutor:
	; LearndexPrepareTutorWalk clobbers de the same way
	; LearndexPrepareLevelUpWalk does (FarCopyData plumbing) - see the
	; matching note on StatusScreen2DrawLevelUp above, same bug class.
	push de
	call LearndexPrepareTutorWalk ; carry = has tutor block, hl = start
	pop de
	jr nc, .noTutorBlock ; nothing to draw - the border, or the per-row
	                     ; clear on a same-view cursor move, already
	                     ; blanked the interior

	push hl
	call LearndexCountTutorEntries ; b = N
	pop hl

	ld a, d
	call LearndexComputeWindowTop ; a = window_top; b (N) preserved
	ld e, a ; e = window_top. d is untouched and still holds the cursor.
	push bc ; stash N (b) for the info-strip draw at .renderDone - nothing
	        ; in this render loop reuses b, but keep the same pattern as
	        ; LevelUp/TMHM for consistency and to not depend on that

	ld c, 0 ; c = running absolute index
.renderLoop
	ld a, [hl]
	and a
	jr z, .renderDone
	ld a, c
	cp LEARNDEX_MAX_ENTRIES
	jr nc, .renderDone
	inc hl ; skip the sentinel level byte (always 2 - not meaningful to the
	       ; player, see LearndexPrepareTutorWalk's header comment)
	ld a, [hl] ; a = move id
	inc hl
	push hl
	call .RenderEntryIfVisible
	pop hl
	inc c
	jr .renderLoop
.renderDone
	pop bc ; b = N again
	; D-5 live info strip for whatever's under the cursor.
	ld a, b
	and a
	jr z, .infoStripEmpty
	ld a, d
	sub e ; a = cursor's row offset within the (already-rendered) window
	ld l, a
	ld h, 0
	ld a, l
	add LOW(wMoveBuffer + LEARNDEX_RECORD_SIZE)
	ld l, a
	ld a, h
	adc HIGH(wMoveBuffer + LEARNDEX_RECORD_SIZE)
	ld h, a
	ld a, [hl]
	jp LearndexDrawInfoStrip ; tail call
.infoStripEmpty
	xor a
	jp LearndexDrawInfoStrip ; tail call
.noTutorBlock
	; No tutor block at all (48 of 190 species) - nothing was rendered, so
	; there is nothing under the cursor either; blank the strip rather than
	; leave a previous species'/view's stale cache showing.
	xor a
	jp LearndexDrawInfoStrip ; tail call

; Input: a = move id, c = absolute index, e = window_top, d = cursor.
; Prints the row (cursor glyph + move name - no level or number prefix; the
; sentinel level is not meaningful to the player, unlike D-2/D-3's rows) if
; c falls in [e, e+7]; no-op otherwise. Preserves b, c, d, e. Clobbers af, hl.
.RenderEntryIfVisible:
	push bc
	push de
	; Safe to write wNamedObjectIndex directly here, unlike D-2/D-3: a
	; tutor row has no PrintNumber call (no level or TM/HM number shown),
	; so nothing overwrites the wNamedObjectIndex/wTempByteValue/wTempTMHM
	; shared scratch byte (ram/wram.asm:1687-1696) between this write and
	; GetMoveName reading it below.
	ld [wNamedObjectIndex], a

	ld a, c
	sub e
	jr c, .done ; c < window_top
	cp LEARNDEX_VISIBLE_ROWS
	jr nc, .done ; c >= window_top + 7
	; a = row offset 0-6

	; D-5 cache write, mirroring LevelUp's RenderEntryIfVisible - the move
	; id is already in wNamedObjectIndex (stashed at function entry above),
	; so unlike TMHM this can happen immediately, no wMoveNum stash needed.
	; b/c/d/e are all still live (glyph decision, absolute index, cursor,
	; window_top), so hl is the only free scratch, same reasoning as
	; LevelUp's own comment.
	ld l, a
	ld h, 0
	ld a, l
	add LOW(wMoveBuffer + LEARNDEX_RECORD_SIZE)
	ld l, a
	ld a, h
	adc HIGH(wMoveBuffer + LEARNDEX_RECORD_SIZE)
	ld h, a
	ld a, [wNamedObjectIndex]
	ld [hl], a
	ld a, c
	sub e ; a = row offset again, for the block below

	; Decide the cursor glyph now, while d still holds the real cursor -
	; the row-address lookup below overwrites de, so this must happen first
	; (same ordering bug class as every other view's RenderEntryIfVisible).
	push af
	ld a, c
	cp d
	ld b, ' '
	jr nz, .noCursorHere
	ld b, '▷' ; same cursor glyph as extra_options.asm ($ec)
.noCursorHere
	pop af

	call LearndexRowAddress ; hl = this row's tilemap address, column 1

	; Blank this one row before writing it - see StatusScreen2DrawLevelUp's
	; own RenderEntryIfVisible for why (StatusScreen2DrawContent skips the
	; border's blanket blank on a same-view cursor move).
	push bc ; b = the cursor glyph decided above, must survive this call
	push hl
	lb bc, 1, 18
	call ClearScreenArea
	pop hl
	pop bc

	ld a, b ; the glyph decided above
	ld [hli], a ; column 1
	ld a, ' '
	ld [hli], a ; column 2

	call GetMoveName ; de = wNameBuffer, preserves hl
	call PlaceString ; columns 3.. up to 12 chars, '@'-terminated

.done
	pop de
	pop bc
	ret
