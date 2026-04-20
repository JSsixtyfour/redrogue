; assigned class for each item and odds

; Item Groupings
const_def
	const HEALING            ; $00
	const STAT               ; $01
	const TM                 ; $02
	const MONEY              ; $03

DEF NUM_ITEM_GROUPS EQU const_value - 1

item_class_odds:
DEF item_pokeball_odds EQU 51
DEF item_greatball_odds EQU 77 + 51
DEF item_ultraball_odds EQU 76 + 77 + 51
DEF item_masterball_odds EQU 51 + 76 + 77 + 51

DEF NUM_HEALING_POKEBALL_CLASS EQU $6
DEF NUM_HEALING_GREATBALL_CLASS EQU $5
DEF NUM_HEALING_ULTRABALL_CLASS EQU $2
DEF NUM_HEALING_MASTERBALL_CLASS EQU $3

DEF NUM_TM_POKEBALL_CLASS EQU $A
DEF NUM_TM_GREATBALL_CLASS EQU $13
DEF NUM_TM_ULTRABALL_CLASS EQU $C
DEF NUM_TM_MASTERBALL_CLASS EQU $A

DEF NUM_MONEY_POKEBALL_CLASS EQU $0
DEF NUM_MONEY_GREATBALL_CLASS EQU $0
DEF NUM_MONEY_ULTRABALL_CLASS EQU $0
DEF NUM_MONEY_MASTERBALL_CLASS EQU $0

DEF NUM_STAT_POKEBALL_CLASS EQU $3
DEF NUM_STAT_GREATBALL_CLASS EQU $1
DEF NUM_STAT_ULTRABALL_CLASS EQU $4
DEF NUM_STAT_MASTERBALL_CLASS EQU $0

item_pokeball_classes::
dw healing_pokeball_class
dw stat_pokeball_class
dw tm_pokeball_class
dw money_pokeball_class

item_greatball_classes::
dw healing_greatball_class
dw tm_greatball_class
dw stat_greatball_class
dw healing_ultraball_class

item_ultraball_classes::
dw healing_ultraball_class
dw stat_ultraball_class
dw tm_ultraball_class
dw money_ultraball_class

item_masterball_classes::
dw healing_masterball_class
dw stat_masterball_class
dw tm_masterball_class
dw money_masterball_class

healing_classes:
table_width 1
healing_pokeball_class:
db ANTIDOTE
db 0x0
db BURN_HEAL
db 0x0
db ICE_HEAL
db 0x0
db AWAKENING 
db 0x0
db PARLYZ_HEAL
db 0x0
db POTION
db 0x0
db ETHER
db 0x0

healing_greatball_class:
db SUPER_POTION
db 0x0
db ELIXER
db 0x0
db LEMONADE
db 0x0
db SODA_POP
db 0x0
db FRESH_WATER
db 0x0
db FULL_HEAL
db 0x0

healing_ultraball_class:
db MAX_ETHER
db 0x0
db HYPER_POTION
db 0x0
db REVIVE
db 0x0

healing_masterball_class:
db FULL_RESTORE
db 0x0
db MAX_POTION
db 0x0
db MAX_REVIVE
db 0x0
db MAX_ELIXER
db 0x0

tm_classes:
table_width 1
tm_pokeball_class:
db TM_BIDE
db 0x0
db TM_RAZOR_WIND
db 0x0
db TM_PAY_DAY
db 0x0
db TM_COUNTER
db 0x0
db TM_RAGE
db 0x0
db TM_MIMIC
db 0x0
db TM_METRONOME
db 0x0
db TM_EGG_BOMB
db 0x0
db TM_PSYWAVE
db 0x0
db HM_CUT
db 0x0
db HM_FLASH
db 0x0

tm_greatball_class:
db TM_SKY_ATTACK
db 0x0
db TM_SUBSTITUTE
db 0x0
db TM_DRAGON_RAGE
db 0x0
db TM_MEGA_PUNCH
db 0x0
db TM_MEGA_KICK
db 0x0
db TM_HORN_DRILL
db 0x0
db TM_TAKE_DOWN
db 0x0
db TM_WATER_GUN
db 0x0
db TM_SEISMIC_TOSS
db 0x0
db TM_MEGA_DRAIN
db 0x0
db TM_SOLARBEAM
db 0x0
db TM_FISSURE
db 0x0
db TM_SWIFT
db 0x0
db TM_SKULL_BASH
db 0x0
db TM_SOFTBOILED
db 0x0
db TM_DREAM_EATER
db 0x0
db TM_REST
db 0x0
db TM_TRI_ATTACK
db 0x0
db HM_FLY
db 0x0
db HM_STRENGTH
db 0x0

tm_ultraball_class:
db TM_LIGHT_SCREEN
db 0x0
db TM_REFLECT
db 0x0
db TM_TOXIC
db 0x0
db TM_DOUBLE_EDGE
db 0x0
db TM_BUBBLEBEAM
db 0x0
db TM_ICE_BEAM
db 0x0
db TM_SUBMISSION
db 0x0
db TM_THUNDER
db 0x0
db TM_DIG
db 0x0
db TM_DOUBLE_TEAM
db 0x0
db TM_SELFDESTRUCT
db 0x0
db TM_FLAMETHROWER
db 0x0
db TM_ROCK_SLIDE
db 0x0

tm_masterball_class:
db TM_BODY_SLAM
db 0x0
db HM_SURF
db 0x0
db TM_BLIZZARD
db 0x0
db TM_SWORDS_DANCE
db 0x0
db TM_PSYCHIC_M
db 0x0
db TM_EARTHQUAKE
db 0x0
db TM_HYPER_BEAM
db 0x0
db TM_THUNDERBOLT
db 0x0
db TM_THUNDER_WAVE
db 0x0
db TM_FIRE_BLAST
db 0x0
db TM_EXPLOSION
db 0x0

money_classes:
table_width 1
money_pokeball_class:
db NUGGET ; MUSHROOM
db 0x0

money_greatball_class:
db NUGGET ; PEARL
db 0x0

money_ultraball_class:
db NUGGET
db 0x0

money_masterball_class:
db NUGGET ; BIG_NUGGET
db 0x0

stat_classes:
table_width 1
stat_pokeball_class:
db PROTEIN
db 0x0
db CARBOS
db 0x0
db CALCIUM
db 0x0
db IRON
db 0x0

stat_greatball_class:
db HP_UP
db 0x0
db PP_UP
db 0x0

stat_ultraball_class:
db MOON_STONE
db 0x0
db FIRE_STONE
db 0x0
db WATER_STONE
db 0x0
db THUNDER_STONE
db 0x0
db LEAF_STONE
db 0x0

stat_masterball_class:
db RARE_CANDY
db 0x0