; Species Groups Phase 2R - form override lookup.
;
; MUST live in BANK(BaseStats). GetMonHeader has already switched to that bank
; when it calls this, so the call is a plain in-bank `call` with no bankswitch
; and no farcall register laundering. home/pokemon.asm carries a link-time
; ASSERT tying the two banks together, so a future relocation of either one is a
; build error rather than a silent cross-bank read of garbage - this project has
; hit that exact class of bug seven times (see the cross-bank-call memory).
;
; Keeping the whole lookup here rather than in HOME costs ROM0 exactly THREE
; bytes (the `call`), which matters: HOME has 113 bytes free.

; ---------------------------------------------------------------------------
; ApplyFormOverride
;
; Patches wMonHeader with a form's own base-stats row, if the pending form
; context applies to the species GetMonHeader just loaded.
;
; INPUT:
;   wCurSpecies           = species whose row was just copied into wMonHeader
;   wFormContextSpecies   = species the pending context applies to, 0 = none
;   wFormContextForm      = form index 1..NUM_FORM_SLOTS, 0 = base species
; OUTPUT:
;   wMonHForm             = the form actually applied (0 if none)
;   wMonHeader            = patched when a form applied, untouched otherwise
; CLOBBERS: af, bc, de, hl
;   Safe at the only call site: GetMonHeader pushes bc/de/hl on entry and pops
;   them after this returns, and reloads `a` from wCurSpecies on the next line.
;
; CONSUMES THE CONTEXT unconditionally - see the wram.asm comment on
; wFormContextSpecies for why zeroing on read is load-bearing rather than tidy.
; The consume happens BEFORE the species compare on purpose: a context that
; turns out not to match must still be cleared, or it would survive to ambush a
; later lookup of the species it does match.
;
; CONTRACT FOR CALLERS: set the context immediately before EACH GetMonHeader
; call. A caller that sets it once and calls twice gets the form only the first
; time. func_fusion.asm calls GetMonHeader repeatedly but writes its own species
; each time, so it is unaffected.
; ---------------------------------------------------------------------------
ApplyFormOverride::
	ld a, [wFormContextSpecies]
	and a
	jr nz, .haveContext

; ---- No context pending. Is this a RELOAD of the header we already hold? ----
; Measured 2026-09-09: several routines reload wMonHeader from the species it
; already describes, WITHOUT publishing a context, purely to refresh it -
; PrintMonType (engine/battle/print_type.asm:6, reached from the status screen
; BEFORE the sprite is drawn) and five sites in status_view.asm/status_screen.asm
; that re-derive wCurSpecies from wMonHIndex. Every one of them would silently
; strip a form: the status screen applied Alolan Meowth's row, then PrintMonType
; overwrote it with vanilla Meowth's, and the sprite drew from the vanilla
; pointers. The form context was provably correct at this routine's entry; it had
; simply already been consumed.
;
; Fixing that HERE rather than at each call site kills all six at once and, more
; importantly, is immune to the seventh nobody has found yet.
;
; The test is exact, not a heuristic: GetMonHeader writes wMonHIndex AFTER this
; routine returns, so wMonHIndex still names the species the CURRENT wMonHeader
; was built for. wCurSpecies == wMonHIndex therefore means "same species, loaded
; again", which is precisely a refresh - and the form it carried is still in
; wMonHForm.
;
; This cannot mis-fire on two same-species mons in a row (an Alolan Meowth in
; slot 4 and a vanilla one in slot 5): every real per-mon load goes through
; LoadMonData_, which ALWAYS publishes a context - form 0 included - so those
; take the .haveContext path and never reach this code.
; ⚠ Compare against wMonHFormSpecies, NEVER wMonHIndex. wMonHIndex is
; wMonHeader + 0 - literally the same byte - and GetMonHeader's base-stats
; CopyData has already overwritten it with the ROM row's BASE_DEX_NO by the time
; this routine runs; the species index is written back only AFTER we return. An
; earlier version of this guard used wMonHIndex and compared $33 (Dugtrio's dex)
; against $76 (its species index), so it never once fired. See wram.asm.
	ld a, [wCurSpecies]
	ld hl, wMonHFormSpecies
	cp [hl]
	jr nz, .noForm               ; different species: a genuine fresh load
	ld a, [wMonHForm]
	and a
	jr z, .noForm                ; the held header had no form either
	ld c, a                      ; re-apply the same form
	ld a, [wCurSpecies]
	ld b, a
	jr .lookup

.noForm
	xor a
	ld [wMonHForm], a
	ld [wMonHFormSpecies], a
	ret

.haveContext
	ld b, a                      ; b = context species
	xor a
	ld [wFormContextSpecies], a  ; consume, unconditionally
	ld [wMonHForm], a            ; and default this header to "no form"
	ld [wMonHFormSpecies], a     ; keep the pair consistent - .found resets both

	ld a, [wCurSpecies]
	cp b
	ret nz                       ; context was for a different species

	ld a, [wFormContextForm]
	and a
	ret z                        ; form 0 is the base species: nothing to patch
	ld c, a                      ; c = wanted form index

.lookup
	ld hl, FormOverrides
.loop
	ld a, [hl]                   ; record's base species
	and a
	jr z, .noForm                ; end of table, no match. Routed through .noForm
	                             ; rather than a bare `ret` so the re-apply path
	                             ; above cannot leave wMonHForm claiming a form
	                             ; that was never actually copied in.
	cp b
	jr nz, .next
	inc hl
	ld a, [hl]                   ; record's form index
	dec hl
	cp c
	jr z, .found
.next
	ld de, FORM_REC_SIZE
	add hl, de
	jr .loop

.found
	ld a, c
	ld [wMonHForm], a
	ld a, b
	ld [wMonHFormSpecies], a     ; remember WHICH species this form belongs to,
	                             ; so a later refresh can recognise itself
	ld de, FORM_REC_DATA         ; skip the 2-byte key
	add hl, de
	ld de, wMonHeader
	ld bc, BASE_DATA_SIZE
	jp CopyData                  ; HOME, always mapped; its ret returns to GetMonHeader

; ---------------------------------------------------------------------------
; GetFormNameSource
;
; Redirects GetMonName's source row to a form's own name when a form context is
; pending for the species being named. Without it a form clone prints its BASE
; species' name, because MonsterNames is indexed by species alone.
;
; Lives here, and is plain-called from HOME, for the same reason as
; ApplyFormOverride: GetMonName has already switched to BANK(MonsterNames), and
; layout.link pins "Monster Names" and "Species Forms" to the SAME bank as
; "Base Stats". home/names.asm asserts that.
;
; INPUT:  hl = the MonsterNames row GetMonName computed (the default)
;         wFormContextSpecies / wFormContextForm
; OUTPUT: hl = the form's 10-character name, or unchanged if no form applies
; CLOBBERS: af, bc, de  (hl is the return value)
;   Safe: GetMonName loads de and bc for the copy AFTER this returns.
;
; Consumes the context, exactly like ApplyFormOverride. That is workable here
; only because species names are BAKED into a nickname buffer at three creation
; sites rather than read live, so each of those three publishes its own context
; immediately before calling. A display path that wants BOTH a form-correct
; header and a form-correct name must publish twice - once per call.
; ---------------------------------------------------------------------------
GetFormNameSource::
	ld a, [wFormContextSpecies]
	and a
	ret z                        ; no context pending - the common case

	ld b, a
	xor a
	ld [wFormContextSpecies], a  ; consume, unconditionally

	ld a, [wNamedObjectIndex]
	cp b
	ret nz                       ; context was for a different species

	ld a, [wFormContextForm]
	and a
	ret z                        ; form 0 is the base species: keep the default row
	ld c, a

	push hl                      ; keep the default MonsterNames row
	ld hl, FormOverrides
.nameLoop
	ld a, [hl]
	and a
	jr z, .nameNotFound
	cp b
	jr nz, .nameNext
	inc hl
	ld a, [hl]
	dec hl
	cp c
	jr z, .nameFound
.nameNext
	ld de, FORM_REC_SIZE
	add hl, de
	jr .nameLoop

.nameNotFound
	pop hl                       ; fall back to the base species' name
	ret

.nameFound
	ld de, FORM_REC_NAME
	add hl, de                   ; hl = the form's name field
	pop de                       ; discard the saved default row
	ret

; ---------------------------------------------------------------------------
; GetFormPaletteForStruct / GetFormPalette
;
; The palette a form draws in. MonsterPalettes is indexed by dex number alone,
; so without this every form drew in its BASE species' palette (A-Ninetales
; yellow, Espeon in Jolteon's). Each form record carries its own PAL_*MON byte
; (FORM_REC_PAL, written by form_end).
;
; INPUT:  GetFormPaletteForStruct: de = a party / box / battle struct. Species
;           at +0, form in MON_CATCH_RATE bits 5-6 (battle_struct's CatchRate is
;           the same offset, which IsGhostVariant already relies on).
;         GetFormPalette: d = species (internal index), e = form index 0..3
; OUTPUT: e = the form's palette, or 0 = no override (form 0, or no record)
; CLOBBERS: af, bc, d, hl
; Farcall-safe: input in d/e, result in e (only d/e cross Bankswitch).
; ---------------------------------------------------------------------------
GetFormPaletteForStruct::
	ld h, d
	ld l, e
	ld d, [hl]                   ; MON_SPECIES
	ld bc, MON_CATCH_RATE
	add hl, bc
	ld a, [hl]
	and FORM_MASK
	rlca                         ; bits 5-6 -> 0..3, as PublishFormContext
	rlca
	rlca
	ld e, a
	; fall through
GetFormPalette::
	ld a, e
	and a
	ret z                        ; form 0: e = 0, keep the species palette
	ld c, a
	ld b, d
	ld hl, FormOverrides
.palLoop
	ld a, [hl]
	and a
	jr z, .palNotFound
	cp b
	jr nz, .palNext
	inc hl
	ld a, [hl]
	dec hl
	cp c
	jr z, .palFound
.palNext
	ld de, FORM_REC_SIZE
	add hl, de
	jr .palLoop

.palNotFound
	ld e, 0
	ret

.palFound
	ld de, FORM_REC_PAL
	add hl, de
	ld e, [hl]
	ret

; ---------------------------------------------------------------------------
 ; RogueRollFormForSpecies
; Compatibility entry for existing trainer callers. Random form substitution
; has ended: only an explicitly selected evolution may publish a form.
; INPUT e = final species. OUTPUT e = evolution form or 0. d preserved.
RogueRollFormForSpecies::
	ld b, e
	ld hl, wPendingEeveeForm
	ld a, [hl]
	ld [hl], 0
	bit 7, a
	jr z, .none
	ld c, a
	bit 6, a                    ; a base list's FORM entry (EvolveMonByLevel): the
	jr nz, .takeForm            ; form belongs to the species that entry just named
.eevee
	ld a, c
	rrca
	rrca
	and %11
	add FLAREON
.matchSpecies
	cp b
	jr nz, .none
.takeForm
	ld a, c
	and %11
	ld e, a
	ret
.none
	ld e, 0
	ret

; ---------------------------------------------------------------------------
; IsFormAllowed
;
; Is this form's species-group unlock active for the current run?
;
; INPUT:  b = species, a = form index, d = active group mask
;         (the mask comes from RogueGetActiveGroupMask, which lives in the
;         roller's bank - it is passed in rather than called, because only
;         d/e/flags survive the farcall that got us here)
; OUTPUT: carry SET if the form may appear
; CLOBBERS: af   (bc, de, hl PRESERVED)
;
; Warp is the default and Johto the listed exception - see FormJohtoPairs.
; ---------------------------------------------------------------------------
IsFormAllowed:
	push bc
	push hl
	ld c, a                      ; c = wanted form
	ld a, (FormJohtoPairsEnd - FormJohtoPairs) / 2
	and a
	jr z, .warp
	ld hl, FormJohtoPairs
.loop
	push af                      ; a = pairs remaining
	ld a, [hli]
	cp b
	jr nz, .next
	ld a, [hl]
	cp c
	jr z, .johto
.next
	inc hl
	pop af
	dec a
	jr nz, .loop
.warp
	ld a, 1 << BIT_GROUP_WARP
	jr .test
.johto
	pop af                       ; discard the loop counter
	ld a, 1 << BIT_GROUP_JOHTO
.test
	and d                        ; is that group active this run?
	pop hl
	pop bc                       ; pops do not disturb the flags
	ret z                        ; locked - carry clear
	scf
	ret

; ---------------------------------------------------------------------------
; RogueRollEeveeBranch
;
; Uniform pick over Eevee's eight stone branches, keeping only the ones whose
; form is unlocked this run - the same IsFormAllowed gate every other form uses,
; so this can never disagree with FormJohtoPairs. Rejection sampling from a
; uniform 0-7 stays uniform over what is accepted, and the three base
; eeveelutions always pass, so it ends quickly (at worst 8/3 rolls on average).
;
; INPUT:  d = active group mask (RogueGetActiveGroupMask)
; OUTPUT: d = species, e = form index
; CLOBBERS: af, bc, hl
; ---------------------------------------------------------------------------
RogueRollEeveeBranch::
	call RollAllowedEeveeBranch
	ld d, b
	ld e, c
	ret

; The shared roll behind RogueRollEeveeBranch and RogueRollEeveeIndexFar.
; INPUT:  d = active group mask
; OUTPUT: a = branch index 0-7, b = species, c = form
; CLOBBERS: af, bc, hl
RollAllowedEeveeBranch:
	call Random
	and %111
	push af                      ; branch index, returned in a
	add a                        ; 2-byte (species, form) pairs
	ld c, a
	ld b, 0
	ld hl, EeveeBranches
	add hl, bc
	ld b, [hl]                   ; b = species
	inc hl
	ld a, [hl]
	ld c, a                      ; c = form; IsFormAllowed preserves bc
	and a
	jr z, .accept                ; a base eeveelution is always allowed
	call IsFormAllowed           ; b = species, a = form, d = mask
	jr c, .accept
	pop af
	jr RollAllowedEeveeBranch
.accept
	pop af
	ret

; ---------------------------------------------------------------------------
; RogueRollEeveeIndexFar
; The Mist Stone's Eevee pick (engine/pokemon/mist_stone_chooser.asm MistStoneChooseEvolution): a
; uniform pick over the branches whose form is unlocked this run. It used to be
; an unconditional 0-7, which handed out Espeon/Glaceon/etc. with their group
; locked. EeveeMistStones is in EeveeBranches' order, so the index carries over.
; OUTPUT: e = branch index 0-7
; CLOBBERS: af, bc, d, hl
; ---------------------------------------------------------------------------
RogueRollEeveeIndexFar::
	farcall RogueGetActiveGroupMaskFar ; e = active group mask
	ld d, e
	call RollAllowedEeveeBranch
	ld e, a
	ret

; ---------------------------------------------------------------------------
; IsFormUnlockedFar
; IsFormAllowed for callers in another bank (the stone evolution in
; engine/pokemon/evos_moves.asm). Fetches the group mask itself.
; INPUT:  d = species, e = form index
; OUTPUT: carry SET if the form may appear (flags survive the farcall return)
; CLOBBERS: af, bc, de, hl
; ---------------------------------------------------------------------------
IsFormUnlockedFar::
	push de
	farcall RogueGetActiveGroupMaskFar ; e = active group mask
	ld a, e
	pop de                       ; d = species, e = form
	ld b, d
	ld d, a                      ; d = mask
	ld a, e                      ; a = form
	jp IsFormAllowed

; ---------------------------------------------------------------------------
; IsFormRecordedFar
; Does (species, form) have a record in FormOverrides? Used by evolution, which
; preserves a form only when the evolved species has the same form: Galarian
; Farfetch'd becomes a plain Sirfetch'd, not SIRFETCHD with a dangling form 1
; that a later record would silently claim.
; Rides on GetFormPalette: every record's palette is a PAL_*MON (>= $10), so
; palette 0 can only mean "no record".
; INPUT:  d = species, e = form index (0 = base, never "recorded")
; OUTPUT: carry SET if the record exists (flags survive the farcall return)
; CLOBBERS: af, bc, de, hl
; ---------------------------------------------------------------------------
IsFormRecordedFar::
	call GetFormPalette          ; e = palette, 0 = no record
	ld a, e
	and a                        ; clears carry
	ret z
	scf
	ret

EeveeBranches:
; Same eight outcomes as EeveeEvosMoves' stone entries plus evos_moves.asm's
; EvoStoneForms, in the Mist Stone's order (engine/pokemon/mist_stone_chooser.asm EeveeMistStones).
	db FLAREON,  0 ; FIRE_STONE
	db JOLTEON,  0 ; THUNDER_STONE
	db VAPOREON, 0 ; WATER_STONE
	db FLAREON,  1 ; LEAF_STONE  - Leafeon
	db JOLTEON,  1 ; SUN_STONE   - Espeon
	db JOLTEON,  2 ; DUSK_STONE  - Umbreon
	db VAPOREON, 1 ; ICE_STONE   - Glaceon
	db VAPOREON, 2 ; MOON_STONE  - Sylveon
EeveeBranchesEnd:
ASSERT EeveeBranchesEnd - EeveeBranches == 8 * 2, "RogueRollEeveeBranch masks Random to 0-7"
ASSERT JOLTEON == FLAREON + 1 && VAPOREON == FLAREON + 2, \
       "wPendingEeveeForm stores the species as a 2-bit offset from FLAREON"

; ---------------------------------------------------------------------------
; GetEnemySpawnForm
;
; The form index for the enemy mon LoadEnemyMonData is about to build.
;
; INPUT:  none (reads hIsInBattle / hWhichPokemon / the enemy party)
; OUTPUT: e = form index (0 = base species, 1..NUM_FORM_SLOTS = a form)
; CLOBBERS: af, bc, hl   (d PRESERVED)
;
; A TRAINER mon carries its own form in its party struct's MON_CATCH_RATE bits
; 5-6, written once at roster-build time by _AddPartyMon. It has to be read back
; from THERE, not from wSpawnForm: that global is consumed and zeroed as each
; roster mon is created, so by the time the battle actually starts it is 0 and
; every trainer mon would be rebuilt as its plain base species - stats, types,
; sprite and name - whatever was stored on it. That is also what made handcrafted
; teams unable to carry a form at all.
;
; A WILD mon has no party struct to read, so it still uses the wSpawnForm
; hand-off published just before the encounter is built.
;
; Indexed by hWhichPokemon, NOT wEnemyMonPartyPos - the latter is not written
; until .copyHPAndStatusFromPartyData, and TOUCH 1 runs well before that. Same
; reasoning as the DV read a few lines below it.
;
; Lives HERE rather than in core.asm because "Battle Core" is a full 16 KiB bank
; and adding ~30 bytes overflowed it by 8 (measured 2026-09-09). Nothing in this
; routine needs bank $30 - it touches only HRAM, WRAM and HOME - so it is here to
; sit with the rest of the form code in a bank that has room. Returns in e
; because only d/e/flags cross a farcall, and Bankswitch's return path writes a.
; ---------------------------------------------------------------------------
GetEnemySpawnForm::
	ldh a, [hIsInBattle]
	cp $2                  ; trainer battle?
	jr nz, .wild
	ld hl, wEnemyMon1CatchRate
	ldh a, [hWhichPokemon]
	ld bc, wEnemyMon2 - wEnemyMon1
	call AddNTimes         ; HOME; clobbers af/hl only
	ld a, [hl]
	and FORM_MASK
	rlca                   ; bits 5-6 -> 0..3; three LEFT rotations are the
	rlca                   ; inverse of the three rrca the encode side uses
	rlca
	ld e, a
	ret
.wild
	ld a, [wSpawnForm]
	ld e, a
	ret

; ---------------------------------------------------------------------------
; PublishEnemyFormContext
;
; Publishes the form context for the enemy mon LoadEnemyMonData is building, so
; the very next GetMonHeader / GetMonName sees it.
;
; INPUT:  none (resolves the form itself via GetEnemySpawnForm)
; OUTPUT: wFormContextForm / wFormContextSpecies set for wEnemyMonSpecies2
; CLOBBERS: af, bc, e, hl   (d PRESERVED)
;
; Exists for SPACE, not tidiness. "Battle Core" is a full 16 KiB bank and the
; _DEBUG build overflowed it by 3 bytes once each of the three form touches
; carried its own farcall plus four stores. Folding the four stores in here makes
; each touch a single farcall, which nets the section back to its ORIGINAL size
; while still reading the form from the party struct.
;
; wEnemyMonSpecies2 is the right species for both callers: TOUCH 1 has just
; copied it into wCurSpecies, and TOUCH 3 has just copied it into
; wNamedObjectIndex. Reading it directly here saves the caller a load.
;
; The context is ONE-SHOT - ApplyFormOverride and GetFormNameSource each consume
; it - which is exactly why LoadEnemyMonData publishes twice rather than once.
; ---------------------------------------------------------------------------
PublishEnemyFormContext::
	call GetEnemySpawnForm       ; e = form index
	ld a, e
	ld [wFormContextForm], a
	ld a, [wEnemyMonSpecies2]
	ld [wFormContextSpecies], a
	ret

; Generated-pool evolution shares this bank with the form records.
; EvolvePoolMon: explicit d=species/e=form in and out. wCurPartySpecies is
; published for existing consumers. Never writes wSpawnForm (bosses defer creation).
; Plain Farfetch'd and paradox forms obey the same no-evolution rule as the player.
EvolvePoolMon::
	xor a
	ld [wPendingEeveeForm], a
	ld a, d
	ld [wCurPartySpecies], a
	ld a, e
	and a
	jr z, .baseForm
; A FORM evolves through its OWN list, exactly as the player's does
; (FORM_EVOLUTION_LISTS_PLAN.md): an A-Rattata's entry names RATICATE form 1,
; and an empty list (a paradox form) never evolves. This replaced "evolve the
; species, then keep the form if the target has one".
	call EvolveFormMonByLevel
	ld a, d
	ld [wCurPartySpecies], a
	ld a, e
	and a
	ret nz                      ; still a form
; The line reached a plain species (Galarian Farfetch'd -> Sirfetch'd): any
; further stage is that species' own list.
.baseForm
	call EvolveMonByLevel
	ld a, [wCurPartySpecies]
	ld d, a
	ld e, 0
	ld a, [wPendingEeveeForm]
	bit 7, a
	ret z
	ld e, d
	farcall RogueRollFormForSpecies ; consumes the exact Eevee evolution choice
	ld a, [wCurPartySpecies]
	ld d, a
	ret

; Evolves a FORM mon along its own list as far as wCurEnemyLevel allows, with
; the same rules EvolveMonByLevel applies to a species: stone and trade entries
; need level 35, a level entry its own level, a plain target must pass the
; species-group gate, and eligible entries are sampled uniformly. A form's entry
; carries its own form forward, which is never gated (as for the player).
; IN:  d = species, e = form (1..NUM_FORM_SLOTS)
; OUT: d = species, e = form at the end of the line; e = 0 once a plain entry
;      is taken (the caller continues on that species' list)
; CLOBBERS: af, bc, hl
EvolveFormMonByLevel:
	ld a, e
	and a
	ret z
	push de                     ; the answer if nothing is eligible
	farcall CopyEvoListForMonFar ; this form's own list -> wEvoDataBuffer
	ld hl, wEvoDataBuffer
	ld b, 0                     ; b = eligible count; d/e = the sampled target
.scan
	ld a, [hli]
	and a
	jr z, .scanned
	ld c, 0                     ; c = this entry's target form
	cp EVOLVE_LEVEL_FORM
	jr c, .gotForm
	ld c, [hl]                  ; a FORM entry: the form follows the type byte
	inc hl
	sub EVOLVE_FORM_TYPE_DELTA
.gotForm
	cp EVOLVE_LEVEL
	jr z, .level
	cp EVOLVE_TRADE
	jr z, .floor
	inc hl                      ; an item entry: past the item id
.floor
	ld a, [wCurEnemyLevel]
	cp 35                       ; the shared generated stone/trade floor
	jr nc, .level
	inc hl                      ; past [level]
	jr .nextEntry
.level
	ld a, [wCurEnemyLevel]
	cp [hl]                     ; carry = below the entry's level
	inc hl                      ; inc rr leaves the flags alone
	jr c, .nextEntry
; A FORM target is never species-gated (IsEvolutionTargetAllowed, the player's
; side): Clodsire and G-Slowking are Johto species but Time Warp forms.
	ld a, c
	and a
	jr nz, .eligible
	push hl
	push bc
	push de
	ld e, [hl]                  ; target species; e, not a, crosses the farcall
	farcall RogueIsSpeciesEvolutionAllowedFar
	pop de                      ; pops leave the carry alone
	pop bc
	pop hl
	jr nc, .nextEntry
.eligible
	inc b                       ; reservoir sampling, as EvolveMonByLevel does
	ld a, b
	cp 1
	jr z, .take
	push bc
	ld c, b
	call Rangerandom
	pop bc
	and a
	jr nz, .nextEntry
.take
	ld d, [hl]
	ld e, c
.nextEntry
	inc hl                      ; past [species]
	jr .scan
.scanned
	ld a, b
	and a
	jr z, .none
	pop af                      ; drop the saved answer
	ld a, d
	ld [wCurPartySpecies], a
	jr EvolveFormMonByLevel     ; the next stage, from the new species and form
.none
	pop de
	ret

; Pokemon needs to be in d. Evolves it as many times as wCurEnemyLevel
; allows (used for enemy trainer mons AND reward/given mons - despite the
; "enemy" scratch vars it reads/writes, it has no actual enemy-specific logic).
EvolveMonByLevel:
	xor a
	ld [wPendingEeveeForm], a     ; stone branches may leave an exact form pending
.loadList
; d must survive the load: .lvl_evolve's EEVEE test reads it. LoadEvoListForSpecies
; ends with de pointing past wEvoDataBuffer, so without this push the test compared
; that address's high byte ($CD) and .handleeevee never ran - every Eevee at 35+
; became FLAREON, its first-listed entry (measured 2026-09-25, 24/24 runs).
	push de
	call LoadEvoListForSpecies
	pop de
	ld bc, 0                   ; b = eligible count, c = sampled target

.evoloop
	ld a, [hli]
	and a
	jr z, .chooseEvolution
; A FORM entry in a base list (Cubone's Dusk Stone -> Alolan Marowak) carries
; its target form after the type byte: e holds it for the rest of the entry, and
; the entry is otherwise read as its plain twin. Sampled with the other entries,
; it makes the generated choice "either target form, uniformly", which replaced
; the RegionalStoneBranches table (FORM_EVOLUTION_LISTS_PLAN.md, Phase 3).
	ld e, 0
	cp EVOLVE_LEVEL_FORM
	jr c, .plainEvoEntry
	ld e, [hl]
	inc hl
	sub EVOLVE_FORM_TYPE_DELTA
.plainEvoEntry
	cp EVOLVE_LEVEL
	jr z, .lvl_evolve
	cp EVOLVE_TRADE
	jr z, .trade_evolve
	;else item evolve
	inc hl              ; past the item id; hl -> [level][species]
.trade_evolve
; EVOLVE_TRADE is handled here, NOT skipped. Generated trainer/reward mons
; use the authored level threshold. The player path also uses that threshold
; on level-up, or bypasses it when actually trading.
;
; It shares EVOLVE_ITEM's level-35 floor. Both are "cannot happen in the wild"
; methods and neither belongs on an early-round trainer, so they take one gate
; rather than each inventing its own. Authored EVOLVE_TRADE entries are at
; level 38 or higher, so the per-entry level below dominates in practice; the floor
; is here to hold if one is ever written lower.
;
; The two layouts differ - EVOLVE_ITEM is [method][item][level][species] and
; EVOLVE_TRADE is [method][level][species] - which is why the item path does
; its extra `inc hl` above and then falls in here with hl on the level byte,
; exactly where a trade entry already is.
	ld a, [wCurEnemyLevel]
	cp 35
	jr nc, .lvl_evolve
.skipentry
	inc hl              ; past [level]
	inc hl              ; past [species]
	jr .evoloop

.lvl_evolve
	ld a, d
	cp EEVEE	;deal with eevee separately
	jr z, .handleeevee
	ld a, [wCurEnemyLevel]
	cp [hl]                     ; carry = below the entry's level
	inc hl                      ; inc rr leaves the flags alone
	jr c, .tooLowForThisEntry
; SPECIES GROUPS. The player's evolution path has gated on this since Phase 2
; (engine/pokemon/evos_moves.asm's .doEvolution) so a Kanto-locked run cannot
; produce a Johto evolution. The TRAINER path never did, so a trainer's Zubat
; at level 45 became a Johto CROBAT in a Kanto-only run. Gating per ENTRY keeps
; split evolutions independent: with Johto off and Warp on, Scyther still
; reaches Kleavor even though Scizor is blocked.
;
; hl is stacked because the farcall macro loads it with the target address.
; `pop` does not disturb flags, so the callee's carry survives to the branch.
	push hl
	push bc             ; preserve the reservoir across the group check
	push de             ; d = the species we are evolving FROM; the callee
	                    ; clobbers de and the loop still needs d for its
	                    ; EEVEE test on a later entry
	ld e, [hl]          ; target species in e, NOT a - Bankswitch's first
	                    ; instruction is `ldh a, [hLoadedROMBank]`, so an `a`
	                    ; input cannot cross a farcall
	farcall RogueIsSpeciesEvolutionAllowedFar
	pop de              ; pop does not disturb flags
	pop bc
	pop hl              ; carry still set = this group is active
	jr nc, .tooLowForThisEntry
; A FORM entry also needs its form unlocked (Alolan/Galarian forms ride on Time
; Warp), exactly as the player's stone evolution asks (IsEvoStoneFormAllowed).
	ld a, e
	and a
	jr z, .formUnlocked
	push hl
	push bc
	push de
	ld d, [hl]          ; d = target species, e = form
	call IsFormUnlockedFar ; same bank
	pop de
	pop bc
	pop hl
	jr nc, .tooLowForThisEntry
.formUnlocked
; Reservoir sampling: eligible entry n replaces the saved target with
; probability 1/n. Rangerandom is unbiased and preserves hl/de/bc.
; A single eligible entry needs no RNG draw.
	inc b
	ld a, b
	cp 1
	jr z, .takeEvolution
	push bc
	ld c, b
	call Rangerandom
	pop bc
	and a
	jr nz, .tooLowForThisEntry
.takeEvolution
	ld c, [hl]
	ld a, e             ; publish the sampled entry's form (0 = none pending)
	and a
	jr z, .publishForm
	or $c0              ; pending + base-list FORM entry + exact form
.publishForm
	ld [wPendingEeveeForm], a
.tooLowForThisEntry
; Scan every entry before committing, so table order cannot prefer a branch.
	inc hl
	jr .evoloop
.chooseEvolution
	ld a, b
	and a
	ret z
	ld a, c
	ld [wCurPartySpecies], a
	ld d, a
	ld a, [wPendingEeveeForm]
	and a
	ret nz                      ; a FORM was chosen: a form evolves on its own
	                            ; list, never on this species path
	jp EvolveMonByLevel         ; repeat for the chosen species' next stage

; Reached only at level 35+ (every Eevee entry is EVOLVE_ITEM, so the item floor
; above gates it). Uniform over the eight stone branches, like the Mist Stone,
; restricted to the ones this run has unlocked: the three Kanto eeveelutions
; always, Espeon/Umbreon with Johto, Leafeon/Glaceon/Sylveon with Time Warp.
; Five of the eight are FORMS, so the form is published in wPendingEeveeForm for
; the caller's next RogueRollFormForSpecies instead of being left to that roll.
.handleeevee
	farcall RogueGetActiveGroupMaskFar
	ld a, e                      ; farcall-safe mask
	ld d, a
	farcall RogueRollEeveeBranch  ; d = species, e = form
	ld a, d
	ld [wCurPartySpecies], a
	sub FLAREON
	add a
	add a                         ; species offset -> bits 2-3
	or e                          ; form -> bits 0-1
	or $80                        ; pending
	ld [wPendingEeveeForm], a
	ret

; d = species. Copies its evolution list (from EvosMovesPointerTable's bank)
; into wEvoDataBuffer and returns hl = wEvoDataBuffer. CLOBBERS af, bc, de.
; Shared by EvolveMonByLevel and AllSpeciesCheck's family walk.
LoadEvoListForSpecies::
	ld hl, EvosMovesPointerTable	;load the address of the pointer table, and worry about the bank later
	ld b, 0
	ld a, d
	dec a
	add a
	rl b
	ld c, a		;BC now contains the pokemon's offset in the pointer table
	add hl, bc	;and HL now points to the correct position in the pointer table
	ld de, wEvoDataBuffer
	ld a, BANK(EvosMovesPointerTable)
	ld bc, 2
	call FarCopyData	;switches banks, then copies the 2-byte address that HL points to into wEvoDataBuffer
	ld hl, wEvoDataBuffer	;let's now point HL to said address
	ld a, [hli]
	ld h, [hl]
	ld l, a				;HL now points to the address of the pokemon's evolution list
	ld de, wEvoDataBuffer
	ld a, BANK(EvosMovesPointerTable)
	ld bc, wEvoDataBufferEnd - wEvoDataBuffer
	call FarCopyData	;now copy the evolution list pointed to by HL into wEvoDataBuffer
	ld hl, wEvoDataBuffer	;we can now reference the evolution list by pointing HL to it
	ret

; Far worker for the bridge menu's level-resolved Pokemon gifts.
; In: e = base species. Out: e = resolved species.
BridgeResolveEvolveSpeciesFar::
	ld d, e
	ld a, [wCurPartySpecies]
	push af
	push de
	farcall GetBridgeRewardMonLevelFar
	ld a, e
	ld [wCurEnemyLevel], a
	pop de
	ld a, d
	ld [wCurPartySpecies], a
	call EvolveMonByLevel
	ld a, [wCurPartySpecies]
	ld e, a
	pop af
	ld [wCurPartySpecies], a
	ret

; Ownership family walk, beside the evolution loader. Called through the
; bank-$38 AllSpeciesCheck wrapper. INPUT d=species; OUTPUT e=owned (0/1).
; No ROM data from bank $38 is read here; the owned list and cursor are WRAM.
DEF FAMILY_WALK_BUDGET EQU 16   ; expansions; Eevee's 8 duplicate branches cost 9

AllSpeciesCheckFar::
	ASSERT PARTY_LENGTH + MONS_PER_BOX + 1 <= $40, \
	       "wAllSpecies (ds $40, ram/wram.asm) must hold a full party, a full box and the terminator"
	push de
	ld bc, wAllSpecies
	ld hl, wPartySpecies
	call .appendList
	ld hl, wBoxSpecies
	call .appendList
	ld a, $ff
	ld [bc], a

; Depth-first over the evolution tree, with the pending species on the stack.
; Each species' evolution list is fully consumed (pushed) before the next
; LoadEvoListForSpecies overwrites wEvoDataBuffer, so one buffer serves all.
	xor a
	push af                       ; NO_MON sentinel marks the bottom
	ld a, d
	ld b, FAMILY_WALK_BUDGET
.visit                            ; a = species to test
	ld d, a
	ld hl, wAllSpecies
.scan
	ld a, [hli]
	cp d
	jr z, .owned
	inc a                         ; $ff terminator -> 0
	jr nz, .scan
	inc b                         ; test b for 0 without changing it: the budget
	dec b                         ; must SATURATE at 0, not wrap to 255 on the
	jr z, .next                   ; next visit (budget spent: stop expanding, keep testing)
	dec b
	push bc
	call LoadEvoListForSpecies
	pop bc
.evoEntry
	ld a, [hli]
	and a
	jr z, .next
	cp EVOLVE_LEVEL_FORM          ; a FORM entry: skip the form byte, then parse plain
	jr c, .plainType
	inc hl
	sub EVOLVE_FORM_TYPE_DELTA
.plainType
	cp EVOLVE_ITEM
	jr nz, .noItem
	inc hl                        ; [method][item][level][species]
.noItem
	inc hl                        ; past [level]
	ld a, [hli]                   ; target species
	push af
	jr .evoEntry
.next
	pop af
	and a
	jr nz, .visit
	ld c, a                       ; sentinel reached: not owned, c = 0
	jr .end

.owned
	pop af                        ; discard pending species down to the sentinel
	and a
	jr nz, .owned
	ld c, 1
.end                              ; single exit, c = result
	pop de
	ld e, c                      ; farcall-safe ownership result
	ret

; copy [hl] to [bc] up to (not including) the $ff terminator
.appendList
	ld a, [hli]
	cp $ff
	ret z
	ld [bc], a
	inc bc
	jr .appendList
