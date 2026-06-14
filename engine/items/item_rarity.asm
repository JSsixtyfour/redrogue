; assigned class for each item and odds

; Item Groupings
const_def
	const_export HEALING            ; $00
	const_export STAT               ; $01
	const_export TM                 ; $02
	const_export MONEY              ; $03

EXPORT DEF item_pokeball_odds EQU 51
DEF item_greatball_odds EQU 77 + 51
DEF item_ultraball_odds EQU 76 + 77 + 51
DEF item_masterball_odds EQU 51 + 76 + 77 + 51

DEF NUM_HEALING_POKEBALL_CLASS EQU 7   ; ANTIDOTE BURN_HEAL ICE_HEAL AWAKENING PARLYZ_HEAL POTION ETHER
DEF NUM_HEALING_GREATBALL_CLASS EQU 6  ; SUPER_POTION ELIXER LEMONADE SODA_POP FRESH_WATER FULL_HEAL
DEF NUM_HEALING_ULTRABALL_CLASS EQU 3  ; MAX_ETHER HYPER_POTION REVIVE
DEF NUM_HEALING_MASTERBALL_CLASS EQU 4 ; FULL_RESTORE MAX_POTION MAX_REVIVE MAX_ELIXER

DEF NUM_TM_POKEBALL_CLASS EQU 11   ; 9 TMs + HM_CUT + HM_FLASH
DEF NUM_TM_GREATBALL_CLASS EQU 20  ; 18 TMs + HM_FLY + HM_STRENGTH
DEF NUM_TM_ULTRABALL_CLASS EQU 13  ; 13 TMs
DEF NUM_TM_MASTERBALL_CLASS EQU 11 ; 10 TMs + HM_SURF

DEF NUM_MONEY_POKEBALL_CLASS EQU $0
DEF NUM_MONEY_GREATBALL_CLASS EQU $0
DEF NUM_MONEY_ULTRABALL_CLASS EQU $0
DEF NUM_MONEY_MASTERBALL_CLASS EQU $0

DEF NUM_STAT_POKEBALL_CLASS EQU 4  ; PROTEIN CARBOS CALCIUM IRON
DEF NUM_STAT_GREATBALL_CLASS EQU 2 ; HP_UP PP_UP
DEF NUM_STAT_ULTRABALL_CLASS EQU 5 ; MOON/FIRE/WATER/THUNDER/LEAF STONE
DEF NUM_STAT_MASTERBALL_CLASS EQU 1 ; RARE_CANDY

item_pokeball_classes::
dw healing_pokeball_class
dw stat_pokeball_class
dw tm_pokeball_class
dw money_pokeball_class

item_greatball_classes::
dw healing_greatball_class
dw stat_greatball_class
dw tm_greatball_class
dw money_greatball_class

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
db BURN_HEAL
db ICE_HEAL
db AWAKENING 
db PARLYZ_HEAL
db POTION
db ETHER

healing_greatball_class:
db SUPER_POTION
db ELIXER
db LEMONADE
db SODA_POP
db FRESH_WATER
db FULL_HEAL

healing_ultraball_class:
db MAX_ETHER
db HYPER_POTION
db REVIVE

healing_masterball_class:
db FULL_RESTORE
db MAX_POTION
db MAX_REVIVE
db MAX_ELIXER

tm_classes:
table_width 1
tm_pokeball_class:
db TM_BIDE
db TM_RAZOR_WIND
db TM_PAY_DAY
db TM_COUNTER
db TM_RAGE
db TM_MIMIC
db TM_METRONOME
db TM_EGG_BOMB
db TM_PSYWAVE
db HM_CUT
db HM_FLASH

tm_greatball_class:
db TM_SKY_ATTACK
db TM_SUBSTITUTE
db TM_DRAGON_RAGE
db TM_MEGA_PUNCH
db TM_MEGA_KICK
db TM_HORN_DRILL
db TM_TAKE_DOWN
db TM_WATER_GUN
db TM_SEISMIC_TOSS
db TM_MEGA_DRAIN
db TM_SOLARBEAM
db TM_FISSURE
db TM_SWIFT
db TM_SKULL_BASH
db TM_SOFTBOILED
db TM_DREAM_EATER
db TM_REST
db TM_TRI_ATTACK
db HM_FLY
db HM_STRENGTH

tm_ultraball_class:
db TM_LIGHT_SCREEN
db TM_REFLECT
db TM_TOXIC
db TM_DOUBLE_EDGE
db TM_BUBBLEBEAM
db TM_ICE_BEAM
db TM_SUBMISSION
db TM_THUNDER
db TM_DIG
db TM_DOUBLE_TEAM
db TM_SELFDESTRUCT
db TM_FLAMETHROWER
db TM_ROCK_SLIDE

tm_masterball_class:
db TM_BODY_SLAM
db HM_SURF
db TM_BLIZZARD
db TM_SWORDS_DANCE
db TM_PSYCHIC_M
db TM_EARTHQUAKE
db TM_HYPER_BEAM
db TM_THUNDERBOLT
db TM_THUNDER_WAVE
db TM_FIRE_BLAST
db TM_EXPLOSION

money_classes:
table_width 1
money_pokeball_class:
db PEARL

money_greatball_class:
db BIG_PEARL ; BIG PEARL

money_ultraball_class:
db NUGGET

money_masterball_class:
db BIG_NUGGET ; BIG_NUGGET

stat_classes:
table_width 1
stat_pokeball_class:
db PROTEIN
db CARBOS
db CALCIUM
db IRON

stat_greatball_class:
db HP_UP
db PP_UP

stat_ultraball_class:
db MOON_STONE
db FIRE_STONE
db WATER_STONE
db THUNDER_STONE
db LEAF_STONE

stat_masterball_class:
db RARE_CANDY