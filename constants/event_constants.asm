; wEventFlags bit flags
;
; ==========================================================================
; GENERATED FILE - DO NOT EDIT BY HAND.
;   regenerate:  python3 tools/gen_event_constants.py
;   verify only: python3 tools/gen_event_constants.py --check
;
; Three zones, each with explicit bounds:
;
;   ZONE 0  PERSISTENT_EVENTS_START .. _END
;           Survives a blackout AND the Hall of Fame. Intro/story state
;           plus the ELEMENT PRISM one-time-ever messages, whose whole
;           mechanism is never being cleared.
;
;   ZONE 1  RUN_EVENTS_START .. _END
;           Everything scoped to one roguelike run. Cleared wholesale by
;           RogueResetRunState on blackout and at the Hall of Fame - one
;           ResetEventRange, not a scatter of per-map ResetEvent calls.
;           Byte-aligned at both ends so that range emits plain
;           `ld [hli], a` stores and can never clip a neighbouring zone.
;
;   ZONE 2  EVENT_GRAVEYARD_BASE ..
;           Maps that no warp or connection can reach. Their scripts and
;           object data are still assembled, so the names must exist -
;           but they are ALIASES onto a shared 2-byte scratch band, and
;           dead maps deliberately overlap each other.
;
;           !!! If a map here is ever made reachable again, its events
;           !!! collide with another dead map - silently, with no build
;           !!! error. Give it fresh constants first. Reachability is
;           !!! re-derived on every run of the generator, and --check
;           !!! fails if the map graph has changed underneath this file.
;
; Reachability comes from the warp graph in data/maps/objects, the
; connection graph in data/maps/headers, and the code-driven destination
; tables named in TABLE 5 of the generator (rogue stages, gyms, bridge
; rooms, wild areas). 74 maps are reachable.
; ==========================================================================

DEF NUM_EVENTS EQU 512

; ==========================================================================
; ZONE 0 - PERSISTENT (never cleared)
; ==========================================================================
DEF PERSISTENT_EVENTS_START EQU 0
DEF EVENT_FIRST_RUN                              EQU    0 ; byte 0 bit 0
DEF EVENT_PALLET_AFTER_FIRST_RUN                 EQU    1 ; byte 0 bit 1
DEF EVENT_DAISY_WALKING                          EQU    2 ; byte 0 bit 2
DEF EVENT_ENTERED_BLUES_HOUSE                    EQU    3 ; byte 0 bit 3
DEF EVENT_GOT_TOWN_MAP                           EQU    4 ; byte 0 bit 4
DEF EVENT_GOT_POKEDEX                            EQU    5 ; byte 0 bit 5
DEF EVENT_ESTABLISHED_STARTER                    EQU    6 ; byte 0 bit 6
DEF EVENT_GOT_STARTER                            EQU    7 ; byte 0 bit 7
DEF EVENT_BATTLED_RIVAL_IN_OAKS_LAB              EQU    8 ; byte 1 bit 0
DEF EVENT_INTRO_TOUR_COMPLETE                    EQU    9 ; byte 1 bit 1
DEF EVENT_GAMMA_SHADER                           EQU   10 ; byte 1 bit 2
DEF EVENT_HALL_OF_FAME_DEX_RATING                EQU   11 ; byte 1 bit 3
DEF EVENT_PRISM_GYM1_SHOWN                       EQU   12 ; byte 1 bit 4
DEF EVENT_PRISM_GYM2_SHOWN                       EQU   13 ; byte 1 bit 5
DEF EVENT_PRISM_GYM3_SHOWN                       EQU   14 ; byte 1 bit 6
DEF EVENT_PRISM_GYM4_SHOWN                       EQU   15 ; byte 1 bit 7
DEF EVENT_PRISM_GYM5_SHOWN                       EQU   16 ; byte 2 bit 0
DEF EVENT_PRISM_GYM6_SHOWN                       EQU   17 ; byte 2 bit 1
DEF EVENT_PRISM_GYM7_SHOWN                       EQU   18 ; byte 2 bit 2
DEF EVENT_PRISM_GYM8_SHOWN                       EQU   19 ; byte 2 bit 3
DEF EVENT_PRISM_E4_ICE_SHOWN                     EQU   20 ; byte 2 bit 4
DEF EVENT_PRISM_E4_FIGHTING_SHOWN                EQU   21 ; byte 2 bit 5
DEF EVENT_PRISM_E4_GHOST_SHOWN                   EQU   22 ; byte 2 bit 6
DEF EVENT_PRISM_E4_DRAGON_SHOWN                  EQU   23 ; byte 2 bit 7
DEF EVENT_PRISM_CHAMPION_SHOWN                   EQU   24 ; byte 3 bit 0
DEF PERSISTENT_EVENTS_END   EQU 24

; ==========================================================================
; ZONE 1 - RUN-SCOPED (cleared by RogueResetRunState)
; ==========================================================================
DEF RUN_EVENTS_START EQU 32

; -- (engine / cross-map)
DEF EVENT_1ST_LOCK_OPENED                        EQU   32 ; byte 4 bit 0

; -- AgathasRoom  [def_trainers 1, 1 trainers]
DEF EVENT_BEAT_AGATHAS_ROOM_TRAINER_0            EQU   33 ; byte 4 bit 1

; -- CinnabarGym
DEF EVENT_2A7                                    EQU   34 ; byte 4 bit 2

; -- (engine / cross-map)
DEF EVENT_2ND_LOCK_OPENED                        EQU   35 ; byte 4 bit 3

; -- Route22
DEF EVENT_2ND_ROUTE22_RIVAL_BATTLE               EQU   36 ; byte 4 bit 4

; -- AgathasRoom  [def_trainers 1, 1 trainers]
DEF EVENT_AUTOWALKED_INTO_AGATHAS_ROOM           EQU   37 ; byte 4 bit 5

; -- BrunosRoom  [def_trainers 1, 1 trainers]
DEF EVENT_AUTOWALKED_INTO_BRUNOS_ROOM            EQU   38 ; byte 4 bit 6

; -- DiglettsCave  [def_trainers 1, 5 trainers]
DEF EVENT_AUTOWALKED_INTO_DIGLETTS_CAVE          EQU   39 ; byte 4 bit 7

; -- LoreleisRoom  [def_trainers 1, 1 trainers]
DEF EVENT_AUTOWALKED_INTO_LORELEIS_ROOM          EQU   40 ; byte 5 bit 0

; -- BrunosRoom  [def_trainers 1, 1 trainers]
DEF EVENT_BEAT_BRUNOS_ROOM_TRAINER_0             EQU   41 ; byte 5 bit 1

; -- MtMoon1F  [def_trainers 1, 5 trainers]
DEF EVENT_AUTOWALKED_INTO_MT_MOON_1F             EQU   42 ; byte 5 bit 2

; -- PokemonMansion1F  [def_trainers 1, 5 trainers]
DEF EVENT_AUTOWALKED_INTO_POKEMON_MANSION_1F     EQU   43 ; byte 5 bit 3

; -- PokemonTower2F  [def_trainers 1, 5 trainers]
DEF EVENT_AUTOWALKED_INTO_POKEMON_TOWER_2F       EQU   44 ; byte 5 bit 4

; -- PokemonTower7F  [def_trainers 1, 5 trainers]
DEF EVENT_AUTOWALKED_INTO_POKEMON_TOWER_7F       EQU   45 ; byte 5 bit 5

; -- PowerPlant  [def_trainers 1, 5 trainers]
DEF EVENT_AUTOWALKED_INTO_POWER_PLANT            EQU   46 ; byte 5 bit 6

; -- RocketHideoutB1F  [def_trainers 1, 5 trainers]
DEF EVENT_AUTOWALKED_INTO_ROCKET_HIDEOUT_B1F     EQU   47 ; byte 5 bit 7

; -- RockTunnel1F  [def_trainers 1, 5 trainers]
DEF EVENT_AUTOWALKED_INTO_ROCK_TUNNEL_1F         EQU   48 ; byte 6 bit 0

; -- Route1  [def_trainers 1, 5 trainers]
DEF EVENT_AUTOWALKED_INTO_ROUTE_1                EQU   49 ; byte 6 bit 1

; -- CeladonGym  [def_trainers 2, 4 trainers]
DEF EVENT_BEAT_CELADON_GYM_TRAINER_0             EQU   50 ; byte 6 bit 2
DEF EVENT_BEAT_CELADON_GYM_TRAINER_1             EQU   51 ; byte 6 bit 3
DEF EVENT_BEAT_CELADON_GYM_TRAINER_2             EQU   52 ; byte 6 bit 4
DEF EVENT_BEAT_CELADON_GYM_TRAINER_3             EQU   53 ; byte 6 bit 5

; -- Route12  [def_trainers 1, 5 trainers]
DEF EVENT_AUTOWALKED_INTO_ROUTE_12               EQU   54 ; byte 6 bit 6

; -- Route13  [def_trainers 1, 5 trainers]
DEF EVENT_AUTOWALKED_INTO_ROUTE_13               EQU   55 ; byte 6 bit 7

; -- Route15  [def_trainers 1, 5 trainers]
DEF EVENT_AUTOWALKED_INTO_ROUTE_15               EQU   56 ; byte 7 bit 0

; -- Route17  [def_trainers 1, 5 trainers]
DEF EVENT_AUTOWALKED_INTO_ROUTE_17               EQU   57 ; byte 7 bit 1

; -- CeruleanGym  [def_trainers 2, 4 trainers]
DEF EVENT_BEAT_CERULEAN_GYM_TRAINER_0            EQU   58 ; byte 7 bit 2
DEF EVENT_BEAT_CERULEAN_GYM_TRAINER_1            EQU   59 ; byte 7 bit 3
DEF EVENT_BEAT_CERULEAN_GYM_TRAINER_2            EQU   60 ; byte 7 bit 4
DEF EVENT_BEAT_CERULEAN_GYM_TRAINER_3            EQU   61 ; byte 7 bit 5

; -- Route24  [def_trainers 1, 5 trainers]
DEF EVENT_AUTOWALKED_INTO_ROUTE_24               EQU   62 ; byte 7 bit 6

; -- Route25  [def_trainers 1, 5 trainers]
DEF EVENT_AUTOWALKED_INTO_ROUTE_25               EQU   63 ; byte 7 bit 7

; -- CinnabarGym
DEF EVENT_BEAT_CINNABAR_GYM_TRAINER_0            EQU   64 ; byte 8 bit 0
DEF EVENT_BEAT_CINNABAR_GYM_TRAINER_1            EQU   65 ; byte 8 bit 1
DEF EVENT_BEAT_CINNABAR_GYM_TRAINER_2            EQU   66 ; byte 8 bit 2
DEF EVENT_BEAT_CINNABAR_GYM_TRAINER_3            EQU   67 ; byte 8 bit 3
DEF EVENT_BEAT_CINNABAR_GYM_TRAINER_4            EQU   68 ; byte 8 bit 4
DEF EVENT_BEAT_CINNABAR_GYM_TRAINER_5            EQU   69 ; byte 8 bit 5
DEF EVENT_BEAT_CINNABAR_GYM_TRAINER_6            EQU   70 ; byte 8 bit 6
DEF EVENT_CINNABAR_GYM_GATE0_UNLOCKED            EQU   71 ; byte 8 bit 7
DEF EVENT_CINNABAR_GYM_GATE1_UNLOCKED            EQU   72 ; byte 9 bit 0
DEF EVENT_CINNABAR_GYM_GATE2_UNLOCKED            EQU   73 ; byte 9 bit 1
DEF EVENT_CINNABAR_GYM_GATE3_UNLOCKED            EQU   74 ; byte 9 bit 2
DEF EVENT_CINNABAR_GYM_GATE4_UNLOCKED            EQU   75 ; byte 9 bit 3

; -- Route3  [def_trainers 1, 5 trainers]
DEF EVENT_AUTOWALKED_INTO_ROUTE_3                EQU   76 ; byte 9 bit 4

; -- Route5  [def_trainers 1, 5 trainers]
DEF EVENT_AUTOWALKED_INTO_ROUTE_5                EQU   77 ; byte 9 bit 5

; -- Route6  [def_trainers 1, 5 trainers]
DEF EVENT_AUTOWALKED_INTO_ROUTE_6                EQU   78 ; byte 9 bit 6

; -- Route9  [def_trainers 1, 5 trainers]
DEF EVENT_AUTOWALKED_INTO_ROUTE_9                EQU   79 ; byte 9 bit 7

; -- SeafoamIslands1F  [def_trainers 1, 5 trainers]
DEF EVENT_AUTOWALKED_INTO_SEAFOAM_ISLANDS_1F     EQU   80 ; byte 10 bit 0

; -- DiglettsCave  [def_trainers 1, 5 trainers]
DEF EVENT_BEAT_DIGLETTS_CAVE_TRAINER_0           EQU   81 ; byte 10 bit 1
DEF EVENT_BEAT_DIGLETTS_CAVE_TRAINER_1           EQU   82 ; byte 10 bit 2
DEF EVENT_BEAT_DIGLETTS_CAVE_TRAINER_2           EQU   83 ; byte 10 bit 3
DEF EVENT_BEAT_DIGLETTS_CAVE_TRAINER_3           EQU   84 ; byte 10 bit 4
DEF EVENT_BEAT_DIGLETTS_CAVE_TRAINER_4           EQU   85 ; byte 10 bit 5

; -- SSAnneB1F
DEF EVENT_AUTOWALKED_INTO_SS_ANNE_B1F            EQU   86 ; byte 10 bit 6

; -- SSAnneBow  [def_trainers 1, 5 trainers]
DEF EVENT_AUTOWALKED_INTO_SS_ANNE_BOW            EQU   87 ; byte 10 bit 7

; -- UndergroundPathWestEast  [def_trainers 1, 5 trainers]
DEF EVENT_AUTOWALKED_INTO_UNDERGROUND_PATH_WEST_EAST EQU   88 ; byte 11 bit 0

; -- ViridianForest  [def_trainers 1, 5 trainers]
DEF EVENT_AUTOWALKED_INTO_VIRIDIAN_FOREST        EQU   89 ; byte 11 bit 1

; -- FuchsiaGym  [def_trainers 2, 4 trainers]
DEF EVENT_BEAT_FUCHSIA_GYM_TRAINER_0             EQU   90 ; byte 11 bit 2
DEF EVENT_BEAT_FUCHSIA_GYM_TRAINER_1             EQU   91 ; byte 11 bit 3
DEF EVENT_BEAT_FUCHSIA_GYM_TRAINER_2             EQU   92 ; byte 11 bit 4
DEF EVENT_BEAT_FUCHSIA_GYM_TRAINER_3             EQU   93 ; byte 11 bit 5
DEF EVENT_BEAT_FUCHSIA_GYM_TRAINER_4             EQU   94 ; byte 11 bit 6
DEF EVENT_BEAT_FUCHSIA_GYM_TRAINER_5             EQU   95 ; byte 11 bit 7

; -- CinnabarGym
DEF EVENT_BEAT_BLAINE                            EQU   96 ; byte 12 bit 0

; -- GameCorner  [def_trainers 1, 5 trainers]
DEF EVENT_BEAT_GAME_CORNER_TRAINER_0             EQU   97 ; byte 12 bit 1
DEF EVENT_BEAT_GAME_CORNER_TRAINER_1             EQU   98 ; byte 12 bit 2
DEF EVENT_BEAT_GAME_CORNER_TRAINER_2             EQU   99 ; byte 12 bit 3
DEF EVENT_BEAT_GAME_CORNER_TRAINER_3             EQU  100 ; byte 12 bit 4
DEF EVENT_BEAT_GAME_CORNER_TRAINER_4             EQU  101 ; byte 12 bit 5

; -- PewterCity
DEF EVENT_BEAT_BROCK                             EQU  102 ; byte 12 bit 6

; -- ChampionsRoom
DEF EVENT_BEAT_CHAMPION_RIVAL                    EQU  103 ; byte 12 bit 7

; -- CeladonGym  [def_trainers 2, 4 trainers]
DEF EVENT_BEAT_ERIKA                             EQU  104 ; byte 13 bit 0

; -- LancesRoom  [def_trainers 1, 1 trainers]
DEF EVENT_BEAT_LANCES_ROOM_TRAINER_0             EQU  105 ; byte 13 bit 1

; -- FuchsiaGym  [def_trainers 2, 4 trainers]
DEF EVENT_BEAT_KOGA                              EQU  106 ; byte 13 bit 2

; -- LancesRoom  [def_trainers 1, 1 trainers]
DEF EVENT_BEAT_LANCE                             EQU  107 ; byte 13 bit 3

; -- VermilionGym  [def_trainers 2, 4 trainers]
DEF EVENT_BEAT_LT_SURGE                          EQU  108 ; byte 13 bit 4

; -- CeruleanGym  [def_trainers 2, 4 trainers]
DEF EVENT_BEAT_MISTY                             EQU  109 ; byte 13 bit 5

; -- Route11Gate2F
DEF EVENT_BEAT_ROUTE12_SNORLAX                   EQU  110 ; byte 13 bit 6

; -- Route16  [def_trainers 1, 6 trainers]
DEF EVENT_BEAT_ROUTE16_SNORLAX                   EQU  111 ; byte 13 bit 7

; -- Route24  [def_trainers 1, 5 trainers]
DEF EVENT_BEAT_ROUTE24_ROCKET                    EQU  112 ; byte 14 bit 0

; -- LoreleisRoom  [def_trainers 1, 1 trainers]
DEF EVENT_BEAT_LORELEIS_ROOM_TRAINER_0           EQU  113 ; byte 14 bit 1

; -- SaffronGym  [def_trainers 2, 4 trainers]
DEF EVENT_BEAT_SABRINA                           EQU  114 ; byte 14 bit 2

; -- (engine / cross-map)
DEF EVENT_BEAT_SILPH_CO_1F_TRAINER_0             EQU  115 ; byte 14 bit 3
DEF EVENT_BEAT_SILPH_CO_1F_TRAINER_1             EQU  116 ; byte 14 bit 4
DEF EVENT_BEAT_SILPH_CO_1F_TRAINER_2             EQU  117 ; byte 14 bit 5
DEF EVENT_BEAT_SILPH_CO_1F_TRAINER_3             EQU  118 ; byte 14 bit 6
DEF EVENT_BEAT_SILPH_CO_1F_TRAINER_4             EQU  119 ; byte 14 bit 7

; -- SilphCo10F  [def_trainers 1, 2 trainers]
DEF EVENT_BEAT_SILPH_CO_GIOVANNI                 EQU  120 ; byte 15 bit 0

; -- MtMoon1F  [def_trainers 1, 5 trainers]
DEF EVENT_BEAT_MT_MOON_1_TRAINER_0               EQU  121 ; byte 15 bit 1
DEF EVENT_BEAT_MT_MOON_1_TRAINER_1               EQU  122 ; byte 15 bit 2
DEF EVENT_BEAT_MT_MOON_1_TRAINER_2               EQU  123 ; byte 15 bit 3
DEF EVENT_BEAT_MT_MOON_1_TRAINER_3               EQU  124 ; byte 15 bit 4
DEF EVENT_BEAT_MT_MOON_1_TRAINER_4               EQU  125 ; byte 15 bit 5

; -- (engine / cross-map)
DEF EVENT_BEAT_SS_ANNE_B1F_TRAINER_0             EQU  126 ; byte 15 bit 6
DEF EVENT_BEAT_SS_ANNE_B1F_TRAINER_1             EQU  127 ; byte 15 bit 7
DEF EVENT_BEAT_SS_ANNE_B1F_TRAINER_2             EQU  128 ; byte 16 bit 0
DEF EVENT_BEAT_SS_ANNE_B1F_TRAINER_3             EQU  129 ; byte 16 bit 1

; -- PewterGym  [def_trainers 2, 4 trainers]
DEF EVENT_BEAT_PEWTER_GYM_TRAINER_0              EQU  130 ; byte 16 bit 2
DEF EVENT_BEAT_PEWTER_GYM_TRAINER_1              EQU  131 ; byte 16 bit 3
DEF EVENT_BEAT_PEWTER_GYM_TRAINER_2              EQU  132 ; byte 16 bit 4
DEF EVENT_BEAT_PEWTER_GYM_TRAINER_3              EQU  133 ; byte 16 bit 5

; -- (engine / cross-map)
DEF EVENT_BEAT_SS_ANNE_B1F_TRAINER_4             EQU  134 ; byte 16 bit 6

; -- ViridianCity
DEF EVENT_BEAT_VIRIDIAN_GYM_GIOVANNI             EQU  135 ; byte 16 bit 7

; -- BillsHouse
DEF EVENT_BILL_SAID_USE_CELL_SEPARATOR           EQU  136 ; byte 17 bit 0

; -- PokemonMansion1F  [def_trainers 1, 5 trainers]
DEF EVENT_BEAT_MANSION_1_TRAINER_0               EQU  137 ; byte 17 bit 1
DEF EVENT_BEAT_MANSION_1_TRAINER_1               EQU  138 ; byte 17 bit 2
DEF EVENT_BEAT_MANSION_1_TRAINER_2               EQU  139 ; byte 17 bit 3
DEF EVENT_BEAT_MANSION_1_TRAINER_3               EQU  140 ; byte 17 bit 4
DEF EVENT_BEAT_MANSION_1_TRAINER_4               EQU  141 ; byte 17 bit 5

; -- IndigoPlateauLobby
DEF EVENT_BOUGHT_POKEMON                         EQU  142 ; byte 17 bit 6

; -- BillsHouse
DEF EVENT_BRIDGE_INTRO                           EQU  143 ; byte 17 bit 7
DEF EVENT_BRIDGE_RECEIVE_GIFT                    EQU  144 ; byte 18 bit 0

; -- PokemonTower2F  [def_trainers 1, 5 trainers]
DEF EVENT_BEAT_POKEMON_TOWER_2F_TRAINER_0        EQU  145 ; byte 18 bit 1
DEF EVENT_BEAT_POKEMON_TOWER_2F_TRAINER_1        EQU  146 ; byte 18 bit 2
DEF EVENT_BEAT_POKEMON_TOWER_2F_TRAINER_2        EQU  147 ; byte 18 bit 3
DEF EVENT_BEAT_POKEMON_TOWER_2F_TRAINER_3        EQU  148 ; byte 18 bit 4
DEF EVENT_BEAT_POKEMON_TOWER_2F_TRAINER_4        EQU  149 ; byte 18 bit 5

; -- BillsHouse
DEF EVENT_ENTER_ROOM                             EQU  150 ; byte 18 bit 6

; -- (engine / cross-map)
DEF EVENT_FIGHT_ROUTE12_SNORLAX                  EQU  151 ; byte 18 bit 7

; -- Route16  [def_trainers 1, 6 trainers]
DEF EVENT_FIGHT_ROUTE16_SNORLAX                  EQU  152 ; byte 19 bit 0

; -- PokemonTower7F  [def_trainers 1, 5 trainers]
DEF EVENT_BEAT_POKEMONTOWER_7_TRAINER_0          EQU  153 ; byte 19 bit 1
DEF EVENT_BEAT_POKEMONTOWER_7_TRAINER_1          EQU  154 ; byte 19 bit 2
DEF EVENT_BEAT_POKEMONTOWER_7_TRAINER_2          EQU  155 ; byte 19 bit 3
DEF EVENT_BEAT_POKEMONTOWER_7_TRAINER_3          EQU  156 ; byte 19 bit 4
DEF EVENT_BEAT_POKEMONTOWER_7_TRAINER_4          EQU  157 ; byte 19 bit 5

; -- GameCorner  [def_trainers 1, 5 trainers]
DEF EVENT_FOUND_ROCKET_HIDEOUT                   EQU  158 ; byte 19 bit 6

; -- (engine / cross-map)
DEF EVENT_GAVE_FOSSIL_TO_LAB                     EQU  159 ; byte 19 bit 7

; -- Route24  [def_trainers 1, 5 trainers]
DEF EVENT_GOT_NUGGET                             EQU  160 ; byte 20 bit 0

; -- PowerPlant  [def_trainers 1, 5 trainers]
DEF EVENT_BEAT_POWER_PLANT_TRAINER_0             EQU  161 ; byte 20 bit 1
DEF EVENT_BEAT_POWER_PLANT_TRAINER_1             EQU  162 ; byte 20 bit 2
DEF EVENT_BEAT_POWER_PLANT_TRAINER_2             EQU  163 ; byte 20 bit 3
DEF EVENT_BEAT_POWER_PLANT_TRAINER_3             EQU  164 ; byte 20 bit 4
DEF EVENT_BEAT_POWER_PLANT_TRAINER_4             EQU  165 ; byte 20 bit 5

; -- DiglettsCave  [def_trainers 1, 5 trainers]
DEF EVENT_GOT_ROGUE_POKEMON                      EQU  166 ; byte 20 bit 6

; -- Route25  [def_trainers 1, 5 trainers]
DEF EVENT_GOT_SS_TICKET                          EQU  167 ; byte 20 bit 7

; -- FuchsiaGym  [def_trainers 2, 4 trainers]
DEF EVENT_GOT_TM06                               EQU  168 ; byte 21 bit 0

; -- ProceduralCave1  [def_trainers 1, 1 trainers]
DEF EVENT_BEAT_PC_BOSS                           EQU  169 ; byte 21 bit 1

; -- CeruleanGym  [def_trainers 2, 4 trainers]
DEF EVENT_GOT_TM11                               EQU  170 ; byte 21 bit 2

; -- CeladonGym  [def_trainers 2, 4 trainers]
DEF EVENT_GOT_TM21                               EQU  171 ; byte 21 bit 3

; -- VermilionGym  [def_trainers 2, 4 trainers]
DEF EVENT_GOT_TM24                               EQU  172 ; byte 21 bit 4

; -- ViridianGym  [def_trainers 2, 4 trainers]
DEF EVENT_GOT_TM27                               EQU  173 ; byte 21 bit 5

; -- PewterGym  [def_trainers 2, 4 trainers]
DEF EVENT_GOT_TM34                               EQU  174 ; byte 21 bit 6

; -- CinnabarGym
DEF EVENT_GOT_TM38                               EQU  175 ; byte 21 bit 7

; -- SaffronGym  [def_trainers 2, 4 trainers]
DEF EVENT_GOT_TM46                               EQU  176 ; byte 22 bit 0

; -- RockTunnel1F  [def_trainers 1, 5 trainers]
DEF EVENT_BEAT_ROCK_TUNNEL_1_TRAINER_0           EQU  177 ; byte 22 bit 1
DEF EVENT_BEAT_ROCK_TUNNEL_1_TRAINER_1           EQU  178 ; byte 22 bit 2
DEF EVENT_BEAT_ROCK_TUNNEL_1_TRAINER_2           EQU  179 ; byte 22 bit 3
DEF EVENT_BEAT_ROCK_TUNNEL_1_TRAINER_3           EQU  180 ; byte 22 bit 4
DEF EVENT_BEAT_ROCK_TUNNEL_1_TRAINER_4           EQU  181 ; byte 22 bit 5

; -- SafariZoneGate
DEF EVENT_IN_SAFARI_ZONE                         EQU  182 ; byte 22 bit 6

; -- CinnabarIsland
DEF EVENT_LAB_STILL_REVIVING_FOSSIL              EQU  183 ; byte 22 bit 7

; -- LancesRoom  [def_trainers 1, 1 trainers]
DEF EVENT_LANCES_ROOM_LOCK_DOOR                  EQU  184 ; byte 23 bit 0

; -- RocketHideoutB1F  [def_trainers 1, 5 trainers]
DEF EVENT_BEAT_ROCKET_HIDEOUT_1_TRAINER_0        EQU  185 ; byte 23 bit 1
DEF EVENT_BEAT_ROCKET_HIDEOUT_1_TRAINER_1        EQU  186 ; byte 23 bit 2
DEF EVENT_BEAT_ROCKET_HIDEOUT_1_TRAINER_2        EQU  187 ; byte 23 bit 3
DEF EVENT_BEAT_ROCKET_HIDEOUT_1_TRAINER_3        EQU  188 ; byte 23 bit 4
DEF EVENT_BEAT_ROCKET_HIDEOUT_1_TRAINER_4        EQU  189 ; byte 23 bit 5

; -- BillsHouse
DEF EVENT_LEFT_BILLS_HOUSE_AFTER_HELPING         EQU  190 ; byte 23 bit 6

; -- CinnabarIsland
DEF EVENT_MANSION_SWITCH_ON                      EQU  191 ; byte 23 bit 7

; -- BillsHouse
DEF EVENT_MET_BILL                               EQU  192 ; byte 24 bit 0

; -- Route1  [def_trainers 1, 5 trainers]
DEF EVENT_BEAT_ROUTE_1_TRAINER_0                 EQU  193 ; byte 24 bit 1
DEF EVENT_BEAT_ROUTE_1_TRAINER_1                 EQU  194 ; byte 24 bit 2
DEF EVENT_BEAT_ROUTE_1_TRAINER_2                 EQU  195 ; byte 24 bit 3
DEF EVENT_BEAT_ROUTE_1_TRAINER_3                 EQU  196 ; byte 24 bit 4
DEF EVENT_BEAT_ROUTE_1_TRAINER_4                 EQU  197 ; byte 24 bit 5

; -- BillsHouse
DEF EVENT_MET_BILL_2                             EQU  198 ; byte 24 bit 6

; -- Route24  [def_trainers 1, 5 trainers]
DEF EVENT_NUGGET_REWARD_AVAILABLE                EQU  199 ; byte 24 bit 7

; -- CeladonGym  [def_trainers 2, 4 trainers]
DEF EVENT_OFFERED_LEGENDARY_TRADE_GYM5           EQU  200 ; byte 25 bit 0

; -- Route12  [def_trainers 1, 5 trainers]
DEF EVENT_BEAT_ROUTE_12_TRAINER_0                EQU  201 ; byte 25 bit 1
DEF EVENT_BEAT_ROUTE_12_TRAINER_1                EQU  202 ; byte 25 bit 2
DEF EVENT_BEAT_ROUTE_12_TRAINER_2                EQU  203 ; byte 25 bit 3
DEF EVENT_BEAT_ROUTE_12_TRAINER_3                EQU  204 ; byte 25 bit 4
DEF EVENT_BEAT_ROUTE_12_TRAINER_4                EQU  205 ; byte 25 bit 5

; -- SaffronGym  [def_trainers 2, 4 trainers]
DEF EVENT_OFFERED_LEGENDARY_TRADE_GYM6           EQU  206 ; byte 25 bit 6

; -- CinnabarGym
DEF EVENT_OFFERED_LEGENDARY_TRADE_GYM7           EQU  207 ; byte 25 bit 7

; -- ViridianGym  [def_trainers 2, 4 trainers]
DEF EVENT_OFFERED_LEGENDARY_TRADE_GYM8           EQU  208 ; byte 26 bit 0

; -- Route13  [def_trainers 1, 5 trainers]
DEF EVENT_BEAT_ROUTE_13_TRAINER_0                EQU  209 ; byte 26 bit 1
DEF EVENT_BEAT_ROUTE_13_TRAINER_1                EQU  210 ; byte 26 bit 2
DEF EVENT_BEAT_ROUTE_13_TRAINER_2                EQU  211 ; byte 26 bit 3
DEF EVENT_BEAT_ROUTE_13_TRAINER_3                EQU  212 ; byte 26 bit 4
DEF EVENT_BEAT_ROUTE_13_TRAINER_4                EQU  213 ; byte 26 bit 5

; -- ProceduralCave1  [def_trainers 1, 1 trainers]
DEF EVENT_PC_BOSS_OFFERED                        EQU  214 ; byte 26 bit 6
DEF EVENT_PC_BUDGET_ENDED                        EQU  215 ; byte 26 bit 7
DEF EVENT_PC_CALMED_SHOWN                        EQU  216 ; byte 27 bit 0

; -- Route15  [def_trainers 1, 5 trainers]
DEF EVENT_BEAT_ROUTE_15_TRAINER_0                EQU  217 ; byte 27 bit 1
DEF EVENT_BEAT_ROUTE_15_TRAINER_1                EQU  218 ; byte 27 bit 2
DEF EVENT_BEAT_ROUTE_15_TRAINER_2                EQU  219 ; byte 27 bit 3
DEF EVENT_BEAT_ROUTE_15_TRAINER_3                EQU  220 ; byte 27 bit 4
DEF EVENT_BEAT_ROUTE_15_TRAINER_4                EQU  221 ; byte 27 bit 5

; -- (engine / cross-map)
DEF EVENT_PC_CEM_BUDGET_ENDED                    EQU  222 ; byte 27 bit 6
DEF EVENT_PC_CEM_CALMED_SHOWN                    EQU  223 ; byte 27 bit 7
DEF EVENT_PF_ITEM_GOT                            EQU  224 ; byte 28 bit 0

; -- Route17  [def_trainers 1, 5 trainers]
DEF EVENT_BEAT_ROUTE_17_TRAINER_0                EQU  225 ; byte 28 bit 1
DEF EVENT_BEAT_ROUTE_17_TRAINER_1                EQU  226 ; byte 28 bit 2
DEF EVENT_BEAT_ROUTE_17_TRAINER_2                EQU  227 ; byte 28 bit 3
DEF EVENT_BEAT_ROUTE_17_TRAINER_3                EQU  228 ; byte 28 bit 4
DEF EVENT_BEAT_ROUTE_17_TRAINER_4                EQU  229 ; byte 28 bit 5

; -- PokemonFanClub
DEF EVENT_PIKACHU_FAN_BOAST                      EQU  230 ; byte 28 bit 6

; -- LavenderMart
DEF EVENT_RESCUED_MR_FUJI                        EQU  231 ; byte 28 bit 7

; -- PokemonTower7F  [def_trainers 1, 5 trainers]
DEF EVENT_RESCUED_MR_FUJI_2                      EQU  232 ; byte 29 bit 0

; -- Route24  [def_trainers 1, 5 trainers]
DEF EVENT_BEAT_ROUTE_24_TRAINER_0                EQU  233 ; byte 29 bit 1
DEF EVENT_BEAT_ROUTE_24_TRAINER_1                EQU  234 ; byte 29 bit 2
DEF EVENT_BEAT_ROUTE_24_TRAINER_2                EQU  235 ; byte 29 bit 3
DEF EVENT_BEAT_ROUTE_24_TRAINER_3                EQU  236 ; byte 29 bit 4
DEF EVENT_BEAT_ROUTE_24_TRAINER_4                EQU  237 ; byte 29 bit 5

; -- DiglettsCave  [def_trainers 1, 5 trainers]
DEF EVENT_ROGUE_POKEMON_OFFERED                  EQU  238 ; byte 29 bit 6

; -- Route22
DEF EVENT_ROUTE22_RIVAL_WANTS_BATTLE             EQU  239 ; byte 29 bit 7

; -- SSAnneCaptainsRoom
DEF EVENT_RUBBED_CAPTAINS_BACK                   EQU  240 ; byte 30 bit 0

; -- Route25  [def_trainers 1, 5 trainers]
DEF EVENT_BEAT_ROUTE_25_TRAINER_0                EQU  241 ; byte 30 bit 1
DEF EVENT_BEAT_ROUTE_25_TRAINER_1                EQU  242 ; byte 30 bit 2
DEF EVENT_BEAT_ROUTE_25_TRAINER_2                EQU  243 ; byte 30 bit 3
DEF EVENT_BEAT_ROUTE_25_TRAINER_3                EQU  244 ; byte 30 bit 4
DEF EVENT_BEAT_ROUTE_25_TRAINER_4                EQU  245 ; byte 30 bit 5

; -- SafariZoneGate
DEF EVENT_SAFARI_GAME_OVER                       EQU  246 ; byte 30 bit 6

; -- PokemonFanClub
DEF EVENT_SEEL_FAN_BOAST                         EQU  247 ; byte 30 bit 7

; -- SSAnneB1F
DEF EVENT_SSANNE_ALL_TRAINERS_DEFEATED           EQU  248 ; byte 31 bit 0

; -- Route3  [def_trainers 1, 5 trainers]
DEF EVENT_BEAT_ROUTE_3_TRAINER_0                 EQU  249 ; byte 31 bit 1
DEF EVENT_BEAT_ROUTE_3_TRAINER_1                 EQU  250 ; byte 31 bit 2
DEF EVENT_BEAT_ROUTE_3_TRAINER_2                 EQU  251 ; byte 31 bit 3
DEF EVENT_BEAT_ROUTE_3_TRAINER_3                 EQU  252 ; byte 31 bit 4
DEF EVENT_BEAT_ROUTE_3_TRAINER_4                 EQU  253 ; byte 31 bit 5

; -- RewardRoom
DEF EVENT_STEP_FORWARD                           EQU  254 ; byte 31 bit 6

; -- BillsHouse
DEF EVENT_USED_CELL_SEPARATOR_ON_BILL            EQU  255 ; byte 31 bit 7

; -- VictoryRoad2F  [def_trainers 1, 6 trainers]
DEF EVENT_VICTORY_ROAD_1_BOULDER_ON_SWITCH       EQU  256 ; byte 32 bit 0

; -- Route5  [def_trainers 1, 5 trainers]
DEF EVENT_BEAT_ROUTE_5_TRAINER_0                 EQU  257 ; byte 32 bit 1
DEF EVENT_BEAT_ROUTE_5_TRAINER_1                 EQU  258 ; byte 32 bit 2
DEF EVENT_BEAT_ROUTE_5_TRAINER_2                 EQU  259 ; byte 32 bit 3
DEF EVENT_BEAT_ROUTE_5_TRAINER_3                 EQU  260 ; byte 32 bit 4
DEF EVENT_BEAT_ROUTE_5_TRAINER_4                 EQU  261 ; byte 32 bit 5

; -- Route23
DEF EVENT_VICTORY_ROAD_2_BOULDER_ON_SWITCH1      EQU  262 ; byte 32 bit 6
DEF EVENT_VICTORY_ROAD_2_BOULDER_ON_SWITCH2      EQU  263 ; byte 32 bit 7
DEF EVENT_VICTORY_ROAD_3_BOULDER_ON_SWITCH1      EQU  264 ; byte 33 bit 0

; -- Route6  [def_trainers 1, 5 trainers]
DEF EVENT_BEAT_ROUTE_6_TRAINER_0                 EQU  265 ; byte 33 bit 1
DEF EVENT_BEAT_ROUTE_6_TRAINER_1                 EQU  266 ; byte 33 bit 2
DEF EVENT_BEAT_ROUTE_6_TRAINER_2                 EQU  267 ; byte 33 bit 3
DEF EVENT_BEAT_ROUTE_6_TRAINER_3                 EQU  268 ; byte 33 bit 4
DEF EVENT_BEAT_ROUTE_6_TRAINER_4                 EQU  269 ; byte 33 bit 5

; -- Route23
DEF EVENT_VICTORY_ROAD_3_BOULDER_ON_SWITCH2      EQU  270 ; byte 33 bit 6

; -- IndigoPlateauLobby
DEF EVENT_VICTORY_ROAD_CLEARED                   EQU  271 ; byte 33 bit 7

; -- Route9  [def_trainers 1, 5 trainers]
DEF EVENT_BEAT_ROUTE_9_TRAINER_0                 EQU  273 ; byte 34 bit 1
DEF EVENT_BEAT_ROUTE_9_TRAINER_1                 EQU  274 ; byte 34 bit 2
DEF EVENT_BEAT_ROUTE_9_TRAINER_2                 EQU  275 ; byte 34 bit 3
DEF EVENT_BEAT_ROUTE_9_TRAINER_3                 EQU  276 ; byte 34 bit 4
DEF EVENT_BEAT_ROUTE_9_TRAINER_4                 EQU  277 ; byte 34 bit 5

; -- SSAnneB1FRooms  [def_trainers 1, 5 trainers]
DEF EVENT_BEAT_SS_ANNE_10_TRAINER_0              EQU  281 ; byte 35 bit 1
DEF EVENT_BEAT_SS_ANNE_10_TRAINER_1              EQU  282 ; byte 35 bit 2
DEF EVENT_BEAT_SS_ANNE_10_TRAINER_2              EQU  283 ; byte 35 bit 3
DEF EVENT_BEAT_SS_ANNE_10_TRAINER_3              EQU  284 ; byte 35 bit 4
DEF EVENT_BEAT_SS_ANNE_10_TRAINER_4              EQU  285 ; byte 35 bit 5

; -- SSAnneBow  [def_trainers 1, 5 trainers]
DEF EVENT_BEAT_SS_ANNE_5_TRAINER_0               EQU  289 ; byte 36 bit 1
DEF EVENT_BEAT_SS_ANNE_5_TRAINER_1               EQU  290 ; byte 36 bit 2
DEF EVENT_BEAT_SS_ANNE_5_TRAINER_2               EQU  291 ; byte 36 bit 3
DEF EVENT_BEAT_SS_ANNE_5_TRAINER_3               EQU  292 ; byte 36 bit 4
DEF EVENT_BEAT_SS_ANNE_5_TRAINER_4               EQU  293 ; byte 36 bit 5

; -- SaffronGym  [def_trainers 2, 4 trainers]
DEF EVENT_BEAT_SAFFRON_GYM_TRAINER_0             EQU  298 ; byte 37 bit 2
DEF EVENT_BEAT_SAFFRON_GYM_TRAINER_1             EQU  299 ; byte 37 bit 3
DEF EVENT_BEAT_SAFFRON_GYM_TRAINER_2             EQU  300 ; byte 37 bit 4
DEF EVENT_BEAT_SAFFRON_GYM_TRAINER_3             EQU  301 ; byte 37 bit 5

; -- SeafoamIslands1F  [def_trainers 1, 5 trainers]
DEF EVENT_BEAT_SEAFOAM_ISLANDS_1F_TRAINER_0      EQU  305 ; byte 38 bit 1
DEF EVENT_BEAT_SEAFOAM_ISLANDS_1F_TRAINER_1      EQU  306 ; byte 38 bit 2
DEF EVENT_BEAT_SEAFOAM_ISLANDS_1F_TRAINER_2      EQU  307 ; byte 38 bit 3
DEF EVENT_BEAT_SEAFOAM_ISLANDS_1F_TRAINER_3      EQU  308 ; byte 38 bit 4
DEF EVENT_BEAT_SEAFOAM_ISLANDS_1F_TRAINER_4      EQU  309 ; byte 38 bit 5

; -- UndergroundPathRoute5  [def_trainers 1, 5 trainers]
DEF EVENT_BEAT_UNDERGROUND_PATH_ROUTE5_TRAINER_0 EQU  313 ; byte 39 bit 1
DEF EVENT_BEAT_UNDERGROUND_PATH_ROUTE5_TRAINER_1 EQU  314 ; byte 39 bit 2
DEF EVENT_BEAT_UNDERGROUND_PATH_ROUTE5_TRAINER_2 EQU  315 ; byte 39 bit 3
DEF EVENT_BEAT_UNDERGROUND_PATH_ROUTE5_TRAINER_3 EQU  316 ; byte 39 bit 4
DEF EVENT_BEAT_UNDERGROUND_PATH_ROUTE5_TRAINER_4 EQU  317 ; byte 39 bit 5

; -- UndergroundPathWestEast  [def_trainers 1, 5 trainers]
DEF EVENT_BEAT_UNDERGROUND_PATH_WEST_EAST_TRAINER_0 EQU  321 ; byte 40 bit 1
DEF EVENT_BEAT_UNDERGROUND_PATH_WEST_EAST_TRAINER_1 EQU  322 ; byte 40 bit 2
DEF EVENT_BEAT_UNDERGROUND_PATH_WEST_EAST_TRAINER_2 EQU  323 ; byte 40 bit 3
DEF EVENT_BEAT_UNDERGROUND_PATH_WEST_EAST_TRAINER_3 EQU  324 ; byte 40 bit 4
DEF EVENT_BEAT_UNDERGROUND_PATH_WEST_EAST_TRAINER_4 EQU  325 ; byte 40 bit 5

; -- VermilionGym  [def_trainers 2, 4 trainers]
DEF EVENT_BEAT_VERMILION_GYM_TRAINER_0           EQU  330 ; byte 41 bit 2
DEF EVENT_BEAT_VERMILION_GYM_TRAINER_1           EQU  331 ; byte 41 bit 3
DEF EVENT_BEAT_VERMILION_GYM_TRAINER_2           EQU  332 ; byte 41 bit 4
DEF EVENT_BEAT_VERMILION_GYM_TRAINER_3           EQU  333 ; byte 41 bit 5

; -- VictoryRoad1F  [def_trainers 1, 5 trainers]
DEF EVENT_BEAT_VICTORY_ROAD_1_TRAINER_0          EQU  337 ; byte 42 bit 1
DEF EVENT_BEAT_VICTORY_ROAD_1_TRAINER_1          EQU  338 ; byte 42 bit 2
DEF EVENT_BEAT_VICTORY_ROAD_1_TRAINER_2          EQU  339 ; byte 42 bit 3
DEF EVENT_BEAT_VICTORY_ROAD_1_TRAINER_3          EQU  340 ; byte 42 bit 4
DEF EVENT_BEAT_VICTORY_ROAD_1_TRAINER_4          EQU  341 ; byte 42 bit 5

; -- VictoryRoad2F  [def_trainers 1, 6 trainers]
DEF EVENT_BEAT_VICTORY_ROAD_2_TRAINER_0          EQU  345 ; byte 43 bit 1
DEF EVENT_BEAT_VICTORY_ROAD_2_TRAINER_1          EQU  346 ; byte 43 bit 2
DEF EVENT_BEAT_VICTORY_ROAD_2_TRAINER_2          EQU  347 ; byte 43 bit 3
DEF EVENT_BEAT_VICTORY_ROAD_2_TRAINER_3          EQU  348 ; byte 43 bit 4
DEF EVENT_BEAT_VICTORY_ROAD_2_TRAINER_4          EQU  349 ; byte 43 bit 5
DEF EVENT_BEAT_MOLTRES                           EQU  350 ; byte 43 bit 6

; -- VictoryRoad3F  [def_trainers 1, 4 trainers]
DEF EVENT_BEAT_VICTORY_ROAD_3_TRAINER_0          EQU  353 ; byte 44 bit 1
DEF EVENT_BEAT_VICTORY_ROAD_3_TRAINER_1          EQU  354 ; byte 44 bit 2
DEF EVENT_BEAT_VICTORY_ROAD_3_TRAINER_2          EQU  355 ; byte 44 bit 3
DEF EVENT_BEAT_VICTORY_ROAD_3_TRAINER_3          EQU  356 ; byte 44 bit 4

; -- ViridianForest  [def_trainers 1, 5 trainers]
DEF EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_0         EQU  361 ; byte 45 bit 1
DEF EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_1         EQU  362 ; byte 45 bit 2
DEF EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_2         EQU  363 ; byte 45 bit 3
DEF EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_3         EQU  364 ; byte 45 bit 4
DEF EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_4         EQU  365 ; byte 45 bit 5

; -- ViridianGym  [def_trainers 2, 4 trainers]
DEF EVENT_BEAT_VIRIDIAN_GYM_TRAINER_0            EQU  370 ; byte 46 bit 2
DEF EVENT_BEAT_VIRIDIAN_GYM_TRAINER_1            EQU  371 ; byte 46 bit 3
DEF EVENT_BEAT_VIRIDIAN_GYM_TRAINER_2            EQU  372 ; byte 46 bit 4
DEF EVENT_BEAT_VIRIDIAN_GYM_TRAINER_3            EQU  373 ; byte 46 bit 5

DEF RUN_EVENTS_END   EQU 375

; ==========================================================================
; ZONE 2 - GRAVEYARD (unreachable maps; aliases, deliberately overlapping)
; ==========================================================================
DEF EVENT_GRAVEYARD_BASE EQU 376

; -- BikeShop (unreachable)
DEF EVENT_GOT_BICYCLE                            EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0

; -- CeladonCity (unreachable)
DEF EVENT_1B8                                    EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0
DEF EVENT_1BF                                    EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_67F                                    EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2
DEF EVENT_GOT_TM41                               EQU EVENT_GRAVEYARD_BASE + 3   ; byte 47 bit 3

; -- CeladonDiner (unreachable)
DEF EVENT_GOT_COIN_CASE                          EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0

; -- CeladonMart3F (unreachable)
DEF EVENT_GOT_TM18                               EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0

; -- CeladonMartRoof (unreachable)
DEF EVENT_GOT_TM13                               EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0
DEF EVENT_GOT_TM48                               EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_GOT_TM49                               EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2

; -- CeruleanCaveB1F (unreachable)
DEF EVENT_BEAT_MEWTWO                            EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1

; -- CeruleanCity (unreachable)
DEF EVENT_BEAT_CERULEAN_RIVAL                    EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0
DEF EVENT_BEAT_CERULEAN_ROCKET_THIEF             EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1

; -- CinnabarLabMetronomeRoom (unreachable)
DEF EVENT_GOT_TM35                               EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0

; -- FightingDojo (unreachable)
DEF EVENT_DEFEATED_FIGHTING_DOJO                 EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0
DEF EVENT_BEAT_KARATE_MASTER                     EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_BEAT_FIGHTING_DOJO_TRAINER_0           EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2
DEF EVENT_BEAT_FIGHTING_DOJO_TRAINER_1           EQU EVENT_GRAVEYARD_BASE + 3   ; byte 47 bit 3
DEF EVENT_BEAT_FIGHTING_DOJO_TRAINER_2           EQU EVENT_GRAVEYARD_BASE + 4   ; byte 47 bit 4
DEF EVENT_BEAT_FIGHTING_DOJO_TRAINER_3           EQU EVENT_GRAVEYARD_BASE + 5   ; byte 47 bit 5
DEF EVENT_GOT_HITMONLEE                          EQU EVENT_GRAVEYARD_BASE + 6   ; byte 47 bit 6
DEF EVENT_GOT_HITMONCHAN                         EQU EVENT_GRAVEYARD_BASE + 7   ; byte 47 bit 7

; -- FuchsiaCity (unreachable)
DEF EVENT_GOT_DOME_FOSSIL                        EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0
DEF EVENT_GOT_HELIX_FOSSIL                       EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1

; -- MrPsychicsHouse (unreachable)
DEF EVENT_GOT_TM29                               EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0

; -- MtMoonB2F (unreachable)
DEF EVENT_BEAT_MT_MOON_3_TRAINER_0               EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2
DEF EVENT_BEAT_MT_MOON_3_TRAINER_1               EQU EVENT_GRAVEYARD_BASE + 3   ; byte 47 bit 3
DEF EVENT_BEAT_MT_MOON_3_TRAINER_2               EQU EVENT_GRAVEYARD_BASE + 4   ; byte 47 bit 4
DEF EVENT_BEAT_MT_MOON_3_TRAINER_3               EQU EVENT_GRAVEYARD_BASE + 5   ; byte 47 bit 5
DEF EVENT_BEAT_MT_MOON_EXIT_SUPER_NERD           EQU EVENT_GRAVEYARD_BASE + 6   ; byte 47 bit 6

; -- MtMoonPokecenter (unreachable)
DEF EVENT_BOUGHT_MAGIKARP                        EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0

; -- Museum1F (unreachable)
DEF EVENT_BOUGHT_MUSEUM_TICKET                   EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0
DEF EVENT_GOT_OLD_AMBER                          EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1

; -- PokemonMansion2F (unreachable)
DEF EVENT_BEAT_MANSION_2_TRAINER_0               EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1

; -- PokemonMansion3F (unreachable)
DEF EVENT_BEAT_MANSION_3_TRAINER_0               EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_BEAT_MANSION_3_TRAINER_1               EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2

; -- PokemonMansionB1F (unreachable)
DEF EVENT_BEAT_MANSION_4_TRAINER_0               EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_BEAT_MANSION_4_TRAINER_1               EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2

; -- PokemonTower3F (unreachable)
DEF EVENT_BEAT_POKEMONTOWER_3_TRAINER_0          EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_BEAT_POKEMONTOWER_3_TRAINER_1          EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2
DEF EVENT_BEAT_POKEMONTOWER_3_TRAINER_2          EQU EVENT_GRAVEYARD_BASE + 3   ; byte 47 bit 3

; -- PokemonTower4F (unreachable)
DEF EVENT_BEAT_POKEMONTOWER_4_TRAINER_0          EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_BEAT_POKEMONTOWER_4_TRAINER_1          EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2
DEF EVENT_BEAT_POKEMONTOWER_4_TRAINER_2          EQU EVENT_GRAVEYARD_BASE + 3   ; byte 47 bit 3

; -- PokemonTower5F (unreachable)
DEF EVENT_IN_PURIFIED_ZONE                       EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0
DEF EVENT_BEAT_POKEMONTOWER_5_TRAINER_0          EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2
DEF EVENT_BEAT_POKEMONTOWER_5_TRAINER_1          EQU EVENT_GRAVEYARD_BASE + 3   ; byte 47 bit 3
DEF EVENT_BEAT_POKEMONTOWER_5_TRAINER_2          EQU EVENT_GRAVEYARD_BASE + 4   ; byte 47 bit 4
DEF EVENT_BEAT_POKEMONTOWER_5_TRAINER_3          EQU EVENT_GRAVEYARD_BASE + 5   ; byte 47 bit 5

; -- PokemonTower6F (unreachable)
DEF EVENT_BEAT_GHOST_MAROWAK                     EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0
DEF EVENT_BEAT_POKEMONTOWER_6_TRAINER_0          EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_BEAT_POKEMONTOWER_6_TRAINER_1          EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2
DEF EVENT_BEAT_POKEMONTOWER_6_TRAINER_2          EQU EVENT_GRAVEYARD_BASE + 3   ; byte 47 bit 3

; -- RockTunnelB1F (unreachable)
DEF EVENT_BEAT_ROCK_TUNNEL_2_TRAINER_0           EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_BEAT_ROCK_TUNNEL_2_TRAINER_1           EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2
DEF EVENT_BEAT_ROCK_TUNNEL_2_TRAINER_2           EQU EVENT_GRAVEYARD_BASE + 3   ; byte 47 bit 3
DEF EVENT_BEAT_ROCK_TUNNEL_2_TRAINER_3           EQU EVENT_GRAVEYARD_BASE + 4   ; byte 47 bit 4
DEF EVENT_BEAT_ROCK_TUNNEL_2_TRAINER_4           EQU EVENT_GRAVEYARD_BASE + 5   ; byte 47 bit 5
DEF EVENT_BEAT_ROCK_TUNNEL_2_TRAINER_5           EQU EVENT_GRAVEYARD_BASE + 6   ; byte 47 bit 6
DEF EVENT_BEAT_ROCK_TUNNEL_2_TRAINER_6           EQU EVENT_GRAVEYARD_BASE + 7   ; byte 47 bit 7
DEF EVENT_BEAT_ROCK_TUNNEL_2_TRAINER_7           EQU EVENT_GRAVEYARD_BASE + 8   ; byte 48 bit 0

; -- RocketHideoutB2F (unreachable)
DEF EVENT_BEAT_ROCKET_HIDEOUT_2_TRAINER_0        EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1

; -- RocketHideoutB3F (unreachable)
DEF EVENT_BEAT_ROCKET_HIDEOUT_3_TRAINER_0        EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_BEAT_ROCKET_HIDEOUT_3_TRAINER_1        EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2

; -- RocketHideoutB4F (unreachable)
DEF EVENT_BEAT_ROCKET_HIDEOUT_GIOVANNI           EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0
DEF EVENT_ROCKET_DROPPED_LIFT_KEY                EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_0        EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2
DEF EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_1        EQU EVENT_GRAVEYARD_BASE + 3   ; byte 47 bit 3
DEF EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_2        EQU EVENT_GRAVEYARD_BASE + 4   ; byte 47 bit 4
DEF EVENT_ROCKET_HIDEOUT_4_DOOR_UNLOCKED         EQU EVENT_GRAVEYARD_BASE + 5   ; byte 47 bit 5

; -- Route10 (unreachable)
DEF EVENT_BEAT_ROUTE_10_TRAINER_0                EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_BEAT_ROUTE_10_TRAINER_1                EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2
DEF EVENT_BEAT_ROUTE_10_TRAINER_2                EQU EVENT_GRAVEYARD_BASE + 3   ; byte 47 bit 3
DEF EVENT_BEAT_ROUTE_10_TRAINER_3                EQU EVENT_GRAVEYARD_BASE + 4   ; byte 47 bit 4
DEF EVENT_BEAT_ROUTE_10_TRAINER_4                EQU EVENT_GRAVEYARD_BASE + 5   ; byte 47 bit 5
DEF EVENT_BEAT_ROUTE_10_TRAINER_5                EQU EVENT_GRAVEYARD_BASE + 6   ; byte 47 bit 6

; -- Route11 (unreachable)
DEF EVENT_BEAT_ROUTE_11_TRAINER_0                EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_BEAT_ROUTE_11_TRAINER_1                EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2
DEF EVENT_BEAT_ROUTE_11_TRAINER_2                EQU EVENT_GRAVEYARD_BASE + 3   ; byte 47 bit 3
DEF EVENT_BEAT_ROUTE_11_TRAINER_3                EQU EVENT_GRAVEYARD_BASE + 4   ; byte 47 bit 4
DEF EVENT_BEAT_ROUTE_11_TRAINER_4                EQU EVENT_GRAVEYARD_BASE + 5   ; byte 47 bit 5
DEF EVENT_BEAT_ROUTE_11_TRAINER_5                EQU EVENT_GRAVEYARD_BASE + 6   ; byte 47 bit 6
DEF EVENT_BEAT_ROUTE_11_TRAINER_6                EQU EVENT_GRAVEYARD_BASE + 7   ; byte 47 bit 7
DEF EVENT_BEAT_ROUTE_11_TRAINER_7                EQU EVENT_GRAVEYARD_BASE + 8   ; byte 48 bit 0
DEF EVENT_BEAT_ROUTE_11_TRAINER_8                EQU EVENT_GRAVEYARD_BASE + 9   ; byte 48 bit 1
DEF EVENT_BEAT_ROUTE_11_TRAINER_9                EQU EVENT_GRAVEYARD_BASE + 10  ; byte 48 bit 2

; -- Route11Gate2F (unreachable)
DEF EVENT_GOT_ITEMFINDER                         EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0

; -- Route12Gate2F (unreachable)
DEF EVENT_GOT_TM39                               EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0

; -- Route14 (unreachable)
DEF EVENT_BEAT_ROUTE_14_TRAINER_0                EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_BEAT_ROUTE_14_TRAINER_1                EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2
DEF EVENT_BEAT_ROUTE_14_TRAINER_2                EQU EVENT_GRAVEYARD_BASE + 3   ; byte 47 bit 3
DEF EVENT_BEAT_ROUTE_14_TRAINER_3                EQU EVENT_GRAVEYARD_BASE + 4   ; byte 47 bit 4
DEF EVENT_BEAT_ROUTE_14_TRAINER_4                EQU EVENT_GRAVEYARD_BASE + 5   ; byte 47 bit 5
DEF EVENT_BEAT_ROUTE_14_TRAINER_5                EQU EVENT_GRAVEYARD_BASE + 6   ; byte 47 bit 6
DEF EVENT_BEAT_ROUTE_14_TRAINER_6                EQU EVENT_GRAVEYARD_BASE + 7   ; byte 47 bit 7
DEF EVENT_BEAT_ROUTE_14_TRAINER_7                EQU EVENT_GRAVEYARD_BASE + 8   ; byte 48 bit 0
DEF EVENT_BEAT_ROUTE_14_TRAINER_8                EQU EVENT_GRAVEYARD_BASE + 9   ; byte 48 bit 1
DEF EVENT_BEAT_ROUTE_14_TRAINER_9                EQU EVENT_GRAVEYARD_BASE + 10  ; byte 48 bit 2

; -- Route15Gate2F (unreachable)
DEF EVENT_GOT_EXP_ALL                            EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0

; -- Route16 (unreachable)
DEF EVENT_BEAT_ROUTE_16_TRAINER_0                EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_BEAT_ROUTE_16_TRAINER_1                EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2
DEF EVENT_BEAT_ROUTE_16_TRAINER_2                EQU EVENT_GRAVEYARD_BASE + 3   ; byte 47 bit 3
DEF EVENT_BEAT_ROUTE_16_TRAINER_3                EQU EVENT_GRAVEYARD_BASE + 4   ; byte 47 bit 4
DEF EVENT_BEAT_ROUTE_16_TRAINER_4                EQU EVENT_GRAVEYARD_BASE + 5   ; byte 47 bit 5
DEF EVENT_BEAT_ROUTE_16_TRAINER_5                EQU EVENT_GRAVEYARD_BASE + 6   ; byte 47 bit 6

; -- Route16FlyHouse (unreachable)
DEF EVENT_GOT_HM02                               EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0

; -- Route18 (unreachable)
DEF EVENT_BEAT_ROUTE_18_TRAINER_0                EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_BEAT_ROUTE_18_TRAINER_1                EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2
DEF EVENT_BEAT_ROUTE_18_TRAINER_2                EQU EVENT_GRAVEYARD_BASE + 3   ; byte 47 bit 3

; -- Route19 (unreachable)
DEF EVENT_BEAT_ROUTE_19_TRAINER_0                EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_BEAT_ROUTE_19_TRAINER_1                EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2
DEF EVENT_BEAT_ROUTE_19_TRAINER_2                EQU EVENT_GRAVEYARD_BASE + 3   ; byte 47 bit 3
DEF EVENT_BEAT_ROUTE_19_TRAINER_3                EQU EVENT_GRAVEYARD_BASE + 4   ; byte 47 bit 4
DEF EVENT_BEAT_ROUTE_19_TRAINER_4                EQU EVENT_GRAVEYARD_BASE + 5   ; byte 47 bit 5
DEF EVENT_BEAT_ROUTE_19_TRAINER_5                EQU EVENT_GRAVEYARD_BASE + 6   ; byte 47 bit 6
DEF EVENT_BEAT_ROUTE_19_TRAINER_6                EQU EVENT_GRAVEYARD_BASE + 7   ; byte 47 bit 7
DEF EVENT_BEAT_ROUTE_19_TRAINER_7                EQU EVENT_GRAVEYARD_BASE + 8   ; byte 48 bit 0
DEF EVENT_BEAT_ROUTE_19_TRAINER_8                EQU EVENT_GRAVEYARD_BASE + 9   ; byte 48 bit 1
DEF EVENT_BEAT_ROUTE_19_TRAINER_9                EQU EVENT_GRAVEYARD_BASE + 10  ; byte 48 bit 2

; -- Route20 (unreachable)
DEF EVENT_IN_SEAFOAM_ISLANDS                     EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0
DEF EVENT_BEAT_ROUTE_20_TRAINER_0                EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_BEAT_ROUTE_20_TRAINER_1                EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2
DEF EVENT_BEAT_ROUTE_20_TRAINER_2                EQU EVENT_GRAVEYARD_BASE + 3   ; byte 47 bit 3
DEF EVENT_BEAT_ROUTE_20_TRAINER_3                EQU EVENT_GRAVEYARD_BASE + 4   ; byte 47 bit 4
DEF EVENT_BEAT_ROUTE_20_TRAINER_4                EQU EVENT_GRAVEYARD_BASE + 5   ; byte 47 bit 5
DEF EVENT_BEAT_ROUTE_20_TRAINER_5                EQU EVENT_GRAVEYARD_BASE + 6   ; byte 47 bit 6
DEF EVENT_BEAT_ROUTE_20_TRAINER_6                EQU EVENT_GRAVEYARD_BASE + 7   ; byte 47 bit 7
DEF EVENT_BEAT_ROUTE_20_TRAINER_7                EQU EVENT_GRAVEYARD_BASE + 8   ; byte 48 bit 0
DEF EVENT_BEAT_ROUTE_20_TRAINER_8                EQU EVENT_GRAVEYARD_BASE + 9   ; byte 48 bit 1
DEF EVENT_BEAT_ROUTE_20_TRAINER_9                EQU EVENT_GRAVEYARD_BASE + 10  ; byte 48 bit 2
DEF EVENT_SEAFOAM3_BOULDER1_DOWN_HOLE            EQU EVENT_GRAVEYARD_BASE + 11  ; byte 48 bit 3
DEF EVENT_SEAFOAM3_BOULDER2_DOWN_HOLE            EQU EVENT_GRAVEYARD_BASE + 12  ; byte 48 bit 4
DEF EVENT_SEAFOAM4_BOULDER1_DOWN_HOLE            EQU EVENT_GRAVEYARD_BASE + 13  ; byte 48 bit 5
DEF EVENT_SEAFOAM4_BOULDER2_DOWN_HOLE            EQU EVENT_GRAVEYARD_BASE + 14  ; byte 48 bit 6

; -- Route21 (unreachable)
DEF EVENT_BEAT_ROUTE_21_TRAINER_0                EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_BEAT_ROUTE_21_TRAINER_1                EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2
DEF EVENT_BEAT_ROUTE_21_TRAINER_2                EQU EVENT_GRAVEYARD_BASE + 3   ; byte 47 bit 3
DEF EVENT_BEAT_ROUTE_21_TRAINER_3                EQU EVENT_GRAVEYARD_BASE + 4   ; byte 47 bit 4
DEF EVENT_BEAT_ROUTE_21_TRAINER_4                EQU EVENT_GRAVEYARD_BASE + 5   ; byte 47 bit 5
DEF EVENT_BEAT_ROUTE_21_TRAINER_5                EQU EVENT_GRAVEYARD_BASE + 6   ; byte 47 bit 6
DEF EVENT_BEAT_ROUTE_21_TRAINER_6                EQU EVENT_GRAVEYARD_BASE + 7   ; byte 47 bit 7
DEF EVENT_BEAT_ROUTE_21_TRAINER_7                EQU EVENT_GRAVEYARD_BASE + 8   ; byte 48 bit 0
DEF EVENT_BEAT_ROUTE_21_TRAINER_8                EQU EVENT_GRAVEYARD_BASE + 9   ; byte 48 bit 1

; -- Route22 (unreachable)
DEF EVENT_1ST_ROUTE22_RIVAL_BATTLE               EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0
DEF EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE          EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_BEAT_ROUTE22_RIVAL_2ND_BATTLE          EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2

; -- Route23 (unreachable)
DEF EVENT_PASSED_CASCADEBADGE_CHECK              EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0
DEF EVENT_PASSED_THUNDERBADGE_CHECK              EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_PASSED_RAINBOWBADGE_CHECK              EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2
DEF EVENT_PASSED_SOULBADGE_CHECK                 EQU EVENT_GRAVEYARD_BASE + 3   ; byte 47 bit 3
DEF EVENT_PASSED_MARSHBADGE_CHECK                EQU EVENT_GRAVEYARD_BASE + 4   ; byte 47 bit 4
DEF EVENT_PASSED_VOLCANOBADGE_CHECK              EQU EVENT_GRAVEYARD_BASE + 5   ; byte 47 bit 5
DEF EVENT_PASSED_EARTHBADGE_CHECK                EQU EVENT_GRAVEYARD_BASE + 6   ; byte 47 bit 6

; -- Route2Gate (unreachable)
DEF EVENT_GOT_HM05                               EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0

; -- Route4 (unreachable)
DEF EVENT_BEAT_ROUTE_4_TRAINER_0                 EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2

; -- Route8 (unreachable)
DEF EVENT_BEAT_ROUTE_8_TRAINER_0                 EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_BEAT_ROUTE_8_TRAINER_1                 EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2
DEF EVENT_BEAT_ROUTE_8_TRAINER_2                 EQU EVENT_GRAVEYARD_BASE + 3   ; byte 47 bit 3
DEF EVENT_BEAT_ROUTE_8_TRAINER_3                 EQU EVENT_GRAVEYARD_BASE + 4   ; byte 47 bit 4
DEF EVENT_BEAT_ROUTE_8_TRAINER_4                 EQU EVENT_GRAVEYARD_BASE + 5   ; byte 47 bit 5
DEF EVENT_BEAT_ROUTE_8_TRAINER_5                 EQU EVENT_GRAVEYARD_BASE + 6   ; byte 47 bit 6
DEF EVENT_BEAT_ROUTE_8_TRAINER_6                 EQU EVENT_GRAVEYARD_BASE + 7   ; byte 47 bit 7
DEF EVENT_BEAT_ROUTE_8_TRAINER_7                 EQU EVENT_GRAVEYARD_BASE + 8   ; byte 48 bit 0
DEF EVENT_BEAT_ROUTE_8_TRAINER_8                 EQU EVENT_GRAVEYARD_BASE + 9   ; byte 48 bit 1

; -- SSAnne1FRooms (unreachable)
DEF EVENT_BEAT_SS_ANNE_8_TRAINER_0               EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_BEAT_SS_ANNE_8_TRAINER_1               EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2
DEF EVENT_BEAT_SS_ANNE_8_TRAINER_2               EQU EVENT_GRAVEYARD_BASE + 3   ; byte 47 bit 3
DEF EVENT_BEAT_SS_ANNE_8_TRAINER_3               EQU EVENT_GRAVEYARD_BASE + 4   ; byte 47 bit 4

; -- SSAnne2FRooms (unreachable)
DEF EVENT_BEAT_SS_ANNE_9_TRAINER_0               EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_BEAT_SS_ANNE_9_TRAINER_1               EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2
DEF EVENT_BEAT_SS_ANNE_9_TRAINER_2               EQU EVENT_GRAVEYARD_BASE + 3   ; byte 47 bit 3
DEF EVENT_BEAT_SS_ANNE_9_TRAINER_3               EQU EVENT_GRAVEYARD_BASE + 4   ; byte 47 bit 4

; -- SafariZoneSecretHouse (unreachable)
DEF EVENT_GOT_HM03                               EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0

; -- SeafoamIslandsB1F (unreachable)
DEF EVENT_SEAFOAM2_BOULDER1_DOWN_HOLE            EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0
DEF EVENT_SEAFOAM2_BOULDER2_DOWN_HOLE            EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1

; -- SeafoamIslandsB4F (unreachable)
DEF EVENT_BEAT_ARTICUNO                          EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2

; -- SilphCo10F (unreachable)
DEF EVENT_SILPH_CO_10_UNLOCKED_DOOR              EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0
DEF EVENT_BEAT_SILPH_CO_10F_TRAINER_0            EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_BEAT_SILPH_CO_10F_TRAINER_1            EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2

; -- SilphCo11F (unreachable)
DEF EVENT_GOT_MASTER_BALL                        EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0
DEF EVENT_SILPH_CO_11_UNLOCKED_DOOR              EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_BEAT_SILPH_CO_11F_TRAINER_0            EQU EVENT_GRAVEYARD_BASE + 4   ; byte 47 bit 4
DEF EVENT_BEAT_SILPH_CO_11F_TRAINER_1            EQU EVENT_GRAVEYARD_BASE + 5   ; byte 47 bit 5

; -- SilphCo2F (unreachable)
DEF EVENT_GOT_TM36                               EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0
DEF EVENT_SILPH_CO_2_UNLOCKED_DOOR1              EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_BEAT_SILPH_CO_2F_TRAINER_0             EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2
DEF EVENT_BEAT_SILPH_CO_2F_TRAINER_1             EQU EVENT_GRAVEYARD_BASE + 3   ; byte 47 bit 3
DEF EVENT_BEAT_SILPH_CO_2F_TRAINER_2             EQU EVENT_GRAVEYARD_BASE + 4   ; byte 47 bit 4
DEF EVENT_BEAT_SILPH_CO_2F_TRAINER_3             EQU EVENT_GRAVEYARD_BASE + 5   ; byte 47 bit 5
DEF EVENT_SILPH_CO_2_UNLOCKED_DOOR2              EQU EVENT_GRAVEYARD_BASE + 6   ; byte 47 bit 6

; -- SilphCo3F (unreachable)
DEF EVENT_SILPH_CO_3_UNLOCKED_DOOR1              EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0
DEF EVENT_SILPH_CO_3_UNLOCKED_DOOR2              EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_BEAT_SILPH_CO_3F_TRAINER_0             EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2
DEF EVENT_BEAT_SILPH_CO_3F_TRAINER_1             EQU EVENT_GRAVEYARD_BASE + 3   ; byte 47 bit 3

; -- SilphCo4F (unreachable)
DEF EVENT_SILPH_CO_4_UNLOCKED_DOOR1              EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0
DEF EVENT_SILPH_CO_4_UNLOCKED_DOOR2              EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_BEAT_SILPH_CO_4F_TRAINER_0             EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2
DEF EVENT_BEAT_SILPH_CO_4F_TRAINER_1             EQU EVENT_GRAVEYARD_BASE + 3   ; byte 47 bit 3
DEF EVENT_BEAT_SILPH_CO_4F_TRAINER_2             EQU EVENT_GRAVEYARD_BASE + 4   ; byte 47 bit 4

; -- SilphCo5F (unreachable)
DEF EVENT_SILPH_CO_5_UNLOCKED_DOOR1              EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0
DEF EVENT_SILPH_CO_5_UNLOCKED_DOOR2              EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_BEAT_SILPH_CO_5F_TRAINER_0             EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2
DEF EVENT_BEAT_SILPH_CO_5F_TRAINER_1             EQU EVENT_GRAVEYARD_BASE + 3   ; byte 47 bit 3
DEF EVENT_BEAT_SILPH_CO_5F_TRAINER_2             EQU EVENT_GRAVEYARD_BASE + 4   ; byte 47 bit 4
DEF EVENT_BEAT_SILPH_CO_5F_TRAINER_3             EQU EVENT_GRAVEYARD_BASE + 5   ; byte 47 bit 5
DEF EVENT_SILPH_CO_5_UNLOCKED_DOOR3              EQU EVENT_GRAVEYARD_BASE + 6   ; byte 47 bit 6

; -- SilphCo6F (unreachable)
DEF EVENT_SILPH_CO_6_UNLOCKED_DOOR               EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0
DEF EVENT_BEAT_SILPH_CO_6F_TRAINER_0             EQU EVENT_GRAVEYARD_BASE + 6   ; byte 47 bit 6
DEF EVENT_BEAT_SILPH_CO_6F_TRAINER_1             EQU EVENT_GRAVEYARD_BASE + 7   ; byte 47 bit 7
DEF EVENT_BEAT_SILPH_CO_6F_TRAINER_2             EQU EVENT_GRAVEYARD_BASE + 8   ; byte 48 bit 0

; -- SilphCo7F (unreachable)
DEF EVENT_BEAT_SILPH_CO_RIVAL                    EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0
DEF EVENT_SILPH_CO_7_UNLOCKED_DOOR1              EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_SILPH_CO_7_UNLOCKED_DOOR2              EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2
DEF EVENT_SILPH_CO_7_UNLOCKED_DOOR3              EQU EVENT_GRAVEYARD_BASE + 3   ; byte 47 bit 3
DEF EVENT_BEAT_SILPH_CO_7F_TRAINER_0             EQU EVENT_GRAVEYARD_BASE + 5   ; byte 47 bit 5
DEF EVENT_BEAT_SILPH_CO_7F_TRAINER_1             EQU EVENT_GRAVEYARD_BASE + 6   ; byte 47 bit 6
DEF EVENT_BEAT_SILPH_CO_7F_TRAINER_2             EQU EVENT_GRAVEYARD_BASE + 7   ; byte 47 bit 7
DEF EVENT_BEAT_SILPH_CO_7F_TRAINER_3             EQU EVENT_GRAVEYARD_BASE + 8   ; byte 48 bit 0

; -- SilphCo8F (unreachable)
DEF EVENT_SILPH_CO_8_UNLOCKED_DOOR               EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0
DEF EVENT_BEAT_SILPH_CO_8F_TRAINER_0             EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2
DEF EVENT_BEAT_SILPH_CO_8F_TRAINER_1             EQU EVENT_GRAVEYARD_BASE + 3   ; byte 47 bit 3
DEF EVENT_BEAT_SILPH_CO_8F_TRAINER_2             EQU EVENT_GRAVEYARD_BASE + 4   ; byte 47 bit 4

; -- SilphCo9F (unreachable)
DEF EVENT_SILPH_CO_9_UNLOCKED_DOOR1              EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0
DEF EVENT_SILPH_CO_9_UNLOCKED_DOOR2              EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1
DEF EVENT_BEAT_SILPH_CO_9F_TRAINER_0             EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2
DEF EVENT_BEAT_SILPH_CO_9F_TRAINER_1             EQU EVENT_GRAVEYARD_BASE + 3   ; byte 47 bit 3
DEF EVENT_BEAT_SILPH_CO_9F_TRAINER_2             EQU EVENT_GRAVEYARD_BASE + 4   ; byte 47 bit 4
DEF EVENT_SILPH_CO_9_UNLOCKED_DOOR3              EQU EVENT_GRAVEYARD_BASE + 5   ; byte 47 bit 5
DEF EVENT_SILPH_CO_9_UNLOCKED_DOOR4              EQU EVENT_GRAVEYARD_BASE + 6   ; byte 47 bit 6

; -- VermilionCity (unreachable)
DEF EVENT_WALKED_PAST_GUARD_AFTER_SS_ANNE_LEFT   EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0
DEF EVENT_SS_ANNE_LEFT                           EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1

; -- VermilionDock (unreachable)
DEF EVENT_GOT_HM01                               EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0
DEF EVENT_STARTED_WALKING_OUT_OF_DOCK            EQU EVENT_GRAVEYARD_BASE + 2   ; byte 47 bit 2
DEF EVENT_WALKED_OUT_OF_DOCK                     EQU EVENT_GRAVEYARD_BASE + 3   ; byte 47 bit 3

; -- ViridianCity (unreachable)
DEF EVENT_GOT_TM42                               EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0
DEF EVENT_VIRIDIAN_GYM_OPEN                      EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1

; -- ViridianMart (unreachable)
DEF EVENT_GOT_OAKS_PARCEL                        EQU EVENT_GRAVEYARD_BASE + 0   ; byte 47 bit 0
DEF EVENT_OAK_GOT_PARCEL                         EQU EVENT_GRAVEYARD_BASE + 1   ; byte 47 bit 1

; ==========================================================================
; Build-time invariants. Each encodes a consumer that would otherwise
; break silently on a renumber. The 334 asserts inside the `trainer` macro
; (macros/scripts/maps.asm) cover trainer bit alignment on top of these.
; ==========================================================================
ASSERT PERSISTENT_EVENTS_END < RUN_EVENTS_START
ASSERT RUN_EVENTS_START % 8 == 0
ASSERT RUN_EVENTS_END % 8 == 7
ASSERT EVENT_GRAVEYARD_BASE > RUN_EVENTS_END
ASSERT EVENT_GRAVEYARD_BASE % 8 == 0
; ELEMENT PRISM first-time-ever flags must survive the run wipe:
ASSERT EVENT_PRISM_GYM1_SHOWN < RUN_EVENTS_START
ASSERT EVENT_PRISM_CHAMPION_SHOWN < RUN_EVENTS_START
; the whole layout must fit the pinned budget:
ASSERT EVENT_GRAVEYARD_BASE + 15 <= NUM_EVENTS

; -- runs that must stay consecutive --
; CinnabarGym: runtime index hGymGateIndex+2 off TRAINER_0 (cinnabar_gym_quiz.asm:106) and SetEventRange TRAINER_0..TRAINER_6 (CinnabarGym.asm:166)
ASSERT EVENT_BEAT_CINNABAR_GYM_TRAINER_6 - EVENT_BEAT_CINNABAR_GYM_TRAINER_0 == 6
; CinnabarGym: runtime index hBackupGymGateIndex off GATE0 (cinnabar_gym_quiz.asm:92)
ASSERT EVENT_CINNABAR_GYM_GATE4_UNLOCKED - EVENT_CINNABAR_GYM_GATE0_UNLOCKED == 4
; FuchsiaGym: SetEventRange TRAINER_0..TRAINER_5 (FuchsiaGym.asm:96) - slots 4 and 5 have no trainer but the range needs them
ASSERT EVENT_BEAT_FUCHSIA_GYM_TRAINER_5 - EVENT_BEAT_FUCHSIA_GYM_TRAINER_0 == 5
; VermilionGym: SetEventRange TRAINER_0..TRAINER_2 (VermilionGym.asm:98)
ASSERT EVENT_BEAT_VERMILION_GYM_TRAINER_2 - EVENT_BEAT_VERMILION_GYM_TRAINER_0 == 2
; __persistent__: RogueGymLeaderVictory computes GYM1 + (wGymLeaderNo - 1) at runtime (element_prism.asm:93)
ASSERT EVENT_PRISM_GYM8_SHOWN - EVENT_PRISM_GYM1_SHOWN == 7
; Route23: EventFlagBit walks CASCADE..EARTH and indexes EARTHBADGE+1 (Route23.asm:33,155-191)
ASSERT EVENT_PASSED_EARTHBADGE_CHECK - EVENT_PASSED_CASCADEBADGE_CHECK == 6
; FightingDojo: SetEventRange BEAT_KARATE_MASTER..TRAINER_3 (FightingDojo.asm:73)
ASSERT EVENT_BEAT_FIGHTING_DOJO_TRAINER_3 - EVENT_BEAT_KARATE_MASTER == 4
ASSERT EVENT_BEAT_CELADON_GYM_TRAINER_3 - EVENT_BEAT_CELADON_GYM_TRAINER_0 == 3 ; CeladonGym trainer block
ASSERT EVENT_BEAT_CERULEAN_GYM_TRAINER_3 - EVENT_BEAT_CERULEAN_GYM_TRAINER_0 == 3 ; CeruleanGym trainer block
ASSERT EVENT_BEAT_DIGLETTS_CAVE_TRAINER_4 - EVENT_BEAT_DIGLETTS_CAVE_TRAINER_0 == 4 ; DiglettsCave trainer block
ASSERT EVENT_BEAT_FIGHTING_DOJO_TRAINER_3 - EVENT_BEAT_FIGHTING_DOJO_TRAINER_0 == 3 ; FightingDojo trainer block
ASSERT EVENT_BEAT_FUCHSIA_GYM_TRAINER_3 - EVENT_BEAT_FUCHSIA_GYM_TRAINER_0 == 3 ; FuchsiaGym trainer block
ASSERT EVENT_BEAT_GAME_CORNER_TRAINER_4 - EVENT_BEAT_GAME_CORNER_TRAINER_0 == 4 ; GameCorner trainer block
ASSERT EVENT_BEAT_MT_MOON_1_TRAINER_4 - EVENT_BEAT_MT_MOON_1_TRAINER_0 == 4 ; MtMoon1F trainer block
ASSERT EVENT_BEAT_MT_MOON_3_TRAINER_3 - EVENT_BEAT_MT_MOON_3_TRAINER_0 == 3 ; MtMoonB2F trainer block
ASSERT EVENT_BEAT_PEWTER_GYM_TRAINER_3 - EVENT_BEAT_PEWTER_GYM_TRAINER_0 == 3 ; PewterGym trainer block
ASSERT EVENT_BEAT_MANSION_1_TRAINER_4 - EVENT_BEAT_MANSION_1_TRAINER_0 == 4 ; PokemonMansion1F trainer block
ASSERT EVENT_BEAT_MANSION_3_TRAINER_1 - EVENT_BEAT_MANSION_3_TRAINER_0 == 1 ; PokemonMansion3F trainer block
ASSERT EVENT_BEAT_MANSION_4_TRAINER_1 - EVENT_BEAT_MANSION_4_TRAINER_0 == 1 ; PokemonMansionB1F trainer block
ASSERT EVENT_BEAT_POKEMON_TOWER_2F_TRAINER_4 - EVENT_BEAT_POKEMON_TOWER_2F_TRAINER_0 == 4 ; PokemonTower2F trainer block
ASSERT EVENT_BEAT_POKEMONTOWER_3_TRAINER_2 - EVENT_BEAT_POKEMONTOWER_3_TRAINER_0 == 2 ; PokemonTower3F trainer block
ASSERT EVENT_BEAT_POKEMONTOWER_4_TRAINER_2 - EVENT_BEAT_POKEMONTOWER_4_TRAINER_0 == 2 ; PokemonTower4F trainer block
ASSERT EVENT_BEAT_POKEMONTOWER_5_TRAINER_3 - EVENT_BEAT_POKEMONTOWER_5_TRAINER_0 == 3 ; PokemonTower5F trainer block
ASSERT EVENT_BEAT_POKEMONTOWER_6_TRAINER_2 - EVENT_BEAT_POKEMONTOWER_6_TRAINER_0 == 2 ; PokemonTower6F trainer block
ASSERT EVENT_BEAT_POKEMONTOWER_7_TRAINER_4 - EVENT_BEAT_POKEMONTOWER_7_TRAINER_0 == 4 ; PokemonTower7F trainer block
ASSERT EVENT_BEAT_POWER_PLANT_TRAINER_4 - EVENT_BEAT_POWER_PLANT_TRAINER_0 == 4 ; PowerPlant trainer block
ASSERT EVENT_BEAT_ROCK_TUNNEL_1_TRAINER_4 - EVENT_BEAT_ROCK_TUNNEL_1_TRAINER_0 == 4 ; RockTunnel1F trainer block
ASSERT EVENT_BEAT_ROCK_TUNNEL_2_TRAINER_7 - EVENT_BEAT_ROCK_TUNNEL_2_TRAINER_0 == 7 ; RockTunnelB1F trainer block
ASSERT EVENT_BEAT_ROCKET_HIDEOUT_1_TRAINER_4 - EVENT_BEAT_ROCKET_HIDEOUT_1_TRAINER_0 == 4 ; RocketHideoutB1F trainer block
ASSERT EVENT_BEAT_ROCKET_HIDEOUT_3_TRAINER_1 - EVENT_BEAT_ROCKET_HIDEOUT_3_TRAINER_0 == 1 ; RocketHideoutB3F trainer block
ASSERT EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_2 - EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_0 == 2 ; RocketHideoutB4F trainer block
ASSERT EVENT_BEAT_ROUTE_1_TRAINER_4 - EVENT_BEAT_ROUTE_1_TRAINER_0 == 4 ; Route1 trainer block
ASSERT EVENT_BEAT_ROUTE_10_TRAINER_5 - EVENT_BEAT_ROUTE_10_TRAINER_0 == 5 ; Route10 trainer block
ASSERT EVENT_BEAT_ROUTE_11_TRAINER_9 - EVENT_BEAT_ROUTE_11_TRAINER_0 == 9 ; Route11 trainer block
ASSERT EVENT_BEAT_ROUTE_12_TRAINER_4 - EVENT_BEAT_ROUTE_12_TRAINER_0 == 4 ; Route12 trainer block
ASSERT EVENT_BEAT_ROUTE_13_TRAINER_4 - EVENT_BEAT_ROUTE_13_TRAINER_0 == 4 ; Route13 trainer block
ASSERT EVENT_BEAT_ROUTE_14_TRAINER_9 - EVENT_BEAT_ROUTE_14_TRAINER_0 == 9 ; Route14 trainer block
ASSERT EVENT_BEAT_ROUTE_15_TRAINER_4 - EVENT_BEAT_ROUTE_15_TRAINER_0 == 4 ; Route15 trainer block
ASSERT EVENT_BEAT_ROUTE_16_TRAINER_5 - EVENT_BEAT_ROUTE_16_TRAINER_0 == 5 ; Route16 trainer block
ASSERT EVENT_BEAT_ROUTE_17_TRAINER_4 - EVENT_BEAT_ROUTE_17_TRAINER_0 == 4 ; Route17 trainer block
ASSERT EVENT_BEAT_ROUTE_18_TRAINER_2 - EVENT_BEAT_ROUTE_18_TRAINER_0 == 2 ; Route18 trainer block
ASSERT EVENT_BEAT_ROUTE_19_TRAINER_9 - EVENT_BEAT_ROUTE_19_TRAINER_0 == 9 ; Route19 trainer block
ASSERT EVENT_BEAT_ROUTE_20_TRAINER_9 - EVENT_BEAT_ROUTE_20_TRAINER_0 == 9 ; Route20 trainer block
ASSERT EVENT_BEAT_ROUTE_21_TRAINER_8 - EVENT_BEAT_ROUTE_21_TRAINER_0 == 8 ; Route21 trainer block
ASSERT EVENT_BEAT_ROUTE_24_TRAINER_4 - EVENT_BEAT_ROUTE_24_TRAINER_0 == 4 ; Route24 trainer block
ASSERT EVENT_BEAT_ROUTE_25_TRAINER_4 - EVENT_BEAT_ROUTE_25_TRAINER_0 == 4 ; Route25 trainer block
ASSERT EVENT_BEAT_ROUTE_3_TRAINER_4 - EVENT_BEAT_ROUTE_3_TRAINER_0 == 4 ; Route3 trainer block
ASSERT EVENT_BEAT_ROUTE_5_TRAINER_4 - EVENT_BEAT_ROUTE_5_TRAINER_0 == 4 ; Route5 trainer block
ASSERT EVENT_BEAT_ROUTE_6_TRAINER_4 - EVENT_BEAT_ROUTE_6_TRAINER_0 == 4 ; Route6 trainer block
ASSERT EVENT_BEAT_ROUTE_8_TRAINER_8 - EVENT_BEAT_ROUTE_8_TRAINER_0 == 8 ; Route8 trainer block
ASSERT EVENT_BEAT_ROUTE_9_TRAINER_4 - EVENT_BEAT_ROUTE_9_TRAINER_0 == 4 ; Route9 trainer block
ASSERT EVENT_BEAT_SS_ANNE_8_TRAINER_3 - EVENT_BEAT_SS_ANNE_8_TRAINER_0 == 3 ; SSAnne1FRooms trainer block
ASSERT EVENT_BEAT_SS_ANNE_9_TRAINER_3 - EVENT_BEAT_SS_ANNE_9_TRAINER_0 == 3 ; SSAnne2FRooms trainer block
ASSERT EVENT_BEAT_SS_ANNE_10_TRAINER_4 - EVENT_BEAT_SS_ANNE_10_TRAINER_0 == 4 ; SSAnneB1FRooms trainer block
ASSERT EVENT_BEAT_SS_ANNE_5_TRAINER_4 - EVENT_BEAT_SS_ANNE_5_TRAINER_0 == 4 ; SSAnneBow trainer block
ASSERT EVENT_BEAT_SAFFRON_GYM_TRAINER_3 - EVENT_BEAT_SAFFRON_GYM_TRAINER_0 == 3 ; SaffronGym trainer block
ASSERT EVENT_BEAT_SEAFOAM_ISLANDS_1F_TRAINER_4 - EVENT_BEAT_SEAFOAM_ISLANDS_1F_TRAINER_0 == 4 ; SeafoamIslands1F trainer block
ASSERT EVENT_BEAT_SILPH_CO_10F_TRAINER_1 - EVENT_BEAT_SILPH_CO_10F_TRAINER_0 == 1 ; SilphCo10F trainer block
ASSERT EVENT_BEAT_SILPH_CO_11F_TRAINER_1 - EVENT_BEAT_SILPH_CO_11F_TRAINER_0 == 1 ; SilphCo11F trainer block
ASSERT EVENT_BEAT_SILPH_CO_2F_TRAINER_3 - EVENT_BEAT_SILPH_CO_2F_TRAINER_0 == 3 ; SilphCo2F trainer block
ASSERT EVENT_BEAT_SILPH_CO_3F_TRAINER_1 - EVENT_BEAT_SILPH_CO_3F_TRAINER_0 == 1 ; SilphCo3F trainer block
ASSERT EVENT_BEAT_SILPH_CO_4F_TRAINER_2 - EVENT_BEAT_SILPH_CO_4F_TRAINER_0 == 2 ; SilphCo4F trainer block
ASSERT EVENT_BEAT_SILPH_CO_5F_TRAINER_3 - EVENT_BEAT_SILPH_CO_5F_TRAINER_0 == 3 ; SilphCo5F trainer block
ASSERT EVENT_BEAT_SILPH_CO_6F_TRAINER_2 - EVENT_BEAT_SILPH_CO_6F_TRAINER_0 == 2 ; SilphCo6F trainer block
ASSERT EVENT_BEAT_SILPH_CO_7F_TRAINER_3 - EVENT_BEAT_SILPH_CO_7F_TRAINER_0 == 3 ; SilphCo7F trainer block
ASSERT EVENT_BEAT_SILPH_CO_8F_TRAINER_2 - EVENT_BEAT_SILPH_CO_8F_TRAINER_0 == 2 ; SilphCo8F trainer block
ASSERT EVENT_BEAT_SILPH_CO_9F_TRAINER_2 - EVENT_BEAT_SILPH_CO_9F_TRAINER_0 == 2 ; SilphCo9F trainer block
ASSERT EVENT_BEAT_UNDERGROUND_PATH_ROUTE5_TRAINER_4 - EVENT_BEAT_UNDERGROUND_PATH_ROUTE5_TRAINER_0 == 4 ; UndergroundPathRoute5 trainer block
ASSERT EVENT_BEAT_UNDERGROUND_PATH_WEST_EAST_TRAINER_4 - EVENT_BEAT_UNDERGROUND_PATH_WEST_EAST_TRAINER_0 == 4 ; UndergroundPathWestEast trainer block
ASSERT EVENT_BEAT_VERMILION_GYM_TRAINER_3 - EVENT_BEAT_VERMILION_GYM_TRAINER_0 == 3 ; VermilionGym trainer block
ASSERT EVENT_BEAT_VICTORY_ROAD_1_TRAINER_4 - EVENT_BEAT_VICTORY_ROAD_1_TRAINER_0 == 4 ; VictoryRoad1F trainer block
ASSERT EVENT_BEAT_MOLTRES - EVENT_BEAT_VICTORY_ROAD_2_TRAINER_0 == 5 ; VictoryRoad2F trainer block
ASSERT EVENT_BEAT_VICTORY_ROAD_3_TRAINER_3 - EVENT_BEAT_VICTORY_ROAD_3_TRAINER_0 == 3 ; VictoryRoad3F trainer block
ASSERT EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_4 - EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_0 == 4 ; ViridianForest trainer block
ASSERT EVENT_BEAT_VIRIDIAN_GYM_TRAINER_3 - EVENT_BEAT_VIRIDIAN_GYM_TRAINER_0 == 3 ; ViridianGym trainer block

; -- trainer runs folded into ONE byte read by an ALL_TRAINERS_MASK --
ASSERT (EVENT_BEAT_DIGLETTS_CAVE_TRAINER_0) / 8 == (EVENT_BEAT_DIGLETTS_CAVE_TRAINER_4) / 8 ; DiglettsCave
ASSERT (EVENT_BEAT_GAME_CORNER_TRAINER_0) / 8 == (EVENT_BEAT_GAME_CORNER_TRAINER_4) / 8 ; GameCorner
ASSERT (EVENT_BEAT_MT_MOON_1_TRAINER_0) / 8 == (EVENT_BEAT_MT_MOON_1_TRAINER_4) / 8 ; MtMoon1F
ASSERT (EVENT_BEAT_MANSION_1_TRAINER_0) / 8 == (EVENT_BEAT_MANSION_1_TRAINER_4) / 8 ; PokemonMansion1F
ASSERT (EVENT_BEAT_POKEMON_TOWER_2F_TRAINER_0) / 8 == (EVENT_BEAT_POKEMON_TOWER_2F_TRAINER_4) / 8 ; PokemonTower2F
ASSERT (EVENT_BEAT_POKEMONTOWER_7_TRAINER_0) / 8 == (EVENT_BEAT_POKEMONTOWER_7_TRAINER_4) / 8 ; PokemonTower7F
ASSERT (EVENT_BEAT_POWER_PLANT_TRAINER_0) / 8 == (EVENT_BEAT_POWER_PLANT_TRAINER_4) / 8 ; PowerPlant
ASSERT (EVENT_BEAT_ROCK_TUNNEL_1_TRAINER_0) / 8 == (EVENT_BEAT_ROCK_TUNNEL_1_TRAINER_4) / 8 ; RockTunnel1F
ASSERT (EVENT_BEAT_ROCKET_HIDEOUT_1_TRAINER_0) / 8 == (EVENT_BEAT_ROCKET_HIDEOUT_1_TRAINER_4) / 8 ; RocketHideoutB1F
ASSERT (EVENT_BEAT_ROUTE_1_TRAINER_0) / 8 == (EVENT_BEAT_ROUTE_1_TRAINER_4) / 8 ; Route1
ASSERT (EVENT_BEAT_ROUTE_12_TRAINER_0) / 8 == (EVENT_BEAT_ROUTE_12_TRAINER_4) / 8 ; Route12
ASSERT (EVENT_BEAT_ROUTE_13_TRAINER_0) / 8 == (EVENT_BEAT_ROUTE_13_TRAINER_4) / 8 ; Route13
ASSERT (EVENT_BEAT_ROUTE_15_TRAINER_0) / 8 == (EVENT_BEAT_ROUTE_15_TRAINER_4) / 8 ; Route15
ASSERT (EVENT_BEAT_ROUTE_17_TRAINER_0) / 8 == (EVENT_BEAT_ROUTE_17_TRAINER_4) / 8 ; Route17
ASSERT (EVENT_BEAT_ROUTE_25_TRAINER_0) / 8 == (EVENT_BEAT_ROUTE_25_TRAINER_4) / 8 ; Route25
ASSERT (EVENT_BEAT_ROUTE_3_TRAINER_0) / 8 == (EVENT_BEAT_ROUTE_3_TRAINER_4) / 8 ; Route3
ASSERT (EVENT_BEAT_ROUTE_5_TRAINER_0) / 8 == (EVENT_BEAT_ROUTE_5_TRAINER_4) / 8 ; Route5
ASSERT (EVENT_BEAT_ROUTE_6_TRAINER_0) / 8 == (EVENT_BEAT_ROUTE_6_TRAINER_4) / 8 ; Route6
ASSERT (EVENT_BEAT_ROUTE_9_TRAINER_0) / 8 == (EVENT_BEAT_ROUTE_9_TRAINER_4) / 8 ; Route9
ASSERT (EVENT_BEAT_SS_ANNE_5_TRAINER_0) / 8 == (EVENT_BEAT_SS_ANNE_5_TRAINER_4) / 8 ; SSAnneBow
ASSERT (EVENT_BEAT_SEAFOAM_ISLANDS_1F_TRAINER_0) / 8 == (EVENT_BEAT_SEAFOAM_ISLANDS_1F_TRAINER_4) / 8 ; SeafoamIslands1F
ASSERT (EVENT_BEAT_UNDERGROUND_PATH_WEST_EAST_TRAINER_0) / 8 == (EVENT_BEAT_UNDERGROUND_PATH_WEST_EAST_TRAINER_4) / 8 ; UndergroundPathWestEast
ASSERT (EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_0) / 8 == (EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_4) / 8 ; ViridianForest

; -- CheckBothEventsSet / CheckEitherEventSet pairs (keeps the small path) --
ASSERT (EVENT_GOT_TOWN_MAP) / 8 == (EVENT_ENTERED_BLUES_HOUSE) / 8
ASSERT (EVENT_GOT_HITMONLEE) / 8 == (EVENT_GOT_HITMONCHAN) / 8
ASSERT (EVENT_GOT_DOME_FOSSIL) / 8 == (EVENT_GOT_HELIX_FOSSIL) / 8
ASSERT (EVENT_SEAFOAM3_BOULDER1_DOWN_HOLE) / 8 == (EVENT_SEAFOAM3_BOULDER2_DOWN_HOLE) / 8
ASSERT (EVENT_SEAFOAM4_BOULDER1_DOWN_HOLE) / 8 == (EVENT_SEAFOAM4_BOULDER2_DOWN_HOLE) / 8
ASSERT (EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_0) / 8 == (EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_1) / 8

