; Evos+moves data structure:
; - Evolution methods:
;    * db EVOLVE_LEVEL, level, species
;    * db EVOLVE_ITEM, used item, min level (1), species
;    * db EVOLVE_TRADE, min level (1), species
; - db 0 ; no more evolutions
; - Learnset (in increasing level order):
;    * db level, move
; - db 0 ; no more level-up moves

; imported from yellow legacy
; don't know if I agree with how sleep moves are now so late for all sleep move having pokemon, poliwag, lapras, parasect, gengar
; horn drill is also later on rhydon andd guillotine on pinsir and all one hits like krabby too
; barrier was pushed back for tentacool, unclear why as well as hydro pump
; double team and swords dance have been pushed back on scyther, probably others
; mirror move delayed for pidgey
; much of gravelers and golems learnset delayed
; low kick no longer in machokes
; bind pushed way back on Onix
; amnesia pushed back
; leer removed from moltres
; hyper beam pushed back for dragonair and agility
; jigglypuff double edge pushed back
; thunderwave pushed back jolteon
; left off at ekans

EvosMovesPointerTable:
	table_width 2, EvosMovesPointerTable
	dw RhydonEvosMoves
	dw KangaskhanEvosMoves
	dw NidoranMEvosMoves
	dw ClefairyEvosMoves
	dw SpearowEvosMoves
	dw VoltorbEvosMoves
	dw NidokingEvosMoves
	dw SlowbroEvosMoves
	dw IvysaurEvosMoves
	dw ExeggutorEvosMoves
	dw LickitungEvosMoves
	dw ExeggcuteEvosMoves
	dw GrimerEvosMoves
	dw GengarEvosMoves
	dw NidoranFEvosMoves
	dw NidoqueenEvosMoves
	dw CuboneEvosMoves
	dw RhyhornEvosMoves
	dw LaprasEvosMoves
	dw ArcanineEvosMoves
	dw MewEvosMoves
	dw GyaradosEvosMoves
	dw ShellderEvosMoves
	dw TentacoolEvosMoves
	dw GastlyEvosMoves
	dw ScytherEvosMoves
	dw StaryuEvosMoves
	dw BlastoiseEvosMoves
	dw PinsirEvosMoves
	dw TangelaEvosMoves
	dw MissingNo1FEvosMoves
	dw ChikoritaEvosMoves
	dw GrowlitheEvosMoves
	dw OnixEvosMoves
	dw FearowEvosMoves
	dw PidgeyEvosMoves
	dw SlowpokeEvosMoves
	dw KadabraEvosMoves
	dw GravelerEvosMoves
	dw ChanseyEvosMoves
	dw MachokeEvosMoves
	dw MrMimeEvosMoves
	dw HitmonleeEvosMoves
	dw HitmonchanEvosMoves
	dw ArbokEvosMoves
	dw ParasectEvosMoves
	dw PsyduckEvosMoves
	dw DrowzeeEvosMoves
	dw GolemEvosMoves
	dw BayleefEvosMoves
	dw MagmarEvosMoves
	dw MeganiumEvosMoves
	dw ElectabuzzEvosMoves
	dw MagnetonEvosMoves
	dw KoffingEvosMoves
	dw CyndaquilEvosMoves
	dw MankeyEvosMoves
	dw SeelEvosMoves
	dw DiglettEvosMoves
	dw TaurosEvosMoves
	dw QuilavaEvosMoves
	dw TyphlosionEvosMoves
	dw TotodileEvosMoves
	dw FarfetchdEvosMoves
	dw VenonatEvosMoves
	dw DragoniteEvosMoves
	dw CroconawEvosMoves
	dw FeraligatrEvosMoves
	dw SentretEvosMoves
	dw DoduoEvosMoves
	dw PoliwagEvosMoves
	dw JynxEvosMoves
	dw MoltresEvosMoves
	dw ArticunoEvosMoves
	dw ZapdosEvosMoves
	dw DittoEvosMoves
	dw MeowthEvosMoves
	dw KrabbyEvosMoves
	dw FurretEvosMoves
	dw HoothootEvosMoves
	dw NoctowlEvosMoves
	dw VulpixEvosMoves
	dw NinetalesEvosMoves
	dw PikachuEvosMoves
	dw RaichuEvosMoves
	dw LedybaEvosMoves
	dw LedianEvosMoves
	dw DratiniEvosMoves
	dw DragonairEvosMoves
	dw KabutoEvosMoves
	dw KabutopsEvosMoves
	dw HorseaEvosMoves
	dw SeadraEvosMoves
	dw SpinarakEvosMoves
	dw AriadosEvosMoves
	dw SandshrewEvosMoves
	dw SandslashEvosMoves
	dw OmanyteEvosMoves
	dw OmastarEvosMoves
	dw JigglypuffEvosMoves
	dw WigglytuffEvosMoves
	dw EeveeEvosMoves
	dw FlareonEvosMoves
	dw JolteonEvosMoves
	dw VaporeonEvosMoves
	dw MachopEvosMoves
	dw ZubatEvosMoves
	dw EkansEvosMoves
	dw ParasEvosMoves
	dw PoliwhirlEvosMoves
	dw PoliwrathEvosMoves
	dw WeedleEvosMoves
	dw KakunaEvosMoves
	dw BeedrillEvosMoves
	dw CrobatEvosMoves
	dw DodrioEvosMoves
	dw PrimeapeEvosMoves
	dw DugtrioEvosMoves
	dw VenomothEvosMoves
	dw DewgongEvosMoves
	dw ChinchouEvosMoves
	dw LanturnEvosMoves
	dw CaterpieEvosMoves
	dw MetapodEvosMoves
	dw ButterfreeEvosMoves
	dw MachampEvosMoves
	dw TogepiEvosMoves
	dw GolduckEvosMoves
	dw HypnoEvosMoves
	dw GolbatEvosMoves
	dw MewtwoEvosMoves
	dw SnorlaxEvosMoves
	dw MagikarpEvosMoves
	dw TogeticEvosMoves
	dw NatuEvosMoves
	dw MukEvosMoves
	dw XatuEvosMoves
	dw KinglerEvosMoves
	dw CloysterEvosMoves
	dw MareepEvosMoves
	dw ElectrodeEvosMoves
	dw ClefableEvosMoves
	dw WeezingEvosMoves
	dw PersianEvosMoves
	dw MarowakEvosMoves
	dw FlaaffyEvosMoves
	dw HaunterEvosMoves
	dw AbraEvosMoves
	dw AlakazamEvosMoves
	dw PidgeottoEvosMoves
	dw PidgeotEvosMoves
	dw StarmieEvosMoves
	dw BulbasaurEvosMoves
	dw VenusaurEvosMoves
	dw TentacruelEvosMoves
	dw AmpharosEvosMoves
	dw GoldeenEvosMoves
	dw SeakingEvosMoves
	dw BellossomEvosMoves
	dw MarillEvosMoves
	dw AzumarillEvosMoves
	dw SudowoodoEvosMoves
	dw PonytaEvosMoves
	dw RapidashEvosMoves
	dw RattataEvosMoves
	dw RaticateEvosMoves
	dw NidorinoEvosMoves
	dw NidorinaEvosMoves
	dw GeodudeEvosMoves
	dw PorygonEvosMoves
	dw AerodactylEvosMoves
	dw PolitoedEvosMoves
	dw MagnemiteEvosMoves
	dw HoppipEvosMoves
	dw SkiploomEvosMoves
	dw CharmanderEvosMoves
	dw SquirtleEvosMoves
	dw CharmeleonEvosMoves
	dw WartortleEvosMoves
	dw CharizardEvosMoves
	dw JumpluffEvosMoves
	dw AipomEvosMoves
	dw SunkernEvosMoves
	dw SunfloraEvosMoves
	dw OddishEvosMoves
	dw GloomEvosMoves
	dw VileplumeEvosMoves
	dw BellsproutEvosMoves
	dw WeepinbellEvosMoves
	dw VictreebelEvosMoves
	dw WeavileEvosMoves
	dw MamoswineEvosMoves
	dw MismagiusEvosMoves
	dw YanmaEvosMoves
	dw WooperEvosMoves
	dw QuagsireEvosMoves
	dw MurkrowEvosMoves
	dw SlowkingEvosMoves
	dw MisdreavusEvosMoves
	dw GirafarigEvosMoves
	dw PinecoEvosMoves
	dw ForretressEvosMoves
	dw DunsparceEvosMoves
	dw GligarEvosMoves
	dw SteelixEvosMoves
	dw SnubbullEvosMoves
	dw GranbullEvosMoves
	dw QwilfishEvosMoves
	dw ScizorEvosMoves
	dw ShuckleEvosMoves
	dw HeracrossEvosMoves
	dw SneaselEvosMoves
	dw TeddiursaEvosMoves
	dw UrsaringEvosMoves
	dw SlugmaEvosMoves
	dw MagcargoEvosMoves
	dw SwinubEvosMoves
	dw PiloswineEvosMoves
	dw CorsolaEvosMoves
	dw RemoraidEvosMoves
	dw OctilleryEvosMoves
	dw MantineEvosMoves
	dw SkarmoryEvosMoves
	dw HoundourEvosMoves
	dw HoundoomEvosMoves
	dw KingdraEvosMoves
	dw PhanpyEvosMoves
	dw DonphanEvosMoves
	dw Porygon2EvosMoves
	dw StantlerEvosMoves
	dw HitmontopEvosMoves
	dw MiltankEvosMoves
	dw BlisseyEvosMoves
	dw RaikouEvosMoves
	dw EnteiEvosMoves
	dw SuicuneEvosMoves
	dw LarvitarEvosMoves
	dw PupitarEvosMoves
	dw TyranitarEvosMoves
	dw LugiaEvosMoves
	dw HoOhEvosMoves
	dw CelebiEvosMoves
	dw AnnihilapeEvosMoves
	dw LickilickyEvosMoves
	dw SirfetchdEvosMoves
	dw MagnezoneEvosMoves
	dw TangrowthEvosMoves
	dw RhyperiorEvosMoves
	dw KleavorEvosMoves
	dw MrRimeEvosMoves
	dw ElectivireEvosMoves
	dw MagmortarEvosMoves
	dw PorygonZEvosMoves
	assert_table_length NUM_POKEMON_INDEXES

RhydonEvosMoves:
; Evolutions
; Species Groups Phase 2: canon Rhydon->Rhyperior is a trade-holding-
; Protector evolution; this project has no held-item trade mechanic, so -
; per the project's own trade-evolution convention (EVOLVE_TRADE at level
; 40, same as Seadra->Kingdra/Porygon->Porygon2) - a plain trade threshold
; is used instead.
	db EVOLVE_TRADE, 40, RHYPERIOR
	db 0
; Learnset
	db 10, TAIL_WHIP
	db 10, FURY_ATTACK
	db 13, STOMP
	db 19, ROCK_THROW
	db 24, DIG
	db 39, ROCK_SLIDE
	db 44, EARTHQUAKE
	db 49, TAKE_DOWN
	db 55, HORN_DRILL
	db 0
    
; Tutor Learnset
    db 2, FIRE_PUNCH
    db 2, THUNDERPUNCH
    db 2, BLIZZARD
    db 2, COUNTER
    db 2, HEADBUTT
    db 2, ICE_BEAM
    db 2, THRASH
    db 0

KangaskhanEvosMoves:
; Evolutions
	db 0
; Learnset
	db 7, LEER
	db 13, BITE
	db 19, TAIL_WHIP
	db 24, MEGA_PUNCH
	db 29, DIZZY_PUNCH
	db 37, BODY_SLAM
	db 48, DOUBLE_EDGE
	db 0

; Tutor Learnset
    db 2, FIRE_PUNCH
    db 2, THUNDERPUNCH
    db 2, ICE_PUNCH
    db 2, HEADBUTT
    db 2, DISABLE
    db 2, FOCUS_ENERGY
    db 2, STOMP
    db 0

NidoranMEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 16, NIDORINO
	db 0
; Learnset
	db 6, POISON_STING
	db 8, HORN_ATTACK
	db 12, DOUBLE_KICK
	db 23, FOCUS_ENERGY
	db 30, FURY_ATTACK
	db 38, HORN_DRILL
	db 0

; Tutor Learnset
    db 2, DEFENSE_CURL
    db 2, HEADBUTT
    db 2, AMNESIA
    db 2, CONFUSION
    db 2, COUNTER
    db 2, DISABLE
    db 2, SUPERSONIC
    db 2, LOVELY_KISS
    db 0

ClefairyEvosMoves:
; Evolutions
	db EVOLVE_ITEM, MOON_STONE, 1, CLEFABLE
	db 0
; Learnset
	db 13, DOUBLESLAP
	db 19, MINIMIZE
	db 26, DEFENSE_CURL
	db 30, METRONOME
	db 32, SING
	db 35, BODY_SLAM
	db 43, LIGHT_SCREEN
	db 0
    
; Tutor Learnset
    db 2, DREAM_EATER
    db 2, HEADBUTT
    db 2, FIRE_PUNCH
    db 2, THUNDERPUNCH
    db 2, ICE_PUNCH
    db 2, HEADBUTT
    db 2, DIZZY_PUNCH
    db 2, AMNESIA
    db 2, SPLASH
    db 2, PETAL_DANCE
    db 2, SWIFT
    db 0

SpearowEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 20, FEAROW
	db 0
; Learnset
	db 7, LEER
	db 10, FURY_ATTACK
	db 14, FOCUS_ENERGY
	db 18, SWIFT
	db 21, MIRROR_MOVE
	db 24, DRILL_PECK
	db 30, SHARPEN
	db 40, AGILITY
	db 0

; Tutor Learnset
    db 2, QUICK_ATTACK
    db 2, TRI_ATTACK
    db 2, SONICBOOM
    db 0

VoltorbEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 30, ELECTRODE
	db 0
; Learnset
	db 17, SONICBOOM
	db 19, THUNDERSHOCK
	db 22, SELFDESTRUCT
	db 26, SWIFT
	db 30, LIGHT_SCREEN
	db 35, THUNDERBOLT
	db 44, EXPLOSION
	db 50, THUNDER
	db 0
    
; Tutor Learnset
    db 2, AGILITY
    db 2, HEADBUTT
    db 0

NidokingEvosMoves:
; Evolutions
	db 0
; Learnset
	db 6, POISON_STING
	db 8, HORN_ATTACK
	db 12, DOUBLE_KICK
	db 25, THRASH
	db 27, FOCUS_ENERGY
	db 32, SLUDGE
	db 36, FURY_ATTACK
	db 40, EARTHQUAKE
	db 46, HORN_DRILL
	db 0
    
; Tutor Learnset
    db 2, FIRE_PUNCH
    db 2, THUNDERPUNCH
    db 2, ICE_PUNCH
    db 0    
	
SlowbroEvosMoves:
; Evolutions
	db 0
; Learnset
	db 5, GROWL
	db 5, WATER_GUN
	db 10, CONFUSION 
	db 18, DISABLE
	db 22, HEADBUTT
	db 25, PSYBEAM
	db 28, WATERFALL
	db 36, WITHDRAW
	db 40, AMNESIA
	db 45, PSYCHIC_M
	db 0
 
; Tutor Learnset
    db 2, TACKLE
    db 2, DREAM_EATER
    db 2, STOMP
    db 2, ICE_PUNCH
    db 0  

IvysaurEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 32, VENUSAUR
	db 0
; Learnset
	db 7, LEECH_SEED
	db 9, VINE_WHIP
	db 16, ACID
	db 22, POISONPOWDER
	db 25, SLEEP_POWDER
	db 29, RAZOR_LEAF
	db 38, GROWTH
	db 42, BODY_SLAM
	db 54, SOLARBEAM
	db 0
    
; Tutor Learnset
    db 2, DEFENSE_CURL
    db 2, FLASH
    db 2, HEADBUTT
    db 2, LIGHT_SCREEN
    db 2, PETAL_DANCE
    db 2, RAZOR_WIND
    db 2, SKULL_BASH
    db 0  

ExeggutorEvosMoves:
; Evolutions
	db 0
; Learnset
	db 10, POISONPOWDER
	db 13, LEECH_SEED
	db 19, CONFUSION
	db 20, MEGA_DRAIN
	db 25, REFLECT
	db 28, STOMP
	db 32, STUN_SPORE
	db 40, EGG_BOMB
	db 45, PSYCHIC_M
	db 48, SLEEP_POWDER
	db 0

; Tutor Learnset
    db 2, DREAM_EATER
    db 2, FLASH
    db 2, STRENGTH
    db 2, HEADBUTT
    db 0  

LickitungEvosMoves:
; Evolutions
; Species Groups Phase 2: canon Lickitung->Lickilicky is a level-up-
; knowing-Rollout evolution; Rollout does not exist in Gen 1, so - matching
; KEP's own fallback for the same species - a plain level threshold is
; used instead.
	db EVOLVE_LEVEL, 32, LICKILICKY
	db 0
; Learnset
	db 7, STOMP
	db 15, DISABLE
	db 19, HEADBUTT
	db 23, DEFENSE_CURL
	db 32, BODY_SLAM
	db 39, SCREECH
	db 44, WRAP
	db 0

; Tutor Learnset
    db 2, LICK
    db 2, DREAM_EATER
    db 2, FIRE_PUNCH
    db 2, ICE_PUNCH
    db 2, THUNDERPUNCH
    db 2, HEADBUTT
    db 2, DOUBLESLAP
    db 0

ExeggcuteEvosMoves:
; Evolutions
	db EVOLVE_ITEM, LEAF_STONE, 1, EXEGGUTOR
	db 0
; Learnset
	db 10, POISONPOWDER
	db 13, LEECH_SEED
	db 19, CONFUSION
	db 20, MEGA_DRAIN
	db 25, REFLECT
	db 32, STUN_SPORE
	db 40, EGG_BOMB
	db 45, PSYCHIC_M
	db 48, SLEEP_POWDER
	db 0

; Tutor Learnset
    db 2, DREAM_EATER
    db 2, FLASH
    db 2, STRENGTH
    db 0

GrimerEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 38, MUK
	db 0
; Learnset
	db 10, HARDEN
	db 16, ACID
	db 19, POISON_GAS
	db 24, ACID_ARMOR
	db 27, MINIMIZE
	db 33, SLUDGE
	db 37, BODY_SLAM
	db 42, TOXIC
	db 45, SCREECH
	db 0
; Tutor Learnset
    db 2, FIRE_PUNCH
    db 2, ICE_PUNCH
    db 2, THUNDERPUNCH
    db 2, HEADBUTT
    db 2, HAZE
    db 2, LICK
    db 0

GengarEvosMoves:
; Evolutions
	db 0
; Learnset
	db 10, SMOG
	db 15, PSYWAVE
    db 55, HYPNOSIS
	db 36, NIGHT_SHADE
	db 55, HYPNOSIS
	db 55, DREAM_EATER
	db 0
    
; Tutoring Learnset   
    db 2, FIRE_PUNCH
    db 2, ICE_PUNCH
    db 2, THUNDERPUNCH
    db 2, HEADBUTT
    db 0

NidoranFEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 16, NIDORINA
	db 0
; Learnset
 	db 6, POISON_STING
	db 8, BITE
	db 12, DOUBLE_KICK
	db 23, TAIL_WHIP
	db 30, HEADBUTT
	db 38, FURY_SWIPES
	db 0

; Tutoring Learnset   
    db 2, COUNTER
    db 2, DISABLE
    db 2, FOCUS_ENERGY
    db 2, SUPERSONIC
    db 2, LOVELY_KISS
    db 0

NidoqueenEvosMoves:
; Evolutions
	db 0
; Learnset
	db 2, TAIL_WHIP
	db 6, POISON_STING
	db 8, HEADBUTT
	db 12, DOUBLE_KICK
	db 25, BODY_SLAM
	db 32, SLUDGE
	db 40, EARTHQUAKE
	db 0
    
; Tutoring Learnset   
    db 2, COUNTER
    db 2, DISABLE
    db 2, FOCUS_ENERGY
    db 2, SUPERSONIC
    db 2, LOVELY_KISS
    db 2, FIRE_PUNCH
    db 2, ICE_PUNCH
    db 2, THUNDERPUNCH
    db 0

CuboneEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 28, MAROWAK
	db 0
; Learnset
	db 5, LEER
	db 10, BONE_CLUB
	db 13, TAIL_WHIP
	db 18, HEADBUTT
	db 25, FOCUS_ENERGY
	db 31, BONEMERANG
	db 38, THRASH
	db 46, RAGE
	db 0
; Tutoring Learnset   
    db 2, ROCK_SLIDE
    db 2, SCREECH
    db 2, SWORDS_DANCE
    db 2, FURY_ATTACK
    db 2, FIRE_PUNCH
    db 2, THUNDERPUNCH
    db 0

RhyhornEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 42, RHYDON
	db 0
; Learnset
	db 10, TAIL_WHIP
	db 10, FURY_ATTACK
	db 13, STOMP
	db 19, ROCK_THROW
	db 24, DIG
	db 39, ROCK_SLIDE
	db 44, EARTHQUAKE
	db 49, TAKE_DOWN
	db 55, HORN_DRILL
	db 0

; Tutoring Learnset   
    db 2, BLIZZARD
    db 2, COUNTER
    db 2, HEADBUTT
    db 2, ICE_BEAM
    db 2, THRASH
    db 0

LaprasEvosMoves:
; Evolutions
	db 0
; Learnset
	db 19, MIST
	db 23, AURORA_BEAM
	db 25, BODY_SLAM
	db 30, CONFUSE_RAY
	db 34, WATERFALL
	db 38, ICE_BEAM
	db 46, SING
	db 51, HYDRO_PUMP
	db 55, BLIZZARD
	db 0
; Tutoring Learnset   
    db 2, DREAM_EATER
    db 2, BITE
    db 2, HEADBUTT
    db 0

ArcanineEvosMoves:
; Evolutions
	db 0
; Learnset
	db 18, EMBER
	db 23, LEER
	db 30, TAKE_DOWN
	db 45, FLAMETHROWER
	db 46, AGILITY
	db 0
; Tutoring Learnset   
    db 2, FIRE_SPIN
    db 2, THRASH
    db 2, HEADBUTT
    db 0
    
MewEvosMoves:
; Evolutions
	db 0
; Learnset
	db 10, TRANSFORM
	db 15, CONFUSION
	db 20, MEGA_PUNCH
	db 25, PSYBEAM
	db 30, METRONOME
	db 40, PSYCHIC_M
	db 0
; Tutoring Learnset   
    db 2, DREAM_EATER
    db 2, FIRE_PUNCH
    db 2, ICE_PUNCH
    db 2, THUNDERPUNCH
    db 2, WATERFALL
    db 2, HEADBUTT
    db 0

GyaradosEvosMoves:
; Evolutions
	db 0
; Learnset
	db 20, BITE
	db 22, GUST
	db 25, WATERFALL
	db 28, DRAGON_RAGE
	db 32, LEER
	db 35, THRASH
	db 41, HYDRO_PUMP
	db 48, SLAM
	db 52, HYPER_BEAM
	db 0

; Tutoring Learnset   
    db 2, BUBBLE
    db 2, HEADBUTT
    db 0

ShellderEvosMoves:
; Evolutions
	db EVOLVE_ITEM, WATER_STONE, 1, CLOYSTER
	db 0
; Learnset
	db 10, WATER_GUN
	db 14, SUPERSONIC
	db 17, LEER
	db 20, AURORA_BEAM
	db 25, BUBBLEBEAM
	db 35, ICE_BEAM
	db 43, CLAMP
	db 50, BLIZZARD
	db 55, EXPLOSION
	db 0
; Tutoring Learnset   
    db 2, BARRIER
    db 2, SCREECH
    db 0

TentacoolEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 30, TENTACRUEL
	db 0
; Learnset
	db 7, SUPERSONIC
	db 13, WATER_GUN
	db 18, ACID
	db 23, BUBBLEBEAM
	db 27, CONSTRICT
	db 35, BARRIER
	db 40, SCREECH
	db 43, SLUDGE
	db 47, WRAP
	db 50, HYDRO_PUMP
	db 0

; Tutoring Learnset   
    db 2, AURORA_BEAM
    db 2, HAZE
    db 2, CONFUSE_RAY
    db 0

GastlyEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 25, HAUNTER
	db 0
; Learnset
	db 10, SMOG
	db 15, PSYWAVE
	db 23, POISON_GAS
	db 36, NIGHT_SHADE
	db 55, HYPNOSIS
	db 55, DREAM_EATER
	db 0

; Tutoring Learnset   
    db 2, HAZE
    db 0
ScytherEvosMoves:
; Evolutions
; Species Groups Phase 2: canon Scyther->Scizor is a trade-holding-Metal-Coat
; evolution; this project has no Metal Coat item, so - matching KEP's own
; fallback path for the same species (tmp/kep/data/pokemon/evos_moves.asm's
; ScytherEvosMoves, EV_LEVEL 41 SCIZOR) - a plain level threshold is used
; instead. Scyther's second branch, Kleavor (added in batch 10), is canon's
; own trade-holding-Black-Augurite evolution - no such item here either, so
; per the project's trade-evolution convention it uses EVOLVE_TRADE at
; level 40, same as every other held-item trade substitute this import.
; Multiple evolution entries on one species are already supported (see
; EeveeEvosMoves's three stone branches).
	db EVOLVE_LEVEL, 41, SCIZOR
	db EVOLVE_TRADE, 40, KLEAVOR
	db 0
; Learnset
	db 6, FOCUS_ENERGY
	db 16, CUT
	db 24, AGILITY
	db 30, WING_ATTACK
	db 36, SLASH
	db 42, TWINEEDLE
	db 48, DOUBLE_TEAM
	db 54, SWORDS_DANCE
	db 0

; Tutoring Learnset   
    db 2, HEADBUTT
    db 2, COUNTER
    db 2, LIGHT_SCREEN
    db 2, RAZOR_WIND
    db 2, SONICBOOM
    db 0
StaryuEvosMoves:
; Evolutions
	db EVOLVE_ITEM, WATER_STONE, 1, STARMIE
	db 0
; Learnset
	db 7, WATER_GUN
	db 10, CONFUSION
	db 15, SWIFT
	db 22, HARDEN
	db 24, BUBBLEBEAM
	db 27, RECOVER
	db 37, MINIMIZE
	db 40, PSYCHIC_M
	db 42, LIGHT_SCREEN
	db 47, HYDRO_PUMP
	db 0
; Tutoring Learnset   
    db 2, WATERFALL
    db 0
BlastoiseEvosMoves:
; Evolutions
	db 0
; Learnset
	db 5, BUBBLE
	db 10, WATER_GUN
	db 15, BITE
	db 21, BUBBLEBEAM
	db 27, BODY_SLAM
	db 31, WITHDRAW
	db 33, WATERFALL
	db 42, SKULL_BASH
	db 45, ICE_BEAM
	db 52, HYDRO_PUMP
	db 0
    
; Tutoring Learnset   
    db 2, DEFENSE_CURL
    db 2, HEADBUTT
    db 2, ICE_PUNCH
    db 2, WATERFALL
    db 2, CONFUSION
    db 2, HAZE
    db 2, MIST
    db 0

PinsirEvosMoves:
; Evolutions
	db 0
; Learnset
	db 5, HARDEN
	db 8, FOCUS_ENERGY
	db 25, SEISMIC_TOSS
	db 30, TWINEEDLE
	db 36, SUBMISSION
	db 42, SLASH
	db 45, GUILLOTINE
	db 48, BIND
	db 54, SWORDS_DANCE
	db 0

; Tutoring Learnset   
    db 2, HEADBUTT
    db 2, FURY_ATTACK
    db 2, ROCK_THROW
    db 0

TangelaEvosMoves:
; Evolutions
; Species Groups Phase 2: canon Tangela->Tangrowth is a level-up-knowing-
; Ancient-Power evolution; Ancient Power does not exist in Gen 1, so -
; matching KEP's own fallback for the same species (already promised in
; PiloswineEvosMoves's own note back in batch 6) - a plain level threshold
; is used instead.
	db EVOLVE_LEVEL, 44, TANGROWTH
	db 0
; Learnset
	db 15, ABSORB
	db 19, VINE_WHIP
	db 21, POISONPOWDER
	db 23, STUN_SPORE
	db 25, SLEEP_POWDER
	db 32, MEGA_DRAIN
	db 42, BODY_SLAM
	db 45, GROWTH
	db 48, BIND
	db 0
    
; Tutoring Learnset   
    db 2, HEADBUTT
    db 2, FLASH
    db 2, AMNESIA
    db 2, CONFUSION
    db 2, REFLECT
    db 0

MissingNo1FEvosMoves:
; Evolutions
	db 0
; Learnset
	db 0

ChikoritaEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 16, BAYLEEF
	db 0
; Learnset - canon Gen 2 levels (tmp/pokegold/data/pokemon/evos_attacks.asm);
; SYNTHESIS and SAFEGUARD do not exist in Gen 1 and are filled with METRONOME.
	db 8, RAZOR_LEAF
	db 12, REFLECT
	db 15, POISONPOWDER
	db 22, METRONOME ; was SYNTHESIS
	db 29, BODY_SLAM
	db 36, LIGHT_SCREEN
	db 43, METRONOME ; was SAFEGUARD
	db 50, SOLARBEAM
	db 0
; Tutoring Learnset
    db 2, DEFENSE_CURL
    db 2, FLASH
    db 2, HEADBUTT
    db 2, LIGHT_SCREEN
    db 2, PETAL_DANCE
    db 2, RAZOR_WIND
    db 2, SKULL_BASH
    db 0

GrowlitheEvosMoves:
; Evolutions
	db EVOLVE_ITEM, FIRE_STONE, 1, ARCANINE
	db 0
; Learnset
	db 18, EMBER
	db 23, LEER
	db 30, TAKE_DOWN
	db 35, FLAMETHROWER
	db 36, AGILITY
	db 0
    
; Tutoring Learnset   
    db 2, HEADBUTT
    db 2, FIRE_SPIN
    db 2, THRASH
    db 0

OnixEvosMoves:
; Evolutions
; Species Groups Phase 2: canon Onix->Steelix is a trade-holding-Metal-Coat
; evolution; this project has no Metal Coat item, so - matching KEP's own
; fallback path for the same species - a plain level threshold is used
; instead.
	db EVOLVE_LEVEL, 38, STEELIX
	db 0
; Learnset
	db 12, ROCK_THROW
	db 19, DIG
	db 25, RAGE
	db 29, HARDEN
	db 31, SLAM
	db 37, ROCK_SLIDE
	db 43, EARTHQUAKE
	db 48, BIND
	db 0
    
; Tutoring Learnset   
    db 2, HEADBUTT
    db 2, SHARPEN
    db 0

FearowEvosMoves:
; Evolutions
	db 0
; Learnset
	db 7, LEER
	db 10, FURY_ATTACK
	db 14, FOCUS_ENERGY
	db 18, SWIFT
	db 20, MIRROR_MOVE
	db 24, DRILL_PECK
	db 30, SHARPEN
	db 40, AGILITY
	db 0
    
; Tutoring Learnset   
    db 2, QUICK_ATTACK
    db 2, TRI_ATTACK
    db 2, SONICBOOM
    db 2, PAY_DAY
    db 0

PidgeyEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 18, PIDGEOTTO
	db 0
; Learnset
	db 5, SAND_ATTACK
	db 12, QUICK_ATTACK
	db 19, WING_ATTACK
	db 29, TAKE_DOWN
	db 34, AGILITY
	db 49, MIRROR_MOVE
	db 0
    
; Tutoring Learnset   
    db 2, TACKLE
    db 0

SlowpokeEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 37, SLOWBRO
; Species Groups Phase 2: canon Slowpoke->Slowking is a trade evolution
; (holding King's Rock); EVOLVE_TRADE is the closest fit this engine has.
; Min level 40, per project convention for this import's trade evolutions.
	db EVOLVE_TRADE, 40, SLOWKING
	db 0
; Learnset
	db 5, GROWL
	db 5, WATER_GUN
	db 10, CONFUSION 
	db 18, DISABLE
	db 22, HEADBUTT
	db 25, PSYBEAM
	db 28, WATERFALL
	db 36, WITHDRAW
	db 40, AMNESIA
	db 45, PSYCHIC_M
	db 0
; Tutoring Learnset   
    db 2, TACKLE
    db 2, DREAM_EATER
    db 2, STOMP
    db 0
    
KadabraEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 42, ALAKAZAM
	db 0
; Learnset
	db 16, CONFUSION
	db 20, DISABLE
	db 27, PSYBEAM
	db 31, RECOVER
	db 38, PSYCHIC_M
	db 42, REFLECT
	db 0
    
; Tutoring Learnset   
    db 2, DREAM_EATER
    db 2, FIRE_PUNCH
    db 2, HEADBUTT
    db 2, ICE_PUNCH
    db 2, THUNDERPUNCH
    db 2, BARRIER
    db 2, LIGHT_SCREEN
    db 0

GravelerEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 38, GOLEM
	db 0
; Learnset
	db 6, DEFENSE_CURL
	db 12, ROCK_THROW
	db 21, DIG
	db 26, HARDEN
	db 31, SELFDESTRUCT
	db 40, ROCK_SLIDE
	db 45, EARTHQUAKE
	db 48, EXPLOSION
	db 0
    
; Tutoring Learnset   
    db 2, FIRE_PUNCH
    db 2, HEADBUTT
    db 0

ChanseyEvosMoves:
; Evolutions
; Species Groups Phase 2: canon Chansey->Blissey is a friendship evolution;
; this project has no friendship mechanic, so - matching KEP's own fallback
; path for the same species (tmp/kep/data/pokemon/evos_moves.asm's
; ChanseyEvosMoves, EV_LEVEL 45 BLISSEY) - a plain level threshold is used
; instead.
	db EVOLVE_LEVEL, 45, BLISSEY
	db 0
; Learnset
	db 12, DOUBLESLAP
	db 24, SING
	db 30, GROWL
	db 38, MINIMIZE
	db 44, DEFENSE_CURL
	db 48, LIGHT_SCREEN
	db 50, MEGA_PUNCH
	db 54, DOUBLE_EDGE
	db 0
; Tutoring Learnset   
    db 2, DREAM_EATER
    db 2, HEADBUTT
    db 0

MachokeEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 38, MACHAMP
	db 0
; Learnset
	db 5, LEER
	db 7, FOCUS_ENERGY
	db 19, SEISMIC_TOSS
	db 28, SUBMISSION
	db 33, BODY_SLAM
	db 37, COUNTER
	db 41, KARATE_CHOP
	db 0
; Tutoring Learnset   
    db 2, MEDITATE
    db 2, FIRE_PUNCH
    db 2, HEADBUTT
    db 2, ICE_PUNCH
    db 2, THUNDERPUNCH
    db 2, ROLLING_KICK
    db 2, LIGHT_SCREEN
    db 2, THRASH
    db 0

MrMimeEvosMoves:
; Evolutions
	db 0
; Learnset
	db 15, CONFUSION
	db 23, LIGHT_SCREEN
	db 23, REFLECT
	db 27, DOUBLESLAP
	db 31, PSYBEAM
	db 39, MEDITATE
	db 43, PSYCHIC_M
	db 47, SUBSTITUTE
	db 50, BARRIER
	db 0
; Tutoring Learnset   
    db 2, DREAM_EATER
    db 2, FIRE_PUNCH
    db 2, HEADBUTT
    db 2, ICE_PUNCH
    db 2, THUNDERPUNCH
    db 2, HYPNOSIS
    db 0
HitmonleeEvosMoves:
; Evolutions
	db 0
; Learnset
	db 25, FOCUS_ENERGY
	db 33, ROLLING_KICK
	db 38, JUMP_KICK
	db 43, MEDITATE
	db 48, HI_JUMP_KICK
	db 53, MEGA_KICK
	db 0
; Tutoring Learnset   
    db 2, HEADBUTT
    db 2, TACKLE
    db 2, DIZZY_PUNCH
    db 0

HitmonchanEvosMoves:
; Evolutions
	db 0
; Learnset
	db 25, KARATE_CHOP
	db 33, FIRE_PUNCH
	db 35, ICE_PUNCH
	db 37, THUNDERPUNCH
	db 40, DIZZY_PUNCH
	db 42, SUBMISSION
	db 48, MEGA_PUNCH
	db 53, COUNTER
	db 0
; Tutoring Learnset   
    db 2, HEADBUTT
    db 2, TACKLE
    db 2, DIZZY_PUNCH
    db 0
ArbokEvosMoves:
; Evolutions
	db 0
; Learnset
	db 9,  POISON_STING
	db 15, BITE
	db 18, ACID
	db 22, SUBSTITUTE
	db 25, GLARE
	db 30, SCREECH
	db 35, SLUDGE
	db 38, WRAP
	db 0
; Tutoring Learnset   
    db 2, HEADBUTT
    db 2, HAZE
    db 2, SLAM
    db 0

ParasectEvosMoves:
; Evolutions
	db 0
; Learnset
	db 6, STUN_SPORE
	db 8, ABSORB
	db 10, LEECH_LIFE
	db 13, POISONPOWDER
	db 24, SPORE
	db 27, MEGA_DRAIN
	db 30, SLASH
	db 36, GROWTH
	db 0
; Tutoring Learnset   
    db 2, FLASH
    db 2, COUNTER
    db 2, LIGHT_SCREEN
    db 2, PSYBEAM
    db 2, SCREECH
    db 0

PsyduckEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 33, GOLDUCK
	db 0
; Learnset
	db 10, DISABLE
	db 15, CONFUSION
	db 17, BUBBLEBEAM
	db 23, SCREECH
	db 40, FURY_SWIPES
	db 42, PSYCHIC_M
	db 45, AMNESIA
	db 50, HYDRO_PUMP
	db 0
    
; Tutoring Learnset   
    db 2, SCREECH
    db 2, FLASH
    db 2, HEADBUTT
    db 2, ICE_PUNCH
    db 2, WATERFALL
    db 2, HYPNOSIS
    db 2, LIGHT_SCREEN
    db 2, PSYBEAM
    db 2, PETAL_DANCE
    db 2, TRI_ATTACK
    db 0

DrowzeeEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 26, HYPNO
	db 0
; Learnset
	db 12, DISABLE
	db 17, CONFUSION
	db 24, HEADBUTT
	db 29, POISON_GAS
	db 32, PSYCHIC_M
	db 37, MEDITATE
	db 40, HYPNOSIS
	db 45, DREAM_EATER
	db 0
; Tutoring Learnset   
    db 2, FIRE_PUNCH
    db 2, HEADBUTT
    db 2, ICE_PUNCH
    db 2, THUNDERPUNCH
    db 2, BARRIER
    db 2, LIGHT_SCREEN
    db 2, AMNESIA
    db 0

GolemEvosMoves:
; Evolutions
	db 0
; Learnset
	db 6, DEFENSE_CURL
	db 12, ROCK_THROW
	db 21, DIG
	db 26, HARDEN
	db 31, SELFDESTRUCT
	db 40, ROCK_SLIDE
	db 45, EARTHQUAKE
	db 48, EXPLOSION
	db 0
    
; Tutoring Learnset   
    db 2, FIRE_PUNCH
    db 2, HEADBUTT
    db 0

BayleefEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 32, MEGANIUM
	db 0
; Learnset - canon Gen 2 levels; SYNTHESIS/SAFEGUARD filled with METRONOME
; (see ChikoritaEvosMoves). RAZOR_LEAF is already granted at level 1 - see
; base_stats/bayleef.asm.
	db 12, REFLECT
	db 15, POISONPOWDER
	db 23, METRONOME ; was SYNTHESIS
	db 31, BODY_SLAM
	db 39, LIGHT_SCREEN
	db 47, METRONOME ; was SAFEGUARD
	db 55, SOLARBEAM
	db 0
; Tutoring Learnset
    db 2, DEFENSE_CURL
    db 2, FLASH
    db 2, HEADBUTT
    db 2, LIGHT_SCREEN
    db 2, PETAL_DANCE
    db 2, RAZOR_WIND
    db 2, SKULL_BASH
    db 0

MagmarEvosMoves:
; Evolutions
; Species Groups Phase 2: canon Magmar->Magmortar is an item evolution -
; FIRE_STONE, already in this project, is the exact canon trigger.
	db EVOLVE_ITEM, FIRE_STONE, 1, MAGMORTAR
	db 0
; Learnset
	db 10, SMOG
	db 15, LEER
	db 20, CONFUSE_RAY
	db 31, FIRE_PUNCH
	db 40, SMOKESCREEN
	db 43, FLAMETHROWER
	db 54, FIRE_BLAST
	db 0
; Tutoring Learnset   
    db 2, HEADBUTT
    db 2, THUNDERPUNCH
    db 2, DIZZY_PUNCH
    db 2, KARATE_CHOP
    db 2, SCREECH
    db 0

MeganiumEvosMoves:
; Evolutions
	db 0
; Learnset - canon Gen 2 levels; SYNTHESIS/SAFEGUARD filled with METRONOME
; (see ChikoritaEvosMoves). RAZOR_LEAF/REFLECT are already granted at level 1
; - see base_stats/meganium.asm.
	db 15, POISONPOWDER
	db 23, METRONOME ; was SYNTHESIS
	db 31, BODY_SLAM
	db 41, LIGHT_SCREEN
	db 51, METRONOME ; was SAFEGUARD
	db 61, SOLARBEAM
	db 0
; Tutoring Learnset
    db 2, DEFENSE_CURL
    db 2, FLASH
    db 2, HEADBUTT
    db 2, LIGHT_SCREEN
    db 2, PETAL_DANCE
    db 2, RAZOR_WIND
    db 2, SKULL_BASH
    db 0

ElectabuzzEvosMoves:
; Evolutions
; Species Groups Phase 2: canon Electabuzz->Electivire is an item
; evolution - THUNDER_STONE, already in this project, is the exact canon
; trigger.
	db EVOLVE_ITEM, THUNDER_STONE, 1, ELECTIVIRE
	db 0
; Learnset
	db 15, THUNDERSHOCK
	db 20, THUNDER_WAVE
	db 25, SCREECH
	db 31, THUNDERPUNCH
	db 40, LIGHT_SCREEN
	db 43, THUNDERBOLT
	db 54, THUNDER
	db 0
    
; Tutoring Learnset   
    db 2, FIRE_PUNCH
    db 2, HEADBUTT
    db 2, ICE_PUNCH
    db 2, BARRIER
    db 2, DIZZY_PUNCH
    db 2, KARATE_CHOP
    db 2, MEDITATE
    db 2, ROLLING_KICK
    db 0

MagnetonEvosMoves:
; Evolutions
; Species Groups Phase 2: canon Magneton->Magnezone is a level-up-in-a-
; special-magnetic-field evolution; this project has no such location
; mechanic, so THUNDER_STONE (already in the project, and Magnemite's own
; Kanto-era item association) substitutes for the trigger.
	db EVOLVE_ITEM, THUNDER_STONE, 1, MAGNEZONE
	db 0
; Learnset
	db 6, THUNDERSHOCK
	db 11, SUPERSONIC
	db 16, SONICBOOM
	db 21, THUNDER_WAVE
	db 24, SWIFT
	db 27, REFLECT
	db 33, THUNDERBOLT
	db 37, TRI_ATTACK
	db 43, SCREECH
	db 50, THUNDER
	db 0
; Tutoring Learnset   
    db 2, AGILITY
    db 2, TRI_ATTACK
    db 0

KoffingEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 35, WEEZING
	db 0
; Learnset
	db 23, ACID
	db 27, SMOKESCREEN
	db 33, SLUDGE
	db 38, AMNESIA
	db 40, SELFDESTRUCT
	db 45, HAZE
	db 48, EXPLOSION
	db 0
    
; Tutoring Learnset   
    db 2, POISON_GAS
    db 2, PSYBEAM
    db 2, PSYWAVE
    db 2, SCREECH
    db 0

CyndaquilEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 14, QUILAVA
	db 0
; Learnset - canon Gen 2 levels; FLAME_WHEEL does not exist in Gen 1, filled
; with METRONOME.
	db 6, SMOKESCREEN
	db 12, EMBER
	db 19, QUICK_ATTACK
	db 27, METRONOME ; was FLAME_WHEEL
	db 36, SWIFT
	db 46, FLAMETHROWER
	db 0

MankeyEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 28, PRIMEAPE
	db 0
; Learnset
	db 9, LOW_KICK
	db 15, FURY_SWIPES
	db 21, KARATE_CHOP
	db 27, FOCUS_ENERGY
	db 33, SEISMIC_TOSS
	db 39, THRASH
	db 45, SCREECH
	db 0
; Tutoring Learnset   
    db 2, HEADBUTT
    db 2, DEFENSE_CURL
    db 2, FIRE_PUNCH
    db 2, ICE_PUNCH
    db 2, THUNDERPUNCH
    db 2, MEDITATE
    db 0
SeelEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 34, DEWGONG
	db 0
; Learnset
	db 5, GROWL
	db 13, WATER_GUN
	db 16, AURORA_BEAM
	db 21, REST
	db 25, BUBBLEBEAM
	db 32, TAKE_DOWN
	db 40, ICE_BEAM
	db 50, BLIZZARD
	db 0
; Tutoring Learnset   
    db 2, WATERFALL
    db 2, DISABLE
    db 2, LICK
    db 2, PECK
    db 2, SLAM
    db 0
DiglettEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 26, DUGTRIO
	db 0
; Learnset
	db 15, GROWL
	db 19, DIG
	db 24, SAND_ATTACK
	db 31, SLASH
	db 35, SCREECH
	db 40, EARTHQUAKE
	db 55, FISSURE
	db 0
; Tutoring Learnset   
    db 2, SCREECH
    db 0
TaurosEvosMoves:
; Evolutions
	db 0
; Learnset
	db 13, HORN_ATTACK
	db 15, LEER
	db 19, STOMP
	db 23, TAIL_WHIP
	db 27, HEADBUTT
	db 35, RAGE
	db 40, TAKE_DOWN
	db 45, THRASH
	db 50, DOUBLE_EDGE
	db 0
; Tutoring Learnset   
    db 2, SURF
    db 2, QUICK_ATTACK
    db 0

QuilavaEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 36, TYPHLOSION
	db 0
; Learnset - SMOKESCREEN already granted at level 1, see base_stats/quilava.asm
	db 12, EMBER
	db 21, QUICK_ATTACK
	db 31, METRONOME ; was FLAME_WHEEL
	db 42, SWIFT
	db 54, FLAMETHROWER
	db 0

TyphlosionEvosMoves:
; Evolutions
	db 0
; Learnset - SMOKESCREEN/EMBER already granted at level 1
	db 21, QUICK_ATTACK
	db 31, METRONOME ; was FLAME_WHEEL
	db 45, SWIFT
	db 60, FLAMETHROWER
	db 0

TotodileEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 18, CROCONAW
	db 0
; Learnset - canon Gen 2 levels; SCARY_FACE does not exist in Gen 1, filled
; with METRONOME.
	db 7, RAGE
	db 13, WATER_GUN
	db 20, BITE
	db 27, METRONOME ; was SCARY_FACE
	db 35, SLASH
	db 43, SCREECH
	db 52, HYDRO_PUMP
	db 0

FarfetchdEvosMoves:
; Evolutions
; Species Groups Phase 2: canon Farfetch'd->Sirfetch'd is a level-up-while-
; knowing-Leek-Swipe-after-winning-3-battles evolution; this engine cannot
; express any of that, so a plain level threshold is used instead (KEP's
; own fallback level for this species, 24, though KEP's own target name
; there was a copy-paste error - Sirfetch'd is the correct target).
	db EVOLVE_LEVEL, 24, SIRFETCHD
	db 0
; Learnset
	db 7, LEER
	db 9, SHARPEN
	db 13, FURY_ATTACK
	db 18, WING_ATTACK
	db 23, SLASH
	db 28, SWORDS_DANCE
	db 31, DRILL_PECK
	db 39, AGILITY
	db 0
; Tutoring Learnset   
    db 2, HEADBUTT
    db 2, GUST
    db 2, MIRROR_MOVE
    db 2, QUICK_ATTACK
    db 0

VenonatEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 31, VENOMOTH
	db 0
; Learnset
	db 11, SUPERSONIC
	db 13, LEECH_LIFE
	db 17, CONFUSION
	db 20, POISONPOWDER
	db 29, STUN_SPORE
	db 33, PSYBEAM
	db 36, SLEEP_POWDER
	db 41, PSYCHIC_M
	db 0
; Tutoring Learnset   
    db 2, SWIFT
    db 2, SCREECH
    db 0

DragoniteEvosMoves:
; Evolutions
	db 0
; Learnset
	db 10, THUNDER_WAVE
	db 20, DRAGON_RAGE
	db 25, AGILITY
	db 30, SLAM
	db 55, WING_ATTACK
	db 60, HYPER_BEAM
	db 0
; Tutoring Learnset  
    db 2, FIRE_PUNCH
    db 2, ICE_PUNCH
    db 2, THUNDERPUNCH
    db 2, HEADBUTT
    db 2, WATERFALL
    db 2, HYDRO_PUMP
    db 2, HAZE
    db 2, LIGHT_SCREEN
    db 2, MIST
    db 2, SUPERSONIC
    db 0 
CroconawEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 30, FERALIGATR
	db 0
; Learnset - RAGE already granted at level 1
	db 13, WATER_GUN
	db 21, BITE
	db 28, METRONOME ; was SCARY_FACE
	db 37, SLASH
	db 45, SCREECH
	db 55, HYDRO_PUMP
	db 0

FeraligatrEvosMoves:
; Evolutions
	db 0
; Learnset - RAGE/WATER_GUN already granted at level 1
	db 21, BITE
	db 28, METRONOME ; was SCARY_FACE
	db 38, SLASH
	db 47, SCREECH
	db 58, HYDRO_PUMP
	db 0

SentretEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 15, FURRET
	db 0
; Learnset - canon Gen 2 levels
	db 5, DEFENSE_CURL
	db 11, QUICK_ATTACK
	db 17, FURY_SWIPES
	db 25, SLAM
	db 33, REST
	db 41, AMNESIA
	db 0

DoduoEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 31, DODRIO
	db 0
; Learnset
	db 20, GROWL
	db 24, FURY_ATTACK
	db 30, DRILL_PECK
	db 36, RAGE
	db 39, TRI_ATTACK
	db 45, LOW_KICK
	db 51, AGILITY
	db 0
; Tutoring Learnset  
    db 2, SWIFT
    db 2, HAZE
    db 2, QUICK_ATTACK
    db 2, SUPERSONIC
    db 2, LOW_KICK
    db 0 
PoliwagEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 18, POLIWHIRL
	db 0
; Learnset
	db 6, MIST
	db 9, BUBBLE
	db 13, WATER_GUN
	db 22, BUBBLEBEAM
	db 35, BODY_SLAM
	db 43, HYPNOSIS
	db 48, AMNESIA
	db 53, HYDRO_PUMP
	db 0
; Tutoring Learnset  
    db 2, DEFENSE_CURL
    db 2, WATERFALL
    db 2, HEADBUTT
    db 2, HAZE
    db 2, MIST
    db 2, SPLASH
    db 2, GROWTH
    db 2, LOVELY_KISS
    db 0 
JynxEvosMoves:
; Evolutions
	db 0
; Learnset
	db 18, CONFUSION
	db 23, DOUBLESLAP
	db 31, ICE_PUNCH
	db 35, LOVELY_KISS
	db 39, PSYCHIC_M
	db 43, ICE_BEAM
	db 47, BODY_SLAM
	db 54, BLIZZARD
	db 0
; Tutoring Learnset  
    db 2, SING
    db 2, DREAM_EATER
    db 2, HEADBUTT
    db 2, DIZZY_PUNCH
    db 2, PETAL_DANCE
    db 2, MEDITATE
    db 0 
MoltresEvosMoves:
; Evolutions
	db 0
; Learnset
    db 6,  EMBER
	db 35, AGILITY
	db 45, FLAMETHROWER
	db 51, FIRE_BLAST
	db 55, SKY_ATTACK
	db 60, FIRE_SPIN
	db 0
; Tutoring Learnset  
    db 2, WING_ATTACK
    db 0 
ArticunoEvosMoves:
; Evolutions
	db 0
; Learnset
    db 6,  AURORA_BEAM
	db 35, AGILITY
	db 45, ICE_BEAM
	db 51, BLIZZARD
	db 55, SKY_ATTACK
	db 60, MIST
	db 0
 ; Tutoring Learnset  
    db 2, GUST
    db 0    

ZapdosEvosMoves:
; Evolutions
	db 0
; Learnset
	db 35, AGILITY
	db 40, DRILL_PECK
	db 45, THUNDERBOLT
	db 51, THUNDER
	db 60, LIGHT_SCREEN
	db 0
    
; Tutoring Learnset  
    db 2, PECK
    db 0 

DittoEvosMoves:
; Evolutions
	db 0
; Learnset
	db 0

MeowthEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 28, PERSIAN
	db 0
; Learnset
	db 10, FURY_SWIPES
	db 15, BITE
	db 18, PAY_DAY
	db 22, SCREECH
	db 29, TAKE_DOWN
	db 34, SLASH
	db 45, HYPER_BEAM
	db 0
; Tutoring Learnset  
    db 2, DEFENSE_CURL
    db 2, DREAM_EATER
    db 2, HEADBUTT
    db 2, AMNESIA
    db 2, HYPNOSIS
    db 0 
KrabbyEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 28, KINGLER
	db 0
; Learnset
	db 20, VICEGRIP
	db 25, BUBBLEBEAM
	db 29, CUT
	db 30, STOMP
	db 35, CRABHAMMER
	db 40, HARDEN
	db 50, GUILLOTINE
	db 0
; Tutoring Learnset  
    db 2, AMNESIA
    db 2, DIG
    db 2, HAZE
    db 2, SLAM
    db 0 
FurretEvosMoves:
; Evolutions
	db 0
; Learnset - DEFENSE_CURL/QUICK_ATTACK already granted at level 1
	db 18, FURY_SWIPES
	db 28, SLAM
	db 38, REST
	db 48, AMNESIA
	db 0

HoothootEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 20, NOCTOWL
	db 0
; Learnset - canon Gen 2 levels; FORESIGHT does not exist in Gen 1, filled
; with METRONOME.
	db 6, METRONOME ; was FORESIGHT
	db 11, PECK
	db 16, HYPNOSIS
	db 22, REFLECT
	db 28, TAKE_DOWN
	db 34, CONFUSION
	db 48, DREAM_EATER
	db 0

NoctowlEvosMoves:
; Evolutions
	db 0
; Learnset - FORESIGHT/PECK already granted at level 1 (see
; base_stats/noctowl.asm)
	db 16, HYPNOSIS
	db 25, REFLECT
	db 33, TAKE_DOWN
	db 41, CONFUSION
	db 57, DREAM_EATER
	db 0

VulpixEvosMoves:
; Evolutions
	db EVOLVE_ITEM, FIRE_STONE, 1, NINETALES
	db 0
; Learnset
	db 7, QUICK_ATTACK
	db 16, CONFUSE_RAY
	db 25, REFLECT
	db 32, FLAMETHROWER
	db 37, NIGHT_SHADE
	db 42, FIRE_SPIN
	db 0
; Tutoring Learnset  
    db 2, HEADBUTT
    db 2, DISABLE
    db 2, HYPNOSIS
    db 0 
NinetalesEvosMoves:
; Evolutions
	db 0
; Learnset
	db 7, QUICK_ATTACK
	db 16, CONFUSE_RAY
	db 25, REFLECT
	db 32, FLAMETHROWER
	db 37, NIGHT_SHADE
	db 42, FIRE_SPIN
	db 0
; Tutoring Learnset  
    db 2, HEADBUTT
    db 2, DISABLE
    db 2, HYPNOSIS
    db 0 
PikachuEvosMoves:
; Evolutions
	db EVOLVE_ITEM, THUNDER_STONE, 1, RAICHU
	db 0
; Learnset
	db 6, QUICK_ATTACK
	db 8, THUNDER_WAVE
	db 11, TAIL_WHIP
	db 15, DOUBLE_TEAM
	db 20, THUNDERPUNCH
	db 24, HEADBUTT
	db 30, THUNDERBOLT
	db 36, AGILITY
	db 41, THUNDER
	db 50, LIGHT_SCREEN
	db 0
    
; Tutoring Learnset  
    db 2, HEADBUTT
    db 2, DEFENSE_CURL
    db 2, STRENGTH
    db 2, THUNDERPUNCH
    db 2, DIZZY_PUNCH
    db 2, DOUBLESLAP
    db 2, PETAL_DANCE
    db 2, SING
    db 2, FLY
    db 2, SURF
    db 0 

RaichuEvosMoves:
; Evolutions
	db 0
; Learnset
	db 6, QUICK_ATTACK
	db 8, THUNDER_WAVE
	db 11, TAIL_WHIP
	db 15, DOUBLE_TEAM
	db 20, THUNDERPUNCH
	db 24, HEADBUTT
	db 30, THUNDERBOLT
	db 36, AGILITY
	db 41, THUNDER
	db 50, LIGHT_SCREEN
	db 0
; Tutoring Learnset  
    db 2, HEADBUTT
    db 2, DEFENSE_CURL
    db 2, STRENGTH
    db 2, THUNDERPUNCH
    db 2, DIZZY_PUNCH
    db 2, DOUBLESLAP
    db 2, PETAL_DANCE
    db 2, SING
    db 2, FLY
    db 2, SURF
    db 0 
LedybaEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 18, LEDIAN
	db 0
; Learnset - canon Gen 2 levels; SAFEGUARD/BATON_PASS do not exist in Gen 1,
; filled with METRONOME.
	db 8, SUPERSONIC
	db 15, COMET_PUNCH
	db 22, LIGHT_SCREEN
	db 22, REFLECT
	db 22, METRONOME ; was SAFEGUARD
	db 29, METRONOME ; was BATON_PASS
	db 36, SWIFT
	db 43, AGILITY
	db 50, DOUBLE_EDGE
	db 0

LedianEvosMoves:
; Evolutions
	db 0
; Learnset - TACKLE/SUPERSONIC already granted at level 1
	db 8, SUPERSONIC
	db 15, COMET_PUNCH
	db 24, LIGHT_SCREEN
	db 24, REFLECT
	db 24, METRONOME ; was SAFEGUARD
	db 33, METRONOME ; was BATON_PASS
	db 42, SWIFT
	db 51, AGILITY
	db 60, DOUBLE_EDGE
	db 0

DratiniEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 30, DRAGONAIR
	db 0
; Learnset
	db 10, THUNDER_WAVE
	db 20, DRAGON_RAGE
	db 25, AGILITY
	db 30, SLAM
	db 60, HYPER_BEAM
	db 0
; Tutoring Learnset  
    db 2, HEADBUTT
    db 2, WATERFALL
    db 2, HAZE
    db 2, LIGHT_SCREEN
    db 2, MIST
    db 2, SUPERSONIC
    db 2, HYDRO_PUMP
    db 0 

DragonairEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 55, DRAGONITE
	db 0
; Learnset
	db 10, THUNDER_WAVE
	db 20, DRAGON_RAGE
	db 25, AGILITY
	db 30, SLAM
	db 45, DRAGON_RAGE
	db 60, HYPER_BEAM
	db 0
; Tutoring Learnset  
    db 2, HEADBUTT
    db 2, WATERFALL
    db 2, HAZE
    db 2, LIGHT_SCREEN
    db 2, MIST
    db 2, SUPERSONIC
    db 2, HYDRO_PUMP
    db 0 
KabutoEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 40, KABUTOPS
	db 0
; Learnset
	db 11, LEER	
	db 15, WATER_GUN
	db 19, ABSORB
	db 25, ROCK_THROW
	db 35, MEGA_DRAIN
	db 39, SLASH
	db 43, SWORDS_DANCE
	db 46, ROCK_SLIDE
	db 53, HYDRO_PUMP
	db 0
; Tutoring Learnset  
    db 2, SAND_ATTACK
    db 2, AURORA_BEAM
    db 2, DIG
    db 0 
KabutopsEvosMoves:
; Evolutions
	db 0
; Learnset
	db 11, LEER	
	db 15, WATER_GUN
	db 19, ABSORB
	db 25, ROCK_THROW
	db 35, MEGA_DRAIN
	db 39, SLASH
	db 43, SWORDS_DANCE
	db 46, ROCK_SLIDE
	db 53, HYDRO_PUMP
	db 0
; Tutoring Learnset  
    db 2, SAND_ATTACK
    db 2, AURORA_BEAM
    db 2, DIG
    db 2, HEADBUTT
    db 0 
HorseaEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 32, SEADRA
	db 0
; Learnset
	db 10, WATER_GUN
	db 14, SMOKESCREEN
	db 18, LEER
	db 22, BUBBLEBEAM
	db 26, DRAGON_RAGE
	db 30, AURORA_BEAM
	db 33, WATERFALL
	db 37, AGILITY
	db 45, HYDRO_PUMP
	db 0
; Tutoring Learnset  
    db 2, HEADBUTT
    db 2, WATERFALL
    db 2, AURORA_BEAM
    db 2, DISABLE
    db 2, DRAGON_RAGE
    db 2, SPLASH
    db 2, HAZE
    db 0 
SeadraEvosMoves:
; Evolutions
; Species Groups Phase 2: canon Seadra->Kingdra is a trade-holding-Dragon-
; Scale evolution. This project has no held-item trade mechanic, so - per
; the project's own trade-evolution convention (EVOLVE_TRADE at level 40,
; same as Slowpoke->Slowking and Poliwhirl->Politoed) - a plain trade
; threshold is used instead.
	db EVOLVE_TRADE, 40, KINGDRA
	db 0
; Learnset
	db 10, WATER_GUN
	db 14, SMOKESCREEN
	db 18, LEER
	db 22, BUBBLEBEAM
	db 26, DRAGON_RAGE
	db 30, AURORA_BEAM
	db 33, WATERFALL
	db 37, AGILITY
	db 41, SLAM
	db 45, HYDRO_PUMP
	db 0
; Tutoring Learnset  
    db 2, HEADBUTT
    db 2, WATERFALL
    db 2, AURORA_BEAM
    db 2, DISABLE
    db 2, DRAGON_RAGE
    db 2, SPLASH
    db 2, HAZE
    db 0 
SpinarakEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 22, ARIADOS
	db 0
; Learnset - canon Gen 2 levels; SCARY_FACE/SPIDER_WEB do not exist in Gen 1,
; filled with METRONOME.
	db 6, METRONOME ; was SCARY_FACE
	db 11, CONSTRICT
	db 17, NIGHT_SHADE
	db 23, LEECH_LIFE
	db 30, FURY_SWIPES
	db 37, METRONOME ; was SPIDER_WEB
	db 45, SCREECH
	db 53, PSYCHIC_M
	db 0

AriadosEvosMoves:
; Evolutions
	db 0
; Learnset - POISON_STING/STRING_SHOT/CONSTRICT already granted at level 1
; (SCARY_FACE's level-1 slot is METRONOME, see base_stats/ariados.asm)
	db 6, METRONOME ; was SCARY_FACE
	db 11, CONSTRICT
	db 17, NIGHT_SHADE
	db 25, LEECH_LIFE
	db 34, FURY_SWIPES
	db 43, METRONOME ; was SPIDER_WEB
	db 53, SCREECH
	db 63, PSYCHIC_M
	db 0

SandshrewEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 22, SANDSLASH
	db 0
; Learnset
	db 5,  POISON_STING
	db 8,  FURY_SWIPES
	db 10, SAND_ATTACK
	db 14, DIG
	db 18, SWIFT
	db 22, SLASH
	db 33, EARTHQUAKE
	db 0
; Tutoring Learnset  
    db 2, DEFENSE_CURL
    db 2, HEADBUTT
    db 2, COUNTER
    db 0 
SandslashEvosMoves:
; Evolutions
	db 0
; Learnset
	db 5,  POISON_STING
	db 8,  FURY_SWIPES
	db 10, SAND_ATTACK
	db 14, DIG
	db 18, SWIFT
	db 22, SLASH
	db 30, EARTHQUAKE
	db 42, SWORDS_DANCE
	db 0
; Tutoring Learnset  
    db 2, DEFENSE_CURL
    db 2, HEADBUTT
    db 2, COUNTER
    db 0 
OmanyteEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 40, OMASTAR
	db 0
; Learnset
	db 15, CONSTRICT
	db 18, BUBBLEBEAM
	db 22, HORN_ATTACK
	db 25, ROCK_THROW
	db 27, SPIKE_CANNON
	db 30, LEER
	db 37, ROCK_SLIDE
	db 46, HYDRO_PUMP
	db 0
; Tutoring Learnset  
    db 2, BITE
    db 2, HEADBUTT
    db 2, AURORA_BEAM
    db 2, HAZE
    db 2, SLAM
    db 2, SUPERSONIC
    db 0 
OmastarEvosMoves:
; Evolutions
	db 0
; Learnset
	db 15, CONSTRICT
	db 18, BUBBLEBEAM
	db 22, HORN_ATTACK
	db 25, ROCK_THROW
	db 27, SPIKE_CANNON
	db 30, LEER
	db 37, ROCK_SLIDE
	db 42, CLAMP
	db 46, HYDRO_PUMP
	db 0
; Tutoring Learnset  
    db 2, BITE
    db 2, HEADBUTT
    db 2, AURORA_BEAM
    db 2, HAZE
    db 2, SLAM
    db 2, SUPERSONIC
    db 0 
JigglypuffEvosMoves:
; Evolutions
	db EVOLVE_ITEM, MOON_STONE, 1, WIGGLYTUFF
	db 0
; Learnset
	db 3, POUND
	db 5, DEFENSE_CURL
	db 14, DISABLE
	db 16, DOUBLESLAP
	db 24, REST
	db 30, BODY_SLAM
	db 38, LOVELY_KISS,
	db 43, DOUBLE_EDGE
	db 0
; Tutoring Learnset  
    db 2, DREAM_EATER
    db 2, FIRE_PUNCH
    db 2, HEADBUTT
    db 2, ICE_PUNCH
    db 2, THUNDERPUNCH
    db 2, DIZZY_PUNCH
    db 2, PETAL_DANCE
    db 0 
WigglytuffEvosMoves:
; Evolutions
	db 0
; Learnset
	db 3, POUND
	db 5, DEFENSE_CURL
	db 14, DISABLE
	db 16, DOUBLESLAP
	db 24, REST
	db 30, BODY_SLAM
	db 38, LOVELY_KISS,
	db 43, DOUBLE_EDGE
	db 0
; Tutoring Learnset  
    db 2, DREAM_EATER
    db 2, FIRE_PUNCH
    db 2, HEADBUTT
    db 2, ICE_PUNCH
    db 2, THUNDERPUNCH
    db 2, DIZZY_PUNCH
    db 2, PETAL_DANCE
    db 0
EeveeEvosMoves:
; Evolutions
; Species Groups Phase 2R: eight branches, all EVOLVE_ITEM. The last five reuse
; the three Kanto eeveelutions as SPECIES and are distinguished by the form index
; ApplyEvoStoneForm assigns from the stone used (evos_moves.asm's EvoStoneForms).
; The 4-byte record has no room for a form, which is why the mapping lives there
; rather than here.
;
; Eight entries is safe: the parser is an unbounded walk terminated by a 0 byte.
; It did NOT used to be - EvolveMonByLevel bulk-copies this list into
; wEvoDataBuffer, which was sized for exactly three entries and would have taken
; a 20-byte overrun. NUM_EVOS_IN_BUFFER was raised to 8 for this.
	db EVOLVE_ITEM, FIRE_STONE, 1, FLAREON
	db EVOLVE_ITEM, THUNDER_STONE, 1, JOLTEON
	db EVOLVE_ITEM, WATER_STONE, 1, VAPOREON
	db EVOLVE_ITEM, LEAF_STONE, 1, FLAREON     ; -> Leafeon  (Flareon form 1)
	db EVOLVE_ITEM, SUN_STONE, 1, JOLTEON      ; -> Espeon   (Jolteon form 1)
	db EVOLVE_ITEM, DUSK_STONE, 1, JOLTEON     ; -> Umbreon  (Jolteon form 2)
	db EVOLVE_ITEM, ICE_STONE, 1, VAPOREON     ; -> Glaceon  (Vaporeon form 1)
	db EVOLVE_ITEM, MOON_STONE, 1, VAPOREON    ; -> Sylveon  (Vaporeon form 2)
	db 0
; Learnset
	db 6, TAIL_WHIP
	db 8, SAND_ATTACK
	db 9, BITE
	db 10, QUICK_ATTACK
	db 14, GROWL
	db 17, DOUBLE_KICK
	db 22, HEADBUTT
	db 30, FOCUS_ENERGY
	db 36, JUMP_KICK
	db 42, TAKE_DOWN
	db 0
; Tutoring Learnset  
    db 2, GROWTH
    db 2, HEADBUTT
    db 0
FlareonEvosMoves:
; Evolutions
	db 0
; Learnset
	db 8, SAND_ATTACK
	db 10, LEER
	db 23, QUICK_ATTACK
	db 26, EMBER
	db 30, DOUBLE_KICK
	db 36, FLAMETHROWER
	db 39, DOUBLE_EDGE
	db 41, GROWTH
	db 47, FIRE_SPIN
	db 52, FIRE_BLAST
	db 0
; Tutoring Learnset  
    db 2, GROWTH
    db 2, HEADBUTT
    db 0
JolteonEvosMoves:
; Evolutions
	db 0
; Learnset
	db 8, SAND_ATTACK
	db 23, QUICK_ATTACK
	db 26, THUNDERSHOCK
	db 30, DOUBLE_KICK
	db 36, THUNDERBOLT
	db 39, PIN_MISSILE
	db 41, AGILITY
	db 47, THUNDER_WAVE
	db 52, THUNDER
	db 0
; Tutoring Learnset  
    db 2, GROWTH
    db 2, HEADBUTT
    db 0
VaporeonEvosMoves:
; Evolutions
	db 0
; Learnset
	db 8, SAND_ATTACK
	db 16, WATER_GUN
	db 23, QUICK_ATTACK
	db 26, BUBBLEBEAM
	db 30, BITE
	db 36, AURORA_BEAM
	db 39, MIST
	db 39, HAZE
	db 41, ACID_ARMOR
	db 47, REST
	db 52, HYDRO_PUMP
	db 0
; Tutoring Learnset  
    db 2, GROWTH
    db 2, HEADBUTT
    db 2, WATERFALL
    db 0
MachopEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 28, MACHOKE
	db 0
; Learnset
	db 5, LEER
	db 7, FOCUS_ENERGY
	db 19, SEISMIC_TOSS
	db 28, SUBMISSION
	db 33, TAKE_DOWN
	db 37, COUNTER
	db 45, KARATE_CHOP
	db 0
; Tutoring Learnset  
    db 2, FIRE_PUNCH
    db 2, HEADBUTT
    db 2, THUNDERPUNCH
    db 2, ICE_PUNCH
    db 2, LIGHT_SCREEN
    db 2, MEDITATE
    db 2, ROLLING_KICK
    db 2, THRASH
    db 0
ZubatEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 22, GOLBAT
	db 0
; Learnset
	db 5, SUPERSONIC
	db 7, GUST
	db 12, BITE
	db 19, CONFUSE_RAY
	db 23, WING_ATTACK
	db 27, ACID
	db 36, SLUDGE
	db 46, HAZE
	db 0

; Tutoring Learnset  
    db 2, QUICK_ATTACK
    db 0
EkansEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 22, ARBOK
	db 0
; Learnset
	db 9,  POISON_STING
	db 12, BITE
	db 15, ACID
	db 22, SUBSTITUTE
	db 25, GLARE
	db 30, SCREECH
	db 35, SLUDGE
	db 47, WRAP
	db 0
; Tutoring Learnset   
    db 2, HEADBUTT
    db 2, HAZE
    db 2, SLAM
    db 0
ParasEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 24, PARASECT
	db 0
; Learnset
	db 6, STUN_SPORE
	db 8, ABSORB
	db 10, LEECH_LIFE
	db 13, POISONPOWDER
	db 24, SPORE
	db 27, MEGA_DRAIN
	db 30, SLASH
	db 36, GROWTH
	db 0
; Tutoring Learnset   
    db 2, FLASH
    db 2, COUNTER
    db 2, LIGHT_SCREEN
    db 2, PSYBEAM
    db 2, SCREECH
    db 0
PoliwhirlEvosMoves:
; Evolutions
	db EVOLVE_ITEM, WATER_STONE, 1, POLIWRATH
; Species Groups Phase 2: canon Poliwhirl->Politoed is a trade evolution
; (holding King's Rock); EVOLVE_TRADE is the closest fit this engine has.
; Min level 40, per project convention for this import's trade evolutions.
	db EVOLVE_TRADE, 40, POLITOED
	db 0
; Learnset
	db 6,  MIST
	db 10, DOUBLESLAP
	db 13, WATER_GUN
	db 22, BUBBLEBEAM
	db 25, KARATE_CHOP
	db 30, ICE_PUNCH
	db 35, BODY_SLAM
	db 43, HYPNOSIS
	db 48, AMNESIA
	db 53, HYDRO_PUMP
	db 0
; Tutoring Learnset  
    db 2, DEFENSE_CURL
    db 2, WATERFALL
    db 2, HEADBUTT
    db 2, HAZE
    db 2, MIST
    db 2, SPLASH
    db 2, GROWTH
    db 2, ICE_PUNCH
    db 2, LOVELY_KISS
    db 0 
PoliwrathEvosMoves:
; Evolutions
	db 0
; Learnset
	db 6,  MIST
	db 10, DOUBLESLAP
	db 13, WATER_GUN
	db 22, BUBBLEBEAM
	db 25, KARATE_CHOP
	db 30, ICE_PUNCH
	db 35, BODY_SLAM
	db 43, HYPNOSIS
	db 48, AMNESIA
	db 53, HYDRO_PUMP
	db 0
; Tutoring Learnset  
    db 2, DEFENSE_CURL
    db 2, WATERFALL
    db 2, HEADBUTT
    db 2, HAZE
    db 2, MIST
    db 2, SPLASH
    db 2, GROWTH
    db 2, ICE_PUNCH
    db 2, LOVELY_KISS
    db 0 
WeedleEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 7, KAKUNA
	db 0
; Learnset
	db 0

KakunaEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 10, BEEDRILL
	db 0
; Learnset
	db 7, HARDEN
	db 0

BeedrillEvosMoves:
; Evolutions
	db 0
; Learnset
	db 10, PIN_MISSILE
	db 12, RAGE
	db 15, FOCUS_ENERGY
	db 18, FURY_ATTACK
	db 21, ACID
	db 27, TWINEEDLE
	db 30, SLUDGE
	db 35, SWORDS_DANCE
	db 40, AGILITY
	db 0

CrobatEvosMoves:
; Evolutions
	db 0
; Learnset - from tmp/kep/data/pokemon/evos_moves.asm, already Gen 1 valid.
; LEECH_LIFE/TACKLE/BITE/SCREECH already granted at level 1.
	db 7, WING_ATTACK
	db 12, GUST
	db 14, SUPERSONIC
	db 20, BITE
	db 26, CONFUSE_RAY
	db 32, DISABLE
	db 38, SCREECH
	db 42, SLUDGE
	db 46, HAZE
	db 50, AGILITY
	db 0

DodrioEvosMoves:
; Evolutions
	db 0
; Learnset
	db 20, GROWL
	db 24, FURY_ATTACK
	db 30, DRILL_PECK
	db 36, RAGE
	db 39, TRI_ATTACK
	db 45, JUMP_KICK
	db 51, AGILITY
	db 0
; Tutoring Learnset  
    db 2, SWIFT
    db 2, HAZE
    db 2, QUICK_ATTACK
    db 2, SUPERSONIC
    db 2, LOW_KICK
    db 0
PrimeapeEvosMoves:
; Evolutions
; Species Groups Phase 2: canon Primeape->Annihilape is a level-up-while-
; knowing-Rage-Fist-after-20-hits evolution; this engine cannot express
; that counter, so a plain level threshold is used instead (not a trade
; evolution in canon, despite KEP's own EV_TRADE fallback for this exact
; species - EVOLVE_LEVEL is more faithful to the real mechanic here).
	db EVOLVE_LEVEL, 35, ANNIHILAPE
	db 0
; Learnset
	db 9, LOW_KICK
	db 15, FURY_SWIPES
	db 21, KARATE_CHOP
	db 27, FOCUS_ENERGY
	db 33, SEISMIC_TOSS
	db 39, THRASH
	db 45, SCREECH
	db 0
; Tutoring Learnset   
    db 2, HEADBUTT
    db 2, DEFENSE_CURL
    db 2, FIRE_PUNCH
    db 2, ICE_PUNCH
    db 2, THUNDERPUNCH
    db 2, MEDITATE
    db 0
DugtrioEvosMoves:
; Evolutions
	db 0
; Learnset
	db 15, GROWL
	db 19, DIG
	db 24, SAND_ATTACK
	db 31, SLASH
	db 35, SCREECH
	db 40, EARTHQUAKE
	db 55, FISSURE
	db 0
; Tutoring Learnset   
    db 2, SCREECH
    db 2, TRI_ATTACK
    db 0
VenomothEvosMoves:
; Evolutions
	db 0
; Learnset
	db 11, SUPERSONIC
	db 13, LEECH_LIFE
	db 17, CONFUSION
	db 20, POISONPOWDER
	db 25, ACID
	db 29, STUN_SPORE
	db 33, PSYBEAM
	db 36, SLEEP_POWDER
	db 41, PSYCHIC_M
	db 46, SLUDGE
	db 0
; Tutoring Learnset   
    db 2, GUST
    db 2, SWIFT
    db 2, SCREECH
    db 0
DewgongEvosMoves:
; Evolutions
	db 0
; Learnset
	db 5, GROWL
	db 13, WATER_GUN
	db 16, AURORA_BEAM
	db 21, REST
	db 25, BUBBLEBEAM
	db 32, TAKE_DOWN
	db 40, ICE_BEAM
	db 50, BLIZZARD
	db 0
; Tutoring Learnset   
    db 2, WATERFALL
    db 2, DISABLE
    db 2, LICK
    db 2, PECK
    db 2, SLAM
    db 0
ChinchouEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 27, LANTURN
	db 0
; Learnset - canon Gen 2 levels; FLAIL/SPARK do not exist in Gen 1, filled
; with METRONOME.
	db 5, SUPERSONIC
	db 13, METRONOME ; was FLAIL
	db 17, WATER_GUN
	db 25, METRONOME ; was SPARK
	db 29, CONFUSE_RAY
	db 37, TAKE_DOWN
	db 41, HYDRO_PUMP
	db 0

LanturnEvosMoves:
; Evolutions
	db 0
; Learnset - BUBBLE/THUNDER_WAVE/SUPERSONIC already granted at level 1
	db 13, METRONOME ; was FLAIL
	db 17, WATER_GUN
	db 25, METRONOME ; was SPARK
	db 33, CONFUSE_RAY
	db 45, TAKE_DOWN
	db 53, HYDRO_PUMP
	db 0

CaterpieEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 7, METAPOD
	db 0
; Learnset
	db 0

MetapodEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 10, BUTTERFREE
	db 0
; Learnset
	db 7, HARDEN
	db 0

ButterfreeEvosMoves:
; Evolutions
	db 0
; Learnset
	db 10, CONFUSION
	db 12, LEECH_LIFE
	db 13, POISONPOWDER
	db 14, STUN_SPORE
	db 15, SLEEP_POWDER
	db 18, SUPERSONIC
	db 24, GUST
	db 24, PSYBEAM
	db 32, PSYCHIC_M
	db 0

MachampEvosMoves:
; Evolutions
	db 0
; Learnset
	db 5, LEER
	db 7, FOCUS_ENERGY
	db 19, SEISMIC_TOSS
	db 28, SUBMISSION
	db 33, TAKE_DOWN
	db 37, COUNTER
	db 45, KARATE_CHOP
	db 0
; Tutoring Learnset   
    db 2, MEDITATE
    db 2, FIRE_PUNCH
    db 2, HEADBUTT
    db 2, ICE_PUNCH
    db 2, THUNDERPUNCH
    db 2, ROLLING_KICK
    db 2, LIGHT_SCREEN
    db 2, THRASH
    db 0
TogepiEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 20, TOGETIC ; substitute for canon happiness evolution -
	                              ; no friendship system in this engine
	db 0
; Learnset - canon Gen 2 levels; SWEET_KISS/ENCORE/SAFEGUARD do not exist in
; Gen 1, filled with METRONOME. Level 7's METRONOME is the real canon move.
	db 7, METRONOME
	db 18, METRONOME ; was SWEET_KISS
	db 25, METRONOME ; was ENCORE
	db 31, METRONOME ; was SAFEGUARD
	db 38, DOUBLE_EDGE
	db 0

GolduckEvosMoves:
; Evolutions
	db 0
; Learnset
	db 28, TAIL_WHIP
	db 10, DISABLE
	db 15, CONFUSION
	db 17, BUBBLEBEAM
	db 23, SCREECH
	db 40, FURY_SWIPES
	db 42, PSYCHIC_M
	db 45, AMNESIA
	db 50, HYDRO_PUMP
	db 0
; Tutoring Learnset   
    db 2, SCREECH
    db 2, FLASH
    db 2, HEADBUTT
    db 2, ICE_PUNCH
    db 2, WATERFALL
    db 2, HYPNOSIS
    db 2, LIGHT_SCREEN
    db 2, PSYBEAM
    db 2, PETAL_DANCE
    db 2, TRI_ATTACK
    db 0
HypnoEvosMoves:
; Evolutions
	db 0
; Learnset
	db 12, DISABLE
	db 17, CONFUSION
	db 24, HEADBUTT
	db 29, POISON_GAS
	db 32, PSYCHIC_M
	db 37, MEDITATE
	db 40, HYPNOSIS
	db 45, DREAM_EATER
	db 0
; Tutoring Learnset   
    db 2, FIRE_PUNCH
    db 2, HEADBUTT
    db 2, ICE_PUNCH
    db 2, THUNDERPUNCH
    db 2, BARRIER
    db 2, LIGHT_SCREEN
    db 2, AMNESIA
    db 0
GolbatEvosMoves:
; Evolutions
; Species Groups Phase 2: canon Golbat->Crobat is a friendship evolution; this
; engine only supports EVOLVE_LEVEL/EVOLVE_ITEM/EVOLVE_TRADE, so it is
; substituted with a level threshold, matching KEP's own precedent for the
; same species.
	db EVOLVE_LEVEL, 40, CROBAT
	db 0
; Learnset
	db 5, SUPERSONIC
	db 7, GUST
	db 12, BITE
	db 19, CONFUSE_RAY
	db 22, WING_ATTACK
	db 27, ACID
	db 36, SLUDGE
	db 46, HAZE
	db 0
; Tutoring Learnset   
    db 2, QUICK_ATTACK
    db 0
MewtwoEvosMoves:
; Evolutions
	db 0
; Learnset
	db 63, BARRIER
	db 66, PSYCHIC_M
	db 70, RECOVER
	db 75, MIST
	db 81, AMNESIA
	db 0
; Tutoring Learnset   
    db 2, DREAM_EATER
    db 2, HEADBUTT
    db 2, ICE_PUNCH
    db 2, THUNDERPUNCH
    db 2, FIRE_PUNCH
    db 0
SnorlaxEvosMoves:
; Evolutions
	db 0
; Learnset
	db 29, HEADBUTT
	db 33, HARDEN
	db 36, REST
	db 43, BODY_SLAM
	db 48, DOUBLE_EDGE
	db 56, HYPER_BEAM
	db 0
; Tutoring Learnset   
    db 2, TACKLE
    db 2, DEFENSE_CURL
    db 2, ICE_PUNCH
    db 2, THUNDERPUNCH
    db 2, FIRE_PUNCH
    db 2, LICK
    db 2, LOVELY_KISS
    db 2, SPLASH
    db 0
MagikarpEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 20, GYARADOS
	db 0
; Learnset
	db 15, TACKLE
	db 0
; Tutoring Learnset   
    db 2, BUBBLE
    db 2, DRAGON_RAGE
    db 0
TogeticEvosMoves:
; Evolutions
	db 0
; Learnset - GROWL/CHARM already granted at level 1 (CHARM's slot is
; METRONOME, see base_stats/togetic.asm)
	db 7, METRONOME
	db 18, METRONOME ; was SWEET_KISS
	db 25, METRONOME ; was ENCORE
	db 31, METRONOME ; was SAFEGUARD
	db 38, DOUBLE_EDGE
	db 0

NatuEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 25, XATU
	db 0
; Learnset - canon Gen 2 levels; FUTURE_SIGHT does not exist in Gen 1, filled
; with METRONOME.
	db 10, NIGHT_SHADE
	db 20, TELEPORT
	db 30, METRONOME ; was FUTURE_SIGHT
	db 40, CONFUSE_RAY
	db 50, PSYCHIC_M
	db 0

MukEvosMoves:
; Evolutions
	db 0
; Learnset
	db 10, HARDEN
	db 16, ACID
	db 19, POISON_GAS
	db 24, ACID_ARMOR
	db 27, MINIMIZE
	db 33, SLUDGE
	db 37, BODY_SLAM
	db 42, TOXIC
	db 45, SCREECH
	db 0
; Tutor Learnset
    db 2, FIRE_PUNCH
    db 2, ICE_PUNCH
    db 2, THUNDERPUNCH
    db 2, HEADBUTT
    db 2, HAZE
    db 2, LICK
    db 0
XatuEvosMoves:
; Evolutions
	db 0
; Learnset - PECK/LEER/NIGHT_SHADE already granted at level 1; FUTURE_SIGHT
; does not exist in Gen 1, filled with METRONOME.
	db 20, TELEPORT
	db 35, METRONOME ; was FUTURE_SIGHT
	db 50, CONFUSE_RAY
	db 65, PSYCHIC_M
	db 0

KinglerEvosMoves:
; Evolutions
	db 0
; Learnset
	db 20, VICEGRIP
	db 25, BUBBLEBEAM
	db 28, CUT
	db 30, STOMP
	db 35, CRABHAMMER
	db 40, HARDEN
	db 50, GUILLOTINE
	db 0
; Tutoring Learnset  
    db 2, AMNESIA
    db 2, DIG
    db 2, HAZE
    db 2, SLAM
    db 0 
CloysterEvosMoves:
; Evolutions
	db 0
; Learnset
	db 10, WATER_GUN
	db 14, SUPERSONIC
	db 17, LEER
	db 20, AURORA_BEAM
	db 25, BUBBLEBEAM
	db 35, CLAMP
	db 40, ICE_BEAM
	db 46, SPIKE_CANNON
	db 50, BLIZZARD
	db 0
; Tutoring Learnset  
    db 2, BARRIER
    db 2, SCREECH
    db 0 
MareepEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 15, FLAAFFY
	db 0
; Learnset - canon Gen 2 levels; COTTON_SPORE does not exist in Gen 1,
; filled with METRONOME.
	db 9, THUNDERSHOCK
	db 16, THUNDER_WAVE
	db 23, METRONOME ; was COTTON_SPORE
	db 30, LIGHT_SCREEN
	db 37, THUNDER
	db 0

ElectrodeEvosMoves:
; Evolutions
	db 0
; Learnset
	db 17, SONICBOOM
	db 19, THUNDERSHOCK
	db 22, SELFDESTRUCT
	db 26, SWIFT
	db 30, LIGHT_SCREEN
	db 35, THUNDERBOLT
	db 44, EXPLOSION
	db 50, THUNDER
	db 0

ClefableEvosMoves:
; Evolutions
	db 0
; Learnset
	db 13, DOUBLESLAP
	db 19, MINIMIZE
	db 26, DEFENSE_CURL
	db 30, METRONOME
	db 35, BODY_SLAM
	db 43, LIGHT_SCREEN
	db 48, SING
	db 0
; Tutoring Learnset  
    db 2, HEADBUTT
    db 2, AGILITY
    db 0 
WeezingEvosMoves:
; Evolutions
	db 0
; Learnset
	db 23, ACID
	db 27, SMOKESCREEN
	db 33, SLUDGE
	db 38, AMNESIA
	db 40, SELFDESTRUCT
	db 45, HAZE
	db 48, EXPLOSION
	db 0
; Tutoring Learnset  
    db 2, POISON_GAS
    db 2, PSYBEAM
    db 2, PSYWAVE
    db 2, SCREECH
    db 0 
PersianEvosMoves:
; Evolutions
	db 0
; Learnset
	db 10, FURY_SWIPES
	db 15, BITE
	db 18, PAY_DAY
	db 22, SCREECH
	db 29, TAKE_DOWN
	db 34, SLASH
	db 50, HYPER_BEAM
	db 0
; Tutoring Learnset  
    db 2, DEFENSE_CURL
    db 2, DREAM_EATER
    db 2, HEADBUTT
    db 2, AMNESIA
    db 2, HYPNOSIS
    db 0
MarowakEvosMoves:
; Evolutions
	db 0
; Learnset
	db 5, LEER
	db 10, BONE_CLUB
	db 13, TAIL_WHIP
	db 18, HEADBUTT
	db 25, FOCUS_ENERGY
	db 31, BONEMERANG
	db 38, THRASH
	db 46, EARTHQUAKE
	db 0
; Tutoring Learnset   
    db 2, ROCK_SLIDE
    db 2, SCREECH
    db 2, SWORDS_DANCE
    db 2, FURY_ATTACK
    db 2, FIRE_PUNCH
    db 2, THUNDERPUNCH
    db 0
FlaaffyEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 30, AMPHAROS
	db 0
; Learnset - TACKLE/GROWL/THUNDERSHOCK already granted at level 1
	db 9, THUNDERSHOCK
	db 18, THUNDER_WAVE
	db 27, METRONOME ; was COTTON_SPORE
	db 36, LIGHT_SCREEN
	db 45, THUNDER
	db 0

HaunterEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 42, GENGAR
	db 0
; Learnset
	db 10, SMOG
	db 15, PSYWAVE
	db 36, NIGHT_SHADE
	db 55, HYPNOSIS
	db 55, DREAM_EATER
	db 0
; Tutoring Learnset   
    db 2, HAZE
    db 0
AbraEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 16, KADABRA
	db 0
; Learnset
	db 0
; Tutoring Learnset   
    db 2, DREAM_EATER
    db 2, FIRE_PUNCH
    db 2, HEADBUTT
    db 2, ICE_PUNCH
    db 2, THUNDERPUNCH
    db 2, BARRIER
    db 2, LIGHT_SCREEN
    db 0
AlakazamEvosMoves:
; Evolutions
	db 0
; Learnset
	db 16, CONFUSION
	db 20, DISABLE
	db 27, PSYBEAM
	db 31, RECOVER
	db 38, PSYCHIC_M
	db 42, REFLECT
	db 0
; Tutoring Learnset   
    db 2, DREAM_EATER
    db 2, FIRE_PUNCH
    db 2, HEADBUTT
    db 2, ICE_PUNCH
    db 2, THUNDERPUNCH
    db 2, BARRIER
    db 2, LIGHT_SCREEN
    db 0
PidgeottoEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 36, PIDGEOT
	db 0
; Learnset
	db 5, SAND_ATTACK
	db 12, QUICK_ATTACK
	db 18, WING_ATTACK
	db 29, TAKE_DOWN
	db 34, AGILITY
	db 49, MIRROR_MOVE
	db 0
; Tutoring Learnset   
    db 2, TACKLE
    db 0
PidgeotEvosMoves:
; Evolutions
	db 0
; Learnset
	db 5, SAND_ATTACK
	db 12, QUICK_ATTACK
	db 18, WING_ATTACK
	db 29, TAKE_DOWN
	db 34, AGILITY
	db 40, SKY_ATTACK
	db 49, MIRROR_MOVE
	db 0
; Tutoring Learnset   
    db 2, TACKLE
    db 0
StarmieEvosMoves:
; Evolutions
	db 0
; Learnset
	db 23, HARDEN
	db 27, RECOVER
	db 37, MINIMIZE
	db 40, PSYCHIC_M
	db 42, LIGHT_SCREEN
	db 47, HYDRO_PUMP
	db 0
; Tutoring Learnset   
    db 2, WATERFALL
    db 0
BulbasaurEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 16, IVYSAUR
	db 0
; Learnset
	db 7, LEECH_SEED
	db 9, VINE_WHIP
	db 22, POISONPOWDER
	db 25, SLEEP_POWDER
	db 29, RAZOR_LEAF
	db 38, GROWTH
	db 42, BODY_SLAM
	db 52, SOLARBEAM
	db 0

; Tutoring Learnset
    db 2, DEFENSE_CURL
    db 2, FLASH
    db 2, HEADBUTT
    db 2, LIGHT_SCREEN
    db 2, PETAL_DANCE
    db 2, RAZOR_WIND
    db 2, SKULL_BASH
    db 0  


VenusaurEvosMoves:
; Evolutions
	db 0
; Learnset
	db 7, LEECH_SEED
	db 9, VINE_WHIP
	db 16, ACID
	db 22, POISONPOWDER
	db 25, SLEEP_POWDER
	db 29, RAZOR_LEAF
	db 36, SLUDGE
	db 38, GROWTH
	db 42, BODY_SLAM
	db 54, SOLARBEAM
	db 0
; Tutoring Learnset  
    db 2, DEFENSE_CURL
    db 2, FLASH
    db 2, HEADBUTT
    db 2, LIGHT_SCREEN
    db 2, PETAL_DANCE
    db 2, RAZOR_WIND
    db 2, SKULL_BASH
    db 0 
TentacruelEvosMoves:
; Evolutions
	db 0
; Learnset
	db 7, SUPERSONIC
	db 13, WATER_GUN
	db 18, ACID
	db 23, BUBBLEBEAM
	db 27, CONSTRICT
	db 35, BARRIER
	db 40, SCREECH
	db 43, SLUDGE
	db 47, WRAP
	db 50, HYDRO_PUMP
	db 0
; Tutoring Learnset   
    db 2, AURORA_BEAM
    db 2, HAZE
    db 2, CONFUSE_RAY
    db 0
AmpharosEvosMoves:
; Evolutions
	db 0
; Learnset - TACKLE/GROWL/THUNDERSHOCK/THUNDER_WAVE already granted at
; level 1
	db 9, THUNDERSHOCK
	db 18, THUNDER_WAVE
	db 27, METRONOME ; was COTTON_SPORE
	db 30, THUNDERPUNCH
	db 42, LIGHT_SCREEN
	db 57, THUNDER
	db 0

GoldeenEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 33, SEAKING
	db 0
; Learnset
	db 7, PECK
	db 10, SUPERSONIC
	db 13, WATER_GUN
	db 15, HORN_ATTACK
	db 17, WATERFALL
	db 24, FURY_ATTACK
	db 33, DRILL_PECK
	db 43, HORN_DRILL
	db 48, AGILITY
	db 0
; Tutoring Learnset   
    db 2, HYDRO_PUMP
    db 2, HAZE
    db 2, PSYBEAM
    db 2, SWORDS_DANCE
    db 0
SeakingEvosMoves:
; Evolutions
	db 0
; Learnset
	db 7, PECK
	db 10, SUPERSONIC
	db 13, WATER_GUN
	db 15, HORN_ATTACK
	db 17, WATERFALL
	db 24, FURY_ATTACK
	db 33, DRILL_PECK
	db 43, HORN_DRILL
	db 48, AGILITY
	db 0
; Tutoring Learnset   
    db 2, HYDRO_PUMP
    db 2, HAZE
    db 2, PSYBEAM
    db 2, SWORDS_DANCE
    db 0
BellossomEvosMoves:
; Evolutions
	db 0
; Learnset - from tmp/kep/data/pokemon/evos_moves.asm, already Gen 1 valid.
; STUN_SPORE/SLEEP_POWDER already granted at level 1.
	db 15, POISONPOWDER
	db 17, STUN_SPORE
	db 19, SLEEP_POWDER
	db 0

MarillEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 18, AZUMARILL
	db 0
; Learnset - canon Gen 2 levels; ROLLOUT/RAIN_DANCE do not exist in Gen 1,
; filled with METRONOME.
	db 3, DEFENSE_CURL
	db 6, TAIL_WHIP
	db 10, WATER_GUN
	db 15, METRONOME ; was ROLLOUT
	db 21, BUBBLEBEAM
	db 28, DOUBLE_EDGE
	db 36, METRONOME ; was RAIN_DANCE
	db 0

AzumarillEvosMoves:
; Evolutions
	db 0
; Learnset - TACKLE/DEFENSE_CURL/TAIL_WHIP/WATER_GUN already granted at
; level 1
	db 3, DEFENSE_CURL
	db 6, TAIL_WHIP
	db 10, WATER_GUN
	db 15, METRONOME ; was ROLLOUT
	db 25, BUBBLEBEAM
	db 36, DOUBLE_EDGE
	db 48, METRONOME ; was RAIN_DANCE
	db 0

SudowoodoEvosMoves:
; Evolutions
	db 0
; Learnset - canon Gen 2 levels; FLAIL/FAINT_ATTACK do not exist in Gen 1,
; filled with METRONOME. ROCK_THROW/MIMIC already granted at level 1.
	db 10, METRONOME ; was FLAIL
	db 19, LOW_KICK
	db 28, ROCK_SLIDE
	db 37, METRONOME ; was FAINT_ATTACK
	db 46, SLAM
	db 0

PonytaEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 40, RAPIDASH
	db 0
; Learnset
	db 19, STOMP
	db 25, DOUBLE_KICK
	db 30, TAIL_WHIP
	db 33, FLAMETHROWER
	db 35, AGILITY
	db 36, FIRE_SPIN
	db 40, TAKE_DOWN
	db 45, FIRE_BLAST
	db 0
; Tutoring Learnset   
    db 2, TACKLE
    db 2, HEADBUTT
    db 2, DOUBLE_KICK
    db 2, HYPNOSIS
    db 2, QUICK_ATTACK
    db 2, THRASH
    db 2, LOW_KICK
    db 0
RapidashEvosMoves:
; Evolutions
	db 0
; Learnset
	db 19, STOMP
	db 25, DOUBLE_KICK
	db 28, GROWL
	db 30, TAIL_WHIP
	db 33, FLAMETHROWER
	db 35, AGILITY
	db 36, FIRE_SPIN
	db 40, TAKE_DOWN
	db 45, FIRE_BLAST
	db 50, HI_JUMP_KICK
	db 0
; Tutoring Learnset   
    db 2, TACKLE
    db 2, HEADBUTT
    db 2, DOUBLE_KICK
    db 2, HYPNOSIS
    db 2, QUICK_ATTACK
    db 2, THRASH
    db 2, LOW_KICK
    db 2, FURY_ATTACK
    db 2, PAY_DAY
    db 0
RattataEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 20, RATICATE
	db 0
; Learnset
	db 7, QUICK_ATTACK
	db 9, BITE
	db 14, HYPER_FANG
	db 19, FOCUS_ENERGY
	db 24, DIG
	db 28, SUPER_FANG
	db 0
; Tutoring Learnset   
    db 2, DEFENSE_CURL
    db 2, HEADBUTT
    db 2, COUNTER
    db 2, FURY_SWIPES
    db 2, SCREECH
    db 0
RaticateEvosMoves:
; Evolutions
	db 0
; Learnset
	db 7, QUICK_ATTACK
	db 9, BITE
	db 14, HYPER_FANG
	db 19, FOCUS_ENERGY
	db 24, DIG
	db 28, SUPER_FANG
	db 0
; Tutoring Learnset   
    db 2, DEFENSE_CURL
    db 2, HEADBUTT
    db 2, COUNTER
    db 2, FURY_SWIPES
    db 2, SCREECH
    db 2, CUT
    db 2, STRENGTH
    db 0
NidorinoEvosMoves:
; Evolutions
	db EVOLVE_ITEM, MOON_STONE, 1, NIDOKING
	db 0
; Learnset
	db 8, HORN_ATTACK
	db 12, DOUBLE_KICK
	db 19, POISON_STING
	db 21, BITE
	db 24, DIG
	db 27, FOCUS_ENERGY
	db 32, SLUDGE
	db 36, FURY_ATTACK
	db 40, EARTHQUAKE
	db 46, HORN_DRILL
	db 0
; Tutor Learnset
    db 2, DEFENSE_CURL
    db 2, HEADBUTT
    db 2, AMNESIA
    db 2, CONFUSION
    db 2, COUNTER
    db 2, DISABLE
    db 2, SUPERSONIC
    db 2, LOVELY_KISS
    db 2, STRENGTH
    db 0
NidorinaEvosMoves:
; Evolutions
	db EVOLVE_ITEM, MOON_STONE, 1, NIDOQUEEN
	db 0
; Learnset
	db 6, POISON_STING
	db 8, BITE
	db 12, DOUBLE_KICK
	db 21, HEADBUTT
	db 24, DIG
	db 27, TAIL_WHIP
	db 32, SLUDGE
	db 36, FURY_SWIPES
	db 40, EARTHQUAKE
	db 0
; Tutoring Learnset   
    db 2, COUNTER
    db 2, DISABLE
    db 2, FOCUS_ENERGY
    db 2, SUPERSONIC
    db 2, LOVELY_KISS
    db 2, STRENGTH
    db 0
GeodudeEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 25, GRAVELER
	db 0
	; Learnset
	db 6, DEFENSE_CURL
	db 12, ROCK_THROW
	db 21, DIG
	db 26, HARDEN
	db 31, SELFDESTRUCT
	db 40, ROCK_SLIDE
	db 45, EARTHQUAKE
	db 48, EXPLOSION
	db 0
; Tutoring Learnset   
    db 2, FIRE_PUNCH
    db 2, HEADBUTT
    db 0
PorygonEvosMoves:
; Evolutions
; Species Groups Phase 2: canon Porygon->Porygon2 is a trade-holding-Up-
; Grade evolution; this project has no held-item trade mechanic, so - per
; the project's own trade-evolution convention (EVOLVE_TRADE at level 40,
; same as Seadra->Kingdra/Slowpoke->Slowking/Poliwhirl->Politoed) - a plain
; trade threshold is used instead.
	db EVOLVE_TRADE, 40, PORYGON2
	db 0
; Learnset
	db 12, PSYBEAM
	db 20, RECOVER
	db 24, SHARPEN
	db 28, TRI_ATTACK
	db 32, AGILITY
	db 40, BARRIER
	db 50, HYPER_BEAM
	db 0
; Tutoring Learnset   
    db 2, DREAM_EATER
    db 2, BARRIER
    db 0
AerodactylEvosMoves:
; Evolutions
	db 0
; Learnset
	db 15, BITE	
	db 22, SUPERSONIC
	db 27, ROCK_THROW
	db 32, WING_ATTACK
	db 40, ROCK_SLIDE
	db 43, TAKE_DOWN
	db 50, HYPER_BEAM
	db 0
; Tutoring Learnset   
    db 2, EARTHQUAKE
    db 2, HEADBUTT
    db 0
PolitoedEvosMoves:
; Evolutions
	db 0
; Learnset - from tmp/kep/data/pokemon/evos_moves.asm, already Gen 1 valid.
; HYPNOSIS/WATER_GUN/DOUBLESLAP/BODY_SLAM already granted at level 1.
	db 0

MagnemiteEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 30, MAGNETON
	db 0
; Learnset
	db 6, THUNDERSHOCK
	db 11, SUPERSONIC
	db 16, SONICBOOM
	db 21, THUNDER_WAVE
	db 24, SWIFT
	db 27, REFLECT
	db 33, THUNDERBOLT
	db 43, SCREECH
	db 50, THUNDER
	db 0
; Tutoring Learnset   
    db 2, AGILITY
    db 0
HoppipEvosMoves:
; Evolutions
; SKIPLOOM is a later batch. When it is added, restore:
;	db EVOLVE_LEVEL, 18, SKIPLOOM
	db 0
; Learnset - canon Gen 2 levels; SYNTHESIS (level 1, filled with METRONOME)
; and COTTON_SPORE do not exist in Gen 1.
	db 5, TAIL_WHIP
	db 10, TACKLE
	db 13, POISONPOWDER
	db 15, STUN_SPORE
	db 17, SLEEP_POWDER
	db 20, LEECH_SEED
	db 25, METRONOME ; was COTTON_SPORE
	db 30, MEGA_DRAIN
	db 0

SkiploomEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 27, JUMPLUFF
	db 0
; Learnset - SPLASH/TAIL_WHIP/TACKLE already granted at level 1 (SYNTHESIS's
; slot is METRONOME, see base_stats/skiploom.asm)
	db 5, TAIL_WHIP
	db 10, TACKLE
	db 13, POISONPOWDER
	db 15, STUN_SPORE
	db 17, SLEEP_POWDER
	db 22, LEECH_SEED
	db 29, METRONOME ; was COTTON_SPORE
	db 36, MEGA_DRAIN
	db 0

CharmanderEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 16, CHARMELEON
	db 0
; Learnset
	db 9, EMBER
	db 13, LEER
	db 17, RAGE
	db 19, FIRE_PUNCH
	db 23, BITE
	db 33, SLASH
	db 38, FLAMETHROWER
	db 46, FIRE_SPIN
	db 50, SLAM
	db 0
; Tutoring Learnset   
    db 2, SMOKESCREEN
    db 2, ROCK_SLIDE
    db 2, DEFENSE_CURL
    db 2, FIRE_PUNCH
    db 2, HEADBUTT
    db 0
SquirtleEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 16, WARTORTLE
	db 0
; Learnset
	db 5, BUBBLE
	db 10, WATER_GUN
	db 15, BITE
	db 21, BUBBLEBEAM
	db 27, BODY_SLAM
	db 31, WITHDRAW
	db 33, WATERFALL
	db 42, SKULL_BASH
	db 45, ICE_BEAM
	db 52, HYDRO_PUMP
	db 0
; Tutoring Learnset   
    db 2, CONFUSION
    db 2, HAZE
    db 2, DEFENSE_CURL
    db 2, ICE_PUNCH
    db 2, HEADBUTT
    db 2, WATERFALL
    db 2, MIST
    db 0
CharmeleonEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 36, CHARIZARD
	db 0
; Learnset
	db 9, EMBER
	db 13, LEER
	db 17, RAGE
	db 19, FIRE_PUNCH
	db 23, BITE
	db 33, SLASH
	db 40, FLAMETHROWER
	db 48, SLAM
	db 56, FIRE_SPIN
	db 0
; Tutoring Learnset   
    db 2, SMOKESCREEN
    db 2, ROCK_SLIDE
    db 2, DEFENSE_CURL
    db 2, FIRE_PUNCH
    db 2, HEADBUTT
    db 0
WartortleEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 36, BLASTOISE
	db 0
; Learnset
	db 5, BUBBLE
	db 10, WATER_GUN
	db 15, BITE
	db 21, BUBBLEBEAM
	db 27, BODY_SLAM
	db 31, WITHDRAW
	db 33, WATERFALL
	db 42, SKULL_BASH
	db 45, ICE_BEAM
	db 52, HYDRO_PUMP
	db 0
; Tutoring Learnset   
    db 2, CONFUSION
    db 2, HAZE
    db 2, DEFENSE_CURL
    db 2, ICE_PUNCH
    db 2, HEADBUTT
    db 2, WATERFALL
    db 2, MIST
    db 0
CharizardEvosMoves:
; Evolutions
	db 0
; Learnset
	db 9, EMBER
	db 13, LEER
	db 17, RAGE
	db 19, FIRE_PUNCH
	db 23, BITE
	db 33, SLASH
	db 36, WING_ATTACK
	db 42, FLAMETHROWER
	db 48, SLAM
	db 56, FIRE_SPIN
	db 0
; Tutoring Learnset   
    db 2, SMOKESCREEN
    db 2, ROCK_SLIDE
    db 2, DEFENSE_CURL
    db 2, FIRE_PUNCH
    db 2, HEADBUTT
    db 0
JumpluffEvosMoves:
; Evolutions
	db 0
; Learnset - SPLASH/TAIL_WHIP/TACKLE already granted at level 1
	db 5, TAIL_WHIP
	db 10, TACKLE
	db 13, POISONPOWDER
	db 15, STUN_SPORE
	db 17, SLEEP_POWDER
	db 22, LEECH_SEED
	db 33, METRONOME ; was COTTON_SPORE
	db 44, MEGA_DRAIN
	db 0

AipomEvosMoves:
; Evolutions
	db 0
; Learnset - SCRATCH/TAIL_WHIP already granted at level 1; BATON_PASS does
; not exist in Gen 1, filled with METRONOME.
	db 6, SAND_ATTACK
	db 12, METRONOME ; was BATON_PASS
	db 19, FURY_SWIPES
	db 27, SWIFT
	db 36, SCREECH
	db 46, AGILITY
	db 0

SunkernEvosMoves:
; Evolutions
	db EVOLVE_ITEM, SUN_STONE, 1, SUNFLORA
	db 0
; Learnset - ABSORB already granted at level 1; SUNNY_DAY/SYNTHESIS/
; GIGA_DRAIN do not exist in Gen 1, filled with METRONOME.
	db 4, GROWTH
	db 10, MEGA_DRAIN
	db 19, METRONOME ; was SUNNY_DAY
	db 31, METRONOME ; was SYNTHESIS
	db 46, METRONOME ; was GIGA_DRAIN
	db 0

SunfloraEvosMoves:
; Evolutions
	db 0
; Learnset - ABSORB/POUND already granted at level 1; SUNNY_DAY does not
; exist in Gen 1, filled with METRONOME.
	db 4, GROWTH
	db 10, RAZOR_LEAF
	db 19, METRONOME ; was SUNNY_DAY
	db 31, PETAL_DANCE
	db 46, SOLARBEAM
	db 0

OddishEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 21, GLOOM
	db 0
; Learnset
	db 5, POISONPOWDER
	db 8, LEECH_SEED
	db 13, ABSORB
	db 16, STUN_SPORE
	db 21, ACID
	db 25, MEGA_DRAIN
	db 30, SLEEP_POWDER
	db 35, PETAL_DANCE
	db 40, SLUDGE
	db 50, SOLARBEAM
	db 0
; Tutoring Learnset   
    db 2, FLASH
    db 2, RAZOR_LEAF
    db 0
GloomEvosMoves:
; Evolutions
	db EVOLVE_ITEM, LEAF_STONE, 1, VILEPLUME
; Species Groups Phase 2: canon Gloom->Bellossom uses a Sun Stone, already in
; the project (added for Espeon).
	db EVOLVE_ITEM, SUN_STONE, 1, BELLOSSOM
	db 0
; Learnset
	db 5, POISONPOWDER
	db 8, LEECH_SEED
	db 13, ABSORB
	db 16, STUN_SPORE
	db 21, ACID
	db 25, MEGA_DRAIN
	db 30, SLEEP_POWDER
	db 35, PETAL_DANCE
	db 40, SLUDGE
	db 50, SOLARBEAM
	db 0
; Tutoring Learnset   
    db 2, FLASH
    db 2, RAZOR_LEAF
    db 0
VileplumeEvosMoves:
; Evolutions
	db 0
; Learnset
	db 5, POISONPOWDER
	db 8, LEECH_SEED
	db 13, ABSORB
	db 16, STUN_SPORE
	db 21, ACID
	db 25, MEGA_DRAIN
	db 30, SLEEP_POWDER
	db 35, PETAL_DANCE
	db 40, SLUDGE
	db 50, SOLARBEAM
	db 0
; Tutoring Learnset   
    db 2, FLASH
    db 2, RAZOR_LEAF
    db 0
BellsproutEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 21, WEEPINBELL
	db 0
; Learnset
	db 13, POISONPOWDER
	db 21, STUN_SPORE
	db 25, ACID
	db 27, HEADBUTT
	db 29, RAZOR_LEAF
	db 36, SLUDGE
	db 43, WRAP
	db 48, SLEEP_POWDER
	db 0
; Tutoring Learnset   
    db 2, FLASH
    db 2, LEECH_LIFE
    db 2, LOVELY_KISS
    db 0
WeepinbellEvosMoves:
; Evolutions
	db EVOLVE_ITEM, LEAF_STONE, 1, VICTREEBEL
	db 0
; Learnset
	db 21, STUN_SPORE
	db 25, ACID
	db 27, HEADBUTT
	db 29, RAZOR_LEAF
	db 36, SLUDGE
	db 43, WRAP
	db 48, SLEEP_POWDER
	db 0
; Tutoring Learnset   
    db 2, FLASH
    db 2, LEECH_LIFE
    db 2, LOVELY_KISS
    db 0
VictreebelEvosMoves:
; Evolutions
	db 0
; Learnset
	db 13, POISONPOWDER
	db 14, VINE_WHIP
	db 21, STUN_SPORE
	db 25, ACID
	db 27, HEADBUTT
	db 29, RAZOR_LEAF
	db 36, SLUDGE
	db 43, WRAP
	db 48, SLEEP_POWDER
	db 0
; Tutoring Learnset   
    db 2, FLASH
    db 2, LEECH_LIFE
    db 2, LOVELY_KISS
    db 0

WeavileEvosMoves:
; Evolutions
	db 0
; Learnset - Weavile evolves from Sneasel (added in batch 6, see
; SneaselEvosMoves for the EVOLVE_ITEM, ICE_STONE wiring).
	db 20, METRONOME ; FILLER - real moveset TBD
	db 40, METRONOME ; FILLER - real moveset TBD
	db 0

MamoswineEvosMoves:
; Evolutions
	db 0
; Learnset - Mamoswine evolves from Piloswine (added in batch 6, see
; PiloswineEvosMoves for the EVOLVE_LEVEL, 44 wiring).
	db 32, METRONOME ; FILLER - real moveset TBD
	db 40, METRONOME ; FILLER - real moveset TBD
	db 48, METRONOME ; FILLER - real moveset TBD
	db 56, METRONOME ; FILLER - real moveset TBD
	db 0

MismagiusEvosMoves:
; Evolutions
	db 0
; Learnset - Mismagius evolves from Misdreavus (part of a later batch); when
; Misdreavus's own entry is added, give it
; `db EVOLVE_ITEM, DUSK_STONE, 1, MISMAGIUS` (DUSK_STONE already exists).
	db 24, METRONOME ; FILLER - real moveset TBD
	db 48, METRONOME ; FILLER - real moveset TBD
	db 0

YanmaEvosMoves:
; Evolutions
	db 0
; Learnset - TACKLE already granted at level 1 (FORESIGHT's slot is
; METRONOME, see base_stats/yanma.asm); DETECT does not exist in Gen 1,
; filled with METRONOME.
	db 7, QUICK_ATTACK
	db 13, DOUBLE_TEAM
	db 19, SONICBOOM
	db 25, METRONOME ; was DETECT
	db 31, SUPERSONIC
	db 37, SWIFT
	db 43, SCREECH
	db 0

WooperEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 20, QUAGSIRE
	db 0
; Learnset - WATER_GUN/TAIL_WHIP already granted at level 1; RAIN_DANCE
; does not exist in Gen 1, filled with METRONOME.
	db 11, SLAM
	db 21, AMNESIA
	db 31, EARTHQUAKE
	db 41, METRONOME ; was RAIN_DANCE
	db 51, MIST
	db 51, HAZE
	db 0

QuagsireEvosMoves:
; Evolutions
	db 0
; Learnset - WATER_GUN/TAIL_WHIP already granted at level 1
	db 11, SLAM
	db 23, AMNESIA
	db 35, EARTHQUAKE
	db 47, METRONOME ; was RAIN_DANCE
	db 59, MIST
	db 59, HAZE
	db 0

MurkrowEvosMoves:
; Evolutions
	db 0
; Learnset - PECK already granted at level 1; PURSUIT/FAINT_ATTACK/
; MEAN_LOOK do not exist in Gen 1, filled with METRONOME.
	db 11, METRONOME ; was PURSUIT
	db 16, HAZE
	db 26, NIGHT_SHADE
	db 31, METRONOME ; was FAINT_ATTACK
	db 41, METRONOME ; was MEAN_LOOK
	db 0

SlowkingEvosMoves:
; Evolutions
	db 0
; Learnset - from tmp/kep/data/pokemon/evos_moves.asm, already Gen 1 valid.
; CONFUSION/DISABLE/HEADBUTT already granted at level 1.
	db 10, BIDE
	db 18, DISABLE
	db 22, HEADBUTT
	db 27, GROWL
	db 33, WATER_GUN
	db 44, AMNESIA
	db 55, PSYCHIC_M
	db 0

MisdreavusEvosMoves:
; Evolutions
	db EVOLVE_ITEM, DUSK_STONE, 1, MISMAGIUS
	db 0
; Learnset - GROWL/PSYWAVE already granted at level 1; SPITE/MEAN_LOOK/
; PAIN_SPLIT/PERISH_SONG do not exist in Gen 1, filled with METRONOME.
	db 6, METRONOME ; was SPITE
	db 12, CONFUSE_RAY
	db 19, METRONOME ; was MEAN_LOOK
	db 27, PSYBEAM
	db 36, METRONOME ; was PAIN_SPLIT
	db 46, METRONOME ; was PERISH_SONG
	db 0

GirafarigEvosMoves:
; Evolutions
	db 0
; Learnset - TACKLE/GROWL/CONFUSION/STOMP already granted at level 1; CRUNCH
; does not exist in Gen 1, filled with METRONOME.
	db 7, CONFUSION
	db 13, STOMP
	db 20, AGILITY
	db 30, METRONOME ; was BATON_PASS
	db 41, PSYBEAM
	db 54, METRONOME ; was CRUNCH
	db 0

PinecoEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 31, FORRETRESS
	db 0
; Learnset - TACKLE already granted at level 1 (PROTECT's slot is METRONOME,
; see base_stats/pineco.asm); RAPID_SPIN/SPIKES do not exist in Gen 1, filled
; with METRONOME.
	db 8, SELFDESTRUCT
	db 15, TAKE_DOWN
	db 22, METRONOME ; was RAPID_SPIN
	db 29, BIDE
	db 36, EXPLOSION
	db 43, METRONOME ; was SPIKES
	db 50, DOUBLE_EDGE
	db 0

ForretressEvosMoves:
; Evolutions
	db 0
; Learnset - TACKLE/SELFDESTRUCT already granted at level 1 (PROTECT's slot is
; METRONOME, see base_stats/forretress.asm)
	db 8, SELFDESTRUCT
	db 15, TAKE_DOWN
	db 22, METRONOME ; was RAPID_SPIN
	db 29, BIDE
	db 39, EXPLOSION
	db 49, METRONOME ; was SPIKES
	db 59, DOUBLE_EDGE
	db 0

DunsparceEvosMoves:
; Evolutions
	db 0
; Learnset - RAGE already granted at level 1; PURSUIT does not exist in
; Gen 1, filled with METRONOME.
	db 5, DEFENSE_CURL
	db 13, GLARE
	db 18, METRONOME ; was SPITE
	db 26, METRONOME ; was PURSUIT
	db 30, SCREECH
	db 38, TAKE_DOWN
	db 0

GligarEvosMoves:
; Evolutions
	db 0
; Learnset - POISON_STING already granted at level 1; FAINT_ATTACK does not
; exist in Gen 1, filled with METRONOME.
	db 6, SAND_ATTACK
	db 13, HARDEN
	db 20, QUICK_ATTACK
	db 28, METRONOME ; was FAINT_ATTACK
	db 36, SLASH
	db 44, SCREECH
	db 52, GUILLOTINE
	db 0

SteelixEvosMoves:
; Evolutions
	db 0
; Learnset - canon Gen 2 levels (tmp/pokegold, since KEP's own Steelix
; learnset uses Gen 4+ moves); TACKLE/SCREECH already granted at level 1;
; SANDSTORM/CRUNCH do not exist in Gen 1, filled with METRONOME.
	db 10, BIND
	db 14, ROCK_THROW
	db 23, HARDEN
	db 27, RAGE
	db 36, METRONOME ; was SANDSTORM
	db 40, SLAM
	db 49, METRONOME ; was CRUNCH
	db 0

SnubbullEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 23, GRANBULL
	db 0
; Learnset - TACKLE already granted at level 1 (SCARY_FACE's slot is
; METRONOME, see base_stats/snubbull.asm); CHARM does not exist in Gen 1,
; filled with METRONOME.
	db 4, TAIL_WHIP
	db 8, METRONOME ; was CHARM
	db 13, BITE
	db 19, LICK
	db 26, METRONOME ; was ROAR
	db 34, RAGE
	db 43, TAKE_DOWN
	db 0

GranbullEvosMoves:
; Evolutions
	db 0
; Learnset - TACKLE/TAIL_WHIP already granted at level 1 (SCARY_FACE's slot
; is METRONOME, see base_stats/granbull.asm)
	db 4, TAIL_WHIP
	db 8, METRONOME ; was CHARM
	db 13, BITE
	db 19, LICK
	db 28, METRONOME ; was ROAR
	db 38, RAGE
	db 51, TAKE_DOWN
	db 0

QwilfishEvosMoves:
; Evolutions
	db 0
; Learnset - TACKLE/POISON_STING already granted at level 1
	db 10, HARDEN
	db 10, MINIMIZE
	db 19, WATER_GUN
	db 28, PIN_MISSILE
	db 37, TAKE_DOWN
	db 46, HYDRO_PUMP
	db 0

ScizorEvosMoves:
; Evolutions
	db 0
; Learnset - from tmp/pokegold/data/pokemon/evos_attacks.asm; QUICK_ATTACK/LEER
; already granted at level 1; PURSUIT/FALSE_SWIPE/METAL_CLAW do not exist in
; Gen 1, filled with METRONOME.
	db 6, FOCUS_ENERGY
	db 12, METRONOME ; was PURSUIT
	db 18, METRONOME ; was FALSE_SWIPE
	db 24, AGILITY
	db 30, METRONOME ; was METAL_CLAW
	db 36, SLASH
	db 42, SWORDS_DANCE
	db 48, DOUBLE_TEAM
	db 0

ShuckleEvosMoves:
; Evolutions
	db 0
; Learnset - CONSTRICT/WITHDRAW already granted at level 1; ENCORE/SAFEGUARD
; do not exist in Gen 1, filled with METRONOME.
	db 9, WRAP
	db 14, METRONOME ; was ENCORE
	db 23, METRONOME ; was SAFEGUARD
	db 28, BIDE
	db 37, REST
	db 0

HeracrossEvosMoves:
; Evolutions
	db 0
; Learnset - TACKLE/LEER already granted at level 1; ENDURE/REVERSAL/MEGAHORN
; do not exist in Gen 1, filled with METRONOME.
	db 6, HORN_ATTACK
	db 12, METRONOME ; was ENDURE
	db 19, FURY_ATTACK
	db 27, COUNTER
	db 35, TAKE_DOWN
	db 44, METRONOME ; was REVERSAL
	db 54, METRONOME ; was MEGAHORN
	db 0

SneaselEvosMoves:
; Evolutions
; Canon Sneasel->Weavile is a level-up-holding-Razor-Claw-at-night evolution;
; this project has no day/night system, so ICE_STONE (already in the project)
; is used as the closest fit - see WeavileEvosMoves's own note.
	db EVOLVE_ITEM, ICE_STONE, 1, WEAVILE
	db 0
; Learnset - SCRATCH/LEER already granted at level 1; FAINT_ATTACK/BEAT_UP do
; not exist in Gen 1, filled with METRONOME.
	db 9, QUICK_ATTACK
	db 17, SCREECH
	db 25, METRONOME ; was FAINT_ATTACK
	db 33, FURY_SWIPES
	db 41, AGILITY
	db 49, SLASH
	db 57, METRONOME ; was BEAT_UP
	db 0

TeddiursaEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 30, URSARING
	db 0
; Learnset - SCRATCH/LEER already granted at level 1; FAINT_ATTACK/SNORE do
; not exist in Gen 1, filled with METRONOME.
	db 8, LICK
	db 15, FURY_SWIPES
	db 22, METRONOME ; was FAINT_ATTACK
	db 29, REST
	db 36, SLASH
	db 43, METRONOME ; was SNORE
	db 50, THRASH
	db 0

UrsaringEvosMoves:
; Evolutions
	db 0
; Learnset - SCRATCH/LEER/LICK/FURY_SWIPES already granted at level 1;
; FAINT_ATTACK/SNORE do not exist in Gen 1, filled with METRONOME.
	db 8, LICK
	db 15, FURY_SWIPES
	db 22, METRONOME ; was FAINT_ATTACK
	db 29, REST
	db 39, SLASH
	db 49, METRONOME ; was SNORE
	db 59, THRASH
	db 0

SlugmaEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 38, MAGCARGO
	db 0
; Learnset - SMOG already granted at level 1.
	db 8, EMBER
	db 15, ROCK_THROW
	db 22, HARDEN
	db 29, AMNESIA
	db 36, FLAMETHROWER
	db 43, ROCK_SLIDE
	db 50, BODY_SLAM
	db 0

MagcargoEvosMoves:
; Evolutions
	db 0
; Learnset - SMOG/EMBER/ROCK_THROW already granted at level 1.
	db 8, EMBER
	db 15, ROCK_THROW
	db 22, HARDEN
	db 29, AMNESIA
	db 36, FLAMETHROWER
	db 48, ROCK_SLIDE
	db 60, BODY_SLAM
	db 0

SwinubEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 33, PILOSWINE
	db 0
; Learnset - TACKLE already granted at level 1; POWDER_SNOW/ENDURE do not
; exist in Gen 1, filled with METRONOME.
	db 10, METRONOME ; was POWDER_SNOW
	db 19, METRONOME ; was ENDURE
	db 28, TAKE_DOWN
	db 37, MIST
	db 46, BLIZZARD
	db 0

PiloswineEvosMoves:
; Evolutions
; Canon Piloswine has no further evolution; Mamoswine is a Gen 4 addition to
; this line kept in the roster (see MamoswineEvosMoves's own note). Mirrors
; KEP's own precedent for Tangela->Tangrowth: a level-up threshold standing
; in for the real "level up knowing Ancient Power" condition, which this
; engine cannot express directly.
	db EVOLVE_LEVEL, 44, MAMOSWINE
	db 0
; Learnset - HORN_ATTACK already granted at level 1; POWDER_SNOW/ENDURE do
; not exist in Gen 1, filled with METRONOME.
	db 10, METRONOME ; was POWDER_SNOW
	db 19, METRONOME ; was ENDURE
	db 28, TAKE_DOWN
	db 33, FURY_ATTACK
	db 42, MIST
	db 56, BLIZZARD
	db 0

CorsolaEvosMoves:
; Evolutions
	db 0
; Learnset - TACKLE already granted at level 1; MIRROR_COAT/ANCIENTPOWER do
; not exist in Gen 1, filled with METRONOME.
	db 7, HARDEN
	db 13, BUBBLE
	db 19, RECOVER
	db 25, BUBBLEBEAM
	db 31, SPIKE_CANNON
	db 37, METRONOME ; was MIRROR_COAT
	db 43, METRONOME ; was ANCIENTPOWER
	db 0

RemoraidEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 25, OCTILLERY
	db 0
; Learnset - WATER_GUN already granted at level 1; LOCK_ON does not exist in
; Gen 1, filled with METRONOME.
	db 11, METRONOME ; was LOCK_ON
	db 22, PSYBEAM
	db 22, AURORA_BEAM
	db 22, BUBBLEBEAM
	db 33, FOCUS_ENERGY
	db 44, ICE_BEAM
	db 55, HYPER_BEAM
	db 0

OctilleryEvosMoves:
; Evolutions
	db 0
; Learnset - WATER_GUN already granted at level 1; OCTAZOOKA does not exist
; in Gen 1, filled with METRONOME.
	db 11, CONSTRICT
	db 22, PSYBEAM
	db 22, AURORA_BEAM
	db 22, BUBBLEBEAM
	db 25, METRONOME ; was OCTAZOOKA
	db 38, FOCUS_ENERGY
	db 54, ICE_BEAM
	db 70, HYPER_BEAM
	db 0

MantineEvosMoves:
; Evolutions
	db 0
; Learnset - TACKLE/BUBBLE already granted at level 1.
	db 10, SUPERSONIC
	db 18, BUBBLEBEAM
	db 25, TAKE_DOWN
	db 32, AGILITY
	db 40, WING_ATTACK
	db 49, CONFUSE_RAY
	db 0

SkarmoryEvosMoves:
; Evolutions
	db 0
; Learnset - LEER/PECK already granted at level 1; STEEL_WING does not exist
; in Gen 1, filled with METRONOME.
	db 13, SAND_ATTACK
	db 19, SWIFT
	db 25, AGILITY
	db 37, FURY_ATTACK
	db 49, METRONOME ; was STEEL_WING
	db 0

HoundourEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 24, HOUNDOOM
	db 0
; Learnset - LEER/EMBER already granted at level 1; FAINT_ATTACK/CRUNCH do
; not exist in Gen 1, filled with METRONOME.
	db 7, WHIRLWIND ; ROAR renamed WHIRLWIND in Gen 1
	db 13, SMOG
	db 20, BITE
	db 27, METRONOME ; was FAINT_ATTACK
	db 35, FLAMETHROWER
	db 43, METRONOME ; was CRUNCH
	db 0

HoundoomEvosMoves:
; Evolutions
	db 0
; Learnset - LEER/EMBER already granted at level 1; FAINT_ATTACK/CRUNCH do
; not exist in Gen 1, filled with METRONOME.
	db 7, WHIRLWIND ; ROAR renamed WHIRLWIND in Gen 1
	db 13, SMOG
	db 20, BITE
	db 30, METRONOME ; was FAINT_ATTACK
	db 41, FLAMETHROWER
	db 52, METRONOME ; was CRUNCH
	db 0

KingdraEvosMoves:
; Evolutions
	db 0
; Learnset - from tmp/kep/data/pokemon/evos_moves.asm, already Gen 1 valid;
; BUBBLE/SMOKESCREEN/LEER already granted at level 1.
	db 19, SMOKESCREEN
	db 24, LEER
	db 30, WATER_GUN
	db 32, PIN_MISSILE
	db 36, QUICK_ATTACK
	db 41, AGILITY
	db 52, HYDRO_PUMP
	db 0

PhanpyEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 25, DONPHAN
	db 0
; Learnset - TACKLE/GROWL already granted at level 1; FLAIL/ENDURE do not
; exist in Gen 1, filled with METRONOME.
	db 9, DEFENSE_CURL
	db 17, METRONOME ; was FLAIL
	db 25, TAKE_DOWN
	db 33, METRONOME ; was ROLLOUT
	db 41, METRONOME ; was ENDURE
	db 49, DOUBLE_EDGE
	db 0

DonphanEvosMoves:
; Evolutions
	db 0
; Learnset - HORN_ATTACK/GROWL already granted at level 1; FLAIL/ROLLOUT do
; not exist in Gen 1, filled with METRONOME; RAPID_SPIN likewise.
	db 9, DEFENSE_CURL
	db 17, METRONOME ; was FLAIL
	db 25, FURY_ATTACK
	db 33, METRONOME ; was ROLLOUT
	db 41, METRONOME ; was RAPID_SPIN
	db 49, EARTHQUAKE
	db 0

Porygon2EvosMoves:
; Evolutions
; Species Groups Phase 2: canon Porygon2->Porygon-Z is a trade-holding-
; Dubious-Disc evolution; this project has no held-item trade mechanic, so
; - per the project's own trade-evolution convention (EVOLVE_TRADE at
; level 40, same as Porygon->Porygon2) - a plain trade threshold is used
; instead.
	db EVOLVE_TRADE, 40, PORYGON_Z
	db 0
; Learnset - from tmp/kep/data/pokemon/evos_moves.asm, already Gen 1 valid;
; TACKLE/SHARPEN/CONVERSION already granted at level 1.
	db 23, PSYBEAM
	db 28, RECOVER
	db 35, AGILITY
	db 42, TRI_ATTACK
	db 45, DEFENSE_CURL
	db 0

StantlerEvosMoves:
; Evolutions
	db 0
; Learnset - TACKLE already granted at level 1.
	db 8, LEER
	db 15, HYPNOSIS
	db 23, STOMP
	db 31, SAND_ATTACK
	db 40, TAKE_DOWN
	db 49, CONFUSE_RAY
	db 0

HitmontopEvosMoves:
; Evolutions
	db 0
; Learnset - from tmp/kep/data/pokemon/evos_moves.asm, already Gen 1 valid;
; ROLLING_KICK/FOCUS_ENERGY already granted at level 1.
	db 33, QUICK_ATTACK
	db 38, COUNTER
	db 43, AGILITY
	db 48, JUMP_KICK
	db 53, DOUBLE_KICK
	db 0

MiltankEvosMoves:
; Evolutions
	db 0
; Learnset - TACKLE already granted at level 1; MILK_DRINK/HEAL_BELL do not
; exist in Gen 1, filled with METRONOME.
	db 4, GROWL
	db 8, DEFENSE_CURL
	db 13, STOMP
	db 19, METRONOME ; was MILK_DRINK
	db 26, BIDE
	db 34, METRONOME ; was ROLLOUT
	db 43, BODY_SLAM
	db 53, METRONOME ; was HEAL_BELL
	db 0

BlisseyEvosMoves:
; Evolutions
	db 0
; Learnset - from tmp/kep/data/pokemon/evos_moves.asm, already Gen 1 valid;
; POUND/TAIL_WHIP already granted at level 1.
	db 12, DOUBLESLAP
	db 24, SING
	db 30, GROWL
	db 38, MINIMIZE
	db 44, DEFENSE_CURL
	db 48, LIGHT_SCREEN
	db 54, DOUBLE_EDGE
	db 0

RaikouEvosMoves:
; Evolutions
	db 0
; Learnset - BITE/LEER already granted at level 1; ROAR renamed WHIRLWIND
; in Gen 1; CRUNCH does not exist in Gen 1, filled with METRONOME.
	db 11, THUNDERSHOCK
	db 21, WHIRLWIND ; was ROAR
	db 31, QUICK_ATTACK
	db 41, METRONOME ; was SPARK
	db 51, REFLECT
	db 61, METRONOME ; was CRUNCH
	db 71, THUNDER
	db 0

EnteiEvosMoves:
; Evolutions
	db 0
; Learnset - BITE/LEER already granted at level 1; ROAR renamed WHIRLWIND
; in Gen 1; SWAGGER does not exist in Gen 1, filled with METRONOME.
	db 11, EMBER
	db 21, WHIRLWIND ; was ROAR
	db 31, FIRE_SPIN
	db 41, STOMP
	db 51, FLAMETHROWER
	db 61, METRONOME ; was SWAGGER
	db 71, FIRE_BLAST
	db 0

SuicuneEvosMoves:
; Evolutions
	db 0
; Learnset - BITE/LEER already granted at level 1; ROAR renamed WHIRLWIND
; in Gen 1; MIRROR_COAT does not exist in Gen 1, filled with METRONOME.
	db 11, WATER_GUN
	db 21, WHIRLWIND ; was ROAR
	db 31, GUST
	db 41, BUBBLEBEAM
	db 51, MIST
	db 61, METRONOME ; was MIRROR_COAT
	db 71, HYDRO_PUMP
	db 0

LarvitarEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 30, PUPITAR
	db 0
; Learnset - BITE/LEER already granted at level 1; SANDSTORM/SCARY_FACE/
; CRUNCH do not exist in Gen 1, filled with METRONOME.
	db 8, METRONOME ; was SANDSTORM
	db 15, SCREECH
	db 22, ROCK_SLIDE
	db 29, THRASH
	db 36, METRONOME ; was SCARY_FACE
	db 43, METRONOME ; was CRUNCH
	db 50, EARTHQUAKE
	db 57, HYPER_BEAM
	db 0

PupitarEvosMoves:
; Evolutions
	db EVOLVE_LEVEL, 55, TYRANITAR
	db 0
; Learnset - BITE/LEER/SCREECH already granted at level 1; SANDSTORM/
; SCARY_FACE/CRUNCH do not exist in Gen 1, filled with METRONOME.
	db 8, METRONOME ; was SANDSTORM
	db 15, SCREECH
	db 22, ROCK_SLIDE
	db 29, THRASH
	db 38, METRONOME ; was SCARY_FACE
	db 47, METRONOME ; was CRUNCH
	db 56, EARTHQUAKE
	db 65, HYPER_BEAM
	db 0

TyranitarEvosMoves:
; Evolutions
	db 0
; Learnset - BITE/LEER/SCREECH already granted at level 1; SANDSTORM/
; SCARY_FACE/CRUNCH do not exist in Gen 1, filled with METRONOME.
	db 8, METRONOME ; was SANDSTORM
	db 15, SCREECH
	db 22, ROCK_SLIDE
	db 29, THRASH
	db 38, METRONOME ; was SCARY_FACE
	db 47, METRONOME ; was CRUNCH
	db 61, EARTHQUAKE
	db 75, HYPER_BEAM
	db 0

LugiaEvosMoves:
; Evolutions
	db 0
; Learnset - GUST already granted at level 1; AEROBLAST/SAFEGUARD/
; RAIN_DANCE/WHIRLWIND(dup)/ANCIENTPOWER/FUTURE_SIGHT do not exist in
; Gen 1 (WHIRLWIND is a real Gen 1 move but is already used elsewhere in
; this list's spirit), filled with METRONOME.
	db 11, METRONOME ; was SAFEGUARD
	db 22, GUST
	db 33, RECOVER
	db 44, HYDRO_PUMP
	db 55, METRONOME ; was RAIN_DANCE
	db 66, SWIFT
	db 77, WHIRLWIND
	db 88, METRONOME ; was ANCIENTPOWER
	db 99, METRONOME ; was FUTURE_SIGHT
	db 0

HoOhEvosMoves:
; Evolutions
	db 0
; Learnset - EMBER already granted at level 1; SACRED_FIRE/SAFEGUARD/
; SUNNY_DAY/ANCIENTPOWER/FUTURE_SIGHT do not exist in Gen 1, filled with
; METRONOME.
	db 11, METRONOME ; was SAFEGUARD
	db 22, GUST
	db 33, RECOVER
	db 44, FIRE_BLAST
	db 55, METRONOME ; was SUNNY_DAY
	db 66, SWIFT
	db 77, WHIRLWIND
	db 88, METRONOME ; was ANCIENTPOWER
	db 99, METRONOME ; was FUTURE_SIGHT
	db 0

CelebiEvosMoves:
; Evolutions
	db 0
; Learnset - LEECH_SEED/CONFUSION/RECOVER already granted at level 1;
; HEAL_BELL/SAFEGUARD/ANCIENTPOWER/FUTURE_SIGHT/BATON_PASS/PERISH_SONG do
; not exist in Gen 1, filled with METRONOME.
	db 10, METRONOME ; was SAFEGUARD
	db 20, METRONOME ; was ANCIENTPOWER
	db 30, METRONOME ; was FUTURE_SIGHT
	db 40, METRONOME ; was BATON_PASS
	db 50, METRONOME ; was PERISH_SONG
	db 0

AnnihilapeEvosMoves:
; Evolutions
	db 0
; Learnset - from tmp/kep/data/pokemon/evos_moves.asm, already Gen 1 valid;
; SCRATCH/LEER/KARATE_CHOP already granted at level 1.
	db 9, LOW_KICK
	db 15, KARATE_CHOP
	db 21, FURY_SWIPES
	db 27, FOCUS_ENERGY
	db 28, RAGE
	db 37, SEISMIC_TOSS
	db 45, SCREECH
	db 0

LickilickyEvosMoves:
; Evolutions
	db 0
; Learnset - from tmp/kep/data/pokemon/evos_moves.asm, already Gen 1 valid;
; WRAP/SUPERSONIC/STOMP already granted at level 1.
	db 7, STOMP
	db 15, DISABLE
	db 23, DEFENSE_CURL
	db 31, SLAM
	db 39, SCREECH
	db 0

SirfetchdEvosMoves:
; Evolutions
	db 0
; Learnset - PECK/SAND_ATTACK already granted at level 1; BRUTAL_SWING
; does not exist in Gen 1, filled with METRONOME.
	db 13, LEER
	db 17, DOUBLE_KICK
	db 21, METRONOME ; was BRUTAL_SWING
	db 25, SWORDS_DANCE
	db 29, LOW_KICK
	db 33, JUMP_KICK
	db 41, ROLLING_KICK
	db 0

MagnezoneEvosMoves:
; Evolutions
	db 0
; Learnset - TACKLE/THUNDERSHOCK/SONICBOOM already granted at level 1;
; METAL_SOUND/MAGNET_BOMB/IRON_HEAD do not exist in Gen 1, filled with
; METRONOME.
	db 31, METRONOME ; was METAL_SOUND
	db 41, METRONOME ; was MAGNET_BOMB
	db 50, METRONOME ; was IRON_HEAD
	db 0

TangrowthEvosMoves:
; Evolutions
	db 0
; Learnset - from tmp/kep/data/pokemon/evos_moves.asm, already Gen 1 valid;
; CONSTRICT/BIND/ABSORB already granted at level 1.
	db 13, BIND
	db 19, ABSORB
	db 24, VINE_WHIP
	db 28, POISONPOWDER
	db 31, STUN_SPORE
	db 34, SLEEP_POWDER
	db 40, SLAM
	db 0

RhyperiorEvosMoves:
; Evolutions
	db 0
; Learnset - from tmp/kep/data/pokemon/evos_moves.asm, already Gen 1 valid;
; HORN_ATTACK/STOMP/TAIL_WHIP/FURY_ATTACK already granted at level 1.
	db 20, STOMP
	db 25, TAIL_WHIP
	db 30, FURY_ATTACK
	db 35, ROCK_SLIDE
	db 40, HORN_DRILL
	db 48, LEER
	db 55, EARTHQUAKE
	db 0

KleavorEvosMoves:
; Evolutions
	db 0
; Learnset - from tmp/kep/data/pokemon/evos_moves.asm, already Gen 1 valid;
; QUICK_ATTACK/ROCK_THROW already granted at level 1.
	db 17, LEER
	db 20, FOCUS_ENERGY
	db 24, DOUBLE_TEAM
	db 29, SLASH
	db 35, SWORDS_DANCE
	db 42, AGILITY
	db 50, ROCK_SLIDE
	db 0

MrRimeEvosMoves:
; Evolutions
	db 0
; Learnset - CONFUSION/BARRIER/REFLECT already granted at level 1;
; FEINT_ATTACK does not exist in Gen 1, filled with METRONOME.
	db 23, LIGHT_SCREEN
	db 28, PSYBEAM
	db 31, AURORA_BEAM
	db 39, ICE_BEAM
	db 44, PSYCHIC_M
	db 50, METRONOME ; was FEINT_ATTACK
	db 0

ElectivireEvosMoves:
; Evolutions
	db 0
; Learnset - from tmp/kep/data/pokemon/evos_moves.asm, already Gen 1 valid;
; QUICK_ATTACK/LEER already granted at level 1.
	db 34, THUNDERSHOCK
	db 37, SCREECH
	db 42, THUNDERPUNCH
	db 49, LIGHT_SCREEN
	db 54, THUNDER
	db 58, LOW_KICK
	db 0

MagmortarEvosMoves:
; Evolutions
	db 0
; Learnset - from tmp/kep/data/pokemon/evos_moves.asm, already Gen 1 valid;
; EMBER already granted at level 1.
	db 36, LEER
	db 39, CONFUSE_RAY
	db 43, FIRE_PUNCH
	db 48, SMOKESCREEN
	db 52, SMOG
	db 55, FLAMETHROWER
	db 0

PorygonZEvosMoves:
; Evolutions
	db 0
; Learnset - TACKLE/SHARPEN/CONVERSION already granted at level 1;
; NASTY_PLOT does not exist in Gen 1, filled with METRONOME.
	db 50, METRONOME ; was NASTY_PLOT
	db 0
