; ============================================================================
; Option screens - shared table-driven page engine.
;
; Replaces three hand-rolled input loops with one: the vanilla OPTION screen
; (DisplayOptionMenu in engine/menus/main_menu.asm, which is now a farjp stub)
; and the Shin Red "extra options" second page (engine/menus/extra_options.asm,
; deleted). engine/debug/debug2_config.asm reuses this same engine.
;
; STYLE. One setting per row with a blank row between groups, label at column 2,
; value RIGHT ALIGNED so every row's value ends on the same column, cursor a
; single '▷' at column 1, inside the box. This is ShinRed's second-page look;
; the fully double-spaced layout it replaced burned eleven rows on six settings.
;
; WHY A TABLE AND NOT MORE HANDWRITTEN ROWS. The vanilla screen inferred each
; setting's value from WHERE THE CURSOR SAT, and rebuilt wOptions from those
; cursor X coordinates on every pass through its loop
; (SetOptionsFromCursorPositions). That is what made INSTANT text need its own
; row plus a matched pair of guards in two routines: a normal TEXT SPEED cursor
; overwrote wOptions the instant the extra page set it. Rows here write their
; variable DIRECTLY, so there is nothing to fight, INSTANT is simply the fastest
; step of TEXT SPEED, and both halves of that guard are gone rather than ported.
;
; PADDING AND ALIGNMENT. Every value string in one row's table is padded to the
; same width, with the padding on the LEFT, and the row's ValueColumn is chosen
; so that width ends on OPT_VALUE_RIGHT. That gives right alignment and means a
; short value still fully overwrites a longer one left behind by the previous
; draw - the engine never blanks a value cell first.
;
; ENTRY POINTS. Two, differing only in which page set they pass:
;   DisplayOptionMenu_       title screen - the settings alone
;   DisplayOptionMenuInGame_ start menu   - the settings plus the CHEAT row
; They share ONE row table; the title page's descriptor simply declares one row
; fewer, so it stops before CHEAT. The split is deliberate: the CHEAT row writes
; progression events and calls SaveGameData, and the title screen reaches this
; menu BEFORE a save is loaded, where wEventFlags holds nothing meaningful and a
; save would write garbage. Declaring a shorter page removes that hazard outright
; instead of guarding it with an invented "is a game running" predicate.
;
; SCRATCH. wOptionsMenuRow is the cursor. hCurrentMenuItem is the row currently
; being drawn or edited, transient for the lifetime of this menu's own loop -
; the same borrowing extra_options.asm documented, and the vanilla screen already
; scribbled it too. Nothing here reads it as "the" global current menu item.
; ============================================================================

; FRAGMENT because engine/debug/debug2_config.asm appends its Debug 2 screen to
; this same section. The engine dispatches every row's Draw and Cycle routine
; with `jp hl`, which cannot cross a bank, so a screen's row routines MUST sit
; in the same bank as the engine. Anything reaching this section from outside
; it uses farcall/farjp, as both entry points' callers do.
SECTION FRAGMENT "Options Menu", ROMX

; ----------------------------------------------------------------------------
; Row descriptor, OPTROW_SIZE bytes.
;
;   dw LabelText    placed at OPT_LABEL_COL of the row
;   db RowY         this row's screen Y. Rows carry their own Y rather than
;                   sitting at a fixed stride, so a blank spacer between groups
;                   costs one byte here and no special case in the engine.
;   db ValueColumn  hlcoord X where this row's value is drawn
;   dw VarAddr      the byte holding this row's field
;   db Mask         the field's bits within that byte
;   dw OrderTable   Count raw values, already shifted into Mask's position, in
;                   the order LEFT/RIGHT walks them
;   dw StringTable  Count string pointers, parallel to OrderTable
;   db Count
;   dw Hook         called after a change; 0 for none
;
; A MASK OF 0 MARKS A CUSTOM ROW, whose value does not live in a single masked
; byte. OrderTable is then read as a Draw routine (entered with hl = the value
; cell) and StringTable as a Cycle routine (which reads its direction from
; hJoy5 and must preserve hCurrentMenuItem, since the engine redraws that row
; afterwards). VarAddr, Count and Hook are unused. The CHEAT row below is one;
; so are the Debug 2 numeric rows. A mask of 0 is meaningless for a real field,
; so it cannot collide with one.
; ----------------------------------------------------------------------------
DEF OPTROW_LABEL   EQU 0
DEF OPTROW_ROWY    EQU 2
DEF OPTROW_VALCOL  EQU 3
DEF OPTROW_VAR     EQU 4
DEF OPTROW_MASK    EQU 6
DEF OPTROW_ORDER   EQU 7
DEF OPTROW_STRINGS EQU 9
DEF OPTROW_COUNT   EQU 11
DEF OPTROW_HOOK    EQU 12
DEF OPTROW_SIZE    EQU 14

; label, screen Y, value column, variable, mask, order, strings, count, hook
MACRO optrow
	dw \1
	db \2
	db \3
	dw \4
	db \5
	dw \6
	dw \7
	db \8
	dw \9
ENDM

; label, screen Y, value column, draw routine, cycle routine
MACRO optrow_custom
	dw \1
	db \2
	db \3
	dw 0
	db 0 ; mask 0: custom row
	dw \4
	dw \5
	db 0
	dw 0
ENDM

; ----------------------------------------------------------------------------
; Page descriptor.
;
;   db NumRows    setting rows. Also the CANCEL row's cursor index, so the
;                 cursor walks 0..NumRows inclusive. A page may declare FEWER
;                 rows than its table holds, which is how the title screen
;                 shares the in-game table but stops before CHEAT.
;   db BoxHeight  TextBoxBorder's b. Kept separate from NumRows so a short page
;                 can still reserve room for rows it does not have yet.
;   db CancelY    screen Y of the CANCEL row, which sits outside the box
;   dw RowTable
;   db PromptCol  column for the page-switch prompt, which is drawn one row
;                 BELOW CANCEL. Stored rather than computed so the prompt can be
;                 centred by hand for its exact length.
;   dw PromptText 0 for none
;
; A page set is `db pageCount` followed by one `dw` per page.
; ----------------------------------------------------------------------------
DEF OPTPAGE_NUMROWS   EQU 0
DEF OPTPAGE_BOXH      EQU 1
DEF OPTPAGE_CANCELY   EQU 2
DEF OPTPAGE_ROWS      EQU 3
DEF OPTPAGE_PROMPTCOL EQU 5
DEF OPTPAGE_PROMPT    EQU 6

; rows, box height, CANCEL Y, row table, prompt column, prompt
MACRO optpage
	db \1
	db \2
	db \3
	dw \4
	db \5
	dw \6
ENDM

; The box spans the full width, columns 0-19, and the cursor lives INSIDE it at
; column 1 with labels starting at column 2.
;
; The cursor used to sit at column 0, which was also the box's left border
; column, so it ate the border tile on whichever row was selected and the box
; looked cut away down its left edge. Moving the cursor inside is what fixes
; that. Putting it in a margin outside the box works too, but costs a content
; column: DIFFICULTY plus its widest value needs all 17 columns from 2 to 18.
DEF OPT_BOX_LEFT    EQU 0
DEF OPT_CURSOR_COL  EQU 1
DEF OPT_LABEL_COL   EQU 2
DEF OPT_BOX_WIDTH   EQU 18
DEF OPT_VALUE_RIGHT EQU 18

; ============================================================================
; Entry points
; ============================================================================

DisplayOptionMenu_::
	ld hl, OptionsPageSetTitle
	jr OptionsMenuEngine

DisplayOptionMenuInGame_::
	ld hl, OptionsPageSetInGame
	; fall through

; ----------------------------------------------------------------------------
; hl = a page set. Runs until the player backs out.
; ----------------------------------------------------------------------------
OptionsMenuEngine:
	ld a, l
	ld [wOptionsMenuPageSet], a
	ld a, h
	ld [wOptionsMenuPageSet + 1], a
	xor a
	ld [wOptionsMenuPage], a
	ld [wOptionsMenuRow], a
	ASSERT BIT_FAST_TEXT_DELAY == 0
	inc a ; 1 << BIT_FAST_TEXT_DELAY
	ld [wLetterPrintingDelayFlags], a
; This screen is a full-width tilemap, so any inherited camera offset shears its
; right border off the edge. Zero the scroll for the menu and put it back on the
; way out - the overworld's hSCX is a running value, and clearing it for good
; would jump the camera out from under the player.
	ldh a, [hSCX]
	ld b, a
	ldh a, [hSCY]
	ld c, a
	push bc
	xor a
	ldh [hSCX], a
	ldh [hSCY], a
.redrawPage
	xor a
	ldh [hAutoBGTransferEnabled], a
	call ClearScreen
	call Delay3
	call OptDrawPage
	ld a, $01
	ldh [hAutoBGTransferEnabled], a
	call Delay3
.loop
	call JoypadLowSensitivity
	ldh a, [hJoy5]
	ld b, a
	and PAD_B | PAD_START
	jr nz, .exit
	bit B_PAD_SELECT, b
	jr nz, .selectPressed
	bit B_PAD_A, b
	jr nz, .aPressed
	ld a, b
	and PAD_UP | PAD_DOWN
	jr nz, .movePressed
	ld a, b
	and PAD_LEFT | PAD_RIGHT
	jr z, .loop
; LEFT/RIGHT edits the row the cursor is on. CANCEL has no value to edit.
	call OptCursorOnCancel
	jr z, .loop
	ld a, SFX_PRESS_AB
	call PlaySound
	ld a, [wOptionsMenuRow]
	ldh [hCurrentMenuItem], a
	call OptCycleValue
	jr .loop
.aPressed
	call OptCursorOnCancel
	jr nz, .loop
.exit
	ld a, SFX_PRESS_AB
	call PlaySound
	pop bc
	ld a, b
	ldh [hSCX], a
	ld a, c
	ldh [hSCY], a
	ret

.movePressed
	ld a, SFX_PRESS_AB
	call PlaySound
	call OptGetPage
	ld a, [hl] ; NumRows, which is also the CANCEL row's index
	ld c, a
	ldh a, [hJoy5]
	bit B_PAD_UP, a
	ld a, [wOptionsMenuRow]
	jr nz, .moveUp
	cp c
	jr nc, .moveToTop
	inc a
	jr .moveStore
.moveToTop
	xor a
	jr .moveStore
; UP steps BACK. The menu this replaced tested PAD_UP and PAD_DOWN together and
; unconditionally incremented, so UP was a full lap forward.
.moveUp
	and a
	jr nz, .moveUpOne
	ld a, c
	jr .moveStore
.moveUpOne
	dec a
.moveStore
	ld [wOptionsMenuRow], a
	call OptDrawCursor
	jp .loop

; Page switching is intact but currently unreachable: both page sets below
; declare a single page while the second page is shelved. Reviving that page is
; enough to bring SELECT back.
.selectPressed
	call OptGetPageCount
	cp 2
	jp c, .loop
	ld a, SFX_PRESS_AB
	call PlaySound
	call OptGetPageCount
	ld b, a
	ld a, [wOptionsMenuPage]
	inc a
	cp b
	jr c, .pageReady
	xor a
.pageReady
	ld [wOptionsMenuPage], a
	xor a
	ld [wOptionsMenuRow], a
	jp .redrawPage

; ============================================================================
; Table walking
; ============================================================================

; Returns a = the current page set's page count. Clobbers af, hl.
OptGetPageCount:
	ld a, [wOptionsMenuPageSet]
	ld l, a
	ld a, [wOptionsMenuPageSet + 1]
	ld h, a
	ld a, [hl]
	ret

; Returns hl = the current page's descriptor. Clobbers af. Preserves bc, de.
OptGetPage:
	push de
	ld a, [wOptionsMenuPageSet]
	ld l, a
	ld a, [wOptionsMenuPageSet + 1]
	ld h, a
	inc hl ; past the page count
	ld a, [wOptionsMenuPage]
	add a
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	pop de
	ret

; a = row index, which must be a setting row. Returns hl = its descriptor.
; Clobbers af, bc. Preserves de.
OptGetRow:
	push af
	call OptGetPage
	push de
	ld de, OPTPAGE_ROWS
	add hl, de
	pop de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	pop af
	ld bc, OPTROW_SIZE
	jp AddNTimes

; a = row index. Returns a = that row's screen Y. Clobbers af.
; Preserves bc, de, hl.
;
; Rows carry their own Y rather than sitting at FirstRowY + index, so blank
; spacer rows cost a byte in the table instead of a special case here.
OptRowY:
	push hl
	push bc
	push de
	ld c, a
	call OptGetPage
	ld a, [hli] ; NumRows
	cp c
	jr z, .cancelRow
	ld a, c
	call OptGetRow
	ld de, OPTROW_ROWY
	add hl, de
	ld a, [hl]
	jr .done
.cancelRow
	inc hl     ; past BoxHeight
	ld a, [hl] ; CancelY
.done
	pop de
	pop bc
	pop hl
	ret

; a = row index. Returns hl = the tilemap address of column 0 of that row.
; Clobbers af. Preserves bc, de.
OptRowCoord:
	push bc
	call OptRowY
	hlcoord 0, 0
	ld bc, SCREEN_WIDTH
	call AddNTimes
	pop bc
	ret

; Z if the cursor is on the CANCEL row. Clobbers af, hl. Preserves bc, de.
OptCursorOnCancel:
	push hl
	call OptGetPage
	ld a, [hl] ; NumRows is the CANCEL row's index
	ld hl, wOptionsMenuRow
	cp [hl]
	pop hl
	ret

; hl = a row descriptor. Returns a = the position of that row's current value
; within its order table, or 0 if the stored value is not listed.
; Clobbers af, bc, de. Preserves hl.
OptEnumIndex:
	push hl
	ld de, OPTROW_COUNT
	add hl, de
	ld b, [hl]
	pop hl
	push hl
	ld de, OPTROW_VAR
	add hl, de
	ld a, [hli]
	ld e, a
	ld d, [hl] ; de = the variable's address
	inc hl     ; -> Mask
	ld a, [de]
	and [hl]
	ld c, a    ; c = the field's current value
	inc hl     ; -> OrderTable
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld d, 0    ; d = position
.search
	ld a, [hli]
	cp c
	jr z, .found
	inc d
	dec b
	jr nz, .search
	ld d, 0 ; not listed: show the first entry
.found
	ld a, d
	pop hl
	ret

; ============================================================================
; Drawing
; ============================================================================

; Draws the current page in full: border, every setting row, the CANCEL row,
; the page prompt and the cursor.
OptDrawPage:
	call OptGetPage
	inc hl ; -> BoxHeight
	ld a, [hl]
	ld b, a
	ld c, OPT_BOX_WIDTH
	hlcoord OPT_BOX_LEFT, 0
	call TextBoxBorder
	xor a
	ldh [hCurrentMenuItem], a
.rowLoop
	call OptDrawRow
	ldh a, [hCurrentMenuItem]
	inc a
	ldh [hCurrentMenuItem], a
	ld c, a
	call OptGetPage
	ld a, [hl] ; NumRows
	cp c
	jr nz, .rowLoop
; a = NumRows, which is the CANCEL row's index.
	call OptRowCoord
	ld bc, OPT_LABEL_COL
	add hl, bc
	ld de, OptTextCancel
	call PlaceString
	call OptGetPage
	ld de, OPTPAGE_PROMPT
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld a, h
	or l
	jr z, .noPrompt
	ld d, h
	ld e, l ; de = the prompt text
	call OptGetPage
	push de
	ld de, OPTPAGE_CANCELY
	add hl, de
	ld a, [hl]
	inc a ; the prompt sits one row below CANCEL
	push af
	call OptGetPage
	ld de, OPTPAGE_PROMPTCOL
	add hl, de
	ld c, [hl]
	ld b, 0
	pop af ; the prompt's screen Y
	push bc
	hlcoord 0, 0
	ld bc, SCREEN_WIDTH
	call AddNTimes
	pop bc
	add hl, bc
	pop de
	call PlaceString
.noPrompt
	jp OptDrawCursor

; Places the cursor glyph at OPT_CURSOR_COL of the selected row and a space on
; every other row, CANCEL included. Redraws all of them rather than tracking
; where the cursor was.
OptDrawCursor:
	call OptGetPage
	ld a, [hl]
	inc a ; the CANCEL row sits one past the last setting
	ld b, a
	ld c, 0
.loop
	ld a, c
	call OptRowCoord
	ASSERT OPT_CURSOR_COL == 1
	inc hl
	ld a, [wOptionsMenuRow]
	cp c
	ld a, ' '
	jr nz, .place
	ld a, '▷'
.place
	ld [hl], a
	inc c
	dec b
	jr nz, .loop
	ret

; Draws the label and value of the row whose index is in hCurrentMenuItem.
OptDrawRow:
	ldh a, [hCurrentMenuItem]
	call OptGetRow
	ld a, [hli]
	ld e, a
	ld d, [hl] ; de = the label
	ldh a, [hCurrentMenuItem]
	push de
	call OptRowCoord
	ld bc, OPT_LABEL_COL
	add hl, bc
	pop de
	call PlaceString
	; fall through

; Draws just the value of the row whose index is in hCurrentMenuItem.
OptDrawValue:
	ldh a, [hCurrentMenuItem]
	call OptGetRow
	push hl
	ld de, OPTROW_VALCOL
	add hl, de
	ld c, [hl]
	ldh a, [hCurrentMenuItem]
	push bc
	call OptRowCoord
	pop bc
	ld b, 0
	add hl, bc ; hl = the value cell
	pop de     ; de = the descriptor
	push hl
	ld h, d
	ld l, e
	ld de, OPTROW_MASK
	add hl, de
	ld a, [hl]
	and a
	jr z, .customDraw
; Enum row: look the current value's position up in the string table.
	ld de, -OPTROW_MASK
	add hl, de ; back to the descriptor head
	call OptEnumIndex
	add a
	ld c, a
	ld b, 0
	ld de, OPTROW_STRINGS
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	add hl, bc
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld d, h
	ld e, l
	pop hl ; the value cell
	jp PlaceString
; Custom row: hl points at the Mask byte, so the slot after it holds this row's
; Draw routine rather than an order table.
.customDraw
	inc hl
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld d, h
	ld e, l
	pop hl  ; hl = the value cell
	push de
	ret     ; tail-jump to the routine

; ============================================================================
; Editing
; ============================================================================

; Steps the value of the row whose index is in hCurrentMenuItem, in the
; direction held in hJoy5, then redraws it.
OptCycleValue:
	ldh a, [hCurrentMenuItem]
	call OptGetRow
	push hl
	ld de, OPTROW_MASK
	add hl, de
	ld a, [hl]
	and a
	jr z, .customCycle
	pop hl
	push hl
	call OptEnumIndex
	ld c, a ; c = the current position
	pop hl
	push hl
	ld de, OPTROW_COUNT
	add hl, de
	ld a, [hl]
	ld d, a ; d = the entry count
	ldh a, [hJoy5]
	bit B_PAD_RIGHT, a
	jr nz, .stepRight
	ld a, c
	and a
	jr nz, .stepLeft
	ld a, d ; wrap past the first entry
.stepLeft
	dec a
	jr .positionReady
.stepRight
	ld a, c
	inc a
	cp d
	jr c, .positionReady
	xor a
.positionReady
	ld c, a
	ld b, 0
	pop hl
	push hl
	ld de, OPTROW_ORDER
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	add hl, bc
	ld c, [hl] ; c = the new raw value, already in the mask's position
	pop hl
	push hl
	ld de, OPTROW_VAR
	add hl, de
	ld a, [hli]
	ld e, a
	ld d, [hl] ; de = the variable's address
	inc hl     ; -> Mask
	ld a, [hl]
	cpl
	ld b, a
	ld a, [de]
	and b
	or c
	ld [de], a
	pop hl
	ld de, OPTROW_HOOK
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld a, h
	or l
	jr z, .done
	ld de, .done
	push de
	jp hl
.done
	jp OptDrawValue
; Custom row: the string-table slot holds this row's Cycle routine.
.customCycle
	pop hl ; the descriptor
	ld de, OPTROW_STRINGS
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld de, .done
	push de
	jp hl

; ============================================================================
; The CHEAT row (in-game entry only)
;
; A fully reversible four-way selector over the two species-group activation
; events and the SRAM enable byte - the same state Prof. Palm's Silph Co B1F
; script and the Room PC toggle menu write, so all three stay consistent.
; Debug 2's UPGRADES row calls these same two routines.
;
;   index 0  KANTO       %001   both events clear
;   index 1  JOHTO       %011   EVENT_JOHTO_ACTIVATED set
;   index 2  TIME WARP   %101   EVENT_KANTO_TIMEWARP_ACTIVATED set
;   index 3  WARP/JOHTO  %111   both set
;
; Kanto is never removable: RogueGetActiveGroupMask re-adds it unconditionally
; and RogueRollGroupForTier assumes it.
;
; The events are the source of truth on read, matching RogueGetActiveGroupMask.
; The write follows the Silph script's sequence (SRAM enable, explicit bank 1,
; read-modify-write, close SRAM, FlagActionPredef, SaveGameData), except that it
; REPLACES the group bits instead of OR-ing them and uses FLAG_RESET as well as
; FLAG_SET, which is what makes it reversible.
;
; NOT retroactive within a run: wRunGymLineup, wRunElite4 and wRunChampion are
; rolled once at run start, so Johto leaders and a Johto Elite Four only appear
; from the next run. Species rolls, regional forms and the per-group credit
; bonus all take effect immediately.
; ============================================================================

; Returns a = the CHEAT row's current index, 0-3. Clobbers af.
OptCheatIndex:
	ASSERT EVENT_KANTO_TIMEWARP_ACTIVATED % 8 == (EVENT_JOHTO_ACTIVATED % 8) + 1
	ld a, [wEventFlags + (EVENT_JOHTO_ACTIVATED / 8)]
	and (1 << (EVENT_JOHTO_ACTIVATED % 8)) | (1 << (EVENT_KANTO_TIMEWARP_ACTIVATED % 8))
	swap a ; bits 5-6 -> bits 1-2
	rrca   ; -> bits 0-1; bit 0 was clear, so nothing rotates in
	ret

; hl = the value cell.
OptDrawCheat:
	push hl
	call OptCheatIndex
	add a
	ld e, a
	ld d, 0
	ld hl, OptCheatValues
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld d, h
	ld e, l
	pop hl
	jp PlaceString

OptCycleCheat:
	call OptCheatIndex
	ld c, a
	ldh a, [hJoy5]
	bit B_PAD_RIGHT, a
	ld a, c
	jr nz, .stepRight
	dec a
	and %11
	jr .indexReady
.stepRight
	inc a
	and %11
.indexReady
; a = the new index. Bit 0 is Johto, bit 1 is Time Warp, and one shift turns
; that straight into the group mask, since BIT_GROUP_JOHTO/WARP sit one place
; higher than the index bits and BIT_GROUP_KANTO is bit 0.
	ld c, a
	ASSERT BIT_GROUP_KANTO == 0
	ASSERT BIT_GROUP_JOHTO == 1
	ASSERT BIT_GROUP_WARP == 2
	add a
	or 1 << BIT_GROUP_KANTO
	ld b, a
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ASSERT BANK("Save Data") == 1
	ld a, 1
	ld [rRAMB], a ; select bank 1 explicitly; the ambient bank is unreliable
	ld a, b
	ld [sRogueSpeciesGroupsEnabled], a
	xor a
	ld [rRAMG], a ; never leave SRAM enabled across a return
	ld a, c
	push af
	ld b, FLAG_RESET
	bit 0, c
	jr z, .johtoAction
	ld b, FLAG_SET
.johtoAction
	ld hl, wEventFlags
	ld c, EVENT_JOHTO_ACTIVATED
	predef FlagActionPredef
	pop af
	ld c, a
	ld b, FLAG_RESET
	bit 1, c
	jr z, .warpAction
	ld b, FLAG_SET
.warpAction
	ld hl, wEventFlags
	ld c, EVENT_KANTO_TIMEWARP_ACTIVATED
	predef FlagActionPredef
; The engine redraws this row from hCurrentMenuItem on return, and save.asm
; writes that byte on at least one path, so carry it across the save.
	ldh a, [hCurrentMenuItem]
	push af
	farcall SaveGameData
	pop af
	ldh [hCurrentMenuItem], a
	ret

; ============================================================================
; Hooks
; ============================================================================

Opt60FPSHook:
	predef SetCPUSpeed
	ret

; ============================================================================
; Page sets and pages
;
; Both sets hold ONE page. The second page is shelved rather than deleted - see
; the commented block below - so CHEAT lives on the main page for now. The
; engine's SELECT handling is still live and costs nothing while unreachable.
; ============================================================================

OptionsPageSetTitle:
	db 1
	dw OptionsPageTitle

OptionsPageSetInGame:
	db 1
	dw OptionsPageInGame

; rows, box height, CANCEL Y, row table, prompt column, prompt
;
; Both pages share OptionsRows. The title screen declares 8 rows and so stops
; one short of CHEAT, which is the last entry in that table; its box is
; correspondingly shorter, ending just under B. STYLE.
OptionsPageTitle:
	optpage 8, 10, 15, OptionsRows, 0, 0
OptionsPageInGame:
	optpage 9, 12, 15, OptionsRows, 0, 0

; label, screen Y, value column, variable, mask, order, strings, count, hook
;
; Grouped, with a blank row between groups: on-screen extras, then text/audio
; presentation, then the two that change how a battle plays, then the cheat.
; A blank row between EVERY item does not fit - nine rows plus eight gaps plus
; two border rows is 19, and the screen holds 18.
;
; Value columns are OPT_VALUE_RIGHT + 1 minus the row's value width, so every
; value ends flush on column 18.
OptionsRows:
	optrow OptFollowerLabel,     1, 16, wOptions2, 1 << BIT_FOLLOWER_DISABLED, OptFollowerOrder,    OptOnOffValues,       2, 0
	optrow OptBattleAnimLabel,   2, 16, wOptions,  1 << BIT_BATTLE_ANIMATION,  OptBattleAnimOrder,  OptOnOffValues,       2, 0
	optrow OptColorLabel,        3, 16, wOptions2, 1 << BIT_ENHANCED_COLORS,   OptColorOrder,       OptOnOffValues,       2, 0
	optrow Opt60FPSLabel,        4, 16, wOptions2, 1 << BIT_60_FPS,            Opt60FPSOrder,       OptOnOffValues,       2, Opt60FPSHook
	optrow OptTextSpeedLabel,    6, 12, wOptions,  TEXT_DELAY_MASK,            OptTextSpeedOrder,   OptTextSpeedValues,   4, 0
	optrow OptAudioLabel,        7, 10, wOptions2, SOUND_MASK2,                OptAudioOrder,       OptAudioValues,       4, 0
	optrow OptDifficultyLabel,   9, 13, wOptions2, DIFFICULTY_MASK,            OptDifficultyOrder,  OptDifficultyValues,  5, 0
	optrow OptBattleStyleLabel, 10, 14, wOptions,  1 << BIT_BATTLE_SHIFT,      OptBattleStyleOrder, OptBattleStyleValues, 2, 0
; In-game only. The title page's descriptor declares 8 rows and stops above it.
	optrow_custom OptCheatLabel, 12, 9, OptDrawCheat, OptCycleCheat

; ----------------------------------------------------------------------------
; SHELVED SECOND PAGE. Kept as a worked example so a second page can come back
; without re-deriving the shape. To revive it:
;   1. uncomment OptionsPage2 and OptionsPage2Rows below, and the two prompt
;      strings at the end of this file;
;   2. give OptionsPageSetInGame a count of 2 and a second `dw OptionsPage2`;
;   3. set OptionsPageInGame's prompt column and pointer to 3 and
;      OptTextPage2Prompt, and move CHEAT's row out of OptionsRows if the page
;      is meant to hold it again (dropping OptionsPageInGame back to 8 rows).
; Column 3 centres a 14-character prompt across the 20-column screen.
;
; OptionsPage2:
;	optpage 1, 3, 15, OptionsPage2Rows, 3, OptTextPage1Prompt
;
; OptionsPage2Rows:
;	optrow_custom OptCheatLabel, 1, 9, OptDrawCheat, OptCycleCheat
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; Order tables. Each entry is a raw value already shifted into its row's mask.
; ----------------------------------------------------------------------------

; INSTANT is the step above FAST, not a row of its own, and is what InitOptions_
; now defaults to.
OptTextSpeedOrder:
	db TEXT_DELAY_INSTANT
	db TEXT_DELAY_FAST
	db TEXT_DELAY_MEDIUM
	db TEXT_DELAY_SLOW

; Both of these bits read inverted: the bit CLEAR is the "on" state.
OptBattleAnimOrder:
	db 0, 1 << BIT_BATTLE_ANIMATION
OptFollowerOrder:
	db 0, 1 << BIT_FOLLOWER_DISABLED

OptBattleStyleOrder:
	db 0, 1 << BIT_BATTLE_SHIFT
OptColorOrder:
	db 1 << BIT_ENHANCED_COLORS, 0
Opt60FPSOrder:
	db 1 << BIT_60_FPS, 0

OptAudioOrder:
	db 0 << 4, 1 << 4, 2 << 4, 3 << 4

; Display order, not stored order: DIFFICULTY_NORMAL is 0 because InitOptions
; defaults there, but it belongs in the middle of the ramp.
OptDifficultyOrder:
	db DIFFICULTY_VERY_EASY
	db DIFFICULTY_EASY
	db DIFFICULTY_NORMAL
	db DIFFICULTY_HARD
	db DIFFICULTY_VERY_HARD

; ----------------------------------------------------------------------------
; Value string tables, parallel to the order tables above.
; ----------------------------------------------------------------------------

OptTextSpeedValues:
	dw OptTextInstant
	dw OptTextFast
	dw OptTextMedium
	dw OptTextSlow

OptOnOffValues:
	dw OptTextOn
	dw OptTextOff

OptBattleStyleValues:
	dw OptTextShift
	dw OptTextSet

OptAudioValues:
	dw OptTextMono
	dw OptTextEarphone1
	dw OptTextEarphone2
	dw OptTextEarphone3

OptDifficultyValues:
	dw OptTextVeryEasy
	dw OptTextEasy
	dw OptTextNormal
	dw OptTextHard
	dw OptTextVeryHard

OptCheatValues::
	dw OptTextCheatKanto
	dw OptTextCheatJohto
	dw OptTextCheatWarp
	dw OptTextCheatBoth

; ----------------------------------------------------------------------------
; Labels. Each must end clear of its row's value column.
;
; BATTLE ANIMATION (16) and BATTLE STYLE (12) are abbreviated so their values
; fit beside them, and stay visibly paired. LEVELS is renamed DIFFICULTY, which
; is what the code has always called it (DIFFICULTY_MASK, DIFFICULTY_VERY_EASY
; and so on); the old display label was the outlier.
; ----------------------------------------------------------------------------

OptTextSpeedLabel:   db "TEXT SPD@"
OptBattleAnimLabel:  db "B. ANIM.@"
OptBattleStyleLabel: db "B. STYLE@"
OptAudioLabel:       db "AUDIO@"
OptDifficultyLabel:  db "DIFFICULTY@"
OptFollowerLabel:    db "FOLLOWER@"
OptColorLabel:       db "ENH COLOR@"
Opt60FPSLabel:       db "60 FPS@"
OptCheatLabel:       db "CHEAT@"

; ----------------------------------------------------------------------------
; Values. Every string in one table is padded to the same width, on the LEFT,
; so the values right-align on column OPT_VALUE_RIGHT and a short value still
; fully overwrites a longer one.
; ----------------------------------------------------------------------------

; width 7, column 12
OptTextInstant:   db "INSTANT@"
OptTextFast:      db "   FAST@"
OptTextMedium:    db " MEDIUM@"
OptTextSlow:      db "   SLOW@"

; width 3, column 16
OptTextOn:        db " ON@"
OptTextOff:       db "OFF@"

; width 5, column 14
OptTextShift:     db "SHIFT@"
OptTextSet:       db "  SET@"

; width 9, column 10
OptTextMono:      db "     MONO@"
OptTextEarphone1: db "EARPHONE1@"
OptTextEarphone2: db "EARPHONE2@"
OptTextEarphone3: db "EARPHONE3@"

; width 6, column 13. DIFFICULTY is 10 characters, and with the label at column
; 2 that leaves exactly 7 columns
; before the border, so the two extremes are abbreviated.
OptTextVeryEasy:  db "V.EASY@"
OptTextEasy:      db "  EASY@"
OptTextNormal:    db "NORMAL@"
OptTextHard:      db "  HARD@"
OptTextVeryHard:  db "V.HARD@"

; width 10, column 9. "WARP+JOHTO" would read better, but '+' is not in the
; charmap (constants/charmap.asm).
OptTextCheatKanto: db "     KANTO@"
OptTextCheatJohto: db "     JOHTO@"
OptTextCheatWarp:  db " TIME WARP@"
OptTextCheatBoth:  db "WARP/JOHTO@"

OptTextCancel: db "CANCEL@"

; Shelved with the second page above. 14 characters, centred at column 3.
; OptTextPage2Prompt: db "SELECT: PAGE 2@"
; OptTextPage1Prompt: db "SELECT: PAGE 1@"
