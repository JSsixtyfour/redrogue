; Species pools for the party spec system (Phase 2).
;
; A pool is the set of species a trainer's slots may roll. Pools are declarative
; and hand-editable; Phase 3 fills in all 19 gym-leader / Elite Four / Champion
; pools plus the shared route-trainer pools, against the pattern established
; here. Constants and the rationale for the record shapes live in
; constants/party_spec_constants.asm.
;
; LAYOUT. Each pool is three CONTIGUOUS runs - Kanto entries, then Johto, then
; Time Warp - and the table entry carries one count per run. At runtime
; RogueBuildParty skips the runs whose species group is not active this run
; (RogueGetActiveGroupMask), so a pool shrinks to the player's unlock state with
; no per-entry group byte and no scanning. This mirrors the tier-entry shape in
; engine/pokemon/rarity.asm.
;
; COUNTS ARE COMPUTED BY THE ASSEMBLER from the run labels. They used to be
; hand-summed EQUs in the rarity tables, kept in sync by hand across two files,
; which is exactly the bookkeeping that rots silently. Do not reintroduce them.
;
; Every pool must define all four labels even when a run is empty - put the
; labels adjacent and the count comes out zero:
;
;   FooPool:        ; Kanto run
;       pool_mon PIDGEY
;   FooPool_Johto:  ; Johto run
;       pool_mon HOOTHOOT
;   FooPool_Warp:   ; Time Warp run (empty here)
;   FooPool_End:

; \1 = species, \2 = optional form spec (default POOL_FORM_ROLL).
;
; `pool_mon SANDSLASH` rolls the form the normal gated way. `pool_mon SANDSLASH,
; 1` pins Alolan Sandslash - which changes its TYPE to Ice, so a pinned form is
; how a type-themed pool gets an off-type body on theme. `pool_mon NINETALES,
; POOL_FORM_BASE` guarantees the Fire one.
MACRO pool_mon
	db \1
	IF _NARG >= 2
	db \2
	ELSE
	db POOL_FORM_ROLL
	ENDC
ENDM

; \1 = pool label. Requires \1, \1_Johto, \1_Warp and \1_End.
MACRO trainer_pool
	db (\1_Johto - \1)      / POOL_ENTRY_SIZE ; Kanto run count
	db (\1_Warp  - \1_Johto) / POOL_ENTRY_SIZE ; Johto run count
	db (\1_End   - \1_Warp)  / POOL_ENTRY_SIZE ; Time Warp run count
	dw \1
ENDM

; --- Banded pools (data/trainers/band_pools.asm, from PARTY_ROSTER.md) -----
; The band_* macros live in data/trainers/band_pool_macros.asm, INCLUDEd by
; party_specs.asm: it runs a fourth pass (BAND_POOL_PASS 3) before this file
; exists, to learn which bands have an Ace or Off-type pool.

; Pool ids, in table order. A spec's `pool_id` indexes this table.
;
; Kanto/Johto run membership below follows engine/pokemon/rarity.asm's own
; group split, not type or generation intuition - checked directly rather
; than assumed, per FalknerPool's own AERODACTYL precedent. One real trap
; found doing this: WEAVILE, MAMOSWINE, MISMAGIUS, ANNIHILAPE, MAGNEZONE,
; SIRFETCHD, LICKILICKY, TANGROWTH, PORYGON_Z, KLEAVOR, RHYPERIOR, ELECTIVIRE
; and MAGMORTAR all read as ordinary Gen 2 (or later) species by name, but
; rarity.asm classifies every one of them as WARP-group, "classification-only,
; reached by EVOLVING something in the Kanto or Johto pool, not by being
; rolled" - putting any of them directly in a pool_mon list here would have
; made a late-game-only species available from round one. None of the 18
; pools below reference any of the 13; each becomes reachable exactly the
; way the rarity tables intend, by including its Kanto/Johto pre-evolution
; (PRIMEAPE, MAGNETON, FARFETCHD, SNEASEL, PILOSWINE, MISDREAVUS, LICKITUNG,
; TANGELA, PORYGON2, SCYTHER, RHYDON, ELECTABUZZ, MAGMAR) and letting
; ScaleTrainer_evolution promote it at a high enough level. The one Warp
; species with NO pre-evolution in this tree, MR_RIME, is left out of every
; pool below for the same reason none of the 18 pools use a `_Warp` run at
; all - matching FalknerPool's own empty one - rather than risk a second
; group-membership mistake for one mon under this phase's time budget.
;
; BROCK and WILL match the original plan's own pools.txt illustrative
; example verbatim (translating its `ESPEON`/`UMBREON` names to this tree's
; `JOLTEON` forms 1/2 - see [[project_forms_are_not_species]]); the other 16
; are this pass's own type-plus-authored-team derivation in the same style,
; absent a written brief entry for each of them.
	const_def
	const POOL_FALKNER
	const POOL_WILL
	const POOL_KAREN
; Phase 7f: procedural stage-event characters (PROCEDURAL_WILD_AREA_PLAN.md).
; Trainer Revamp (TRAINER_REVAMP_FIXES_PLAN.md step 4). Appended rather than
; slotted in by role so no existing pool id moves.
	const POOL_LORELEI
	const POOL_BRUNO
	const POOL_AGATHA
	const POOL_LANCE
	const POOL_KOGA_E4
	const POOL_RIVAL3
; Gym leader banded pools, one id each (a `band_same` is an alias, not an id).
DEF BAND_POOL_PASS = 0
INCLUDE "data/trainers/band_pools.asm"
DEF NUM_TRAINER_POOLS EQU const_value

TrainerPoolTable::
	table_width POOL_TABLE_ENTRY_SIZE, TrainerPoolTable
	trainer_pool FalknerPool
	trainer_pool WillPool
	trainer_pool KarenPool
	trainer_pool LoreleiPool
	trainer_pool BrunoPool
	trainer_pool AgathaPool
	trainer_pool LancePool
	trainer_pool KogaE4Pool
	trainer_pool RivalThreePool
DEF BAND_POOL_PASS = 1
INCLUDE "data/trainers/band_pools.asm"
	assert_table_length NUM_TRAINER_POOLS

; ---------------------------------------------------------------------------
; Falkner - Flying. The Phase 2 worked example; Phase 3 adds the other 18.
;
; ARTICUNO is an ordinary member here, NOT a gated one. Measured, not assumed:
; it sits in KantoUltraball in engine/pokemon/rarity.asm, and this tree's
; RARITY_TIER_UBER is exactly {MEW, MEWTWO}, so BIT_PSPEC_ALLOW_UBER does not
; cover the legendary birds. See that flag's note in
; constants/party_spec_constants.asm.
;
; MEWTWO was here through Phase 2 purely so BIT_PSPEC_ALLOW_UBER had an uber to
; reject. Phase 3 removed it: it was off-theme, and the test that needed it
; (test_uber_filter_reads_the_spec_flag) drives PartyGenPoolCandidateOk directly
; with wCurPartySpecies written by hand, so it never read the pool at all.
; SabrinaPool is where MEW and MEWTWO are real, on-theme content.
;
; AERODACTYL is deliberately in the Kanto run despite being a fossil mon: run
; membership follows the rarity tables' group split, not flavour.
; ---------------------------------------------------------------------------
FalknerPool:
	pool_mon PIDGEY
	pool_mon PIDGEOTTO
	pool_mon PIDGEOT
	pool_mon SPEAROW
	pool_mon FEAROW
	pool_mon DODUO
	pool_mon DODRIO
	pool_mon ZUBAT
	pool_mon GOLBAT
	pool_mon FARFETCHD
	pool_mon AERODACTYL
	pool_mon ARTICUNO
FalknerPool_Johto:
	pool_mon HOOTHOOT
	pool_mon NOCTOWL
	pool_mon CROBAT
	pool_mon MURKROW
	pool_mon SKARMORY
	pool_mon YANMA
	pool_mon GLIGAR
FalknerPool_Warp:
FalknerPool_End:

; The other 16 gym leaders' pools are the banded pools in
; data/trainers/band_pools.asm (BALANCE_PHASE5_PLAN.md F, 2026-09-29).
; FalknerPool above stays: FalknerSpec2/3, the Phase 2 worked examples that the
; party-spec tests drive by name, still read it.
DEF BAND_POOL_PASS = 2
INCLUDE "data/trainers/band_pools.asm"

; ---------------------------------------------------------------------------
; Will - Elite Four, Psychic. Named additions (CLEFABLE/
; ELECTABUZZ/MANTINE/FLAREON/CHANSEY/HYPNO) plus every PSYCHIC_TYPE species
; and form (tools/list_pool_candidates.py PSYCHIC_TYPE). ESPEON is this
; tree's JOLTEON form 1 (there is no ESPEON species - see
; [[project_forms_are_not_species]]), sitting in the Warp run with every
; other pinned form so it stays gated on a Kanto-only run. NATU is added
; alongside the brief's own XATU as its pre-evolution.
; ---------------------------------------------------------------------------
WillPool:
	pool_mon EXEGGUTOR
	pool_mon SLOWBRO
	pool_mon JYNX
	pool_mon ALAKAZAM
	pool_mon CLEFABLE
	pool_mon ELECTABUZZ
	pool_mon FLAREON
	pool_mon CHANSEY
	pool_mon HYPNO
	pool_mon ABRA
	pool_mon KADABRA
	pool_mon DROWZEE
	pool_mon MR_MIME
	pool_mon SLOWPOKE
	pool_mon STARMIE
WillPool_Johto:
	pool_mon NATU
	pool_mon XATU
	pool_mon SLOWKING
	pool_mon GIRAFARIG
	pool_mon MANTINE
WillPool_Warp:
	pool_mon JOLTEON, 1 ; Espeon
	pool_mon MR_RIME
	pool_mon ARTICUNO, 1 ; Galarian
	pool_mon JIGGLYPUFF, 1 ; Paldean
	pool_mon MR_MIME, 1 ; Galarian
	pool_mon PONYTA, 1 ; Galarian
	pool_mon RAICHU, 1 ; Alolan
	pool_mon RAPIDASH, 1 ; Galarian
	pool_mon SLOWBRO, 1 ; Galarian
	pool_mon SLOWKING, 1 ; Galarian
	pool_mon SLOWPOKE, 1 ; Galarian
WillPool_End:

; ---------------------------------------------------------------------------
; Karen - Elite Four, Dark. UMBREON is JOLTEON form 2 in this tree, pinned for
; the same reason WillPool pins Espeon.
;
; Dark did not exist as a type until Generation 2, so no Gen 1 species in this
; dex was ever Dark-typed, and this tree has no DARK type to sweep with
; tools/list_pool_candidates.py - the Warp pins below are the real-world
; Dark-types named by hand (Alolan Persian/Meowth/Rattata/Raticate/
; Muk/Grimer, Galarian Moltres, Hisuian Qwilfish).
;
; An empty Kanto run is a real fault, not just thin content: with Johto
; locked every run of the pool would be ineligible, PartyGenRollFromPool
; takes its .giveUp branch, and that branch falls back to the pool's FIRST
; entry UNFILTERED - yielding a team of six identical Murkrow rather than a
; crash, which is exactly the kind of fault that survives a clean build. The
; Kanto run below (her own Gen 2 roster's Kanto half plus other
; Kanto-side additions) keeps that from ever happening, even though Karen is
; only expected to be drawn with Johto enabled.
; ---------------------------------------------------------------------------
KarenPool:
	pool_mon GENGAR
	pool_mon VILEPLUME
	pool_mon ARBOK
	pool_mon PERSIAN
	pool_mon GOLBAT
	pool_mon MAGMAR
	pool_mon SLOWBRO
	pool_mon ELECTRODE
	pool_mon RAPIDASH
	pool_mon FLAREON
KarenPool_Johto:
	pool_mon MURKROW
	pool_mon HOUNDOUR
	pool_mon HOUNDOOM
	pool_mon SNEASEL
	pool_mon TYRANITAR
	pool_mon LARVITAR
	pool_mon PUPITAR
	pool_mon MISDREAVUS
	pool_mon URSARING
KarenPool_Warp:
	pool_mon JOLTEON, 2 ; Umbreon
	pool_mon PERSIAN, 1 ; Alolan
	pool_mon MEOWTH, 1 ; Alolan
	pool_mon RATTATA, 1 ; Alolan
	pool_mon RATICATE, 1 ; Alolan
	pool_mon MUK, 1 ; Alolan
	pool_mon GRIMER, 1 ; Alolan
	pool_mon MOLTRES, 1 ; Galarian
	pool_mon QWILFISH, 1 ; Hisuian
KarenPool_End:

; Phase 7f stage-event characters: all five live in PARTY_ROSTER.md now (below).

; Jessie & James moved to the banded pools (PARTY_ROSTER.md "Wild-area
; trainers", party roster Phase 3, 2026-10-07): JessieJames_Fod<band> and
; JessieJames_Ace<band> in data/trainers/band_pools.asm.

; The Psychic, the Burglar, Nurse Joy and Officer Jenny moved to the banded pools
; (PARTY_ROSTER.md "Wild-area trainers", party roster Phase 3, 2026-10-07):
; <Prefix>_Fod<band> and <Prefix>_Ace<band> in data/trainers/band_pools.asm.

; ===========================================================================
; Trainer Revamp pools (TRAINER_REVAMP_FIXES_PLAN.md steps 4 and 7).
;
; Lorelei/Bruno/Agatha/Lance carry the full lists from the plan's "E4
; pool contents" section: their own authored team plus every "all <type>"
; clause, expanded with tools/list_pool_candidates.py.
;
; Uber-tier species (MEW/MEWTWO, and CELEBI/LUGIA/HO_OH which classify the
; same way - engine/pokemon/rarity.asm's JohtoUber) are left out of every
; type sweep below: none of these specs sets BIT_PSPEC_ALLOW_UBER, matching
; the FalknerPool/SabrinaPool precedent that only one leader's pool ever
; carries uber-tier content.
; ===========================================================================

LoreleiPool:
	pool_mon DEWGONG
	pool_mon CLOYSTER
	pool_mon SLOWBRO
	pool_mon JYNX
	pool_mon LAPRAS
	pool_mon ARTICUNO
	pool_mon EXEGGUTOR
	pool_mon WIGGLYTUFF
	pool_mon STARMIE
	pool_mon OMASTAR
	pool_mon POLIWRATH
LoreleiPool_Johto:
	pool_mon SWINUB
	pool_mon PILOSWINE
	pool_mon SNEASEL
	pool_mon SLOWKING
LoreleiPool_Warp:
	pool_mon MAMOSWINE
	pool_mon MR_RIME
	pool_mon WEAVILE
	pool_mon MR_MIME, 1 ; Galarian
	pool_mon NINETALES, 1 ; Alolan
	pool_mon SANDSHREW, 1 ; Alolan
	pool_mon SANDSLASH, 1 ; Alolan
	pool_mon VAPOREON, 1 ; Glaceon
	pool_mon VULPIX, 1 ; Alolan
LoreleiPool_End:

BrunoPool:
	pool_mon HITMONCHAN
	pool_mon HITMONLEE
	pool_mon MACHAMP
	pool_mon MACHOKE
	pool_mon MACHOP
	pool_mon MANKEY
	pool_mon POLIWRATH
	pool_mon PRIMEAPE
	pool_mon CLEFABLE
	pool_mon MUK
	pool_mon SLOWBRO
	pool_mon RHYDON
	pool_mon GOLEM
	pool_mon ONIX
	pool_mon KANGASKHAN
	pool_mon BLASTOISE
	pool_mon EXEGGUTOR
	pool_mon CLOYSTER
BrunoPool_Johto:
	pool_mon HERACROSS
	pool_mon HITMONTOP
	pool_mon STEELIX
	pool_mon GRANBULL
	pool_mon URSARING
BrunoPool_Warp:
	pool_mon ANNIHILAPE
	pool_mon SIRFETCHD
	pool_mon FARFETCHD, 1 ; Galarian
	pool_mon SNEASEL, 1 ; Hisuian
	pool_mon TAUROS, 1 ; Paldean Combat
	pool_mon TAUROS, 2 ; Paldean Blaze
	pool_mon TAUROS, 3 ; Paldean Aqua
	pool_mon ZAPDOS, 1 ; Galarian
	pool_mon GOLEM, 1 ; Alolan
BrunoPool_End:

AgathaPool:
	pool_mon GASTLY
	pool_mon HAUNTER
	pool_mon GENGAR
	pool_mon ARBOK
	pool_mon BEEDRILL
	pool_mon BELLSPROUT
	pool_mon BULBASAUR
	pool_mon EKANS
	pool_mon GLOOM
	pool_mon GOLBAT
	pool_mon GRIMER
	pool_mon IVYSAUR
	pool_mon KAKUNA
	pool_mon KOFFING
	pool_mon MUK
	pool_mon NIDOKING
	pool_mon NIDOQUEEN
	pool_mon NIDORAN_F
	pool_mon NIDORAN_M
	pool_mon NIDORINA
	pool_mon NIDORINO
	pool_mon ODDISH
	pool_mon TENTACOOL
	pool_mon TENTACRUEL
	pool_mon VENOMOTH
	pool_mon VENONAT
	pool_mon VENUSAUR
	pool_mon VICTREEBEL
	pool_mon VILEPLUME
	pool_mon WEEDLE
	pool_mon WEEPINBELL
	pool_mon WEEZING
	pool_mon ZUBAT
	pool_mon MAROWAK
	pool_mon NINETALES
	pool_mon JYNX
	pool_mon ALAKAZAM
	pool_mon GYARADOS
AgathaPool_Johto:
	pool_mon MISDREAVUS
	pool_mon ARIADOS
	pool_mon CROBAT
	pool_mon QWILFISH
	pool_mon SPINARAK
AgathaPool_Warp:
	pool_mon ANNIHILAPE
	pool_mon MISMAGIUS
	pool_mon MAROWAK, 1 ; Alolan
	pool_mon GRIMER, 1 ; Alolan
	pool_mon MUK, 1 ; Alolan
	pool_mon QWILFISH, 1 ; Hisuian
	pool_mon SLOWBRO, 1 ; Galarian
	pool_mon SLOWKING, 1 ; Galarian
	pool_mon SNEASEL, 1 ; Hisuian
	pool_mon WEEZING, 1 ; Galarian
	pool_mon WOOPER, 1 ; Paldean
AgathaPool_End:

LancePool:
	pool_mon DRAGONAIR
	pool_mon DRAGONITE
	pool_mon DRATINI
	pool_mon GYARADOS
	pool_mon AERODACTYL
	pool_mon CHARIZARD
	pool_mon HORSEA
	pool_mon SEADRA
	pool_mon LAPRAS
	pool_mon EXEGGUTOR
	pool_mon KANGASKHAN
	pool_mon ARCANINE
	pool_mon SNORLAX
	pool_mon ELECTABUZZ
LancePool_Johto:
	pool_mon KINGDRA
	pool_mon LARVITAR
	pool_mon PUPITAR
	pool_mon TYRANITAR
	pool_mon STEELIX
	pool_mon FERALIGATR
	pool_mon AMPHAROS
LancePool_Warp:
	pool_mon EXEGGUTOR, 1 ; Alolan
	pool_mon ELECTIVIRE
LancePool_End:

; The Elite Four Koga's own pool, split from the gym KogaPool because the two
; roles now differ: Articuno is Elite Four only (and Beedrill gym only).
KogaE4Pool:
	pool_mon EKANS
	pool_mon ARBOK
	pool_mon NIDORAN_M
	pool_mon NIDORINO
	pool_mon NIDOKING
	pool_mon NIDORAN_F
	pool_mon NIDORINA
	pool_mon NIDOQUEEN
	pool_mon ZUBAT
	pool_mon GOLBAT
	pool_mon GRIMER
	pool_mon MUK
	pool_mon WEEZING
	pool_mon KOFFING
	pool_mon VENONAT
	pool_mon VENOMOTH
	pool_mon GASTLY
	pool_mon HAUNTER
	pool_mon GENGAR
	pool_mon BULBASAUR
	pool_mon IVYSAUR
	pool_mon VENUSAUR
	pool_mon ODDISH
	pool_mon GLOOM
	pool_mon VILEPLUME
	pool_mon BELLSPROUT
	pool_mon WEEPINBELL
	pool_mon VICTREEBEL
	pool_mon WEEDLE
	pool_mon KAKUNA
	pool_mon TENTACOOL
	pool_mon TENTACRUEL
	pool_mon PARASECT
	pool_mon TANGELA
	pool_mon HYPNO
	pool_mon ELECTRODE
	pool_mon MAGMAR
	pool_mon LAPRAS
	pool_mon SCYTHER
	pool_mon RHYDON
	pool_mon NINETALES
	pool_mon CHANSEY
	pool_mon DITTO
	pool_mon PIDGEY
	pool_mon PIDGEOTTO
	pool_mon PIDGEOT
	pool_mon VAPOREON
	pool_mon ARTICUNO ; Elite Four only - see KogaPool's BEEDRILL
KogaE4Pool_Johto:
	pool_mon CROBAT
	pool_mon QWILFISH
	pool_mon ARIADOS
	pool_mon SPINARAK
	pool_mon FORRETRESS
	pool_mon STANTLER
	pool_mon LANTURN
	pool_mon SCIZOR
	pool_mon GIRAFARIG
	pool_mon MEGANIUM
	pool_mon SHUCKLE
KogaE4Pool_Warp:
	pool_mon GRIMER, 1 ; Alolan
	pool_mon MUK, 1 ; Alolan
	pool_mon QWILFISH, 1 ; Hisuian
	pool_mon SLOWBRO, 1 ; Galarian
	pool_mon SLOWKING, 1 ; Galarian
	pool_mon SNEASEL, 1 ; Hisuian
	pool_mon WEEZING, 1 ; Galarian
	pool_mon WOOPER, 1 ; Paldean
KogaE4Pool_End:

; ---------------------------------------------------------------------------
; Rival (Champion). Full roster list, transcribed as specified.
;
; Entries are BASE forms, and that is load-bearing: the Champion spec sets
; BIT_PSPEC_NO_RIVAL_STARTER, which rejects a draw EQUAL to wRivalStarter, and
; the starter is always a base species. A base-form pool therefore blocks the
; whole line of whatever he picked - list CHARMANDER, never CHARMELEON.
; SEADRA is entered as HORSEA for exactly that reason (at level 60+
; ScaleTrainer_evolution promotes it to Kingdra anyway).
;
; The accepted exceptions, listed by name: the eeveelutions
; (VAPOREON / JOLTEON / FLAREON and the pinned Espeon / Umbreon / Glaceon /
; Sylveon / Leafeon forms), SCIZOR and ELECTIVIRE. Only an EEVEE / SCYTHER /
; ELECTABUZZ starter can double up with those. test_rival3_pool_is_base_forms
; holds the rest of the pool to the rule.
;
; Groups follow engine/pokemon/rarity.asm (tools/list_pool_candidates.py
; --species): SCIZOR is Johto, ELECTIVIRE is Warp. Espeon / Umbreon sit in the
; Johto run, as KarenPool's Umbreon does; the three later eeveelutions are Warp.
; ---------------------------------------------------------------------------
RivalThreePool:
	pool_mon GROWLITHE
	pool_mon PONYTA
	pool_mon WEEDLE
	pool_mon CHARMANDER
	pool_mon NIDORAN_M
	pool_mon ELECTABUZZ
	pool_mon SLOWPOKE
	pool_mon PIDGEY
	pool_mon BULBASAUR
	pool_mon SQUIRTLE
	pool_mon RHYHORN
	pool_mon NIDORAN_F
	pool_mon MAGMAR
	pool_mon SCYTHER
	pool_mon KRABBY
	pool_mon GEODUDE
	pool_mon DODUO
	pool_mon EEVEE
	pool_mon VAPOREON
	pool_mon JOLTEON
	pool_mon FLAREON
	pool_mon PINSIR
	pool_mon SPEAROW
	pool_mon ABRA
	pool_mon HORSEA
	pool_mon MAGIKARP
	pool_mon EXEGGCUTE
	pool_mon SANDSHREW
	pool_mon VULPIX
	pool_mon MAGNEMITE
	pool_mon SHELLDER
	pool_mon MACHOP
	pool_mon AERODACTYL
	pool_mon TAUROS
	pool_mon CUBONE
	pool_mon CLEFAIRY
	pool_mon GASTLY
	pool_mon DRATINI
	pool_mon ZAPDOS
	pool_mon RATTATA
RivalThreePool_Johto:
	pool_mon SCIZOR
	pool_mon LARVITAR
	pool_mon HOUNDOUR
	pool_mon SKARMORY
	pool_mon HERACROSS
	pool_mon MILTANK
	pool_mon SWINUB
	pool_mon JOLTEON, 1 ; Espeon
	pool_mon JOLTEON, 2 ; Umbreon
RivalThreePool_Warp:
	pool_mon ELECTIVIRE
	pool_mon VAPOREON, 1 ; Glaceon
	pool_mon VAPOREON, 2 ; Sylveon
	pool_mon FLAREON, 1 ; Leafeon
RivalThreePool_End:
