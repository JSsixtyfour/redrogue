; custom_functions/element_prism.asm
;
; ELEMENT PRISM (see KEY_ITEM_EFFECTS_PLAN_PC.md §3i). Granted by the first
; gym leader defeated, never sold. The player picks its type by using it from
; the bag; the choice lives in sElementPrismType (SRAM, so it survives run
; reset and blackout like key-item ownership). Its tier is key item index 14
; in sKeyItemTiers and is bought from the Credit Exchange upgrade vendor like
; every other key item.
;
; Two effects:
;   1. Damage: player-turn moves of the prism's type deal +10/15/20% (by tier).
;   2. Encounter bias: a rolled species whose types both differ from the
;      prism's is discarded and re-rolled (1 extra attempt normally, 16
;      during starter selection so "all starters are that type" is effectively
;      guaranteed).
;
; CACHE DISCIPLINE - the one subtle thing in this file. The damage hook runs
; on every damaging hit, so it reads two WRAM caches (wPrismType /
; wPrismDamageBonus) refreshed once per battle by RoguePrismRefreshCache.
; The encounter-bias hook does NOT use those caches: reward/starter rolls
; happen in the reward room and Oak's Lab, where no battle has necessarily
; started yet, so the caches can be stale or (on a fresh file) still zero -
; and zero is a VALID type constant (NORMAL), which would silently bias every
; roll toward Normal-types. It resolves ownership and type fresh from SRAM
; instead via RoguePrismGetTypeFresh; that path is cold (a few times per
; stage), so the SRAM round trip costs nothing that matters.

; ============================================================
; RogueGymLeaderVictory — replaces the plain `farcall RogueAwardCredits2` in
; TrainerBattleVictory's gym-leader branch (engine/battle/core.asm). Costs
; that call site zero extra bytes: same 8-byte farcall, different target.
; Deliberately NOT folded into RogueAwardCredits2 itself, which the Elite
; Four room scripts also call - the prism is a gym-leader grant only.
;
; The prism/cartridge grant itself is silent (no text box): this fires
; between `inc wBattleCount` and the "TrainerDefeated"/money messages, and
; printing there would cut in front of the normal victory sequence. The
; one-time messages below print AFTER the grant instead, which is what makes
; them safe to add without touching that ordering.
; CLOBBERS: af, bc, de, hl
; ============================================================
RogueGymLeaderVictory::
	call RogueAwardCredits2       ; same bank (custom_functions/credit_award.asm)

	ld a, [wGymLeaderNo]
	and a
	ret z                         ; defensive: not actually a gym leader
	cp 9
	ret nc                        ; out of table range (1-8 valid)

	call RogueGetGymLeaderType    ; a = this leader's type
	call RoguePrismGrantCartridge

	ld a, ELEMENT_PRISM
	ld [wCurItem], a
	call IsKeyItemOwned           ; same bank; Z = not owned yet
	jr nz, .alreadyHadPrism

	; First-ever grant: hand over the prism itself and equip this leader's
	; cartridge, so it is never granted in a useless state. Always shows a
	; message here - owning nothing before this call IS "first time", so
	; there is no separate "already shown" event to check for this branch.
	call RogueGetGymLeaderType
	ld c, a
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ASSERT BANK("Save Data") == 1
	ld a, 1
	ld [rRAMB], a       ; select bank 1 explicitly; ambient bank is unreliable
	ld a, c
	ld [sElementPrismType], a     ; equip it immediately
	xor a
	ld [rRAMG], a                 ; never leave SRAM enabled across a return
	call RoguePrismRefreshCache   ; make the equipped type live this battle
	ld b, ELEMENT_PRISM
	ld c, 1
	call GiveItem
	call RogueGetGymLeaderType
	jp RoguePrismShowFirstGrantMessage ; tail call; a = type

.alreadyHadPrism
	; Not the first leader - only show a message the first time THIS leader's
	; own cartridge is granted. EVENT_PRISM_GYM1_SHOWN..GYM8_SHOWN are
	; contiguous in wGymLeaderNo order (see event_constants.asm), so the
	; right one is computed at runtime rather than needing 8 separate
	; compile-time CheckEvent/SetEvent call sites. This event number is
	; ~2600+, so it travels in de (a 16-bit add), never a - NUM_EVENTS is
	; thousands, so it does not fit an 8-bit register or an 8-bit `add a, n`.
	ld a, [wGymLeaderNo]
	dec a
	ld e, a
	ld d, 0
	ld hl, EVENT_PRISM_GYM1_SHOWN
	add hl, de
	ld d, h
	ld e, l                        ; de = this leader's event number
	call RoguePrismCheckAndSetEvent ; Z = first time this leader's message fires
	ret nz
	call RogueGetGymLeaderType
	jp RoguePrismShowCartridgeMessage  ; tail call; a = type

; wGymLeaderNo (1-8) -> a = signature type. Order is badge order, matching
; the `ld a, $N / ld [wGymLeaderNo], a` in each gym script.
RogueGetGymLeaderType:
	ld a, [wGymLeaderNo]
	dec a
	ld hl, GymLeaderCartridgeTable
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hl]
	ret

GymLeaderCartridgeTable:
	db ROCK          ; 1 Brock
	db WATER         ; 2 Misty
	db ELECTRIC      ; 3 Lt. Surge
	db GRASS         ; 4 Erika
	db POISON        ; 5 Koga
	db PSYCHIC_TYPE  ; 6 Sabrina
	db FIRE          ; 7 Blaine
	db GROUND        ; 8 Giovanni

; ============================================================
; Elite Four / Champion cartridge grants. Separate entry points per type
; rather than one parameterised routine because `farcall` clobbers `a` via
; Bankswitch's first instruction, so a caller cannot pass the type in a -
; the same reason RogueAwardCredits1/2/3 exist as three entry points.
; Called from each room's end-battle script alongside its credit award.
;
; The prism is always already owned by the time any of these fire - all 8
; badges (all 8 gym leaders) are required before the Elite Four is reachable
; (see the final-sequence badge gate) - so unlike RogueGymLeaderVictory these
; never need to grant the prism itself, only the cartridge, each gated by its
; own one-time event.
; ============================================================
RogueGrantCartridgeIce::
	ld de, EVENT_PRISM_E4_ICE_SHOWN
	ld a, ICE
	jr RoguePrismGrantAndAnnounce
RogueGrantCartridgeFighting::
	ld de, EVENT_PRISM_E4_FIGHTING_SHOWN
	ld a, FIGHTING
	jr RoguePrismGrantAndAnnounce
RogueGrantCartridgeGhost::
	ld de, EVENT_PRISM_E4_GHOST_SHOWN
	ld a, GHOST
	jr RoguePrismGrantAndAnnounce
RogueGrantCartridgeDragon::
	ld de, EVENT_PRISM_E4_DRAGON_SHOWN
	ld a, DRAGON
	; fall through

; INPUT: a = type, de = this grantor's one-time event number.
; Checks the event BEFORE granting, specifically so the type (only live in a)
; never needs to survive a clobbering call while ALSO holding the event
; number - each stage's input is consumed before the next stage runs.
RoguePrismGrantAndAnnounce:
	push af                       ; save type across the check call (clobbers af too)
	call RoguePrismCheckAndSetEvent ; Z = first time; clobbers af/bc/de/hl
	jr z, .firstTime
	pop af                        ; not first time - discard the saved type, balance the stack
	ret
.firstTime
	pop af                        ; a = type again
	push af                       ; re-save it - RoguePrismGrantCartridge clobbers af too
	call RoguePrismGrantCartridge
	pop af                        ; a = type, restored
	jp RoguePrismShowCartridgeMessage ; tail call

; Champion covers the three types no gym leader or Elite Four member owns
; (provisional - if these later get their own owners, drop them from here).
; One shared event and one combined message, not per-type, since all three
; are always granted together.
RogueChampionCartridges::
	ld de, EVENT_PRISM_CHAMPION_SHOWN
	call RoguePrismCheckAndSetEvent ; Z = first time; clobbers af/bc/de/hl
	push af                       ; save the result across the three grants below
	ld a, NORMAL
	call RoguePrismGrantCartridge
	ld a, FLYING
	call RoguePrismGrantCartridge
	ld a, BUG
	call RoguePrismGrantCartridge
	pop af
	ret nz                        ; not first time - grants above are idempotent, stay silent
	ld hl, PrismChampionGrantText
	jp PrintText

; ============================================================
; RoguePrismCheckAndSetEvent — test-and-set a wEventFlags bit given a
; RUNTIME event number, unlike the CheckEvent/SetEvent macros (which need a
; compile-time constant, since they fold the byte/bit split into DEF
; arithmetic at assemble time - see macros/scripts/events.asm). Needed here
; because RogueGymLeaderVictory picks one of 8 events at runtime rather than
; having 8 separate compile-time call sites.
;
; The event number travels in de, a 16-bit register pair, NOT a. NUM_EVENTS
; is in the thousands (2623 as of this addition), so it does not fit an
; 8-bit register - an earlier version of this file tried to pass it in a/b
; and add it with 8-bit `add`, which rgbasm correctly flagged as truncating
; a value that does not fit.
; INPUT:  de = event number (0 to NUM_EVENTS-1)
; OUTPUT: Z set = this is the first time (bit was 0, now set to 1)
;         Z clear (NZ) = already shown before (bit was already 1)
; CLOBBERS: af, bc, de, hl
; ============================================================
RoguePrismCheckAndSetEvent:
	ld a, e
	and 7
	ld c, a                        ; c = bit position 0-7
	srl d
	rr e
	srl d
	rr e
	srl d
	rr e                            ; de >>= 3 (16-bit shift; de = byte offset)
	ld hl, wEventFlags
	add hl, de
	ld a, 1
	ld b, c
	inc b
.shift
	dec b
	jr z, .gotMask
	rlca
	jr .shift
.gotMask
	ld c, a                       ; c = mask
	ld a, [hl]
	and c                         ; Z reflects the bit's state BEFORE this call
	push af
	ld a, [hl]
	or c
	ld [hl], a                    ; set it unconditionally
	pop af
	ret

; ============================================================
; RoguePrismShowFirstGrantMessage / RoguePrismShowCartridgeMessage — print
; the appropriate one-time leader/E4 message. Both take the granted type in
; a and copy its name into wStringBuffer for text_ram
; (_PrismFirstGrantText / _PrismCartridgeGrantText both read it there).
; INPUT: a = type constant (always one already in PrismTypeList - every
;        caller here passes a hardcoded valid type, so PrismTypeToIndex's
;        "not found" case is not defended against)
; CLOBBERS: af, bc, de, hl
; ============================================================
RoguePrismShowFirstGrantMessage::
	call RoguePrismCopyTypeName
	ld hl, PrismFirstGrantText
	jp PrintText

RoguePrismShowCartridgeMessage::
	call RoguePrismCopyTypeName
	ld hl, PrismCartridgeGrantText
	jp PrintText

; INPUT: a = type constant. Copies its name into wStringBuffer.
RoguePrismCopyTypeName:
	call PrismTypeToIndex          ; a = index
	call PrismIndexToNamePtr       ; hl = name string
	ld de, wStringBuffer
	jp PrismCopyName               ; tail call

PrismFirstGrantText:
	text_far _PrismFirstGrantText
	text_end

PrismCartridgeGrantText:
	text_far _PrismCartridgeGrantText
	text_end

PrismChampionGrantText:
	text_far _PrismChampionGrantText
	text_end

; ============================================================
; RoguePrismGrantCartridge — unlock the cartridge for the type in a.
; Idempotent: re-beating a leader simply re-sets a bit that is already set.
; INPUT: a = type constant
; CLOBBERS: af, bc, de, hl
; ============================================================
RoguePrismGrantCartridge::
	call PrismTypeToIndex         ; a = 0-14, or carry clear if not selectable
	ret nc
	; bit index -> byte offset + mask
	ld c, a
	and 7
	ld b, a
	ld a, c
	srl a
	srl a
	srl a                         ; a = byte offset (0 or 1)
	ld e, a
	ld d, 0
	ld hl, sPrismCartridges
	add hl, de
	ld a, 1
	inc b
.shift
	dec b
	jr z, .gotMask
	rlca
	jr .shift
.gotMask
	ld b, a                       ; b = mask
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ASSERT BANK("Save Data") == 1
	ld a, 1
	ld [rRAMB], a       ; select bank 1 explicitly; ambient bank is unreliable
	ld a, [hl]
	or b
	ld [hl], a
	xor a
	ld [rRAMG], a                 ; never leave SRAM enabled across a return
	ret

; ============================================================
; PrismTypeToIndex — type constant -> its position in PrismTypeList (0-14).
; Needed because type constants are not contiguous (0-8 then 20-26), so they
; cannot index a 15-bit field directly.
; INPUT:  a = type constant
; OUTPUT: carry set + a = index, or carry clear if the type is not selectable
; CLOBBERS: af, bc, hl
; ============================================================
PrismTypeToIndex::
	ld c, a
	ld b, 0
	ld hl, PrismTypeList
.scan
	ld a, [hl]
	cp c
	jr z, .found
	inc hl
	inc b
	ld a, b
	cp PRISM_TYPE_COUNT
	jr c, .scan
	and a                         ; carry clear = not a selectable type
	ret
.found
	ld a, b
	scf
	ret

; ============================================================
; PrismHasCartridge — is the type at index a unlocked?
; INPUT:  a = index (0-14)
; OUTPUT: Z set = locked, Z clear (NZ) = unlocked
; CLOBBERS: af, bc, de, hl
; ============================================================
PrismHasCartridge::
	ld c, a
	and 7
	ld b, a
	ld a, c
	srl a
	srl a
	srl a
	ld e, a
	ld d, 0
	ld hl, sPrismCartridges
	add hl, de
	ld a, 1
	inc b
.shift
	dec b
	jr z, .gotMask
	rlca
	jr .shift
.gotMask
	ld c, a                       ; c = mask
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ASSERT BANK("Save Data") == 1
	ld a, 1
	ld [rRAMB], a       ; select bank 1 explicitly; ambient bank is unreliable
	ld a, [hl]
	and c
	ld b, a
	xor a
	ld [rRAMG], a
	ld a, b
	and a
	ret

; ============================================================
; RoguePrismGetTypeFresh — resolve the prism's active type with no reliance
; on the WRAM caches (see CACHE DISCIPLINE above).
; OUTPUT: a = type constant, or $ff if the prism is not active or its type
;         has not been chosen yet.
; CLOBBERS: af, bc, de, hl
; ============================================================
RoguePrismGetTypeFresh::
	; wCurItem IS wCurPartySpecies (one byte, three labels - see ram/wram.asm).
	; Preserve it across the key-item lookup: callers may have a live species in
	; it, and clobbering it corrupted the battle intro's enemy pic. See the
	; comment on RoguePrismRefreshCache below for the full failure mode.
	ld a, [wCurPartySpecies]
	push af
	ld a, ELEMENT_PRISM
	ld [wCurItem], a
	call GetKeyItemPower          ; same bank; 0 = not active
	and a
	jr z, .none
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ASSERT BANK("Save Data") == 1
	ld a, 1
	ld [rRAMB], a       ; select bank 1 explicitly; ambient bank is unreliable
	ld a, [sElementPrismType]
	ld c, a
	xor a
	ld [rRAMG], a                 ; never leave SRAM enabled across a return
	pop af
	ld [wCurPartySpecies], a      ; restore the aliased byte
	ld a, c
	ret
.none
	; must also restore here - this path is taken whenever the prism is inactive,
	; i.e. the common case, and leaving the push unbalanced would corrupt the stack
	pop af
	ld [wCurPartySpecies], a
	ld a, $ff
	ret

; ============================================================
; RoguePrismRefreshCache — farcalled once per battle from
; InitBattleVariables (engine/battle/init_battle_variables.asm). Resolves
; the two hot-path caches the damage hook reads. Also called after an
; upgrade purchase so a new tier applies immediately (see
; ApplyKeyItemTierEffects, engine/events/credit_mart.asm).
;
; wPrismDamageBonus = 0 is the "skip entirely" sentinel, so the damage hook's
; common case is one load and a conditional return.
; CLOBBERS: af, bc, de, hl
;
; MUST NOT clobber wCurPartySpecies. wCurItem aliases it (one byte, three labels
; in ram/wram.asm), and this routine runs at EVERY battle start, at a point where
; wCurPartySpecies still holds the species whose front pic is about to be drawn.
; The pic load reads TWO different variables: GetMonHeader (home/pokemon.asm) uses
; wCurSpecies for the pic POINTER, while UncompressMonSprite (home/pics.asm) uses
; wCurPartySpecies to pick the pic BANK. Leaving ELEMENT_PRISM ($70) in it made
; every wild battle draw the correct pic offset out of BANK("Pics 3"), which is
; garbage for any species not genuinely in that bank - the intermittent scrambled
; wild-mon sprite (a species that really does live in Pics 3 rendered fine, which
; is what made it look random). Hence the save/restore wrapper below.
; ============================================================
RoguePrismRefreshCache::
	ld a, [wCurPartySpecies]
	push af
	call .body
	pop af
	ld [wCurPartySpecies], a
	ret
.body
	xor a
	ld [wPrismDamageBonus], a
	ld a, $ff
	ld [wPrismType], a

	ld a, ELEMENT_PRISM
	ld [wCurItem], a
	call GetKeyItemPower          ; a = 0 (not active) or 1-3 (displayed tier)
	and a
	ret z
	dec a
	ld hl, .BonusTable
	ld e, a
	ld d, 0
	add hl, de
	ld b, [hl]                    ; b = percent bonus for this tier

	call RoguePrismGetTypeFresh   ; a = chosen type, or $ff
	cp $ff
	ret z                         ; owned but no type picked yet - stays disabled
	ld [wPrismType], a
	ld a, b
	ld [wPrismDamageBonus], a
	ret

.BonusTable:
	db 10, 15, 20

; ============================================================
; RoguePrismDamageBoost — farcalled from the `.done` exit of
; AdjustDamageForMoveType (engine/battle/core.asm). Scales wDamage by
; (100 + bonus)/100 when the player's move matches the prism's type.
;
; Placed at `.done` rather than the two call sites (one hook instead of two)
; and safe there because both callers follow immediately with
; `call RandomizeDamage`, which takes no register inputs - nothing of theirs
; is live across the return, which matters because farcall itself destroys
; b/h/l before the callee even runs.
;
; The wDamage read/multiply/write below deliberately mirrors the existing
; type-multiplier block a few lines above it in that same routine, including
; the `ld a, [hld]` / `ld [hli], a` cursor trick, rather than inventing a
; second idiom for the same job.
; CLOBBERS: af, bc, de, hl
; ============================================================
RoguePrismDamageBoost::
	ldh a, [hWhoseTurn]
	and a
	ret nz                        ; enemy turn - this is a player-only boost
	ld a, [wPrismDamageBonus]
	and a
	ret z                         ; prism inactive / no type chosen
	ld b, a                       ; b = percent bonus
	ld a, [wPrismType]
	ld c, a
	ld a, [wMoveType]
	cp c
	ret nz                        ; move type is not the prism's type

	ld a, 100
	add b
	ldh [hMultiplier], a          ; multiplier = 100 + bonus
	xor a
	ldh [hMultiplicand], a
	ld hl, wDamage
	ld a, [hli]
	ldh [hMultiplicand + 1], a
	ld a, [hld]
	ldh [hMultiplicand + 2], a
	call Multiply
	ld a, 100
	ldh [hDivisor], a
	ld b, 4
	call Divide
	ldh a, [hQuotient + 2]
	ld [hli], a
	ldh a, [hQuotient + 3]
	ld [hl], a
	ret

; ============================================================
; RoguePrismSetRerollBudget — called at the top of Random_Pokemon_Selection
; (engine/pokemon/random_pokemon_selection.asm, same bank). Sets how many
; type-mismatch re-rolls this selection may spend.
;
; Preserves EVERY register: the very next thing its caller does is `ld a, 1 /
; cp c` on the class argument in c, so clobbering c would silently change
; which rarity class gets rolled.
; ============================================================
RoguePrismSetRerollBudget::
	push af
	push bc
	push de
	push hl
	CheckEvent EVENT_GOT_STARTER
	ld a, 16                      ; starter selection - effectively guarantee the type
	jr z, .gotBudget              ; Z = event NOT set = starter not chosen yet
	ld a, 1                       ; normal reward roll - a single extra attempt
.gotBudget
	ld [wPrismRerollsLeft], a
	pop hl
	pop de
	pop bc
	pop af
	ret

; ============================================================
; RoguePrismShouldRerollSpecies — called from Random_Pokemon_Selection once a
; species has passed the existing AllSpeciesCheck.
; INPUT:  d = candidate species
; OUTPUT: Z set = keep it, Z clear (NZ) = discard and re-roll (budget spent)
;         d preserved.
; CLOBBERS: af, bc, e, hl  (d preserved; the caller's hl is saved by the
;           caller, since it holds the class-selection retry address)
; ============================================================
RoguePrismShouldRerollSpecies::
	ld a, [wPrismRerollsLeft]
	and a
	jr z, .keep                   ; budget exhausted - accept whatever we rolled
	push de
	call RoguePrismGetTypeFresh   ; a = prism type, or $ff (clobbers de)
	pop de
	cp $ff
	jr z, .keep                   ; prism not active / no type chosen

	ld b, a                       ; b = prism type
	push de
	ld a, d
	ld [wCurSpecies], a
	call GetMonHeader             ; HOME; fills wMonHTypes for this species
	pop de
	ld a, [wMonHType1]
	cp b
	jr z, .keep
	ld a, [wMonHType2]
	cp b
	jr z, .keep

	ld hl, wPrismRerollsLeft      ; mismatch - spend one attempt and re-roll
	dec [hl]
	ld a, 1
	and a                         ; NZ
	ret
.keep
	xor a                         ; Z
	ret

; ============================================================
; RoguePrismCartridgeMenu — farcalled from the Player PC's CARTRIDGE option
; (engine/menus/players_pc.asm). Lists only the cartridges the player has
; actually unlocked and equips the chosen one.
;
; Built from TextBoxBorder + PlaceString + HandleMenuInput, the same shape
; RogueRewardMenu uses, rather than a new LISTMENU id: adding a list-menu id
; would mean auditing every `cp <LISTMENU>` site in the codebase, and missing
; one is exactly the bug that made the Credit Exchange upgrade vendor show
; "TIER 2" on every row.
;
; The type names are shipped locally rather than read from TypeNames
; (data/types/names.asm) because that table lives in bank $09, a different
; bank from this one - reading it would need a bankswitch inside the draw
; loop for no benefit.
;
; The listed subset is RECOMPUTED (PrismCountCartridges /
; PrismNthCartridgeIndex) rather than cached in a buffer. An index map would
; have needed 16 bytes of WRAM0, which does not exist - and recomputing over
; 15 bits in a menu that only redraws on open costs nothing measurable.
; ============================================================
RoguePrismCartridgeMenu::
	; Nothing unlocked yet? Say so - a zero-row TextBoxBorder is malformed.
	call PrismCountCartridges
	and a
	jr nz, .haveCartridges
	ld hl, PrismNoCartridgesText
	jp PrintText

.haveCartridges
	call SaveScreenTilesToBuffer2

	call PrismCountCartridges
	hlcoord 0, 0
	ld b, a                       ; interior rows: one per UNLOCKED cartridge
	ld c, 10                      ; interior cols: fits "FIGHTING"/"ELECTRIC" at x=2
	call TextBoxBorder

	hlcoord 2, 1                  ; hl = screen cursor, advanced a row per entry
	ld c, 0                       ; c = type index under test
.drawLoop
	ld a, c
	push bc
	push hl
	call PrismHasCartridge        ; NZ = unlocked (clobbers everything)
	pop hl
	pop bc
	jr z, .drawNext
	push bc                       ; save index counter
	push hl                       ; save screen pos across the name lookup
	ld a, c
	call PrismIndexToNamePtr      ; hl = name string (clobbers b)
	ld d, h
	ld e, l                       ; de = string for PlaceString
	pop hl                        ; hl = screen pos again
	call PlaceString              ; preserves hl (pushes/pops it internally)
	ld bc, SCREEN_WIDTH
	add hl, bc                    ; next row
	pop bc                        ; restore index counter
.drawNext
	inc c
	ld a, c
	cp PRISM_TYPE_COUNT
	jr c, .drawLoop

	xor a
	ldh [hCurrentMenuItem], a
	ld [wLastMenuItem], a
	ld a, PAD_A | PAD_B | PAD_UP | PAD_DOWN
	ld [wMenuWatchedKeys], a
	call PrismCountCartridges
	dec a
	ld [wMaxMenuItem], a
	ld a, 1
	ld [wTopMenuItemY], a
	ld a, 1
	ld [wTopMenuItemX], a
	call HandleMenuInput
	bit B_PAD_B, a
	jr nz, .cancelled

	; cursor row -> nth unlocked index -> type constant
	ldh a, [hCurrentMenuItem]
	call PrismNthCartridgeIndex   ; a = type index
	ld hl, PrismTypeList
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hl]                    ; a = type constant
	ld b, a

	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ASSERT BANK("Save Data") == 1
	ld a, 1
	ld [rRAMB], a       ; select bank 1 explicitly; ambient bank is unreliable
	ld a, b
	ld [sElementPrismType], a
	xor a
	ld [rRAMG], a                 ; never leave SRAM enabled across a return

	call LoadScreenTilesFromBuffer2 ; put the PC screen back before confirming
	call RoguePrismRefreshCache   ; new type applies immediately, not next battle
	ld hl, ElementPrismSetText
	jp PrintText

.cancelled
	call LoadScreenTilesFromBuffer2
	ret

; ============================================================
; RoguePrismShowEquipped — farcalled from ItemUseElementPrism. Read-only:
; swapping happens at the PC, so using the prism from the bag just reports
; which cartridge is installed. The name is copied into wStringBuffer for the
; text_ram field in _ElementPrismStatusText.
; CLOBBERS: af, bc, de, hl
; ============================================================
RoguePrismShowEquipped::
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ASSERT BANK("Save Data") == 1
	ld a, 1
	ld [rRAMB], a       ; select bank 1 explicitly; ambient bank is unreliable
	ld a, [sElementPrismType]
	ld b, a
	xor a
	ld [rRAMG], a
	ld a, b
	cp $ff
	jr z, .none
	call PrismTypeToIndex
	jr nc, .none                  ; stored a type that is not selectable
	call PrismIndexToNamePtr      ; hl = name string
	ld de, wStringBuffer
	call PrismCopyName
	ld hl, ElementPrismStatusText
	jp PrintText
.none
	ld hl, PrismNoCartridgesText
	jp PrintText

; hl = source string (ends '@'), de = dest. Copies including the terminator.
PrismCopyName:
	ld a, [hli]
	ld [de], a
	inc de
	cp '@'
	jr nz, PrismCopyName
	ret

; ============================================================
; PrismCountCartridges — how many cartridges are unlocked (0-15).
; OUTPUT: a = count.  CLOBBERS: af, de, hl (bc preserved)
; ============================================================
PrismCountCartridges:
	push bc
	ld b, 0                       ; b = running count
	ld c, 0                       ; c = index under test
.loop
	ld a, c
	push bc
	call PrismHasCartridge
	pop bc
	jr z, .next
	inc b
.next
	inc c
	ld a, c
	cp PRISM_TYPE_COUNT
	jr c, .loop
	ld a, b                       ; read out BEFORE the pop restores bc
	pop bc
	ret

; ============================================================
; PrismNthCartridgeIndex — turn a menu row into a type index by walking the
; unlocked set again, which is what lets the menu list an arbitrary subset
; without storing an index map.
; INPUT:  a = n (0-based menu row)
; OUTPUT: a = type index (0-14) of the nth unlocked cartridge
; CLOBBERS: af, de, hl (bc preserved)
; ============================================================
PrismNthCartridgeIndex:
	push bc
	ld b, a                       ; b = how many unlocked entries still to skip
	ld c, 0                       ; c = index under test
.loop
	ld a, c
	push bc
	call PrismHasCartridge
	pop bc
	jr z, .next
	ld a, b
	and a
	jr z, .found
	dec b
.next
	inc c
	ld a, c
	cp PRISM_TYPE_COUNT
	jr c, .loop
	ld c, 0                       ; defensive: should be unreachable
.found
	ld a, c                       ; read out BEFORE the pop restores bc
	pop bc
	ret

; ============================================================
; PrismIndexToNamePtr — index (0-14) -> pointer to its name string.
; PrismTypeNames is variable-length, so this walks it rather than indexing.
; INPUT:  a = index
; OUTPUT: hl = name string
; CLOBBERS: af, b, hl
; ============================================================
PrismIndexToNamePtr:
	ld b, a
	ld hl, PrismTypeNames
	inc b
.walk
	dec b
	ret z
.skip
	ld a, [hli]
	cp '@'
	jr nz, .skip
	jr .walk

ElementPrismSetText:
	text_far _ElementPrismSetText
	text_end

ElementPrismStatusText:
	text_far _ElementPrismStatusText
	text_end

PrismNoCartridgesText:
	text_far _PrismNoCartridgesText
	text_end

; The 15 selectable types, in menu order. BIRD and the UNUSED_TYPES block are
; deliberately excluded - they are not real, obtainable types.
PrismTypeList:
	db NORMAL, FIGHTING, FLYING, POISON, GROUND, ROCK, BUG, GHOST
	db FIRE, WATER, GRASS, ELECTRIC, PSYCHIC_TYPE, ICE, DRAGON
DEF PRISM_TYPE_COUNT EQU 15

; Must stay in the same order as PrismTypeList above - the menu draws these
; sequentially and indexes that table by cursor position.
PrismTypeNames:
	db "NORMAL@"
	db "FIGHTING@"
	db "FLYING@"
	db "POISON@"
	db "GROUND@"
	db "ROCK@"
	db "BUG@"
	db "GHOST@"
	db "FIRE@"
	db "WATER@"
	db "GRASS@"
	db "ELECTRIC@"
	db "PSYCHIC@"
	db "ICE@"
	db "DRAGON@"
