; assigned class for each pokemon and odds

pokemon_class_odds:
DEF pokeball_odds EQU $7F
DEF greatball_odds EQU $66 + $7F
DEF ultraball_odds EQU $1A + $66 + $7F
DEF masterball_odds EQU $A ; if prerequisites met

pokemon_classes:
table_width 1
pokeball_class:
db CATERPIE
db 0x0
db WEEDLE
db 0x0
db PIDGEY
db 0x0
db RATTATA
db 0x0
db FARFETCHD
db 0x0
db EKANS
db 0x0
db DITTO
db 0x0
db MANKEY
db 0x0
db KRABBY
db 0x0
db CUBONE
db 0x0
db GRIMER
db 0x0
db KRABBY
db 0x0
db GROWLITHE
db 0x0
db SEEL
db 0x0
db VOLTORB
db 0x0
db SPEAROW
db 0x0
db KABUTO
db 0x0
db MAGNEMITE
db 0x0
db POLIWAG
db 0x0
db ODDISH
db 0x0
db ZUBAT
db 0x0
db JIGGLYPUFF
db 0x0
db SANDSHREW
db 0x0
db PARAS
db 0x0
db PSYDUCK
db 0x0
db BELLSPROUT
db 0x0
db GRIMER
db 0x0
db KOFFING
db 0x0
db HORSEA
db 0x0
db GOLDEEN
db 0x0

greatball_class:
db BULBASAUR
db 0x0
db CHARMANDER
db 0x0
db SQUIRTLE
db 0x0
db EEVEE
db 0x0
db DODUO
db 0x0
db DRATINI
db 0x0
db OMANYTE
db 0x0
db MACHOP
db 0x0
db SHELLDER
db 0x0
db GEODUDE
db 0x0
db LICKITUNG
db 0x0
db NIDORAN_F
db 0x0
db CLEFAIRY
db 0x0
db DIGLETT 
db 0x0
db MAGIKARP
db 0x0
db PIKACHU
db 0x0
db SLOWPOKE
db 0x0
db DROWZEE
db 0x0
db PONYTA
db 0x0
db MEOWTH
db 0x0
db VULPIX
db 0x0
db TANGELA
db 0x0
db VENONAT
db 0x0
db NIDORAN_M
db 0x0
db HITMONCHAN
db 0x0
db TENTACOOL
db 0x0
db ONIX
db 0x0
db PORYGON
db 0x0

ultraball_class:
db GASTLY
db 0x0
db ABRA
db 0x0
db JYNX
db 0x0
db ARTICUNO
db 0x0
db MOLTRES
db 0x0
db CHANSEY
db 0x0
db RHYHORN
db 0x0
db LAPRAS
db 0x0
db KANGASKHAN
db 0x0
db SCYTHER
db 0x0
db HITMONLEE
db 0x0
db MR_MIME
db 0x0
db ELECTABUZZ
db 0x0
db MAGMAR
db 0x0
db PINSIR
db 0x0
db AERODACTYL
db 0x0

masterball_class:
db TAUROS
db 0x0
db SNORLAX
db 0x0
db EXEGGCUTE
db 0x0
db EXEGGUTOR
db 0x0
db STARYU
db 0x0
db STARMIE
db 0x0
db ZAPDOS
db 0x0

uber_class:
db MEW
db 0x0
db MEWTWO
db 0x0