ItemPrices::
	table_width 3
	bcd3 0     ; MASTER_BALL
	bcd3 1200  ; ULTRA_BALL
	bcd3 600   ; GREAT_BALL
	bcd3 200   ; POKE_BALL
	bcd3 0     ; TOWN_MAP
	bcd3 0     ; BICYCLE
	bcd3 0     ; SURFBOARD
	bcd3 1000  ; SAFARI_BALL
	bcd3 0     ; POKEDEX
	bcd3 2100  ; MOON_STONE
	bcd3 100   ; ANTIDOTE
	bcd3 250   ; BURN_HEAL
	bcd3 250   ; ICE_HEAL
	bcd3 200   ; AWAKENING
	bcd3 200   ; PARLYZ_HEAL
	bcd3 3000  ; FULL_RESTORE
	bcd3 2500  ; MAX_POTION
	bcd3 1500  ; HYPER_POTION
	bcd3 700   ; SUPER_POTION
	bcd3 300   ; POTION
	bcd3 0     ; BOULDERBADGE
	bcd3 0     ; CASCADEBADGE
	bcd3 0     ; THUNDERBADGE
	bcd3 0     ; RAINBOWBADGE
	bcd3 0     ; SOULBADGE
	bcd3 0     ; MARSHBADGE
	bcd3 0     ; VOLCANOBADGE
	bcd3 0     ; EARTHBADGE
	bcd3 550   ; ESCAPE_ROPE
	bcd3 350   ; REPEL
	bcd3 0     ; OLD_AMBER
	bcd3 2100  ; FIRE_STONE
	bcd3 2100  ; THUNDER_STONE
	bcd3 2100  ; WATER_STONE
	bcd3 5000  ; HP_UP
	bcd3 5000  ; PROTEIN
	bcd3 5000  ; IRON
	bcd3 5000  ; CARBOS
	bcd3 5000  ; CALCIUM
	bcd3 4800  ; RARE_CANDY
	bcd3 0     ; DOME_FOSSIL
	bcd3 0     ; HELIX_FOSSIL
	bcd3 0     ; SECRET_KEY
	bcd3 6000  ; ITEM_2C, BIG PEARL
	bcd3 0     ; BIKE_VOUCHER
	bcd3 950   ; X_ACCURACY
	bcd3 2100  ; LEAF_STONE
	bcd3 0     ; CARD_KEY
	bcd3 10000 ; NUGGET
	bcd3 20000 ; ITEM_32, BIG NUGGET
	bcd3 1000  ; POKE_DOLL
	bcd3 600   ; FULL_HEAL
	bcd3 1500  ; REVIVE
	bcd3 4000  ; MAX_REVIVE
	bcd3 700   ; GUARD_SPEC
	bcd3 500   ; SUPER_REPEL
	bcd3 700   ; MAX_REPEL
	bcd3 650   ; DIRE_HIT
	bcd3 10    ; COIN
	bcd3 200   ; FRESH_WATER
	bcd3 300   ; SODA_POP
	bcd3 350   ; LEMONADE
	bcd3 0     ; S_S_TICKET
	bcd3 0     ; GOLD_TEETH
	bcd3 500   ; X_ATTACK
	bcd3 550   ; X_DEFEND
	bcd3 350   ; X_SPEED
	bcd3 350   ; X_SPECIAL
	bcd3 0     ; COIN_CASE
	bcd3 0     ; OAKS_PARCEL
	bcd3 0     ; ITEMFINDER
	bcd3 0     ; SILPH_SCOPE
	bcd3 0     ; POKE_FLUTE
	bcd3 0     ; LIFT_KEY
	bcd3 0     ; EXP_ALL
	bcd3 0     ; OLD_ROD
	bcd3 0     ; GOOD_ROD
	bcd3 0     ; SUPER_ROD
	bcd3 5000  ; PP_UP
	bcd3 500   ; ETHER
	bcd3 1000  ; MAX_ETHER
	bcd3 2000  ; ELIXER
	bcd3 3000  ; MAX_ELIXER
	assert_table_length NUM_ITEMS
	bcd3 0     ; FLOOR_B2F
	bcd3 0     ; FLOOR_B1F
	bcd3 0     ; FLOOR_1F
	bcd3 0     ; FLOOR_2F
	bcd3 0     ; FLOOR_3F
	bcd3 0     ; FLOOR_4F
	bcd3 0     ; FLOOR_5F
	bcd3 0     ; FLOOR_6F
	bcd3 0     ; FLOOR_7F
	bcd3 0     ; FLOOR_8F
	bcd3 0     ; FLOOR_9F
	bcd3 0     ; FLOOR_10F
	bcd3 0     ; FLOOR_11F
	bcd3 0     ; FLOOR_B4F
	bcd3 0     ; LEFTOVERS
	bcd3 5000  ; PEARL
	bcd3 0     ; PP_TONIC
	bcd3 0     ; KO_DEFIANCE
	bcd3 0     ; SHINY_CHARM
	bcd3 0     ; AMULET_COIN
	bcd3 0     ; TURN_REWIND
	bcd3 0     ; RARE_SCOPE
	bcd3 0     ; RARE_LENS
	bcd3 0     ; IV_BOOSTER
	bcd3 0     ; STAT_BOOSTER
	bcd3 0     ; DOOR_DICE
	bcd3 0     ; MON_DICE
	bcd3 0     ; ITEM_DICE
	bcd3 0     ; ELEMENT_PRISM
	assert_table_length NUM_ITEMS + NUM_FLOORS + 15

; Credit (not money) prices for the Credit Exchange key-item seller.
; See engine/events/credit_mart.asm.
;
; GetItemPrice (home/item_price.asm) resolves an entry as base + (itemID-1)*3
; and hardcodes a bankswitch to BANK(ItemPrices), so this table MUST live in
; this file's bank. The vendor points wItemPrices at CreditItemPrices biased
; back by (SHINY_CHARM - 1) * 3, so item $66 lands on the first row; only the
; ten ids below are ever looked up here, and they are contiguous by design.
;
; ELEMENT_PRISM is deliberately absent - it is an NPC gift, never for sale.
CreditItemPrices::
	bcd3 30    ; SHINY_CHARM
	bcd3 20    ; AMULET_COIN
	bcd3 25    ; TURN_REWIND
	bcd3 25    ; RARE_SCOPE
	bcd3 25    ; RARE_LENS
	bcd3 35    ; IV_BOOSTER
	bcd3 30    ; STAT_BOOSTER
	bcd3 15    ; DOOR_DICE
	bcd3 15    ; MON_DICE
	bcd3 15    ; ITEM_DICE
