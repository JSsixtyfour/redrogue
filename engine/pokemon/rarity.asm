; Rarity pools for every random species pick in Red Rogue.
;
; Structure (see constants/rogue_species_groups.asm):
;
;   RarityGroupTable  ->  one `dw` per species group
;        |
;        +-> per-group tier table, NUM_RARITY_TIERS x RARITY_TIER_ENTRY_SIZE
;                 db base count, db total count, dw species list
;
; Each species list is laid out as [base forms][evolved forms]. Only the
; base-form prefix is rolled directly; evolved forms are reached through
; EvolveMonByLevel and exist here so an arbitrary owned species can still be
; classified back to its tier (RogueClassifySpecies).
;
; Counts are computed by the assembler from the list labels. They used to be
; hand-summed EQUs kept in sync by hand in TWO files, which is exactly the kind
; of bookkeeping that silently rots - do not reintroduce them.
;
; Johto and Kanto Time Warp ship EMPTY. A zero base count makes a group
; invisible to the roller, so behaviour is bit-identical to the pre-group code
; until their lists are populated.

; Class-roll thresholds against a 0-255 roll. Ultraball is the fall-through, so
; it deliberately has no threshold of its own. Masterball and uber are never
; reachable from the random path - a caller must ask for them by class.
DEF pokeball_odds  EQU $7F
DEF greatball_odds EQU $66 + $7F

; \1 = list label. Requires \1, \1_Evos and \1_End to be defined.
MACRO rarity_tier
	db \1_Evos - \1   ; rollable base-form count
	db \1_End  - \1   ; total count, for classification
	dw \1
ENDM

MACRO rarity_tier_empty
	db 0, 0
	dw 0
ENDM

RarityGroupTable::
	dw RarityKanto
	dw RarityJohto
	dw RarityWarp
RarityGroupTableEnd:
ASSERT RarityGroupTableEnd - RarityGroupTable == NUM_SPECIES_GROUPS * 2, "RarityGroupTable needs one entry per species group"

RarityKanto:
	rarity_tier KantoPokeball
	rarity_tier KantoGreatball
	rarity_tier KantoUltraball
	rarity_tier KantoMasterball
	rarity_tier KantoUber

; Johto - unlocked after the first champion win. Populated in Phase 2.
RarityJohto:
	rarity_tier_empty ; pokeball
	rarity_tier_empty ; greatball
	rarity_tier_empty ; ultraball
	rarity_tier_empty ; masterball
	rarity_tier_empty ; uber

; Kanto Time Warp - unlocked after the second champion win. Populated in Phase 2.
RarityWarp:
	rarity_tier_empty ; pokeball
	rarity_tier_empty ; greatball
	rarity_tier_empty ; ultraball
	rarity_tier_empty ; masterball
	rarity_tier_empty ; uber


KantoPokeball:
	db CATERPIE
	db WEEDLE
	db PIDGEY
	db RATTATA
	db FARFETCHD
	db EKANS
	db DITTO
	db MANKEY
	db KRABBY
	db CUBONE
	db GRIMER
	db GROWLITHE
	db SEEL
	db VOLTORB
	db SPEAROW
	db KABUTO
	db MAGNEMITE
	db POLIWAG
	db ODDISH
	db ZUBAT
	db JIGGLYPUFF
	db SANDSHREW
	db PARAS
	db PSYDUCK
	db BELLSPROUT
	db KOFFING
	db HORSEA
	db GOLDEEN
KantoPokeball_Evos:
; stage 2
	db METAPOD
	db KAKUNA
	db PIDGEOTTO
	db RATICATE
	db ARBOK
	db PRIMEAPE
	db KINGLER
	db MAROWAK
	db MUK
	db ARCANINE
	db DEWGONG
	db ELECTRODE
	db FEAROW
	db KABUTOPS
	db MAGNETON
	db POLIWHIRL
	db GLOOM
	db GOLBAT
	db WIGGLYTUFF
	db SANDSLASH
	db PARASECT
	db GOLDUCK
	db WEEPINBELL
	db WEEZING
	db SEADRA
	db SEAKING
; stage 3
	db BUTTERFREE
	db BEEDRILL
	db PIDGEOT
	db POLIWRATH
	db VILEPLUME
	db VICTREEBEL
KantoPokeball_End:

KantoGreatball:
	db BULBASAUR
	db CHARMANDER
	db SQUIRTLE
	db EEVEE
	db DODUO
	db DRATINI
	db OMANYTE
	db MACHOP
	db SHELLDER
	db GEODUDE
	db LICKITUNG
	db NIDORAN_F
	db CLEFAIRY
	db DIGLETT
	db MAGIKARP
	db PIKACHU
	db SLOWPOKE
	db DROWZEE
	db PONYTA
	db MEOWTH
	db VULPIX
	db TANGELA
	db VENONAT
	db NIDORAN_M
	db HITMONCHAN
	db TENTACOOL
	db ONIX
	db PORYGON
KantoGreatball_Evos:
; stage 2
	db IVYSAUR
	db CHARMELEON
	db WARTORTLE
	db JOLTEON
	db FLAREON
	db VAPOREON
	db DODRIO
	db DRAGONAIR
	db OMASTAR
	db MACHOKE
	db CLOYSTER
	db GRAVELER
	db NIDORINA
	db CLEFABLE
	db DUGTRIO
	db GYARADOS
	db RAICHU
	db SLOWBRO
	db HYPNO
	db RAPIDASH
	db PERSIAN
	db NINETALES
	db VENOMOTH
	db NIDORINO
	db TENTACRUEL
; stage 3
	db VENUSAUR
	db CHARIZARD
	db BLASTOISE
	db DRAGONITE
	db MACHAMP
	db GOLEM
	db NIDOQUEEN
	db NIDOKING
KantoGreatball_End:

KantoUltraball:
	db GASTLY
	db ABRA
	db JYNX
	db ARTICUNO
	db MOLTRES
	db CHANSEY
	db RHYHORN
	db LAPRAS
	db KANGASKHAN
	db SCYTHER
	db HITMONLEE
	db MR_MIME
	db ELECTABUZZ
	db MAGMAR
	db PINSIR
	db AERODACTYL
KantoUltraball_Evos:
; stage 2
	db HAUNTER
	db KADABRA
	db RHYDON
; stage 3
	db GENGAR
	db ALAKAZAM
KantoUltraball_End:

KantoMasterball:
	db TAUROS
	db SNORLAX
	db EXEGGCUTE
	db STARYU
	db ZAPDOS
KantoMasterball_Evos:
; stage 2
	db EXEGGUTOR
	db STARMIE
KantoMasterball_End:

; Never rollable and never reached by evolution - uber exists so MEW and MEWTWO
; classify into a tier of their own (the Legendary Boss challenge hands them out
; directly). Its base count is 0, so the roller skips it like an empty group.
KantoUber:
KantoUber_Evos:
	db MEW
	db MEWTWO
KantoUber_End:

; The Kanto pool must still describe exactly the 151 Kanto species.
ASSERT (KantoPokeball_End - KantoPokeball) + (KantoGreatball_End - KantoGreatball) + \
       (KantoUltraball_End - KantoUltraball) + (KantoMasterball_End - KantoMasterball) + \
       (KantoUber_End - KantoUber) == 151, "Kanto rarity pool is no longer 151 species"


; ===========================================================================
; Pool accessors.
;
; These are the ONLY sanctioned way to read the tables above. Four separate
; hand-rolled scans over the old flat table used to exist (two here, one in
; legendary_boss_helpers.asm, one in scripts/IndigoPlateauLobby.asm); all four
; were unbounded and ran off the end of the table on an unknown species, and the
; lobby copy was reading the table from the WRONG BANK entirely (it sits in
; bank $06 and did a plain `ld hl, pokemon_classes` into bank $2F data).
; ===========================================================================

ASSERT RARITY_TIER_ENTRY_SIZE == 4, "RogueGetTierEntry hardcodes a 4-byte stride"

; ---------------------------------------------------------------------------
; RogueGetTierEntry
; INPUT:  a = group id, b = tier id
; OUTPUT: hl = species list, b = base-form count, c = total count
;         Z set if this tier is empty (base count 0)
; CLOBBERS: af, bc, hl   (de PRESERVED - RogueClassifySpecies parks the species
;           it is searching for in e across this call)
; ---------------------------------------------------------------------------
RogueGetTierEntry::
	push de
	ld hl, RarityGroupTable
	add a                        ; group * 2 (dw)
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a                      ; hl = tier table for this group
	ld a, b
	add a
	add a                        ; tier * RARITY_TIER_ENTRY_SIZE
	ld e, a
	ld d, 0
	add hl, de
	pop de
	ld a, [hli]
	ld b, a                      ; base count
	ld a, [hli]
	ld c, a                      ; total count
	ld a, [hli]
	ld h, [hl]
	ld l, a                      ; hl = species list
	ld a, b
	and a
	ret

; ---------------------------------------------------------------------------
; RogueGetTierBaseCount
; INPUT:  a = group id, b = tier id
; OUTPUT: a = base-form count for that (group, tier)
; CLOBBERS: af, hl   (bc, de PRESERVED - the roller keeps loop counters there)
; ---------------------------------------------------------------------------
RogueGetTierBaseCount::
	push bc
	call RogueGetTierEntry
	ld a, b
	pop bc
	ret

; ---------------------------------------------------------------------------
; RogueGetActiveGroupMask
; OUTPUT: a = bitmask of groups that may supply a species this run.
;         Kanto (bit 0) is always set; it is not toggleable.
; CLOBBERS: af   (bc, de, hl PRESERVED)
;
; Unlock state is DERIVED from wNumHoFTeams rather than stored: one champion win
; unlocks Johto, two unlock Kanto Time Warp. That byte is already saved, already
; saturating (engine/movie/hall_of_fame.asm), and already survives the run-reset
; script, so deriving it avoids a second source of truth that could desync from
; the save file.
;
; A save made before sRogueSpeciesGroupsEnabled existed reads $ff here, which the
; final AND clamps to "every unlocked group enabled" - a sane default, and
; self-correcting the first time the player opens the toggle menu.
; ---------------------------------------------------------------------------
RogueGetActiveGroupMask::
	push bc
	ld a, [wNumHoFTeams]
	ld b, 1 << BIT_GROUP_KANTO
	and a
	jr z, .gotUnlocks
	set BIT_GROUP_JOHTO, b
	dec a
	jr z, .gotUnlocks
	set BIT_GROUP_WARP, b
.gotUnlocks
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ASSERT BANK("Save Data") == 1
	ld a, 1
	ld [rRAMB], a               ; select bank 1 explicitly; ambient bank is unreliable
	ld a, [sRogueSpeciesGroupsEnabled]
	ld c, a
	xor a
	ld [rRAMG], a               ; never leave SRAM enabled across a return
	ld a, c
	set BIT_GROUP_KANTO, a      ; Kanto is always in the pool
	and b                       ; drop anything not yet unlocked
	pop bc
	ret

; ---------------------------------------------------------------------------
; RogueRollGroupForTier
; INPUT:  b = tier id
; OUTPUT: a = group id that supplies this roll, carry CLEAR
;         carry SET if no active group has any base form at this tier
; CLOBBERS: af, c, de, hl   (b PRESERVED)
;
; Picks a group with probability proportional to how many base forms it offers at
; this tier, i.e. exactly uniform across the union of the active lists. To bias
; it later (say, Kanto-primary), scale the per-group count at the two
; RogueGetTierBaseCount calls below by a weight table; the running total is
; 8-bit, so keep the weighted sum at or under 255.
; ---------------------------------------------------------------------------
RogueRollGroupForTier::
	push bc
	call RogueGetActiveGroupMask
	pop bc
	push af                      ; keep the mask for the second pass
	ld d, a                      ; d = mask, consumed by shifting
	ld e, 0                      ; e = running total
	ld c, 0                      ; c = group index
.sum
	ld a, d
	and 1
	jr z, .sumNext
	ld a, c
	push de
	call RogueGetTierBaseCount
	pop de
	add e
	jr nc, .sumNoSat
	ld a, $ff
.sumNoSat
	ld e, a
.sumNext
	srl d
	inc c
	ld a, c
	cp NUM_SPECIES_GROUPS
	jr c, .sum

	ld a, e
	and a
	jr z, .none
	ld c, e
	call Rangerandom             ; a = 0 .. total-1, unbiased; preserves bc/de/hl
	ld e, a                      ; e = index left to walk off
	pop af
	ld d, a                      ; d = mask again
	ld c, 0
.pick
	ld a, d
	and 1
	jr z, .pickNext
	ld a, c
	push de
	call RogueGetTierBaseCount
	pop de
	ld h, a
	ld a, e
	sub h
	jr c, .found                 ; the index landed inside this slice
	ld e, a
.pickNext
	srl d
	inc c
	ld a, c
	cp NUM_SPECIES_GROUPS
	jr c, .pick
	ld a, SPECIES_GROUP_KANTO    ; unreachable unless the counts moved mid-roll
	and a
	ret
.found
	ld a, c
	and a                        ; clear carry
	ret
.none
	pop af                       ; discard the saved mask
	scf
	ret

; ---------------------------------------------------------------------------
; RogueRollSpeciesInList
; INPUT:  hl = species list, a = count (must be at least 1)
; OUTPUT: d = species
; CLOBBERS: af, bc, hl   (e PRESERVED)
;
; The single index formula for every species roll in the game. Uses Rangerandom,
; which rejection-samples and is therefore unbiased; the two hand-rolled formulas
; this replaces were both biased and disagreed with each other - the reward path
; divided by 255 and the trainer path by 256, which silently made the LAST base
; species of every trainer tier unreachable.
; ---------------------------------------------------------------------------
RogueRollSpeciesInList::
	ld c, a
	call Rangerandom             ; a = 0 .. count-1
	ld c, a
	ld b, 0
	add hl, bc
	ld d, [hl]
	ret

; ---------------------------------------------------------------------------
; RogueClassifySpecies
; INPUT:  a = species
; OUTPUT: b = tier id, c = group id, carry CLEAR on success
;         carry SET if the species is in no pool at all
; CLOBBERS: af, de, hl
;
; Bounded, unlike the four scans it replaces: it walks each list by its recorded
; length instead of scanning until it happens to hit a match, so an unknown
; species now reports "not found" rather than reading off the end of the table.
; ---------------------------------------------------------------------------
RogueClassifySpecies::
	ld e, a                      ; e = species; survives RogueGetTierEntry
	ld d, 0                      ; d = group index
.groupLoop
	ld b, 0                      ; b = tier index
.tierLoop
	push bc                      ; save tier index
	ld a, d
	call RogueGetTierEntry       ; hl = list, b = base, c = total
	ld a, c
	and a
	jr z, .nextTier              ; empty tier
	ld b, c                      ; b = bytes left to scan
.scan
	ld a, [hli]
	cp e
	jr z, .hit
	dec b
	jr nz, .scan
.nextTier
	pop bc
	inc b
	ld a, b
	cp NUM_RARITY_TIERS
	jr c, .tierLoop
	inc d
	ld a, d
	cp NUM_SPECIES_GROUPS
	jr c, .groupLoop
	scf                          ; not in any pool
	ret
.hit
	pop bc                       ; b = tier index
	ld c, d                      ; c = group index
	and a                        ; clear carry (a holds the match, non-zero)
	ret

; ---------------------------------------------------------------------------
; RogueClassifySpeciesLegacy
; INPUT:  a = species
; OUTPUT: c = legacy class 1-4 (pokeball, greatball, ultraball, masterball)
;         carry SET if the species is in no pool
; CLOBBERS: af, b, de, hl
;
; Uber folds into masterball, matching the old reverse lookups, which had no
; ceiling check and so classified MEW/MEWTWO as masterball.
; ---------------------------------------------------------------------------
RogueClassifySpeciesLegacy::
	call RogueClassifySpecies
	ret c
	ld a, b
	cp RARITY_TIER_UBER
	jr c, .notUber
	ld a, RARITY_TIER_MASTERBALL
.notUber
	inc a
	ld c, a
	and a                        ; clear carry
	ret

; ---------------------------------------------------------------------------
; RogueClassifySpeciesFar
; The farcall-safe face of RogueClassifySpeciesLegacy.
; INPUT:  e = species
; OUTPUT: e = legacy class 1-4 (1 if the species is in no pool)
; CLOBBERS: af, bc, d, hl
;
; Bankswitch (home/bankswitch.asm) clobbers a, b, c, h and l on BOTH sides of a
; farcall: it takes the target bank from b, then does `ld bc, .Return` before
; `jp hl` on the way in, and `pop bc` on the way out. Only d, e and flags cross
; intact. So do NOT farcall RogueClassifySpeciesLegacy directly - its result
; comes back in c, which the exit path overwrites.
; ---------------------------------------------------------------------------
RogueClassifySpeciesFar::
	ld a, e
	call RogueClassifySpeciesLegacy
	jr nc, .ok
	ld c, 1                      ; unknown species - treat as pokeball class
.ok
	ld e, c
	ret
