DEF OFF EQU $11
DEF ON  EQU $15

MACRO toggle_consts_for
	DEF TOGGLEMAP{\1}_ID EQU const_value
	DEF TOGGLEMAP{\1}_NAME EQUS "\1"
ENDM

; ToggleableObjectStates indexes (see data/maps/toggleable_objects.asm)
; This lists the object_events that can be toggled by ShowObject/HideObject.
; The constants marked with an X are never used, because those object_events
; are not toggled on/off in any map's script.
; (The X-ed ones are either items or static Pokemon encounters that deactivate
; after battle and are detected in wToggleableObjectList.)

	const_def

	toggle_consts_for PALLET_TOWN
	const TOGGLE_PALLET_TOWN_OAK ; 00

	toggle_consts_for VIRIDIAN_CITY
	const TOGGLE_LYING_OLD_MAN ; 01
	const TOGGLE_OLD_MAN ; 02

	toggle_consts_for PEWTER_CITY
	const TOGGLE_MUSEUM_GUY ; 03
	const TOGGLE_GYM_GUY ; 04

	toggle_consts_for CERULEAN_CITY
	const TOGGLE_CERULEAN_RIVAL ; 05
	const TOGGLE_CERULEAN_ROCKET ; 06
	const TOGGLE_CERULEAN_GUARD_1 ; 07
	const TOGGLE_CERULEAN_CAVE_GUY ; 08
	const TOGGLE_CERULEAN_GUARD_2 ; 09

	; Reuse this ID for the intro-only Mini Saffron Palm.  Keeping the constant
	; value preserves every later toggleable-object ID.
	toggle_consts_for MINI_SAFFRON
	const TOGGLE_MINI_SAFFRON_PROF_PALM

    toggle_consts_for REWARD_ROOM
    const TOGGLE_ROGUE_REWARD_POKEBALL_1 ; 19
	const TOGGLE_ROGUE_REWARD_POKEBALL_2 ; 1A
	const TOGGLE_ROGUE_REWARD_POKEBALL_3 ; 1B
    const TOGGLE_STAGE_RANDOM_ITEM       ; 1C
    const TOGGLE_ROGUE_TRADE_NPC         ; 1D

	toggle_consts_for ROUTE_2
	const TOGGLE_ROUTE_2_ITEM_1 ; 1C X
	const TOGGLE_ROUTE_2_ITEM_2 ; 1D X

	toggle_consts_for ROUTE_4
	const TOGGLE_ROUTE_4_ITEM ; 1E X

	toggle_consts_for ROUTE_9
	const TOGGLE_ROUTE_9_ITEM ; 1F X

	toggle_consts_for ROUTE_12
	const TOGGLE_ROUTE_12_SNORLAX ; 20
	const TOGGLE_ROUTE_12_ITEM_1 ; 21 X
	const TOGGLE_ROUTE_12_ITEM_2 ; 22 X

	toggle_consts_for ROUTE_15
	const TOGGLE_ROUTE_15_ITEM ; 23 X

	toggle_consts_for ROUTE_16
	const TOGGLE_ROUTE_16_SNORLAX ; 24

	toggle_consts_for ROUTE_22
	const TOGGLE_ROUTE_22_RIVAL_1 ; 25
	const TOGGLE_ROUTE_22_RIVAL_2 ; 26

	toggle_consts_for ROUTE_24
	const TOGGLE_NUGGET_BRIDGE_GUY ; 27
	const TOGGLE_ROUTE_24_ITEM ; 28 X
    const TOGGLE_ROUTE_24_ITEM_2 ; 29 X

	toggle_consts_for ROUTE_25
	const TOGGLE_ROUTE_25_ITEM ; 2A X

	toggle_consts_for BLUES_HOUSE
	const TOGGLE_DAISY_SITTING ; 2B
	const TOGGLE_DAISY_WALKING ; 2C
	const TOGGLE_TOWN_MAP ; 2D

	toggle_consts_for OAKS_LAB
	const TOGGLE_ROGUE_STARTER_POKEBALL_1 ; 2E
	const TOGGLE_ROGUE_STARTER_POKEBALL_2 ; 2F
	const TOGGLE_ROGUE_STARTER_POKEBALL_3 ; 30
    const TOGGLE_OAKS_LAB_RIVAL ; 31

	toggle_consts_for VIRIDIAN_GYM
	const TOGGLE_VIRIDIAN_GYM_GIOVANNI ; 32
	const TOGGLE_VIRIDIAN_GYM_ITEM ; 33 X

	toggle_consts_for MUSEUM_1F
	const TOGGLE_OLD_AMBER ; 34

	toggle_consts_for CERULEAN_CAVE_1F
	const TOGGLE_CERULEAN_CAVE_1F_ITEM_1 ; 35 X
	const TOGGLE_CERULEAN_CAVE_1F_ITEM_2 ; 36 X
	const TOGGLE_CERULEAN_CAVE_1F_ITEM_3 ; 37 X

	toggle_consts_for POKEMON_TOWER_2F

	toggle_consts_for POKEMON_TOWER_3F
	const TOGGLE_POKEMON_TOWER_3F_ITEM ; 39 X

	toggle_consts_for POKEMON_TOWER_4F
	const TOGGLE_POKEMON_TOWER_4F_ITEM_1 ; 3A X
	const TOGGLE_POKEMON_TOWER_4F_ITEM_2 ; 3B X
	const TOGGLE_POKEMON_TOWER_4F_ITEM_3 ; 3C X

	toggle_consts_for POKEMON_TOWER_5F
	const TOGGLE_POKEMON_TOWER_5F_ITEM ; 3D X

	toggle_consts_for POKEMON_TOWER_6F
	const TOGGLE_POKEMON_TOWER_6F_ITEM_1 ; 3E X
	const TOGGLE_POKEMON_TOWER_6F_ITEM_2 ; 3F X

	toggle_consts_for POKEMON_TOWER_7F
	const TOGGLE_POKEMON_TOWER_7F_ROCKET_1 ; 40 X
	const TOGGLE_POKEMON_TOWER_7F_ROCKET_2 ; 41 X
	const TOGGLE_POKEMON_TOWER_7F_ROCKET_3 ; 42 X
	const TOGGLE_POKEMON_TOWER_7F_MR_FUJI ; 43

	toggle_consts_for MR_FUJIS_HOUSE
	const TOGGLE_MR_FUJIS_HOUSE_MR_FUJI ; 44

	toggle_consts_for CELADON_MANSION_ROOF_HOUSE
	const TOGGLE_CELADON_MANSION_EEVEE_GIFT ; 45

	toggle_consts_for GAME_CORNER
	const TOGGLE_GAME_CORNER_ROCKET ; 46

	toggle_consts_for WARDENS_HOUSE
	const TOGGLE_WARDENS_HOUSE_ITEM ; 47 X

	toggle_consts_for POKEMON_MANSION_1F
	const TOGGLE_POKEMON_MANSION_1F_ITEM_1 ; 48 X
	const TOGGLE_POKEMON_MANSION_1F_ITEM_2 ; 49 X

	toggle_consts_for FIGHTING_DOJO
	const TOGGLE_FIGHTING_DOJO_GIFT_1 ; 4A
	const TOGGLE_FIGHTING_DOJO_GIFT_2 ; 4B

	toggle_consts_for SILPH_CO_1F
	const TOGGLE_SILPH_CO_1F_PROF_PALM
	const TOGGLE_SILPH_CO_1F_RECEPTIONIST

	toggle_consts_for POWER_PLANT

	toggle_consts_for VICTORY_ROAD_2F
	const TOGGLE_MOLTRES ; 4D X
	const TOGGLE_VICTORY_ROAD_2F_ITEM_1 ; 4E X
	const TOGGLE_VICTORY_ROAD_2F_ITEM_2 ; 4F X
	const TOGGLE_VICTORY_ROAD_2F_ITEM_3 ; 50 X
	const TOGGLE_VICTORY_ROAD_2F_ITEM_4 ; 51 X
	const TOGGLE_VICTORY_ROAD_2F_BOULDER ; 52

	toggle_consts_for BILLS_HOUSE
	const TOGGLE_BILL_POKEMON ; 53
	const TOGGLE_BILL_1 ; 54
	const TOGGLE_BILL_2 ; 55

	toggle_consts_for VIRIDIAN_FOREST
	const TOGGLE_VIRIDIAN_FOREST_ITEM_1 ; 56 X
	const TOGGLE_VIRIDIAN_FOREST_ITEM_2 ; 57 X
	const TOGGLE_VIRIDIAN_FOREST_ITEM_3 ; 58 X
    

	toggle_consts_for MT_MOON_1F
	const TOGGLE_MT_MOON_1F_ITEM_1 ; 59 X
	const TOGGLE_MT_MOON_1F_ITEM_2 ; 5A X
	const TOGGLE_MT_MOON_1F_ITEM_3 ; 5B X
	const TOGGLE_MT_MOON_1F_ITEM_4 ; 5C X
	const TOGGLE_MT_MOON_1F_ITEM_5 ; 5D X
	const TOGGLE_MT_MOON_1F_ITEM_6 ; 5E X

	toggle_consts_for MT_MOON_B2F
	const TOGGLE_MT_MOON_B2F_FOSSIL_1 ; 5F
	const TOGGLE_MT_MOON_B2F_FOSSIL_2 ; 60
	const TOGGLE_MT_MOON_B2F_ITEM_1 ; 61 X
	const TOGGLE_MT_MOON_B2F_ITEM_2 ; 62 X

	toggle_consts_for SS_ANNE_2F
	const TOGGLE_SS_ANNE_2F_RIVAL ; 63

	toggle_consts_for SS_ANNE_B1F
	const TOGGLE_SS_ANNE_B1F_CAPTAIN ; 64 X

	toggle_consts_for VICTORY_ROAD_3F
	const TOGGLE_VICTORY_ROAD_3F_ITEM_1 ; 67 X
	const TOGGLE_VICTORY_ROAD_3F_ITEM_2 ; 68 X
	const TOGGLE_VICTORY_ROAD_3F_BOULDER ; 69

	toggle_consts_for ROCKET_HIDEOUT_B1F
	const TOGGLE_ROCKET_HIDEOUT_B1F_ITEM_1 ; 6D X
	const TOGGLE_ROCKET_HIDEOUT_B1F_ITEM_2 ; 6E X

	toggle_consts_for ROCKET_HIDEOUT_B2F
	const TOGGLE_ROCKET_HIDEOUT_B2F_ITEM_1 ; 6F X
	const TOGGLE_ROCKET_HIDEOUT_B2F_ITEM_2 ; 70 X
	const TOGGLE_ROCKET_HIDEOUT_B2F_ITEM_3 ; 71 X
	const TOGGLE_ROCKET_HIDEOUT_B2F_ITEM_4 ; 72 X

	toggle_consts_for ROCKET_HIDEOUT_B3F
	const TOGGLE_ROCKET_HIDEOUT_B3F_ITEM_1 ; 73 X
	const TOGGLE_ROCKET_HIDEOUT_B3F_ITEM_2 ; 74 X

	toggle_consts_for ROCKET_HIDEOUT_B4F
	const TOGGLE_ROCKET_HIDEOUT_B4F_GIOVANNI ; 75
	const TOGGLE_ROCKET_HIDEOUT_B4F_ITEM_1 ; 76 X
	const TOGGLE_ROCKET_HIDEOUT_B4F_ITEM_2 ; 77 X
	const TOGGLE_ROCKET_HIDEOUT_B4F_ITEM_3 ; 78 X
	const TOGGLE_ROCKET_HIDEOUT_B4F_ITEM_4 ; 79
	const TOGGLE_ROCKET_HIDEOUT_B4F_ITEM_5 ; 7A

	toggle_consts_for SILPH_CO_2F
	const TOGGLE_SILPH_CO_2F_1 ; 7B X
	const TOGGLE_SILPH_CO_2F_2 ; 7C
	const TOGGLE_SILPH_CO_2F_3 ; 7D
	const TOGGLE_SILPH_CO_2F_4 ; 7E
	const TOGGLE_SILPH_CO_2F_5 ; 7F

	toggle_consts_for SILPH_CO_3F
	const TOGGLE_SILPH_CO_3F_1 ; 80
	const TOGGLE_SILPH_CO_3F_2 ; 81
	const TOGGLE_SILPH_CO_3F_ITEM ; 82 X

	toggle_consts_for SILPH_CO_4F
	const TOGGLE_SILPH_CO_4F_1 ; 83
	const TOGGLE_SILPH_CO_4F_2 ; 84
	const TOGGLE_SILPH_CO_4F_3 ; 85
	const TOGGLE_SILPH_CO_4F_ITEM_1 ; 86 X
	const TOGGLE_SILPH_CO_4F_ITEM_2 ; 87 X
	const TOGGLE_SILPH_CO_4F_ITEM_3 ; 88 X

	toggle_consts_for SILPH_CO_5F
	const TOGGLE_SILPH_CO_5F_1 ; 89
	const TOGGLE_SILPH_CO_5F_2 ; 8A
	const TOGGLE_SILPH_CO_5F_3 ; 8B
	const TOGGLE_SILPH_CO_5F_4 ; 8C
	const TOGGLE_SILPH_CO_5F_ITEM_1 ; 8D X
	const TOGGLE_SILPH_CO_5F_ITEM_2 ; 8E X
	const TOGGLE_SILPH_CO_5F_ITEM_3 ; 8F X

	toggle_consts_for SILPH_CO_6F
	const TOGGLE_SILPH_CO_6F_1 ; 90
	const TOGGLE_SILPH_CO_6F_2 ; 91
	const TOGGLE_SILPH_CO_6F_3 ; 92
	const TOGGLE_SILPH_CO_6F_ITEM_1 ; 93 X
	const TOGGLE_SILPH_CO_6F_ITEM_2 ; 94 X

	toggle_consts_for SILPH_CO_7F
	const TOGGLE_SILPH_CO_7F_1 ; 95
	const TOGGLE_SILPH_CO_7F_2 ; 96
	const TOGGLE_SILPH_CO_7F_3 ; 97
	const TOGGLE_SILPH_CO_7F_4 ; 98
	const TOGGLE_SILPH_CO_7F_RIVAL ; 99
	const TOGGLE_SILPH_CO_7F_ITEM_1 ; 9A X
	const TOGGLE_SILPH_CO_7F_ITEM_2 ; 9B X
	const TOGGLE_SILPH_CO_7F_8 ; 9C X

	toggle_consts_for SILPH_CO_8F
	const TOGGLE_SILPH_CO_8F_1 ; 9D
	const TOGGLE_SILPH_CO_8F_2 ; 9E
	const TOGGLE_SILPH_CO_8F_3 ; 9F

	toggle_consts_for SILPH_CO_9F
	const TOGGLE_SILPH_CO_9F_1 ; A0
	const TOGGLE_SILPH_CO_9F_2 ; A1
	const TOGGLE_SILPH_CO_9F_3 ; A2

	toggle_consts_for SILPH_CO_10F
	const TOGGLE_SILPH_CO_10F_1 ; A3
	const TOGGLE_SILPH_CO_10F_2 ; A4
	const TOGGLE_SILPH_CO_10F_3 ; A5 X
	const TOGGLE_SILPH_CO_10F_ITEM_1 ; A6 X
	const TOGGLE_SILPH_CO_10F_ITEM_2 ; A7 X
	const TOGGLE_SILPH_CO_10F_ITEM_3 ; A8 X

	toggle_consts_for SILPH_CO_11F
	const TOGGLE_SILPH_CO_11F_1 ; A9
	const TOGGLE_SILPH_CO_11F_2 ; AA
	const TOGGLE_SILPH_CO_11F_3 ; AB

	toggle_consts_for SILPH_CO_VR
	const TOGGLE_SILPH_CO_VR_1 ; AC X

	toggle_consts_for POKEMON_MANSION_2F
	const TOGGLE_POKEMON_MANSION_2F_ITEM ; AD X

	toggle_consts_for POKEMON_MANSION_3F
	const TOGGLE_POKEMON_MANSION_3F_ITEM_1 ; AE X
	const TOGGLE_POKEMON_MANSION_3F_ITEM_2 ; AF X

	toggle_consts_for POKEMON_MANSION_B1F
	const TOGGLE_POKEMON_MANSION_B1F_ITEM_1 ; B0 X
	const TOGGLE_POKEMON_MANSION_B1F_ITEM_2 ; B1 X
	const TOGGLE_POKEMON_MANSION_B1F_ITEM_3 ; B2 X
	const TOGGLE_POKEMON_MANSION_B1F_ITEM_4 ; B3 X
	const TOGGLE_POKEMON_MANSION_B1F_ITEM_5 ; B4 X

	toggle_consts_for SAFARI_ZONE_EAST
	const TOGGLE_SAFARI_ZONE_EAST_ITEM_1 ; B5 X
	const TOGGLE_SAFARI_ZONE_EAST_ITEM_2 ; B6 X
	const TOGGLE_SAFARI_ZONE_EAST_ITEM_3 ; B7 X
	const TOGGLE_SAFARI_ZONE_EAST_ITEM_4 ; B8 X

	toggle_consts_for SAFARI_ZONE_NORTH
	const TOGGLE_SAFARI_ZONE_NORTH_ITEM_1 ; B9 X
	const TOGGLE_SAFARI_ZONE_NORTH_ITEM_2 ; BA X

	toggle_consts_for SAFARI_ZONE_WEST
	const TOGGLE_SAFARI_ZONE_WEST_ITEM_1 ; BB X
	const TOGGLE_SAFARI_ZONE_WEST_ITEM_2 ; BC X
	const TOGGLE_SAFARI_ZONE_WEST_ITEM_3 ; BD X
	const TOGGLE_SAFARI_ZONE_WEST_ITEM_4 ; BE X

	toggle_consts_for SAFARI_ZONE_CENTER
	const TOGGLE_SAFARI_ZONE_CENTER_ITEM ; BF X

	toggle_consts_for CERULEAN_CAVE_2F
	const TOGGLE_CERULEAN_CAVE_2F_ITEM_1 ; C0 X
	const TOGGLE_CERULEAN_CAVE_2F_ITEM_2 ; C1 X
	const TOGGLE_CERULEAN_CAVE_2F_ITEM_3 ; C2 X

	toggle_consts_for CERULEAN_CAVE_B1F
	const TOGGLE_MEWTWO ; C3 X
	const TOGGLE_CERULEAN_CAVE_B1F_ITEM_1 ; C4 X
	const TOGGLE_CERULEAN_CAVE_B1F_ITEM_2 ; C5 X

	toggle_consts_for VICTORY_ROAD_1F
	const TOGGLE_VICTORY_ROAD_1F_ITEM_1 ; C6 X
	const TOGGLE_VICTORY_ROAD_1F_ITEM_2 ; C7 X

	toggle_consts_for CHAMPIONS_ROOM
	const TOGGLE_CHAMPIONS_ROOM_OAK ; C8

	toggle_consts_for SEAFOAM_ISLANDS_1F
	const TOGGLE_SEAFOAM_ISLANDS_1F_BOULDER_1 ; C9
	const TOGGLE_SEAFOAM_ISLANDS_1F_BOULDER_2 ; CA

	toggle_consts_for SEAFOAM_ISLANDS_B1F
	const TOGGLE_SEAFOAM_ISLANDS_B1F_BOULDER_1 ; CB
	const TOGGLE_SEAFOAM_ISLANDS_B1F_BOULDER_2 ; CC

	toggle_consts_for SEAFOAM_ISLANDS_B2F
	const TOGGLE_SEAFOAM_ISLANDS_B2F_BOULDER_1 ; CD
	const TOGGLE_SEAFOAM_ISLANDS_B2F_BOULDER_2 ; CE

	toggle_consts_for SEAFOAM_ISLANDS_B3F
	const TOGGLE_SEAFOAM_ISLANDS_B3F_BOULDER_1 ; CF
	const TOGGLE_SEAFOAM_ISLANDS_B3F_BOULDER_2 ; D0
	const TOGGLE_SEAFOAM_ISLANDS_B3F_BOULDER_3 ; D1
	const TOGGLE_SEAFOAM_ISLANDS_B3F_BOULDER_4 ; D2

	toggle_consts_for SEAFOAM_ISLANDS_B4F
	const TOGGLE_SEAFOAM_ISLANDS_B4F_BOULDER_1 ; D3
	const TOGGLE_SEAFOAM_ISLANDS_B4F_BOULDER_2 ; D4
	const TOGGLE_ARTICUNO ; D5 X
    
    toggle_consts_for INDIGO_PLATEAU_LOBBY
    const TOGGLE_PC_PSYCHIC, ; D6
	const TOGGLE_PC_WITCH, ; D7
	const TOGGLE_PC_POKESALESMAN, ; D8
    const TOGGLE_PC_TRADENERD, ; D9
    const TOGGLE_PC_MOVETUTOR, ; DA
    const TOGGLE_PC_DOOR2_SIGN, ; DB

	; Wild area pokeballs (procedurally generated stages, e.g. ProceduralCave1) -
	; 4 independent random items, one per dead-end. Hardcoded slot check lives
	; in engine/overworld/toggleable_objects.asm's IsObjectHidden and
	; engine/events/pick_up_item.asm's RandomPickUpItem, same pattern as the
	; existing single TOGGLE_STAGE_RANDOM_ITEM but gated on the map being a
	; wild-area stage specifically, not the generic IsRogueStageMap check -
	; avoids colliding with Route1-style maps' existing slot 7-10 usage
	; (reward pokeballs / trade NPC). Still needs a toggleable_objects_for
	; block in data/maps/toggleable_objects.asm even though the hardcoded
	; bypass never actually reads it - assert_table_length enforces every
	; toggle const has a matching declared state.
	toggle_consts_for PROCEDURAL_FOREST
	;const TOGGLE_FOREST_BOSS         ; slot 1 = boss
	;const TOGGLE_FOREST_POKEBALL_1   ; slot 2
	;const TOGGLE_FOREST_POKEBALL_2   ; slot 3
	;const TOGGLE_FOREST_POKEBALL_3   ; slot 4
	;const TOGGLE_FOREST_POKEBALL_4   ; slot 5

	toggle_consts_for PROCEDURAL_CAVE_1
    const TOGGLE_WILD_AREA_BOSS       ; slot 1 (first object_event)
	const TOGGLE_WILD_AREA_POKEBALL_1 ; slot 2
	const TOGGLE_WILD_AREA_POKEBALL_2 ; slot 3
	const TOGGLE_WILD_AREA_POKEBALL_3 ; slot 4
	const TOGGLE_WILD_AREA_POKEBALL_4 ; slot 5

	; Facility reuses the cave's TOGGLE_WILD_AREA_* constants above (same
	; port-don't-reimplement pattern as PROCEDURAL_FOREST above) - still needs
	; a toggle_consts_for block even though every const here stays commented,
	; since data/maps/toggleable_objects.asm's toggleable_objects_for macro
	; asserts a matching TOGGLEMAP{id}_ID exists.
	toggle_consts_for PROCEDURAL_FACILITY
	;const TOGGLE_FACILITY_BOSS         ; slot 1 = boss
	;const TOGGLE_FACILITY_POKEBALL_1   ; slot 2
	;const TOGGLE_FACILITY_POKEBALL_2   ; slot 3
	;const TOGGLE_FACILITY_POKEBALL_3   ; slot 4
	;const TOGGLE_FACILITY_POKEBALL_4   ; slot 5

	toggle_consts_for PROCEDURAL_CEMETERY_1
	const TOGGLE_CEMETERY_1_POKEBALL

	toggle_consts_for PROCEDURAL_CEMETERY_2
	const TOGGLE_CEMETERY_2_POKEBALL

	toggle_consts_for PROCEDURAL_CEMETERY_3
	const TOGGLE_CEMETERY_3_POKEBALL

	toggle_consts_for PROCEDURAL_CEMETERY_4
	const TOGGLE_CEMETERY_4_POKEBALL

DEF NUM_TOGGLEABLE_OBJECTS EQU const_value
