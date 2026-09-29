; HM and TM prices, one price-tier nybble per machine (HM01-HM05, then
; TM01-TM50: HMs sit directly below TM01, so one array covers both).
; GetMachinePrice (engine/items/tm_prices.asm) turns the tier into a price
; through TMPriceTierTable; the prices themselves are the TM_PRICE_*_BCD knobs
; in constants/balance_constants.asm.
;
; Each tier is the move's grade in MoveRankByID (data/moves/move_ranks.asm),
; the moveset system's ranking (BALANCE_PHASE5_PLAN.md E, 2026-09-28). Written
; by a one-shot script; edit a row by hand to override a single machine.

TMPriceTierTable:
	table_width 1, TMPriceTierTable
	db TM_PRICE_F_BCD ; TM_PRICE_TIER_F
	db TM_PRICE_D_BCD ; TM_PRICE_TIER_D
	db TM_PRICE_C_BCD ; TM_PRICE_TIER_C
	db TM_PRICE_B_BCD ; TM_PRICE_TIER_B
	db TM_PRICE_A_BCD ; TM_PRICE_TIER_A
	db TM_PRICE_S_BCD ; TM_PRICE_TIER_S
	assert_table_length NUM_TM_PRICE_TIERS

	ASSERT TM01 == HM01 + NUM_HMS, "GetMachinePrice indexes HMs and TMs as one run"

TechnicalMachinePrices:
	nybble_array TechnicalMachinePrices
	nybble TM_PRICE_TIER_F ; HM01 CUT (F)
	nybble TM_PRICE_TIER_D ; HM02 FLY (D)
	nybble TM_PRICE_TIER_A ; HM03 SURF (A)
	nybble TM_PRICE_TIER_B ; HM04 STRENGTH (B)
	nybble TM_PRICE_TIER_F ; HM05 FLASH (F)
	nybble TM_PRICE_TIER_D ; TM01 MEGA_PUNCH (D)
	nybble TM_PRICE_TIER_F ; TM02 RAZOR_WIND (F)
	nybble TM_PRICE_TIER_A ; TM03 SWORDS_DANCE (A)
	nybble TM_PRICE_TIER_B ; TM04 LIGHT_SCREEN (B)
	nybble TM_PRICE_TIER_C ; TM05 MEGA_KICK (C)
	nybble TM_PRICE_TIER_B ; TM06 TOXIC (B)
	nybble TM_PRICE_TIER_C ; TM07 HORN_DRILL (C)
	nybble TM_PRICE_TIER_S ; TM08 BODY_SLAM (S)
	nybble TM_PRICE_TIER_B ; TM09 TAKE_DOWN (B)
	nybble TM_PRICE_TIER_B ; TM10 DOUBLE_EDGE (B)
	nybble TM_PRICE_TIER_B ; TM11 BUBBLEBEAM (B)
	nybble TM_PRICE_TIER_D ; TM12 WATER_GUN (D)
	nybble TM_PRICE_TIER_A ; TM13 ICE_BEAM (A)
	nybble TM_PRICE_TIER_S ; TM14 BLIZZARD (S)
	nybble TM_PRICE_TIER_S ; TM15 HYPER_BEAM (S)
	nybble TM_PRICE_TIER_F ; TM16 PAY_DAY (F)
	nybble TM_PRICE_TIER_D ; TM17 SUBMISSION (D)
	nybble TM_PRICE_TIER_B ; TM18 COUNTER (B)
	nybble TM_PRICE_TIER_B ; TM19 SEISMIC_TOSS (B)
	nybble TM_PRICE_TIER_D ; TM20 RAGE (D)
	nybble TM_PRICE_TIER_B ; TM21 MEGA_DRAIN (B)
	nybble TM_PRICE_TIER_C ; TM22 SOLARBEAM (C)
	nybble TM_PRICE_TIER_B ; TM23 DRAGON_RAGE (B)
	nybble TM_PRICE_TIER_S ; TM24 THUNDERBOLT (S)
	nybble TM_PRICE_TIER_B ; TM25 THUNDER (B)
	nybble TM_PRICE_TIER_S ; TM26 EARTHQUAKE (S)
	nybble TM_PRICE_TIER_C ; TM27 FISSURE (C)
	nybble TM_PRICE_TIER_B ; TM28 DIG (B)
	nybble TM_PRICE_TIER_S ; TM29 PSYCHIC_M (S)
	nybble TM_PRICE_TIER_B ; TM30 FLAMETHROWER (B)
	nybble TM_PRICE_TIER_C ; TM31 MIMIC (C)
	nybble TM_PRICE_TIER_C ; TM32 DOUBLE_TEAM (C)
	nybble TM_PRICE_TIER_A ; TM33 REFLECT (A)
	nybble TM_PRICE_TIER_F ; TM34 BIDE (F)
	nybble TM_PRICE_TIER_D ; TM35 METRONOME (D)
	nybble TM_PRICE_TIER_A ; TM36 SELFDESTRUCT (A)
	nybble TM_PRICE_TIER_D ; TM37 EGG_BOMB (D)
	nybble TM_PRICE_TIER_A ; TM38 FIRE_BLAST (A)
	nybble TM_PRICE_TIER_B ; TM39 SWIFT (B)
	nybble TM_PRICE_TIER_D ; TM40 SKULL_BASH (D)
	nybble TM_PRICE_TIER_S ; TM41 SOFTBOILED (S)
	nybble TM_PRICE_TIER_D ; TM42 DREAM_EATER (D)
	nybble TM_PRICE_TIER_C ; TM43 SKY_ATTACK (C)
	nybble TM_PRICE_TIER_C ; TM44 REST (C)
	nybble TM_PRICE_TIER_S ; TM45 THUNDER_WAVE (S)
	nybble TM_PRICE_TIER_F ; TM46 PSYWAVE (F)
	nybble TM_PRICE_TIER_S ; TM47 EXPLOSION (S)
	nybble TM_PRICE_TIER_A ; TM48 ROCK_SLIDE (A)
	nybble TM_PRICE_TIER_B ; TM49 TRI_ATTACK (B)
	nybble TM_PRICE_TIER_B ; TM50 SUBSTITUTE (B)
	end_nybble_array NUM_HMS + NUM_TMS
