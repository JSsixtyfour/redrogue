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
	const POOL_BROCK
	const POOL_MISTY
	const POOL_LT_SURGE
	const POOL_ERIKA
	const POOL_KOGA
	const POOL_BLAINE
	const POOL_SABRINA
	const POOL_GIOVANNI
	const POOL_BUGSY
	const POOL_WHITNEY
	const POOL_MORTY
	const POOL_CHUCK
	const POOL_JASMINE
	const POOL_PRYCE
	const POOL_CLAIR
	const POOL_JANINE
	const POOL_WILL
	const POOL_KAREN
; Phase 7f: procedural stage-event characters (PROCEDURAL_WILD_AREA_PLAN.md).
	const POOL_JESSIE_JAMES
	const POOL_PSYCHIC
	const POOL_BURGLAR
	const POOL_JOY
	const POOL_JENNY
; Trainer Revamp (TRAINER_REVAMP_FIXES_PLAN.md step 4). Appended rather than
; slotted in by role so no existing pool id moves.
	const POOL_LORELEI
	const POOL_BRUNO
	const POOL_AGATHA
	const POOL_LANCE
	const POOL_KOGA_E4
	const POOL_RIVAL3
DEF NUM_TRAINER_POOLS EQU const_value

TrainerPoolTable::
	table_width POOL_TABLE_ENTRY_SIZE, TrainerPoolTable
	trainer_pool FalknerPool
	trainer_pool BrockPool
	trainer_pool MistyPool
	trainer_pool LtSurgePool
	trainer_pool ErikaPool
	trainer_pool KogaPool
	trainer_pool BlainePool
	trainer_pool SabrinaPool
	trainer_pool GiovanniPool
	trainer_pool BugsyPool
	trainer_pool WhitneyPool
	trainer_pool MortyPool
	trainer_pool ChuckPool
	trainer_pool JasminePool
	trainer_pool PrycePool
	trainer_pool ClairPool
	trainer_pool JaninePool
	trainer_pool WillPool
	trainer_pool KarenPool
	trainer_pool JessieJamesPool
	trainer_pool PsychicPool
	trainer_pool BurglarPool
	trainer_pool JoyPool
	trainer_pool JennyPool
	trainer_pool LoreleiPool
	trainer_pool BrunoPool
	trainer_pool AgathaPool
	trainer_pool LancePool
	trainer_pool KogaE4Pool
	trainer_pool RivalThreePool
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

; ---------------------------------------------------------------------------
; Brock - Rock. Matches the plan's own pools.txt example verbatim: type ROCK
; plus explicit additions OMANYTE/OMASTAR/KABUTO/KABUTOPS/AERODACTYL/GOLBAT/
; CHANSEY, minus PARAS. GOLBAT and CHANSEY are genuinely off-type - the
; brief's own deliberate "surprising pick" additions, kept rather than
; smoothed away.
; ---------------------------------------------------------------------------
BrockPool:
	pool_mon GEODUDE
	pool_mon GRAVELER
	pool_mon GOLEM
	pool_mon ONIX
	pool_mon RHYHORN
	pool_mon RHYDON
	pool_mon OMANYTE
	pool_mon OMASTAR
	pool_mon KABUTO
	pool_mon KABUTOPS
	pool_mon AERODACTYL
	pool_mon GOLBAT
	pool_mon CHANSEY
BrockPool_Johto:
	pool_mon SUDOWOODO
	pool_mon CORSOLA
	pool_mon SHUCKLE
	pool_mon LARVITAR
	pool_mon PUPITAR
	pool_mon TYRANITAR
BrockPool_Warp:
BrockPool_End:

; ---------------------------------------------------------------------------
; Misty - Water.
; ---------------------------------------------------------------------------
MistyPool:
	pool_mon STARYU
	pool_mon STARMIE
	pool_mon PSYDUCK
	pool_mon GOLDUCK
	pool_mon POLIWAG
	pool_mon POLIWRATH
	pool_mon TENTACOOL
	pool_mon TENTACRUEL
	pool_mon SEADRA
	pool_mon SEAKING
	pool_mon GYARADOS
	pool_mon LAPRAS
	pool_mon VAPOREON
	pool_mon SLOWBRO
	pool_mon SQUIRTLE
	pool_mon BLASTOISE
MistyPool_Johto:
	pool_mon CHINCHOU
	pool_mon LANTURN
	pool_mon QWILFISH
	pool_mon OCTILLERY
	pool_mon MANTINE
	pool_mon WOOPER
	pool_mon QUAGSIRE
	pool_mon MARILL
	pool_mon AZUMARILL
	pool_mon KINGDRA
MistyPool_Warp:
MistyPool_End:

; ---------------------------------------------------------------------------
; Lt. Surge - Electric.
; ---------------------------------------------------------------------------
LtSurgePool:
	pool_mon PIKACHU
	pool_mon RAICHU
	pool_mon VOLTORB
	pool_mon ELECTRODE
	pool_mon MAGNEMITE
	pool_mon MAGNETON
	pool_mon ELECTABUZZ
	pool_mon ZAPDOS
LtSurgePool_Johto:
	pool_mon MAREEP
	pool_mon FLAAFFY
	pool_mon AMPHAROS
LtSurgePool_Warp:
LtSurgePool_End:

; ---------------------------------------------------------------------------
; Erika - Grass.
; ---------------------------------------------------------------------------
ErikaPool:
	pool_mon BULBASAUR
	pool_mon IVYSAUR
	pool_mon VENUSAUR
	pool_mon ODDISH
	pool_mon GLOOM
	pool_mon VILEPLUME
	pool_mon BELLSPROUT
	pool_mon WEEPINBELL
	pool_mon VICTREEBEL
	pool_mon EXEGGCUTE
	pool_mon EXEGGUTOR
	pool_mon TANGELA
	pool_mon PARASECT
ErikaPool_Johto:
	pool_mon CHIKORITA
	pool_mon BAYLEEF
	pool_mon MEGANIUM
	pool_mon HOPPIP
	pool_mon SKIPLOOM
	pool_mon JUMPLUFF
	pool_mon SUNKERN
	pool_mon SUNFLORA
	pool_mon BELLOSSOM
ErikaPool_Warp:
ErikaPool_End:

; ---------------------------------------------------------------------------
; Koga - Poison.
; ---------------------------------------------------------------------------
KogaPool:
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
KogaPool_Johto:
	pool_mon CROBAT
	pool_mon QWILFISH
KogaPool_Warp:
KogaPool_End:

; ---------------------------------------------------------------------------
; Blaine - Fire.
; ---------------------------------------------------------------------------
BlainePool:
	pool_mon VULPIX
	pool_mon NINETALES
	pool_mon GROWLITHE
	pool_mon ARCANINE
	pool_mon PONYTA
	pool_mon RAPIDASH
	pool_mon CHARMANDER
	pool_mon CHARMELEON
	pool_mon CHARIZARD
	pool_mon MOLTRES
	pool_mon MAGMAR
BlainePool_Johto:
	pool_mon CYNDAQUIL
	pool_mon QUILAVA
	pool_mon TYPHLOSION
	pool_mon SLUGMA
	pool_mon MAGCARGO
	pool_mon HOUNDOUR
	pool_mon HOUNDOOM
BlainePool_Warp:
BlainePool_End:

; ---------------------------------------------------------------------------
; Sabrina - Psychic. MEW and MEWTWO are ordinary entries here (both
; RARITY_TIER_UBER), gated the normal way by BIT_PSPEC_ALLOW_UBER on
; whichever spec sets it - matching canon's "Sabrina has Mewtwo" without
; inventing a second mechanism. This is separate from her named legendary
; ace-substitution encounter (Celebi/Lugia added to Mew/Mewtwo per
; GYM_LEADER_EXPANSION_PLAN.md Phase 3), which extends
; custom_functions/legendary_boss_helpers.asm and is not a pool entry at all.
; ---------------------------------------------------------------------------
SabrinaPool:
	pool_mon ABRA
	pool_mon KADABRA
	pool_mon ALAKAZAM
	pool_mon DROWZEE
	pool_mon HYPNO
	pool_mon MR_MIME
	pool_mon JYNX
	pool_mon SLOWPOKE
	pool_mon SLOWBRO
	pool_mon EXEGGCUTE
	pool_mon EXEGGUTOR
	pool_mon STARMIE
	pool_mon MEW
	pool_mon MEWTWO
SabrinaPool_Johto:
	pool_mon NATU
	pool_mon XATU
	pool_mon GIRAFARIG
	pool_mon SLOWKING
SabrinaPool_Warp:
SabrinaPool_End:

; ---------------------------------------------------------------------------
; Giovanni - Ground, plus the "crime boss" off-type picks his authored team
; already carries (PERSIAN, MEOWTH, KANGASKHAN).
; ---------------------------------------------------------------------------
GiovanniPool:
	pool_mon NIDORAN_M
	pool_mon NIDORINO
	pool_mon NIDOKING
	pool_mon NIDORAN_F
	pool_mon NIDORINA
	pool_mon NIDOQUEEN
	pool_mon RHYHORN
	pool_mon RHYDON
	pool_mon ONIX
	pool_mon DUGTRIO
	pool_mon DIGLETT
	pool_mon SANDSHREW
	pool_mon SANDSLASH
	pool_mon GEODUDE
	pool_mon GRAVELER
	pool_mon GOLEM
	pool_mon PERSIAN
	pool_mon MEOWTH
	pool_mon KANGASKHAN
	pool_mon CUBONE
	pool_mon MAROWAK
	pool_mon GYARADOS
GiovanniPool_Johto:
	pool_mon PHANPY
	pool_mon DONPHAN
	pool_mon STEELIX
	pool_mon SNUBBULL
	pool_mon GRANBULL
	pool_mon MURKROW
	pool_mon HOUNDOUR
	pool_mon HOUNDOOM
GiovanniPool_Warp:
GiovanniPool_End:

; ---------------------------------------------------------------------------
; Bugsy - Bug.
; ---------------------------------------------------------------------------
BugsyPool:
	pool_mon CATERPIE
	pool_mon METAPOD
	pool_mon BUTTERFREE
	pool_mon WEEDLE
	pool_mon KAKUNA
	pool_mon BEEDRILL
	pool_mon PARAS
	pool_mon PARASECT
	pool_mon VENONAT
	pool_mon VENOMOTH
	pool_mon SCYTHER
	pool_mon PINSIR
BugsyPool_Johto:
	pool_mon LEDYBA
	pool_mon LEDIAN
	pool_mon SPINARAK
	pool_mon ARIADOS
	pool_mon YANMA
	pool_mon FORRETRESS
	pool_mon HERACROSS
	pool_mon SHUCKLE
BugsyPool_Warp:
BugsyPool_End:

; ---------------------------------------------------------------------------
; Whitney - Normal.
; ---------------------------------------------------------------------------
WhitneyPool:
	pool_mon RATTATA
	pool_mon RATICATE
	pool_mon CLEFAIRY
	pool_mon CLEFABLE
	pool_mon JIGGLYPUFF
	pool_mon WIGGLYTUFF
	pool_mon PERSIAN
	pool_mon CHANSEY
	pool_mon KANGASKHAN
	pool_mon TAUROS
	pool_mon DITTO
	pool_mon EEVEE
	pool_mon SNORLAX
	pool_mon PORYGON
WhitneyPool_Johto:
	pool_mon SENTRET
	pool_mon FURRET
	pool_mon TOGEPI
	pool_mon TOGETIC
	pool_mon MILTANK
	pool_mon BLISSEY
	pool_mon STANTLER
	pool_mon DUNSPARCE
	pool_mon GRANBULL
	pool_mon PORYGON2
WhitneyPool_Warp:
WhitneyPool_End:

; ---------------------------------------------------------------------------
; Morty - Ghost. Small and deliberately so: GASTLY/HAUNTER/GENGAR and
; MISDREAVUS are the entire pure-or-mixed Ghost roster this dex has: canon's
; own Morty is likewise almost entirely the Gastly line.
; ---------------------------------------------------------------------------
MortyPool:
	pool_mon GASTLY
	pool_mon HAUNTER
	pool_mon GENGAR
MortyPool_Johto:
	pool_mon MISDREAVUS
MortyPool_Warp:
MortyPool_End:

; ---------------------------------------------------------------------------
; Chuck - Fighting.
; ---------------------------------------------------------------------------
ChuckPool:
	pool_mon MANKEY
	pool_mon PRIMEAPE
	pool_mon MACHOP
	pool_mon MACHOKE
	pool_mon MACHAMP
	pool_mon HITMONLEE
	pool_mon HITMONCHAN
ChuckPool_Johto:
	pool_mon HERACROSS
ChuckPool_Warp:
ChuckPool_End:

; ---------------------------------------------------------------------------
; Jasmine - Steel. Small on purpose: Steel-type coverage in this dex is
; genuinely thin pre-Warp-group (SCIZOR and MAGNEZONE do not exist as
; directly rollable entries here - see the header note on Warp species).
; ---------------------------------------------------------------------------
JasminePool:
	pool_mon MAGNEMITE
	pool_mon MAGNETON
JasminePool_Johto:
	pool_mon STEELIX
	pool_mon FORRETRESS
JasminePool_Warp:
JasminePool_End:

; ---------------------------------------------------------------------------
; Pryce - Ice.
; ---------------------------------------------------------------------------
PrycePool:
	pool_mon SEEL
	pool_mon DEWGONG
	pool_mon JYNX
	pool_mon ARTICUNO
PrycePool_Johto:
	pool_mon SWINUB
	pool_mon PILOSWINE
	pool_mon SNEASEL
PrycePool_Warp:
PrycePool_End:

; ---------------------------------------------------------------------------
; Clair - Dragon. Small on purpose: DRATINI's line is this dex's only pure
; Dragon family, so KINGDRA (Water/Dragon) is the only Johto addition that
; actually shares her type.
; ---------------------------------------------------------------------------
ClairPool:
	pool_mon DRATINI
	pool_mon DRAGONAIR
	pool_mon DRAGONITE
ClairPool_Johto:
	pool_mon KINGDRA
ClairPool_Warp:
ClairPool_End:

; ---------------------------------------------------------------------------
; Janine - Poison, mirroring Koga's theme (her Fuchsia Gym predecessor).
; ---------------------------------------------------------------------------
JaninePool:
	pool_mon EKANS
	pool_mon ARBOK
	pool_mon ZUBAT
	pool_mon GOLBAT
	pool_mon GRIMER
	pool_mon MUK
	pool_mon WEEZING
	pool_mon KOFFING
	pool_mon NIDORAN_M
	pool_mon NIDORINO
	pool_mon NIDOKING
	pool_mon NIDORAN_F
	pool_mon NIDORINA
	pool_mon NIDOQUEEN
	pool_mon VENONAT
	pool_mon VENOMOTH
JaninePool_Johto:
	pool_mon CROBAT
	pool_mon QWILFISH
JaninePool_Warp:
JaninePool_End:

; ---------------------------------------------------------------------------
; Will - Elite Four, Psychic. Matches the plan's own pools.txt example
; verbatim: type PSYCHIC plus explicit additions CLEFABLE/ELECTABUZZ/MANTINE/
; FLAREON/CHANSEY/HYPNO, and ESPEON translated to this tree's JOLTEON form 1
; (there is no ESPEON species - see [[project_forms_are_not_species]]). NATU
; is added alongside the brief's own XATU as its pre-evolution.
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
	pool_mon JOLTEON, 1 ; pinned Espeon form
WillPool_Johto:
	pool_mon NATU
	pool_mon XATU
	pool_mon SLOWKING
	pool_mon GIRAFARIG
	pool_mon MANTINE
WillPool_Warp:
WillPool_End:

; ---------------------------------------------------------------------------
; Karen - Elite Four, Dark. UMBREON is JOLTEON form 2 in this tree, pinned for
; the same reason WillPool pins Espeon.
;
; Dark did not exist as a type until Generation 2, so no Gen 1 species in this
; dex was ever Dark-typed, and this pool started life with an EMPTY Kanto run.
; That is a real fault rather than just thin content: with Johto locked every
; run of the pool is ineligible, PartyGenRollFromPool takes its .giveUp branch,
; and that branch falls back to the pool's FIRST entry UNFILTERED - yielding a
; team of five identical Murkrow rather than a crash, which is exactly the kind
; of fault that survives a clean build. The Kanto run below is her own Gen 2
; roster's Kanto half (Gengar and Vileplume are literally on it) plus three
; Kanto mons that read as her kind of dark. Phase 7 is expected to draw Karen
; only when Johto is enabled, but the pool must not depend on that holding.
; ---------------------------------------------------------------------------
KarenPool:
	pool_mon GENGAR
	pool_mon VILEPLUME
	pool_mon ARBOK
	pool_mon PERSIAN
	pool_mon GOLBAT
KarenPool_Johto:
	pool_mon MURKROW
	pool_mon HOUNDOUR
	pool_mon HOUNDOOM
	pool_mon SNEASEL
	pool_mon TYRANITAR
	pool_mon JOLTEON, 2 ; pinned Umbreon form
KarenPool_Warp:
KarenPool_End:

; ===========================================================================
; Phase 7f pools - procedural stage-event characters
; (PROCEDURAL_WILD_AREA_PLAN.md, 7f). Team size and level ride
; stage_event_team_spec's own round ladder (data/trainers/party_specs.asm), so
; every pool below just supplies the species.
;
; The Warp run is left empty on all five, matching FalknerPool's own precedent
; and the caution above KarenPool's entry: LICKILICKY, PORYGON2/PORYGON_Z and
; WEAVILE are all classification-only Warp-group species reached by evolving a
; Kanto/Johto pool member (LICKITUNG, PORYGON, SNEASEL respectively) once that
; group unlocks, not by a direct pool_mon entry. "Meowth alternates" likewise
; need no Warp entry - they are FORMS of the one Kanto MEOWTH entry, rolled by
; the ordinary default POOL_FORM_ROLL, independent of which run a species sits
; in.
; ===========================================================================

; ---------------------------------------------------------------------------
; Jessie & James - the paired villain. "Line" families expanded to every
; member; the plan's single-species entries (Lickitung, Shellder, Chansey,
; Scyther, Growlithe, Mr. Mime, Pinsir, Porygon, Hitmonlee) are deliberately
; NOT expanded to their evolutions, several of which are Warp-group and reach
; the team automatically once that group unlocks (see the header note above).
; ---------------------------------------------------------------------------
JessieJamesPool:
	pool_mon MEOWTH
	pool_mon EKANS
	pool_mon LICKITUNG
	pool_mon SHELLDER
	pool_mon CHANSEY
	pool_mon KOFFING
	pool_mon SCYTHER
	pool_mon CLEFAIRY
	pool_mon GROWLITHE
	pool_mon MR_MIME
	pool_mon MAGIKARP
	pool_mon BELLSPROUT
	pool_mon PIDGEY
	pool_mon PINSIR
	pool_mon GRIMER
	pool_mon PORYGON
	pool_mon KRABBY
	pool_mon HITMONLEE
	pool_mon MACHOP
	pool_mon RHYHORN
	pool_mon ZUBAT
	pool_mon MANKEY
JessieJamesPool_Johto:
	pool_mon YANMA
	pool_mon STANTLER
	pool_mon SNEASEL
	pool_mon HOPPIP
JessieJamesPool_Warp:
JessieJamesPool_End:

; ---------------------------------------------------------------------------
; The Psychic - themed on the type, the same brief SabrinaPool follows.
; ---------------------------------------------------------------------------
PsychicPool:
	pool_mon ABRA
	pool_mon SLOWPOKE
	pool_mon DROWZEE
	pool_mon EXEGGCUTE
	pool_mon MR_MIME
	pool_mon JYNX
	pool_mon PSYDUCK
	pool_mon STARYU
	pool_mon CLEFAIRY
	pool_mon PORYGON
PsychicPool_Johto:
	pool_mon NATU
	pool_mon GIRAFARIG
PsychicPool_Warp:
PsychicPool_End:

; ---------------------------------------------------------------------------
; The Burglar - sneaky, venomous, urban-pest flavour rather than a type theme
; (Gen 1 has no Dark type to draw on).
; ---------------------------------------------------------------------------
BurglarPool:
	pool_mon RATTATA
	pool_mon EKANS
	pool_mon GRIMER
	pool_mon KOFFING
	pool_mon ZUBAT
	pool_mon MEOWTH
	pool_mon SANDSHREW
	pool_mon GASTLY
	pool_mon MANKEY
	pool_mon DIGLETT
BurglarPool_Johto:
	pool_mon MURKROW
	pool_mon SNEASEL
BurglarPool_Warp:
BurglarPool_End:

; ---------------------------------------------------------------------------
; Nurse Joy - "healing and cute". Seeded from the donor species in
; reference/yellow_legacy/joy_jenny/options.asm (cRz-Shadows/Pokemon_Yellow_Legacy),
; taken as a pool rather than pasted as the donor's flat level-65 team - see
; that file's own README - then extended on the user's brief.
;
; SYLVEON is VAPOREON form 2, and it is the one deliberate exception to the
; "sublist must match the species' rarity group" rule at the top of this file.
; VAPOREON is a KANTO-group species, so by that rule the entry would belong in
; the Kanto run - but a PINNED form index is passed through UNGATED
; (PartyGenResolveForm says so explicitly, matching authored TRAINERPARTY_FORMS
; teams), and Sylveon is Time Warp content. Sitting it in the _Warp run is the
; only thing that stops a Kanto-only run fielding one, and it serves exactly
; the intent that rule exists for: no late-game-only content from round one.
;
; It is also the one entry here that is NOT a base form, because Sylveon has no
; pre-evolution that reaches it - EEVEE picks its evolution at random
; (EvolveMonByLevel.handleeevee), so a plain EEVEE entry could never guarantee
; one. Consequence: a round-1 Time Warp run can field a level-5 Sylveon.
; Accepted as the price of having it at all.
; ---------------------------------------------------------------------------
JoyPool:
	pool_mon KANGASKHAN
	pool_mon SNORLAX
	pool_mon STARYU
	pool_mon PORYGON
	pool_mon EXEGGCUTE
	pool_mon CHANSEY
	pool_mon JIGGLYPUFF
	pool_mon CLEFAIRY
	pool_mon PIKACHU
JoyPool_Johto:
	pool_mon MILTANK
	pool_mon MARILL
	pool_mon TOGEPI
JoyPool_Warp:
	pool_mon VAPOREON, 2          ; Sylveon
JoyPool_End:

; ---------------------------------------------------------------------------
; Officer Jenny - police-dog and patrol flavour, same donor source and
; reasoning as JoyPool above, extended on the user's brief.
;
; Every line here is entered at its BASE form, per this file's own convention:
; GROWLITHE not Arcanine, GASTLY not Gengar, SQUIRTLE not Blastoise, PIDGEY not
; Pidgeot, PARAS not Parasect, HOPPIP not Jumpluff, CHIKORITA not Meganium,
; TOTODILE not Feraligatr, MARILL not Azumarill, SNUBBULL not Granbull, REMORAID
; not Octillery. ScaleTrainer_evolution promotes each one back at a high enough
; level, so listing the base fixes the round-1 case without weakening round 9 -
; and listing BOTH stages, as this pool used to, is exactly what produced the
; reported level-5 Arcanine.
;
; HITMONCHAN is the one entry with no evolution in either direction - there is
; no TYROGUE in this tree - so it is already its own base form, the same way
; HITMONLEE sits in JessieJamesPool.
;
; The KANTO run is deliberately 9 deep, not 6. Seven of the twelve lines this
; roster wanted are Johto-group and correctly sit below, which left the Kanto
; run - the only one a first playthrough ever sees - the same size as a round-9
; team. PARTY_GEN_MAX_RETRIES is 8 and PartyGenRollFromPool is
; bounded-then-accept, so a pool that tight repeats a species outright. See
; audit_stage_pool_base_forms.py.
; ---------------------------------------------------------------------------
JennyPool:
	pool_mon PIDGEY
	pool_mon SQUIRTLE
	pool_mon TANGELA
	pool_mon GASTLY
	pool_mon PARAS
	pool_mon GROWLITHE
	pool_mon MACHOP
	pool_mon PONYTA
	pool_mon HITMONCHAN
JennyPool_Johto:
	pool_mon SPINARAK
	pool_mon HOPPIP
	pool_mon CHIKORITA
	pool_mon TOTODILE
	pool_mon MARILL
	pool_mon SNUBBULL
	pool_mon REMORAID
JennyPool_Warp:
JennyPool_End:

; ===========================================================================
; Trainer Revamp pools (TRAINER_REVAMP_FIXES_PLAN.md step 4).
;
; !!! The five Elite Four pools below are PLACEHOLDERS: each member's own
; authored team (plus Articuno for the E4 Koga), so step 4's wiring builds
; and tests against real content. Step 7 replaces them with the user's full
; lists from the plan's "E4 pool contents" section, expanding every
; "all <type>" clause with tools/list_pool_candidates.py.
; ===========================================================================

LoreleiPool:
	pool_mon DEWGONG
	pool_mon CLOYSTER
	pool_mon SLOWBRO
	pool_mon JYNX
	pool_mon LAPRAS
LoreleiPool_Johto:
LoreleiPool_Warp:
LoreleiPool_End:

BrunoPool:
	pool_mon ONIX
	pool_mon HITMONCHAN
	pool_mon HITMONLEE
	pool_mon MACHAMP
BrunoPool_Johto:
BrunoPool_Warp:
BrunoPool_End:

AgathaPool:
	pool_mon GENGAR
	pool_mon GOLBAT
	pool_mon HAUNTER
	pool_mon ARBOK
AgathaPool_Johto:
AgathaPool_Warp:
AgathaPool_End:

LancePool:
	pool_mon GYARADOS
	pool_mon DRAGONAIR
	pool_mon AERODACTYL
	pool_mon DRAGONITE
LancePool_Johto:
LancePool_Warp:
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
	pool_mon ARTICUNO
KogaE4Pool_Johto:
	pool_mon CROBAT
	pool_mon QWILFISH
KogaE4Pool_Warp:
KogaE4Pool_End:

; ---------------------------------------------------------------------------
; Rival (Champion). The user's list, transcribed in full.
;
; Entries are BASE forms, and that is load-bearing: the Champion spec sets
; BIT_PSPEC_NO_RIVAL_STARTER, which rejects a draw EQUAL to wRivalStarter, and
; the starter is always a base species. A base-form pool therefore blocks the
; whole line of whatever he picked - list CHARMANDER, never CHARMELEON. The
; user's SEADRA is entered as HORSEA for exactly that reason (at level 60+
; ScaleTrainer_evolution promotes it to Kingdra anyway).
;
; The accepted exceptions, listed by name by the user: the eeveelutions
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
