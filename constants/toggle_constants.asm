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
	const TOGGLE_MINI_SAFFRON_PROF_PALM ; 0A

    toggle_consts_for REWARD_ROOM
    const TOGGLE_ROGUE_REWARD_POKEBALL_1 ; 0B
	const TOGGLE_ROGUE_REWARD_POKEBALL_2 ; 0C
	const TOGGLE_ROGUE_REWARD_POKEBALL_3 ; 0D
    const TOGGLE_STAGE_RANDOM_ITEM ; 0E
    const TOGGLE_ROGUE_TRADE_NPC ; 0F

	toggle_consts_for ROUTE_2
	const TOGGLE_ROUTE_2_ITEM_1 ; 10 X
	const TOGGLE_ROUTE_2_ITEM_2 ; 11 X

	toggle_consts_for ROUTE_4
	const TOGGLE_ROUTE_4_ITEM ; 12 X

	toggle_consts_for ROUTE_9
	const TOGGLE_ROUTE_9_ITEM ; 13 X

	toggle_consts_for ROUTE_12
	const TOGGLE_ROUTE_12_SNORLAX ; 14
	const TOGGLE_ROUTE_12_ITEM_1 ; 15 X
	const TOGGLE_ROUTE_12_ITEM_2 ; 16 X

	toggle_consts_for ROUTE_15
	const TOGGLE_ROUTE_15_ITEM ; 17 X

	toggle_consts_for ROUTE_16
	const TOGGLE_ROUTE_16_SNORLAX ; 18

	toggle_consts_for ROUTE_22
	const TOGGLE_ROUTE_22_RIVAL_1 ; 19
	const TOGGLE_ROUTE_22_RIVAL_2 ; 1A

	toggle_consts_for ROUTE_24
	const TOGGLE_NUGGET_BRIDGE_GUY ; 1B
	const TOGGLE_ROUTE_24_ITEM ; 1C X
    const TOGGLE_ROUTE_24_ITEM_2 ; 1D X

	toggle_consts_for ROUTE_25
	const TOGGLE_ROUTE_25_ITEM ; 1E X

	toggle_consts_for BLUES_HOUSE
	const TOGGLE_DAISY_SITTING ; 1F
	const TOGGLE_DAISY_WALKING ; 20
	const TOGGLE_TOWN_MAP ; 21

	toggle_consts_for OAKS_LAB
	const TOGGLE_ROGUE_STARTER_POKEBALL_1 ; 22
	const TOGGLE_ROGUE_STARTER_POKEBALL_2 ; 23
	const TOGGLE_ROGUE_STARTER_POKEBALL_3 ; 24
    const TOGGLE_OAKS_LAB_RIVAL ; 25

	toggle_consts_for VIRIDIAN_GYM
	const TOGGLE_VIRIDIAN_GYM_GIOVANNI ; 26
	const TOGGLE_VIRIDIAN_GYM_ITEM ; 27 X

	toggle_consts_for MUSEUM_1F
	const TOGGLE_OLD_AMBER ; 28

	toggle_consts_for CERULEAN_CAVE_1F
	const TOGGLE_CERULEAN_CAVE_1F_ITEM_1 ; 29 X
	const TOGGLE_CERULEAN_CAVE_1F_ITEM_2 ; 2A X
	const TOGGLE_CERULEAN_CAVE_1F_ITEM_3 ; 2B X

	toggle_consts_for POKEMON_TOWER_2F

	toggle_consts_for POKEMON_TOWER_3F
	const TOGGLE_POKEMON_TOWER_3F_ITEM ; 2C X

	toggle_consts_for POKEMON_TOWER_4F
	const TOGGLE_POKEMON_TOWER_4F_ITEM_1 ; 2D X
	const TOGGLE_POKEMON_TOWER_4F_ITEM_2 ; 2E X
	const TOGGLE_POKEMON_TOWER_4F_ITEM_3 ; 2F X

	toggle_consts_for POKEMON_TOWER_5F
	const TOGGLE_POKEMON_TOWER_5F_ITEM ; 30 X

	toggle_consts_for POKEMON_TOWER_6F
	const TOGGLE_POKEMON_TOWER_6F_ITEM_1 ; 31 X
	const TOGGLE_POKEMON_TOWER_6F_ITEM_2 ; 32 X

	toggle_consts_for POKEMON_TOWER_7F
	const TOGGLE_POKEMON_TOWER_7F_ROCKET_1 ; 33 X
	const TOGGLE_POKEMON_TOWER_7F_ROCKET_2 ; 34 X
	const TOGGLE_POKEMON_TOWER_7F_ROCKET_3 ; 35 X
	const TOGGLE_POKEMON_TOWER_7F_ROCKET_5 ; 36
	const TOGGLE_POKEMON_TOWER_7F_MR_FUJI ; 37

	toggle_consts_for MR_FUJIS_HOUSE
	const TOGGLE_MR_FUJIS_HOUSE_MR_FUJI ; 38

	toggle_consts_for CELADON_MANSION_ROOF_HOUSE
	const TOGGLE_CELADON_MANSION_EEVEE_GIFT ; 39

	toggle_consts_for GAME_CORNER
	const TOGGLE_GAME_CORNER_ROCKET ; 3A

	toggle_consts_for WARDENS_HOUSE
	const TOGGLE_WARDENS_HOUSE_ITEM ; 3B X

	toggle_consts_for POKEMON_MANSION_1F
	const TOGGLE_POKEMON_MANSION_1F_ITEM_1 ; 3C X
	const TOGGLE_POKEMON_MANSION_1F_ITEM_2 ; 3D X

	toggle_consts_for FIGHTING_DOJO
	const TOGGLE_FIGHTING_DOJO_RANDOM_ITEM ; 3E (Karate mini-boss stage item)

	toggle_consts_for SILPH_CO_1F
	const TOGGLE_SILPH_CO_1F_PROF_PALM ; 3F
	const TOGGLE_SILPH_CO_1F_RECEPTIONIST ; 40

	toggle_consts_for POWER_PLANT

	toggle_consts_for VICTORY_ROAD_2F
	const TOGGLE_MOLTRES ; 41 X
	const TOGGLE_VICTORY_ROAD_2F_ITEM_1 ; 42 X
	const TOGGLE_VICTORY_ROAD_2F_ITEM_2 ; 43 X
	const TOGGLE_VICTORY_ROAD_2F_ITEM_3 ; 44 X
	const TOGGLE_VICTORY_ROAD_2F_ITEM_4 ; 45 X
	const TOGGLE_VICTORY_ROAD_2F_BOULDER ; 46

	toggle_consts_for BILLS_HOUSE
	const TOGGLE_BILL_POKEMON ; 47
	const TOGGLE_BILL_1 ; 48
	const TOGGLE_BILL_2 ; 49

	toggle_consts_for VIRIDIAN_FOREST
	const TOGGLE_VIRIDIAN_FOREST_ITEM_1 ; 4A X
	const TOGGLE_VIRIDIAN_FOREST_ITEM_2 ; 4B X
	const TOGGLE_VIRIDIAN_FOREST_ITEM_3 ; 4C X
    

	toggle_consts_for MT_MOON_1F
	const TOGGLE_MT_MOON_1F_ITEM_1 ; 4D X
	const TOGGLE_MT_MOON_1F_ITEM_2 ; 4E X
	const TOGGLE_MT_MOON_1F_ITEM_3 ; 4F X
	const TOGGLE_MT_MOON_1F_ITEM_4 ; 50 X
	const TOGGLE_MT_MOON_1F_ITEM_5 ; 51 X
	const TOGGLE_MT_MOON_1F_ITEM_6 ; 52 X

	toggle_consts_for MT_MOON_B2F
	const TOGGLE_MT_MOON_B2F_FOSSIL_1 ; 53
	const TOGGLE_MT_MOON_B2F_FOSSIL_2 ; 54
	const TOGGLE_MT_MOON_B2F_ITEM_1 ; 55 X
	const TOGGLE_MT_MOON_B2F_ITEM_2 ; 56 X

	toggle_consts_for SS_ANNE_2F
	const TOGGLE_SS_ANNE_2F_RIVAL ; 57

	toggle_consts_for SS_ANNE_B1F
	const TOGGLE_SS_ANNE_B1F_CAPTAIN ; 58 X

	toggle_consts_for VICTORY_ROAD_3F
	const TOGGLE_VICTORY_ROAD_3F_ITEM_1 ; 59 X
	const TOGGLE_VICTORY_ROAD_3F_ITEM_2 ; 5A X
	const TOGGLE_VICTORY_ROAD_3F_BOULDER ; 5B

	toggle_consts_for ROCKET_HIDEOUT_B1F
	const TOGGLE_ROCKET_HIDEOUT_B1F_ITEM_1 ; 5C X
	const TOGGLE_ROCKET_HIDEOUT_B1F_ITEM_2 ; 5D X

	toggle_consts_for ROCKET_HIDEOUT_B2F
	const TOGGLE_ROCKET_HIDEOUT_B2F_ITEM_1 ; 5E X
	const TOGGLE_ROCKET_HIDEOUT_B2F_ITEM_2 ; 5F X
	const TOGGLE_ROCKET_HIDEOUT_B2F_ITEM_3 ; 60 X
	const TOGGLE_ROCKET_HIDEOUT_B2F_ITEM_4 ; 61 X

	toggle_consts_for ROCKET_HIDEOUT_B3F
	const TOGGLE_ROCKET_HIDEOUT_B3F_ITEM_1 ; 62 X
	const TOGGLE_ROCKET_HIDEOUT_B3F_ITEM_2 ; 63 X

	toggle_consts_for ROCKET_HIDEOUT_B4F
	const TOGGLE_ROCKET_HIDEOUT_B4F_GIOVANNI ; 64
	const TOGGLE_ROCKET_HIDEOUT_B4F_ITEM_1 ; 65 X
	const TOGGLE_ROCKET_HIDEOUT_B4F_ITEM_2 ; 66 X
	const TOGGLE_ROCKET_HIDEOUT_B4F_ITEM_3 ; 67 X
	const TOGGLE_ROCKET_HIDEOUT_B4F_ITEM_4 ; 68
	const TOGGLE_ROCKET_HIDEOUT_B4F_ITEM_5 ; 69

	toggle_consts_for SILPH_CO_2F
	const TOGGLE_SILPH_CO_2F_1 ; 6A X
	const TOGGLE_SILPH_CO_2F_2 ; 6B
	const TOGGLE_SILPH_CO_2F_3 ; 6C
	const TOGGLE_SILPH_CO_2F_4 ; 6D
	const TOGGLE_SILPH_CO_2F_5 ; 6E

	toggle_consts_for SILPH_CO_3F
	const TOGGLE_SILPH_CO_3F_1 ; 6F
	const TOGGLE_SILPH_CO_3F_2 ; 70
	const TOGGLE_SILPH_CO_3F_ITEM ; 71 X

	toggle_consts_for SILPH_CO_4F
	const TOGGLE_SILPH_CO_4F_1 ; 72
	const TOGGLE_SILPH_CO_4F_2 ; 73
	const TOGGLE_SILPH_CO_4F_3 ; 74
	const TOGGLE_SILPH_CO_4F_ITEM_1 ; 75 X
	const TOGGLE_SILPH_CO_4F_ITEM_2 ; 76 X
	const TOGGLE_SILPH_CO_4F_ITEM_3 ; 77 X

	toggle_consts_for SILPH_CO_5F
	const TOGGLE_SILPH_CO_5F_1 ; 78
	const TOGGLE_SILPH_CO_5F_2 ; 79
	const TOGGLE_SILPH_CO_5F_3 ; 7A
	const TOGGLE_SILPH_CO_5F_4 ; 7B
	const TOGGLE_SILPH_CO_5F_ITEM_1 ; 7C X
	const TOGGLE_SILPH_CO_5F_ITEM_2 ; 7D X
	const TOGGLE_SILPH_CO_5F_ITEM_3 ; 7E X

	toggle_consts_for SILPH_CO_6F
	const TOGGLE_SILPH_CO_6F_1 ; 7F
	const TOGGLE_SILPH_CO_6F_2 ; 80
	const TOGGLE_SILPH_CO_6F_3 ; 81
	const TOGGLE_SILPH_CO_6F_ITEM_1 ; 82 X
	const TOGGLE_SILPH_CO_6F_ITEM_2 ; 83 X

	toggle_consts_for SILPH_CO_7F
	const TOGGLE_SILPH_CO_7F_1 ; 84
	const TOGGLE_SILPH_CO_7F_2 ; 85
	const TOGGLE_SILPH_CO_7F_3 ; 86
	const TOGGLE_SILPH_CO_7F_4 ; 87
	const TOGGLE_SILPH_CO_7F_RIVAL ; 88
	const TOGGLE_SILPH_CO_7F_ITEM_1 ; 89 X
	const TOGGLE_SILPH_CO_7F_ITEM_2 ; 8A X
	const TOGGLE_SILPH_CO_7F_8 ; 8B X

	toggle_consts_for SILPH_CO_8F
	const TOGGLE_SILPH_CO_8F_1 ; 8C
	const TOGGLE_SILPH_CO_8F_2 ; 8D
	const TOGGLE_SILPH_CO_8F_3 ; 8E

	toggle_consts_for SILPH_CO_9F
	const TOGGLE_SILPH_CO_9F_1 ; 8F
	const TOGGLE_SILPH_CO_9F_2 ; 90
	const TOGGLE_SILPH_CO_9F_3 ; 91

	toggle_consts_for SILPH_CO_10F
	const TOGGLE_SILPH_CO_10F_1 ; 92
	const TOGGLE_SILPH_CO_10F_2 ; 93
	const TOGGLE_SILPH_CO_10F_3 ; 94 X
	const TOGGLE_SILPH_CO_10F_ITEM_1 ; 95 X
	const TOGGLE_SILPH_CO_10F_ITEM_2 ; 96 X
	const TOGGLE_SILPH_CO_10F_ITEM_3 ; 97 X

	toggle_consts_for SILPH_CO_11F
	const TOGGLE_SILPH_CO_11F_1 ; 98
	const TOGGLE_SILPH_CO_11F_2 ; 99
	const TOGGLE_SILPH_CO_11F_3 ; 9A

	toggle_consts_for SILPH_CO_VR
	const TOGGLE_SILPH_CO_VR_1 ; 9B X

	toggle_consts_for POKEMON_MANSION_2F
	const TOGGLE_POKEMON_MANSION_2F_ITEM ; 9C X

	toggle_consts_for POKEMON_MANSION_3F
	const TOGGLE_POKEMON_MANSION_3F_ITEM_1 ; 9D X
	const TOGGLE_POKEMON_MANSION_3F_ITEM_2 ; 9E X

	toggle_consts_for POKEMON_MANSION_B1F
	const TOGGLE_POKEMON_MANSION_B1F_ITEM_1 ; 9F X
	const TOGGLE_POKEMON_MANSION_B1F_ITEM_2 ; A0 X
	const TOGGLE_POKEMON_MANSION_B1F_ITEM_3 ; A1 X
	const TOGGLE_POKEMON_MANSION_B1F_ITEM_4 ; A2 X
	const TOGGLE_POKEMON_MANSION_B1F_ITEM_5 ; A3 X

	toggle_consts_for SAFARI_ZONE_EAST
	const TOGGLE_SAFARI_ZONE_EAST_ITEM_1 ; A4 X
	const TOGGLE_SAFARI_ZONE_EAST_ITEM_2 ; A5 X
	const TOGGLE_SAFARI_ZONE_EAST_ITEM_3 ; A6 X
	const TOGGLE_SAFARI_ZONE_EAST_ITEM_4 ; A7 X

	toggle_consts_for SAFARI_ZONE_NORTH
	const TOGGLE_SAFARI_ZONE_NORTH_ITEM_1 ; A8 X
	const TOGGLE_SAFARI_ZONE_NORTH_ITEM_2 ; A9 X

	toggle_consts_for SAFARI_ZONE_WEST
	const TOGGLE_SAFARI_ZONE_WEST_ITEM_1 ; AA X
	const TOGGLE_SAFARI_ZONE_WEST_ITEM_2 ; AB X
	const TOGGLE_SAFARI_ZONE_WEST_ITEM_3 ; AC X
	const TOGGLE_SAFARI_ZONE_WEST_ITEM_4 ; AD X

	toggle_consts_for SAFARI_ZONE_CENTER
	const TOGGLE_SAFARI_ZONE_CENTER_ITEM ; AE X

	toggle_consts_for CERULEAN_CAVE_2F
	const TOGGLE_CERULEAN_CAVE_2F_ITEM_1 ; AF X
	const TOGGLE_CERULEAN_CAVE_2F_ITEM_2 ; B0 X
	const TOGGLE_CERULEAN_CAVE_2F_ITEM_3 ; B1 X

	toggle_consts_for CERULEAN_CAVE_B1F
	const TOGGLE_MEWTWO ; B2 X
	const TOGGLE_CERULEAN_CAVE_B1F_ITEM_1 ; B3 X
	const TOGGLE_CERULEAN_CAVE_B1F_ITEM_2 ; B4 X

	toggle_consts_for VICTORY_ROAD_1F
	const TOGGLE_VICTORY_ROAD_1F_ITEM_1 ; B5 X
	const TOGGLE_VICTORY_ROAD_1F_ITEM_2 ; B6 X

	toggle_consts_for CHAMPIONS_ROOM
	const TOGGLE_CHAMPIONS_ROOM_OAK ; B7
; Lance and Oak as alternate Champions (Phase 7e). Appended directly after the
; map's existing single entry, NOT at the file's end like the Johto gym guides:
; ToggleableObjectMapPointers holds exactly ONE pointer per map, and
; MarkTownVisitedAndLoadToggleableObjects walks forward from it only while the
; map id byte keeps matching, so an existing map's toggle block must stay ONE
; contiguous run in data/maps/toggleable_objects.asm. There is no way to add
; to it except in place. This renumbers every later TOGGLE_* constant, which
; is safe: nothing outside these two files reads a TOGGLE_* value as a literal.
	const TOGGLE_CHAMPIONS_ROOM_RIVAL ; B8
	const TOGGLE_CHAMPIONS_ROOM_LANCE ; B9
	const TOGGLE_CHAMPIONS_ROOM_OAK_CHAMPION ; BA

	toggle_consts_for SEAFOAM_ISLANDS_1F
	const TOGGLE_SEAFOAM_ISLANDS_1F_BOULDER_1 ; BB
	const TOGGLE_SEAFOAM_ISLANDS_1F_BOULDER_2 ; BC

	toggle_consts_for SEAFOAM_ISLANDS_B1F
	const TOGGLE_SEAFOAM_ISLANDS_B1F_BOULDER_1 ; BD
	const TOGGLE_SEAFOAM_ISLANDS_B1F_BOULDER_2 ; BE

	toggle_consts_for SEAFOAM_ISLANDS_B2F
	const TOGGLE_SEAFOAM_ISLANDS_B2F_BOULDER_1 ; BF
	const TOGGLE_SEAFOAM_ISLANDS_B2F_BOULDER_2 ; C0

	toggle_consts_for SEAFOAM_ISLANDS_B3F
	const TOGGLE_SEAFOAM_ISLANDS_B3F_BOULDER_1 ; C1
	const TOGGLE_SEAFOAM_ISLANDS_B3F_BOULDER_2 ; C2
	const TOGGLE_SEAFOAM_ISLANDS_B3F_BOULDER_3 ; C3
	const TOGGLE_SEAFOAM_ISLANDS_B3F_BOULDER_4 ; C4

	toggle_consts_for SEAFOAM_ISLANDS_B4F
	const TOGGLE_SEAFOAM_ISLANDS_B4F_BOULDER_1 ; C5
	const TOGGLE_SEAFOAM_ISLANDS_B4F_BOULDER_2 ; C6
	const TOGGLE_ARTICUNO ; C7 X
    
    toggle_consts_for INDIGO_PLATEAU_LOBBY
    const TOGGLE_PC_PSYCHIC ; C8, ; D6
	const TOGGLE_PC_WITCH ; C9, ; D7
	const TOGGLE_PC_POKESALESMAN ; CA, ; D8
    const TOGGLE_PC_TRADENERD ; CB, ; D9
    const TOGGLE_PC_MOVETUTOR ; CC, ; DA
    const TOGGLE_PC_DOOR2_SIGN ; CD, ; DB

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
	; Stage-event NPCs (Phase 7 rollout) stay commented too, for the same
	; reason slots 1-5 do: IsObjectHidden's WildAreaStageMapTable fast path
	; (.checkMaybeRoguePB in engine/overworld/toggleable_objects.asm) now
	; resolves slots 6/7 to TOGGLE_WILD_AREA_NPC_1/2 directly for any map in
	; WildAreaStageMapTable, the same way .checkMaybeRoguePG already does for
	; slots 1-5 - so this per-map table is never consulted for them either.

	toggle_consts_for PROCEDURAL_CAVE_1
    const TOGGLE_WILD_AREA_BOSS ; CE       ; slot 1 (first object_event)
	const TOGGLE_WILD_AREA_POKEBALL_1 ; CF ; slot 2
	const TOGGLE_WILD_AREA_POKEBALL_2 ; D0 ; slot 3
	const TOGGLE_WILD_AREA_POKEBALL_3 ; D1 ; slot 4
	const TOGGLE_WILD_AREA_POKEBALL_4 ; D2 ; slot 5
	; Phase 7b stage-event NPCs. Unlike slots 1-5, these need NO new branch in
	; IsObjectHidden: its hardcoded wild-area mapping only covers slots 1-5,
	; and slots 6+ fall through .checkMaybeGenericRoguePB, which tests
	; IsRogueStageMap - PROCEDURAL_CAVE_1 is in WildAreaStageMapTable but NOT
	; in RogueStageMapTable, so the cave lands in .normalCheck and is resolved
	; from wToggleableObjectList, i.e. from these constants. (The Facility
	; needed its own branch precisely because its slots 6-9 collided with the
	; generic rogue-stage reward meanings.)
	const TOGGLE_WILD_AREA_NPC_1 ; D3      ; slot 6
	const TOGGLE_WILD_AREA_NPC_2 ; D4      ; slot 7

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
	const TOGGLE_FACILITY_FAKE_BALL_1 ; D5  ; slot 6
	const TOGGLE_FACILITY_FAKE_BALL_2 ; D6  ; slot 7
	const TOGGLE_FACILITY_FAKE_BALL_3 ; D7  ; slot 8
	const TOGGLE_FACILITY_FAKE_BALL_4 ; D8  ; slot 9
	; Stage-event NPC pair (Phase 7 rollout), slots 10-11. Unlike the cave and
	; forest's shared TOGGLE_WILD_AREA_NPC_1/2 (resolved by a hardcoded
	; WildAreaStageMapTable fast path in IsObjectHidden), slots 10-11 are NOT
	; covered by any fast path - IsObjectHidden's slot dispatch chain stops at
	; 10, and even that one falls through to .normalCheck for the facility
	; (its slot 6-9 fake-ball branch only claims b-6 < 4). So these need real
	; entries, both here and in data/maps/toggleable_objects.asm's
	; PROCEDURAL_FACILITY block.
	const TOGGLE_FACILITY_NPC_1 ; D9        ; slot 10
	const TOGGLE_FACILITY_NPC_2 ; DA        ; slot 11

	toggle_consts_for PROCEDURAL_CEMETERY_1
	const TOGGLE_CEMETERY_1_POKEBALL ; DB
	const TOGGLE_CEMETERY_1_NPC_1 ; DC
	const TOGGLE_CEMETERY_1_NPC_2 ; DD

	toggle_consts_for PROCEDURAL_CEMETERY_2
	const TOGGLE_CEMETERY_2_POKEBALL ; DE
	const TOGGLE_CEMETERY_2_NPC_1 ; DF
	const TOGGLE_CEMETERY_2_NPC_2 ; E0

	toggle_consts_for PROCEDURAL_CEMETERY_3
	const TOGGLE_CEMETERY_3_POKEBALL ; E1
	const TOGGLE_CEMETERY_3_NPC_1 ; E2
	const TOGGLE_CEMETERY_3_NPC_2 ; E3

	toggle_consts_for PROCEDURAL_CEMETERY_4
	const TOGGLE_CEMETERY_4_POKEBALL ; E4
	const TOGGLE_CEMETERY_4_NPC_1 ; E5
	const TOGGLE_CEMETERY_4_NPC_2 ; E6

; Fuchsia Gym carries BOTH leader objects and hides one per run, so the
; Koga/Janine coin flip needs no map swap. APPENDED at the end of this file
; deliberately: toggle_consts_for records TOGGLEMAP{id}_ID = the running
; const_value, and data/maps/toggleable_objects.asm asserts
; TOGGLEMAP{id}_ID * 3 == its own byte offset, so the blocks in the two files
; must appear in the SAME ORDER. Appending renumbers nothing; inserting this
; block next to the other gyms would shift every later TOGGLE_* constant and
; require the same move in that file to stay in lockstep.
	toggle_consts_for FUCHSIA_GYM
	const TOGGLE_FUCHSIA_KOGA ; E7
	const TOGGLE_FUCHSIA_JANINE ; E8

; New Johto gyms. Each needs its OWN gym-guide toggle: the Kanto gyms hide
; TOGGLE_GYM_GUY, which belongs to PEWTER_CITY, and ToggleableObjectStates rows
; carry the map id, so reusing it from another map would hide Pewter City's
; object instead. Append each new gym here AND in the same order at the end of
; data/maps/toggleable_objects.asm.
	toggle_consts_for VIOLET_GYM
	const TOGGLE_VIOLET_GYM_GUIDE ; E9

	toggle_consts_for AZALEA_GYM
	const TOGGLE_AZALEA_GYM_GUIDE ; EA

	toggle_consts_for GOLDENROD_GYM
	const TOGGLE_GOLDENROD_GYM_GUIDE ; EB

	toggle_consts_for ECRUTEAK_GYM
	const TOGGLE_ECRUTEAK_GYM_GUIDE ; EC

	toggle_consts_for CIANWOOD_GYM
	const TOGGLE_CIANWOOD_GYM_GUIDE ; ED

	toggle_consts_for OLIVINE_GYM
	const TOGGLE_OLIVINE_GYM_GUIDE ; EE

	toggle_consts_for MAHOGANY_GYM
	const TOGGLE_MAHOGANY_GYM_GUIDE ; EF

	toggle_consts_for BLACKTHORN_GYM
	const TOGGLE_BLACKTHORN_GYM_GUIDE ; F0

; B1F keeps Palm separate from the stair scientist. Appended so no existing
; toggle id shifts; keep this block last in data/maps/toggleable_objects.asm.
	toggle_consts_for SILPH_CO_B1F
	const TOGGLE_SILPH_CO_B1F_SCIENTIST ; F1
	const TOGGLE_SILPH_CO_B1F_PROF_PALM ; F2
	const TOGGLE_SILPH_CO_B1F_LANCE ; F3
	const TOGGLE_SILPH_CO_B1F_ROCKET ; F4

	toggle_consts_for AI_LAIR
	const TOGGLE_AI_LAIR_OPPONENT ; F5

	toggle_consts_for PALMS_ROOM
	const TOGGLE_PALMS_ROOM_PROF_PALM ; F6
	const TOGGLE_PALMS_ROOM_LANCE ; F7

DEF NUM_TOGGLEABLE_OBJECTS EQU const_value
