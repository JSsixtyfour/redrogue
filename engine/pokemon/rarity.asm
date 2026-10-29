; Rarity pools for every random species pick in Red Rogue.
;
; Structure (see constants/rogue_species_groups.asm):
;
;   RarityGroupTable  ->  one `dw` per species group
;        |
;        +-> per-group tier table, NUM_RARITY_TIERS x RARITY_TIER_ENTRY_SIZE
;                 db base count, db total count, dw species list
;
; Each two-byte (species, form) list is laid out as [base forms][evolved forms]. Only the
; base-form prefix is rolled directly; evolved forms are reached through
; EvolveMonByLevel and exist here so an arbitrary owned species can still be
; classified back to its tier (RogueClassifySpecies).
;
; Counts are computed by the assembler from the list labels. They used to be
; hand-summed EQUs kept in sync by hand in TWO files, which is exactly the kind
; of bookkeeping that silently rots - do not reintroduce them.
;
; A zero base count makes a group invisible to the roller at that tier.
; Every direct species/form entry in enabled groups has equal weight.

; Class-roll thresholds against a 0-255 roll. Ultraball is the fall-through, so
; it deliberately has no threshold of its own. Masterball and uber are never
; reachable from the random path - a caller must ask for them by class.
DEF pokeball_odds  EQU $7F
DEF greatball_odds EQU $66 + $7F

; \1 = list label. Optional \2 is the default direct-pick boundary.
; Conditional pools can extend that boundary without duplicating whole lists.
MACRO rarity_tier
	IF _NARG == 2
	db (\2 - \1) / 2
	ELSE
	db (\1_Evos - \1) / 2   ; rollable base-form count
	ENDC
	db (\1_End  - \1) / 2   ; total count, for classification
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

; Johto - unlocked after the first champion win. Being populated in Phase 2;
; every tier still empty here is skipped by the roller, so a partially filled
; group behaves exactly like a fully filled smaller one.
RarityJohto:
	rarity_tier JohtoPokeball
	rarity_tier JohtoGreatball, JohtoGreatball.defaultEvos
	rarity_tier JohtoUltraball
	rarity_tier JohtoMasterball
	rarity_tier JohtoUber

; When Johto AND Warp are active, Swinub's whole line becomes Great Ball.
; Skip its first pair in Poke Ball and include its extra Great Ball pair.
; The other three Johto tiers are unchanged and use RarityJohto directly.
RarityJohtoWarp:
	db (JohtoPokeball_Evos - JohtoPokeball.withoutSwinub) / 2
	db (JohtoPokeball_End - JohtoPokeball.withoutSwinub) / 2
	dw JohtoPokeball.withoutSwinub
	rarity_tier JohtoGreatball
RarityJohtoWarpEnd:
ASSERT RarityJohtoWarpEnd - RarityJohtoWarp == 2 * RARITY_TIER_ENTRY_SIZE

; Kanto Time Warp - unlocked after the second champion win. Populated in Phase 2.
RarityWarp:
	rarity_tier WarpPokeball
	rarity_tier WarpGreatball
	rarity_tier WarpUltraball
	rarity_tier WarpMasterball
	rarity_tier WarpUber


; Each entry explicitly names its species and form. Omitted form means 0.
; The prefix before _Evos is rolled uniformly; the tail is classification only.
MACRO rarity_mon
	db \1
	IF _NARG == 2
		db \2
	ELSE
		db 0
	ENDC
ENDM

KantoPokeball:
	rarity_mon CATERPIE
	rarity_mon WEEDLE
	rarity_mon PIDGEY
	rarity_mon RATTATA
	rarity_mon FARFETCHD
	rarity_mon EKANS
	rarity_mon DITTO
	rarity_mon MANKEY
	rarity_mon KRABBY
	rarity_mon CUBONE
	rarity_mon GRIMER
	rarity_mon GROWLITHE
	rarity_mon SEEL
	rarity_mon VOLTORB
	rarity_mon SPEAROW
	rarity_mon KABUTO
	rarity_mon MAGNEMITE
	rarity_mon POLIWAG
	rarity_mon ODDISH
	rarity_mon ZUBAT
	rarity_mon JIGGLYPUFF
	rarity_mon SANDSHREW
	rarity_mon PARAS
	rarity_mon PSYDUCK
	rarity_mon BELLSPROUT
	rarity_mon KOFFING
	rarity_mon HORSEA
	rarity_mon GOLDEEN
KantoPokeball_Evos:
; stage 2
	rarity_mon METAPOD
	rarity_mon KAKUNA
	rarity_mon PIDGEOTTO
	rarity_mon RATICATE
	rarity_mon ARBOK
	rarity_mon PRIMEAPE
	rarity_mon KINGLER
	rarity_mon MAROWAK
	rarity_mon MUK
	rarity_mon ARCANINE
	rarity_mon DEWGONG
	rarity_mon ELECTRODE
	rarity_mon FEAROW
	rarity_mon KABUTOPS
	rarity_mon MAGNETON
	rarity_mon POLIWHIRL
	rarity_mon GLOOM
	rarity_mon GOLBAT
	rarity_mon WIGGLYTUFF
	rarity_mon SANDSLASH
	rarity_mon PARASECT
	rarity_mon GOLDUCK
	rarity_mon WEEPINBELL
	rarity_mon WEEZING
	rarity_mon SEADRA
	rarity_mon SEAKING
; stage 3
	rarity_mon BUTTERFREE
	rarity_mon BEEDRILL
	rarity_mon PIDGEOT
	rarity_mon POLIWRATH
	rarity_mon VILEPLUME
	rarity_mon VICTREEBEL
KantoPokeball_End:

KantoGreatball:
	rarity_mon BULBASAUR
	rarity_mon CHARMANDER
	rarity_mon SQUIRTLE
	rarity_mon EEVEE
	rarity_mon DODUO
	rarity_mon DRATINI
	rarity_mon OMANYTE
	rarity_mon MACHOP
	rarity_mon SHELLDER
	rarity_mon GEODUDE
	rarity_mon LICKITUNG
	rarity_mon NIDORAN_F
	rarity_mon CLEFAIRY
	rarity_mon DIGLETT
	rarity_mon MAGIKARP
	rarity_mon PIKACHU
	rarity_mon SLOWPOKE
	rarity_mon DROWZEE
	rarity_mon PONYTA
	rarity_mon MEOWTH
	rarity_mon VULPIX
	rarity_mon TANGELA
	rarity_mon VENONAT
	rarity_mon NIDORAN_M
	rarity_mon HITMONCHAN
	rarity_mon TENTACOOL
	rarity_mon ONIX
	rarity_mon PORYGON
KantoGreatball_Evos:
; stage 2
	rarity_mon IVYSAUR
	rarity_mon CHARMELEON
	rarity_mon WARTORTLE
	rarity_mon JOLTEON
	rarity_mon FLAREON
	rarity_mon VAPOREON
	rarity_mon DODRIO
	rarity_mon DRAGONAIR
	rarity_mon OMASTAR
	rarity_mon MACHOKE
	rarity_mon CLOYSTER
	rarity_mon GRAVELER
	rarity_mon NIDORINA
	rarity_mon CLEFABLE
	rarity_mon DUGTRIO
	rarity_mon GYARADOS
	rarity_mon RAICHU
	rarity_mon SLOWBRO
	rarity_mon HYPNO
	rarity_mon RAPIDASH
	rarity_mon PERSIAN
	rarity_mon NINETALES
	rarity_mon VENOMOTH
	rarity_mon NIDORINO
	rarity_mon TENTACRUEL
; stage 3
	rarity_mon VENUSAUR
	rarity_mon CHARIZARD
	rarity_mon BLASTOISE
	rarity_mon DRAGONITE
	rarity_mon MACHAMP
	rarity_mon GOLEM
	rarity_mon NIDOQUEEN
	rarity_mon NIDOKING
KantoGreatball_End:

KantoUltraball:
	rarity_mon GASTLY
	rarity_mon ABRA
	rarity_mon JYNX
	rarity_mon CHANSEY
	rarity_mon RHYHORN
	rarity_mon LAPRAS
	rarity_mon KANGASKHAN
	rarity_mon SCYTHER
	rarity_mon HITMONLEE
	rarity_mon MR_MIME
	rarity_mon ELECTABUZZ
	rarity_mon MAGMAR
	rarity_mon PINSIR
	rarity_mon AERODACTYL
KantoUltraball_Evos:
; stage 2
	rarity_mon HAUNTER
	rarity_mon KADABRA
	rarity_mon RHYDON
; stage 3
	rarity_mon GENGAR
	rarity_mon ALAKAZAM
KantoUltraball_End:

KantoMasterball:
	rarity_mon TAUROS
	rarity_mon SNORLAX
	rarity_mon EXEGGCUTE
	rarity_mon STARYU
	rarity_mon ZAPDOS
	rarity_mon ARTICUNO ; masterball with Zapdos since 2026-09-28 (user); was ultraball
	rarity_mon MOLTRES
KantoMasterball_Evos:
; stage 2
	rarity_mon EXEGGUTOR
	rarity_mon STARMIE
KantoMasterball_End:

; Never rollable and never reached by evolution - uber exists so MEW and MEWTWO
; classify into a tier of their own (the Legendary Boss challenge hands them out
; directly). Its base count is 0, so the roller skips it like an empty group.
KantoUber:
KantoUber_Evos:
	rarity_mon MEW
	rarity_mon MEWTWO
KantoUber_End:

; ===========================================================================
; Johto lists. Same layout as Kanto: [base forms][evolved forms], split by the
; _Evos label. Only the base prefix is rolled; the tail exists so an owned
; evolved mon still classifies back into its tier.
; ===========================================================================

; Starters sit in greatball, matching where the Kanto starters live.
; Base form of the Johto pokeball tier - common early-route mons.
JohtoPokeball:
	rarity_mon SWINUB ; Great Ball instead when Johto + Warp are both active
.withoutSwinub:
	rarity_mon SENTRET
	rarity_mon HOOTHOOT
	rarity_mon LEDYBA
	rarity_mon SPINARAK
	rarity_mon MARILL
	rarity_mon HOPPIP
	rarity_mon AIPOM
	rarity_mon SUNKERN
	rarity_mon WOOPER
	rarity_mon PINECO
	rarity_mon SNUBBULL
	rarity_mon TEDDIURSA
	rarity_mon SLUGMA
	rarity_mon CORSOLA
	rarity_mon REMORAID
JohtoPokeball_Evos:
; stage 1
	rarity_mon FURRET
	rarity_mon NOCTOWL
	rarity_mon LEDIAN
	rarity_mon ARIADOS
	rarity_mon AZUMARILL
	rarity_mon SKIPLOOM
	rarity_mon SUNFLORA
	rarity_mon QUAGSIRE
	rarity_mon FORRETRESS
	rarity_mon GRANBULL
	rarity_mon URSARING
	rarity_mon MAGCARGO
	rarity_mon PILOSWINE ; classified as Great Ball with Johto + Warp
	rarity_mon OCTILLERY
; stage 2
	rarity_mon JUMPLUFF
; Crobat/Bellossom/Politoed are evolved-only (from Golbat/Gloom/Poliwhirl, all
; Kanto base species - see the EVOLVE_LEVEL/EVOLVE_ITEM/EVOLVE_TRADE additions
; to their EvosMoves). Parked here as classification-only placeholders, same
; pattern as Weavile/Mamoswine/Mismagius in JohtoGreatball - the Kanto base
; species stay in the Kanto pool, since they predate this project.
	rarity_mon CROBAT
	rarity_mon BELLOSSOM
	rarity_mon POLITOED
; Kingdra is evolved-only (from Seadra, a Kanto POKEBALL-tier base species -
; see the EVOLVE_TRADE added to SeadraEvosMoves). Same classification-only-
; placeholder pattern as above, matched to Seadra's own tier.
	rarity_mon KINGDRA
; Annihilape/Magnezone/Sirfetch'd are post-Gen-2 evolutions of Kanto species,
; so they live in the WARP group, not here - see WarpPokeball below.
JohtoPokeball_End:

JohtoGreatball:
	rarity_mon CHIKORITA
	rarity_mon CYNDAQUIL
	rarity_mon TOTODILE
	rarity_mon MISDREAVUS
	rarity_mon SNEASEL
	rarity_mon HOUNDOUR
	rarity_mon PHANPY
	rarity_mon GIRAFARIG
	rarity_mon MAREEP
	rarity_mon CHINCHOU
	rarity_mon YANMA
	rarity_mon SUDOWOODO
	rarity_mon MURKROW
	rarity_mon QWILFISH
	rarity_mon DUNSPARCE
	rarity_mon SHUCKLE
	rarity_mon MANTINE
	rarity_mon NATU
	rarity_mon TOGEPI
.defaultEvos:
; Conditional direct pick: excluded by the default RarityJohto row above.
	rarity_mon SWINUB ; direct only with Johto + Warp; evolves through Mamoswine
JohtoGreatball_Evos:
; rarity_mon JOLTEON, 1 ; Eevee + Sun Stone -> Espeon (evolution only)
; rarity_mon JOLTEON, 2 ; Eevee + Dusk Stone -> Umbreon (evolution only)
; stage 1
	rarity_mon BAYLEEF
	rarity_mon QUILAVA
	rarity_mon CROCONAW
	rarity_mon HOUNDOOM
	rarity_mon DONPHAN
	rarity_mon FLAAFFY
	rarity_mon LANTURN
	rarity_mon XATU
	rarity_mon TOGETIC
; stage 2
	rarity_mon MEGANIUM
	rarity_mon TYPHLOSION
	rarity_mon FERALIGATR
	rarity_mon AMPHAROS
; Weavile/Mamoswine/Mismagius are post-Gen-2 evolutions (of Sneasel/Piloswine/
; Misdreavus), so they live in the WARP group, not here - see WarpGreatball
; (Mamoswine follows Piloswine into WarpPokeball).
; Slowking is evolved-only (from Slowpoke, a Kanto GREATBALL-tier base
; species - see the EVOLVE_TRADE added to SlowpokeEvosMoves). Same
; classification-only-placeholder pattern as above, matched to Slowpoke's
; own tier rather than JohtoPokeball.
	rarity_mon SLOWKING
; Steelix is evolved-only (from Onix, a Kanto GREATBALL-tier base species -
; see the EVOLVE_LEVEL added to OnixEvosMoves). Same pattern as Slowking
; above, matched to Onix's own tier.
	rarity_mon STEELIX
; Porygon2 is evolved-only (from Porygon, a Kanto GREATBALL-tier base
; species - see the EVOLVE_TRADE added to PorygonEvosMoves). Same
; classification-only-placeholder pattern as above, matched to Porygon's
; own tier.
	rarity_mon PORYGON2
; Lickilicky/Tangrowth/Porygon-Z are post-Gen-2 evolutions (of Lickitung/
; Tangela/Porygon2), so they live in the WARP group - see WarpGreatball.
JohtoGreatball_End:

JohtoUltraball:
	rarity_mon GLIGAR
	rarity_mon HERACROSS
	rarity_mon SKARMORY
	rarity_mon STANTLER
	rarity_mon HITMONTOP
	rarity_mon LARVITAR
	rarity_mon MILTANK
JohtoUltraball_Evos:
; stage 1
	rarity_mon PUPITAR
; Scizor is evolved-only (from Scyther, a Kanto ULTRABALL-tier base species -
; see the EVOLVE_LEVEL added to ScytherEvosMoves). Same classification-only-
; placeholder pattern as Slowking/Steelix in JohtoGreatball, matched to
; Scyther's own tier. Scyther's OTHER branch, Kleavor, is post-Gen-2 and
; lives in the WARP group instead - see WarpUltraball.
	rarity_mon SCIZOR
; Blissey is evolved-only (from Chansey, a Kanto ULTRABALL-tier base
; species - see the EVOLVE_LEVEL added to ChanseyEvosMoves). Same pattern
; as Scizor above, matched to Chansey's own tier.
	rarity_mon BLISSEY
; Rhyperior/Electivire/Magmortar are post-Gen-2 evolutions (of Rhydon/
; Electabuzz/Magmar), so they live in the WARP group - see WarpUltraball.
; stage 3 - Tyranitar continues the Larvitar/Pupitar line already placed in
; this tier's base/stage-1 sections above.
	rarity_mon TYRANITAR
JohtoUltraball_End:

JohtoMasterball:
; Raikou/Entei/Suicune are the legendary beasts - no evolution, same
; singular-legendary rarity treatment as Zapdos in the Kanto pool.
	rarity_mon RAIKOU
	rarity_mon ENTEI
	rarity_mon SUICUNE
JohtoMasterball_Evos:
JohtoMasterball_End:

; Never rollable and never reached by evolution - same pattern as KantoUber,
; so Lugia/Ho-oh/Celebi (box legendaries/mythical, no evolution) classify
; into a tier of their own rather than being rolled as ordinary encounters.
; Its base count is 0, so the roller skips it like an empty group.
JohtoUber:
JohtoUber_Evos:
	rarity_mon LUGIA
	rarity_mon HO_OH
	rarity_mon CELEBI
JohtoUber_End:

; ===========================================================================
; Kanto Time Warp: explicit regional/convergent/paradox form picks, followed
; by ordinary evolution-only species. Form indices are declared on every pick.
; Commented rarity_mon lines document evolved forms at their assigned tier.
; Mr. Rime remains directly rollable: MrMimeEvosMoves currently has no evolution.
; Regional evolved forms below are reached through their ordinary predecessors.
; ===========================================================================
WarpPokeball:
; Direct form picks, equal weight to each ordinary species entry.
	rarity_mon RATTATA, 1 ; Alolan Rattata
	rarity_mon FARFETCHD, 1 ; Galarian Farfetch'd
	rarity_mon GRIMER, 1 ; Alolan Grimer
	rarity_mon GROWLITHE, 1 ; Hisuian Growlithe
	rarity_mon VOLTORB, 1 ; Hisuian Voltorb
	rarity_mon SANDSHREW, 1 ; Alolan Sandshrew
	rarity_mon MAGNETON, 1 ; Sandy Shocks; never evolves
WarpPokeball_Evos:
; Evolution-only form references. Commented entries are NOT direct picks.
; rarity_mon MAROWAK, 1 ; Cubone + Dusk Stone -> Alolan Marowak
; rarity_mon WEEZING, 1 ; Koffing + Moon Stone -> Galarian Weezing
; rarity_mon RATICATE, 1 ; Alolan Rattata -> Alolan Raticate
; rarity_mon MUK, 1 ; Alolan Grimer -> Alolan Muk
; rarity_mon ARCANINE, 1 ; Hisuian Growlithe -> Hisuian Arcanine
; rarity_mon ELECTRODE, 1 ; Hisuian Voltorb -> Hisuian Electrode
; rarity_mon SANDSLASH, 1 ; Alolan Sandshrew -> Alolan Sandslash
; from Primeape/Magneton (Kanto POKEBALL evolved forms) and Farfetch'd
; (Kanto POKEBALL base) - see PrimeapeEvosMoves/MagnetonEvosMoves/
; FarfetchdEvosMoves - and Piloswine (Johto POKEBALL).
	rarity_mon ANNIHILAPE
	rarity_mon MAGNEZONE
	rarity_mon SIRFETCHD
	rarity_mon MAMOSWINE ; classified as Great Ball with Johto + Warp
WarpPokeball_End:

WarpGreatball:
; Direct form picks, equal weight to each ordinary species entry.
	rarity_mon MEOWTH, 1 ; Alolan Meowth
	rarity_mon MEOWTH, 2 ; Galarian Meowth
	rarity_mon DIGLETT, 1 ; Alolan Diglett
	rarity_mon DIGLETT, 2 ; Wiglett
	rarity_mon GEODUDE, 1 ; Alolan Geodude
	rarity_mon VULPIX, 1 ; Alolan Vulpix
	rarity_mon PONYTA, 1 ; Galarian Ponyta
	rarity_mon SLOWPOKE, 1 ; Galarian Slowpoke
WarpGreatball_Evos:
; Evolution-only form references. Commented entries are NOT direct picks.
; rarity_mon RAICHU, 1 ; Pikachu + Moon Stone -> Alolan Raichu
; rarity_mon PERSIAN, 1 ; Alolan Meowth -> Alolan Persian
; rarity_mon PERSIAN, 2 ; Galarian Meowth -> Perrserker
; rarity_mon DUGTRIO, 1 ; Alolan Diglett -> Alolan Dugtrio
; rarity_mon DUGTRIO, 2 ; Wiglett -> Wugtrio
; rarity_mon GRAVELER, 1 ; Alolan Geodude -> Alolan Graveler
; rarity_mon GOLEM, 1 ; Alolan Graveler -> Alolan Golem
; rarity_mon NINETALES, 1 ; Alolan Vulpix + Ice Stone -> Alolan Ninetales
; rarity_mon RAPIDASH, 1 ; Galarian Ponyta -> Galarian Rapidash
; rarity_mon SLOWBRO, 1 ; Galarian Slowpoke -> Galarian Slowbro
; rarity_mon SLOWKING, 1 ; Galarian Slowpoke + Water Stone -> Galarian Slowking
; rarity_mon FLAREON, 1 ; Eevee + Leaf Stone -> Leafeon
; rarity_mon VAPOREON, 1 ; Eevee + Ice Stone -> Glaceon
; rarity_mon VAPOREON, 2 ; Eevee + Moon Stone -> Sylveon
; from Sneasel/Misdreavus (Johto GREATBALL) and Lickitung/Tangela/
; Porygon2 (Kanto and Johto GREATBALL).
	rarity_mon WEAVILE
	rarity_mon MISMAGIUS
	rarity_mon LICKILICKY
	rarity_mon TANGROWTH
	rarity_mon PORYGON_Z
WarpGreatball_End:

WarpUltraball:
; Direct form picks, equal weight to each ordinary species entry.
	rarity_mon MR_MIME, 1 ; Galarian Mr. Mime
WarpUltraball_Evos:
; Evolution-only form references. Commented entries are NOT direct picks.
; from Galarian Mr. Mime (level 42).
	rarity_mon MR_RIME
; from Scyther/Rhydon/Electabuzz/Magmar, all Kanto ULTRABALL tier.
	rarity_mon KLEAVOR
	rarity_mon RHYPERIOR
	rarity_mon ELECTIVIRE
	rarity_mon MAGMORTAR
WarpUltraball_End:

WarpMasterball:
; Direct form picks, equal weight to each ordinary species entry.
	rarity_mon TENTACOOL, 1 ; Toedscool
	rarity_mon ARTICUNO, 1 ; Galarian Articuno
	rarity_mon ZAPDOS, 1 ; Galarian Zapdos
	rarity_mon MOLTRES, 1 ; Galarian Moltres
	rarity_mon TAUROS, 1 ; Paldean Combat Tauros
	rarity_mon TAUROS, 2 ; Paldean Blaze Tauros
	rarity_mon TAUROS, 3 ; Paldean Aqua Tauros
	rarity_mon JIGGLYPUFF, 1 ; Scream Tail; never evolves
WarpMasterball_Evos:
; Evolution-only form references. Commented entries are NOT direct picks.
; rarity_mon TENTACRUEL, 1 ; Toedscool -> Toedscruel
; rarity_mon EXEGGUTOR, 1 ; Exeggcute + Moon Stone -> Alolan Exeggutor
WarpMasterball_End:
WarpUber:
; Direct form picks, equal weight to each ordinary species entry.
WarpUber_Evos:
; Evolution-only form references. Commented entries are NOT direct picks.
WarpUber_End:

; The Kanto pool must still describe exactly the 151 Kanto species.
ASSERT (KantoPokeball_End - KantoPokeball) + (KantoGreatball_End - KantoGreatball) + \
       (KantoUltraball_End - KantoUltraball) + (KantoMasterball_End - KantoMasterball) + \
       (KantoUber_End - KantoUber) == 151 * 2, "Kanto rarity pool is no longer 151 species"


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
	push af
	cp SPECIES_GROUP_JOHTO
	jr nz, .ordinaryGroup
	ld a, b
	cp RARITY_TIER_GREATBALL + 1
	jr nc, .ordinaryGroup
	call RogueSwinubRarityBoostActive
	jr nz, .ordinaryGroup
	pop af
	ld hl, RarityJohtoWarp
	jr .tierTable
.ordinaryGroup
	pop af
	ld hl, RarityGroupTable
	add a                        ; group * 2 (dw)
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a                      ; hl = tier table for this group
.tierTable
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

; Z SET only if both expansions are unlocked AND enabled for this run.
; The same condition owns pool selection and family classification.
; CLOBBERS af only; bc/de/hl preserved by RogueGetActiveGroupMask.
RogueSwinubRarityBoostActive::
	call RogueGetActiveGroupMask
	and (1 << BIT_GROUP_JOHTO) | (1 << BIT_GROUP_WARP)
	cp (1 << BIT_GROUP_JOHTO) | (1 << BIT_GROUP_WARP)
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
; Unlock state is derived from the persistent activation events rather than from
; the number of recorded Hall of Fame teams. The events are saved with the
; player's story flags and survive the run-reset script, so the event itself is
; the source of truth for Johto and Kanto Time Warp availability.
;
; A save made before sRogueSpeciesGroupsEnabled existed reads $ff here, which the
; final AND clamps to "every unlocked group enabled" - a sane default, and
; self-correcting the first time the player opens the toggle menu.
; ---------------------------------------------------------------------------
RogueGetActiveGroupMask::
	push bc
; CHEAT and Debug 2 tag the enabled byte instead of setting story events.
; An exact high-bit tag bypasses the unlock mask below; ordinary PC toggles
; and legacy $ff still require the player's permanent activation events.
.deriveUnlocks
	; The two persistent activation bits are deliberately four positions above
	; their species-group bits (5->1 and 6->2). One nibble swap converts both
	; unlocks at once; Kanto is then added unconditionally.
	ASSERT EVENT_JOHTO_ACTIVATED % 8 == BIT_GROUP_JOHTO + 4
	ASSERT EVENT_KANTO_TIMEWARP_ACTIVATED % 8 == BIT_GROUP_WARP + 4
	ld a, [wEventFlags + (EVENT_JOHTO_ACTIVATED / 8)]
	and (1 << (EVENT_JOHTO_ACTIVATED % 8)) | (1 << (EVENT_KANTO_TIMEWARP_ACTIVATED % 8))
	swap a
	inc a ; bit 0 is clear after the mask/swap, so this sets Kanto size-neutrally
	ld b, a
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
	and GROUP_OVERRIDE_MASK
	cp GROUP_OVERRIDE_TAG
	jr nz, .applyEnabled
	ld b, GROUP_ENABLE_MASK
.applyEnabled
	ld a, c
	set BIT_GROUP_KANTO, a      ; Kanto is always in the pool
	and b                       ; drop anything not yet unlocked
	pop bc
	ret

; ---------------------------------------------------------------------------
; RogueGetActiveGroupMaskFar
; OUTPUT: e = the same mask RogueGetActiveGroupMask returns in a
; CLOBBERS: af (bc, d, hl preserved, as above)
;
; RogueGetActiveGroupMask returns in `a`, which makes it UNREACHABLE by farcall:
; Bankswitch's return leg does `pop bc / ld a, b / ldh [hLoadedROMBank], a`, so
; `a` is destroyed on the way back and the caller would read the restored bank
; number as a group mask. Every in-tree caller so far is a plain call from this
; same bank, which is why the hazard had not surfaced.
;
; RogueBuildParty (bank $39) is the first out-of-bank caller, so it goes through
; this wrapper instead. `e` is used because d and e are the only registers
; Bankswitch spares - the same contract RogueClassifySpeciesFar and
; RogueRollFormForSpecies use, and for the same reason. Do NOT "simplify" this
; away by farcalling the routine above directly.
RogueGetActiveGroupMaskFar::
	call RogueGetActiveGroupMask
	ld e, a
	ret

; ---------------------------------------------------------------------------
; RogueGetSpeciesTierFar
; INPUT:  e = species
; OUTPUT: e = RARITY_TIER_*, or $FF if the species is in no pool
; CLOBBERS: af, bc, d, hl
;
; The farcall-safe face of RogueClassifySpecies, returning the RAW tier. Note
; the difference from RogueClassifySpeciesFar, which folds RARITY_TIER_UBER into
; masterball for backwards compatibility with the old reverse lookups: that fold
; makes it useless for telling a legendary from an ordinary masterball species,
; which is exactly what RogueBuildParty's BIT_PSPEC_ALLOW_LEGEND filter needs to
; do. Hence a second wrapper rather than a caller of the first.
;
; $FF for "in no pool" rather than a tier, so an unclassified species cannot
; accidentally satisfy a rarity filter.
RogueGetSpeciesTierFar::
	ld a, e
	call RogueClassifySpecies    ; b = tier, c = group, carry set if unknown
	ld e, $FF
	ret c
	ld e, b
	ret

; ---------------------------------------------------------------------------
; RogueFormsUnlocked
; OUTPUT: Z SET   = regional forms must NOT appear this run
;         Z CLEAR = forms may appear
; CLOBBERS: af   (bc, de, hl PRESERVED - callers hold a rolled species in d)
;
; Regional forms are expansion content and are gated behind the same unlocks as
; the Johto and Kanto Time Warp species groups, so a base Kanto run never sees
; one.
;
; ⚠ This is NOT the same as asking whether a form's BASE species is in an
; unlocked group, and that distinction is the whole reason this exists: 47 of the
; 48 form records hang off KANTO species (Meowth, Dugtrio, Vulpix, Moltres,
; Tauros...), and Kanto is always active. Only gslowking has a Johto base.
; Without an explicit gate, Alolan Meowth shows up on
; turn one of a fresh run - which is exactly what happened in testing.
; ---------------------------------------------------------------------------
RogueFormsUnlocked::
	call RogueGetActiveGroupMask ; documented to preserve bc/de/hl
	and (1 << BIT_GROUP_JOHTO) | (1 << BIT_GROUP_WARP)
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
; OUTPUT: d = species, e = explicit form index
; CLOBBERS: af, bc, hl
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
RogueSpeciesAtIndex::             ; a = entry index, hl = pair list
	ld c, a
	ld b, 0
	add hl, bc
	add hl, bc
	ld d, [hl]
	inc hl
	ld e, [hl]
	ret

; ---------------------------------------------------------------------------
; RogueDrawUber  (ENDLESS_MODE_CHECKPOINT_E.md section 3)
; INPUT:  e = 0: any Uber; nonzero: only species the player does not own
;         (AllSpeciesCheck, the bosses' family-wide gate)
; OUTPUT: carry SET   = d = species, e = form, uniform over every allowed entry
;                       of the active groups' Uber tiers
;         carry CLEAR = nothing allowed
; CLOBBERS: everything. Farcall-safe: only d, e and flags carry results.
;
; Uber tiers have base count 0 (every entry sits in the _Evos tail), so the
; ordinary roller can never reach them; this reads the WHOLE list instead. Every
; Uber species is single-stage. Must stay in the tables' bank: RogueGetTierEntry
; returns a plain pointer into them.
; ---------------------------------------------------------------------------
RogueDrawUber::
	ld d, $ff                    ; count pass: no index reaches $ff
	call .walk                   ; a = allowed entries, carry clear
	and a
	ret z
	ld c, a
	call Rangerandom             ; a = 0 .. count-1; preserves bc/de/hl
	ld d, a
	; fallthrough: the same walk stops on entry d (nothing it reads changed)

; In: d = index to stop on, e = filter. Out: carry SET with d/e = that entry,
; or carry CLEAR with a = the number of allowed entries.
.walk
	call RogueGetActiveGroupMask ; a = mask; bc/de/hl preserved
	ld b, a                      ; b = groups left, bit 0 = the next one
	ld c, 0                      ; c = allowed entries passed so far
	xor a                        ; a = group id
.group
	srl b
	jr nc, .nextGroup            ; group not active
	push af
	push bc
	ld b, RARITY_TIER_UBER
	call RogueGetTierEntry       ; hl = list, c = total; de preserved
	ld a, c
	pop bc
	and a
	jr z, .groupDone
.entry
	push af                      ; entries left in this list
	call .allowed
	jr nc, .skip
	ld a, c
	cp d
	jr z, .hit
	inc c
.skip
	inc hl
	inc hl
	pop af
	dec a
	jr nz, .entry
.groupDone
	pop af                       ; group id
.nextGroup
	inc a
	cp NUM_SPECIES_GROUPS
	jr c, .group
	ld a, c
	and a                        ; carry clear: index d not reached
	ret
.hit
	pop af                       ; entries left
	pop af                       ; group id
	ld d, [hl]
	inc hl
	ld e, [hl]
	scf
	ret

; hl -> entry, e = filter. Out: carry SET if allowed. Preserves bc/de/hl.
.allowed
	ld a, e
	and a
	scf
	ret z                        ; no filter
	push bc
	push de
	push hl
	ld d, [hl]
	call AllSpeciesCheck         ; c = 1 if owned
	ld a, c
	pop hl
	pop de
	pop bc
	cp 1                         ; carry when not owned
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
	jr nz, .nextEntry
	ld a, [hl]                   ; species-only classification ignores form entries
	and a
	jr z, .hit
.nextEntry
	inc hl
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
	ld a, e
	cp SWINUB
	jr z, .swinubFamily
	cp PILOSWINE
	jr z, .swinubFamily
	cp MAMOSWINE
	jr nz, .classified
.swinubFamily
	call RogueSwinubRarityBoostActive
	jr nz, .classified
	ld b, RARITY_TIER_GREATBALL
.classified
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

; ---------------------------------------------------------------------------
; RogueIsSpeciesEvolutionAllowedFar
; The farcall-safe face of RogueIsSpeciesEvolutionAllowed, and the ONLY way to
; reach it from another bank.
; INPUT:  e = the species an evolution is about to produce
; OUTPUT: carry as below; flags survive Bankswitch's all-pop/ld/ret exit
; CLOBBERS: af, bc, de, hl
;
; RogueIsSpeciesEvolutionAllowed takes its species in `a`, and Bankswitch's
; FIRST instruction is `ldh a, [hLoadedROMBank]` - so a farcall can never
; deliver an `a` input. Both callers did exactly that, which meant they were
; really asking "is the species whose internal id happens to equal my own ROM
; BANK NUMBER allowed?" - one constant answer per calling bank, applied to
; every evolution in the game. Measured 2026-09-17: with the trainer path
; calling from bank $38, a Kanto-only run evolved NOTHING, and unlocking Johto
; let a Porygon run all the way to Warp-group PORYGON_Z.
;
; Same hazard, same `e`-shaped fix as RogueClassifySpeciesFar and
; RogueGetActiveGroupMaskFar above. Do NOT farcall the routine below directly.
; ---------------------------------------------------------------------------
RogueIsSpeciesEvolutionAllowedFar::
	ld a, e
	jr RogueIsSpeciesEvolutionAllowed

; ---------------------------------------------------------------------------
; RogueIsSpeciesEvolutionAllowed
; INPUT:  a = the species an evolution is about to produce (NOT farcall-safe -
;         use RogueIsSpeciesEvolutionAllowedFar from another bank)
; OUTPUT: carry SET   = that species' group is unlocked AND enabled - evolve
;         carry CLEAR = group locked or toggled off - caller skips the branch
; CLOBBERS: af, bc, de, hl
;
; Species Groups Phase 2. The group toggles gate what the ROLLER may hand out,
; but evolution walks EvosMoves directly and reaches the _Evos tail of a tier
; list without ever consulting them. Without this check a Kanto Poliwhirl would
; still become a Johto Politoed with Johto locked, and a Piloswine would still
; become a Warp-group Mamoswine with Kanto Time Warp locked.
;
; Callers live in another bank and arrive by farcall, which already destroys
; a/b/c/h/l, so nothing here needs preserving - only the flag crosses back.
; Flags DO survive the Bankswitch return path (it is all `pop`/`ld`/`ret`).
;
; A species in no pool at all is ALLOWED. That covers every ordinary vanilla
; evolution, whose targets are Kanto species that classify normally, plus
; anything the tables do not know about; blocking those would break base play.
; ---------------------------------------------------------------------------
RogueIsSpeciesEvolutionAllowed::
	call RogueClassifySpecies    ; b = tier, c = group, carry set = in no pool
	jr c, .allow
	call RogueGetActiveGroupMask ; a = unlocked AND player-enabled group bits
	                             ; (documented + verified to preserve bc)
	inc c                        ; shift the wanted group's bit down to bit 0
.shiftToBit0
	dec c
	jr z, .testBit
	srl a
	jr .shiftToBit0
.testBit
	rra                          ; bit 0 -> carry: set = group active
	ret
.allow
	scf
	ret
