; assigned class for each pokemon and odds


DEF pokeball_odds EQU $7F
DEF greatball_odds EQU $66 + $7F
DEF ultraball_odds EQU $1A + $66 + $7F
DEF masterball_odds EQU $A ; if prerequisites met

DEF pokeball_pokemon_line_number EQU 28
DEF pokeball_pokemon_number EQU 28 + 26 + 6
DEF pokeball_pokemon_line_amount EQU 28 - 1
DEF greatball_pokemon_line_number EQU pokeball_pokemon_line_number + 28
DEF greatball_pokemon_number EQU pokeball_pokemon_number + 28 + 25 + 8
DEF greatball_pokemon_line_amount EQU 28
DEF ultraball_pokemon_line_number EQU greatball_pokemon_line_number+ 16
DEF ultraball_pokemon_number EQU greatball_pokemon_number + 16 + 3 + 2
DEF ultraball_pokemon_line_amount EQU 16 - 1
DEF masterball_pokemon_line_number EQU ultraball_pokemon_line_number + 5
DEF masterball_pokemon_number EQU ultraball_pokemon_number + 5 + 2
DEF masterball_pokemon_line_amount EQU 5 - 1

pokemon_classes::
table_width 1
pokeball_class:
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

; evolved forms, STAGE 2
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

greatball_class:
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

; evolved forms


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

ultraball_class:

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

; evolutions, stage 2

db HAUNTER

db KADABRA

db RHYDON

; stage 3


db GENGAR

db ALAKAZAM

masterball_class:

db TAUROS

db SNORLAX

db EXEGGCUTE

db STARYU

db ZAPDOS

; evolutions, stage 2

db EXEGGUTOR

db STARMIE

uber_class:

db MEW

db MEWTWO
