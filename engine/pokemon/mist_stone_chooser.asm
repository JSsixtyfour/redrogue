; Mist Stone evolution chooser.
;
; Lives in "Evos Moves" (bank $31) beside EvosMovesPointerTable and the form
; evolution blocks, so it walks the mon's OWN evolution list (GetEvoListForMon)
; with plain in-bank reads. Moved here from custom_functions/bridge_effects.asm
; (bank $38, "rogue") on 2026-10-17: $38 was down to 2 B free in the debug build,
; and the move both frees it and drops the two FarCopyData round trips the old
; copy needed to reach this bank's tables. Its one caller is a farcall
; (ItemUseEvoStone, engine/items/item_effects.asm), so the bank is free to move.

; Choose among every immediate evolution in the selected mon's own list.
; Requirements are intentionally ignored; EvolutionAfterBattle validates the
; chosen target again before evolving. Carry clear means the player declined
; every available branch or the mon has no evolution.
MistStoneChooseEvolution::
	xor a
	ld [wMonDataLocation], a
	call LoadMonData             ; selected source, not the last menu row
; Species Groups Phase 2R: EEVEE is handled separately, and not for convenience.
;
; The menu below walks the mon's evolution entries and prompts "Evolve into X?"
; for each. That works when every entry names a different species. Eevee's eight
; entries do not: the five eeveelution FORMS reuse FLAREON, JOLTEON and VAPOREON
; as their species and differ only by a form index, so the player would be asked
; about FLAREON twice, JOLTEON three times and VAPOREON three times with no way
; to tell Leafeon from Flareon.
;
; It would also be wrong even if the player guessed right. The parser's Mist
; Stone branch matches on wEvoNewSpecies alone, so it always takes the FIRST
; entry with that species, while ApplyEvoStoneForm keys on wEvoStoneItemID -
; which is MIST_STONE here, not the stone that carries the form. Picking the
; Leafeon entry would hand back a plain Flareon.
;
; So Eevee rolls instead. The trick is to substitute a real stone into
; wEvoStoneItemID rather than special-case anything downstream: the ordinary
; EVOLVE_ITEM match then fires, and ApplyEvoStoneForm sets the right form, with
; no change to the parser, the evolution data or the form table.
;
; The species comes from the party, NOT wCurPartySpecies. That byte is also
; wCurItem, and ItemUseEvoStone writes the stone's id back into it after the
; party menu, so here it reads MIST_STONE ($76, internal DUGTRIO, which has no
; evolutions): nothing was ever offered and the stone was never used.
; hWhichPokemon is the mon picked in the party menu.
	ldh a, [hWhichPokemon]
	ld c, a
	ld b, 0
	ld hl, wPartySpecies
	add hl, bc
	ld a, [hl]
	cp EEVEE
	jr nz, .notEevee
	; Uniform over the branches whose form is unlocked this run (the roller's
	; IsFormAllowed gate), so a Kanto-only Eevee can't become Espeon.
	farcall RogueRollEeveeIndexFar ; e = branch index 0-7
	ld d, 0
	ld hl, EeveeMistStones
	add hl, de
	ld a, [hl]
	ld [wEvoStoneItemID], a
	scf                   ; carry = "an evolution was chosen", same as the menu
	ret

.notEevee
; This mon's own list: its species' for a base form, its form's block otherwise,
; exactly what the evolution loop will walk (FORM_EVOLUTION_LISTS_PLAN.md).
	ld d, a                      ; d = species, from above
	ldh a, [hWhichPokemon]
	ld hl, wPartyMon1CatchRate
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	ld a, [hl]
	and FORM_MASK
	rlca                         ; bits 5-6 -> 0..3
	rlca
	rlca
	ld e, a
	call GetEvoListForMon        ; hl = the list
.nextEvolution
	ld a, [hli]
	and a
	jr z, .noneChosen
; A FORM entry carries its target form straight after the type byte (see
; EvoEntryTakeForm); take it, and the rest parses as an ordinary entry.
	ld b, a
	call EvoEntryTakeForm
	ld a, b
	cp EVOLVE_ITEM
	jr nz, .skipRequirement
	inc hl                       ; item id
.skipRequirement
	inc hl                       ; minimum level
	call IsEvolutionTargetAllowed
	jr nc, .skipTarget
	ld a, [hli]                  ; target species
	push hl
	; Name the target as the form this entry evolves it into: "A-PERSIAN" for
	; an A-MEOWTH's entry, which names form 1 itself.
	ld [wNamedObjectIndex], a
	ld [wFormContextSpecies], a
	ld a, [wEvoNewForm]
	cp $ff
	jr nz, .nameForm
	xor a
.nameForm
	ld [wFormContextForm], a
	call GetMonName
	ld hl, MistStoneChoiceText
	call PrintText
	lb bc, 8, 15
	ld a, TWO_OPTION_MENU
	ld [wTextBoxID], a
	call DisplayTextBoxID
	ld a, [wMenuExitMethod]
	cp CHOSE_SECOND_ITEM
	pop hl
	jr z, .nextEvolution
; Write wEvoNewSpecies only AFTER the Yes/No menu has closed. It is wBuffer+1
; (UNION), and TwoOptionMenu_SaveScreenTiles/RestoreScreenTiles copy 30 bytes of
; tilemap through wBuffer, so a species stored before the menu came back as a
; tile id: the evolution parser matched no entry and printed "no effect".
	dec hl                       ; back onto the target species byte
	ld a, [hl]
	ld [wEvoNewSpecies], a
	scf
	ret
.skipTarget
	inc hl
	jr .nextEvolution
.noneChosen
	and a
	ret

MistStoneChoiceText:
	text_far _MistStoneChoiceText
	text_end

EeveeMistStones:
; One stone per Eevee EVOLVE_ITEM entry, in the same order as EeveeEvosMoves.
; Keep the two in sync: this table's LENGTH is what the Random mask in
; MistStoneChooseEvolution assumes.
;
; Placed AFTER the routine on purpose: a global label between a routine's entry
; and its local labels re-scopes them (`.notEevee` became
; EeveeMistStones.notEevee and the link failed).
	db FIRE_STONE, THUNDER_STONE, WATER_STONE, LEAF_STONE
	db SUN_STONE,  DUSK_STONE,    ICE_STONE,   MOON_STONE
EeveeMistStonesEnd:
ASSERT EeveeMistStonesEnd - EeveeMistStones == 8, \
       "EeveeMistStones must hold exactly 8 entries - the Random mask assumes it"
ASSERT BANK(MistStoneChooseEvolution) == BANK(EvosMovesPointerTable), \
       "MistStoneChooseEvolution walks the evolution lists with plain in-bank reads"
