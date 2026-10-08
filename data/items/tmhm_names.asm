; TM/HM display names: the move part GetMachineName (home/names.asm) appends
; after "TM44 ", so the bag, marts and "got" texts read "TM44 REST".
; Item names are capped at ITEM_NAME_LENGTH - 1 = 12 characters and the prefix
; takes 5, so each entry is at most 7; longer moves are abbreviated in Shin
; Red's style. Fixed 8-byte stride (padded with '@') so the lookup is a shift.
; Indexed by item id - HM01: HM01-HM05 first, then TM01-TM50.

DEF __tmhm_name_index__ = 0

; tmhm_name MOVE, "ABBR" - asserts MOVE really is the machine at this index,
; so reordering the add_tm list in constants/item_constants.asm cannot
; silently mislabel a TM.
MACRO tmhm_name
	IF __tmhm_name_index__ < NUM_HMS
		ASSERT \1_TMNUM == NUM_TMS + 1 + __tmhm_name_index__, \
			"tmhm_name: \1 is out of order (HM01-HM05 come first)"
	ELSE
		ASSERT \1_TMNUM == __tmhm_name_index__ - NUM_HMS + 1, \
			"tmhm_name: \1 is out of order (must follow the add_tm list)"
	ENDC
	ASSERT CHARLEN(\2) < TMHM_DISPLAY_NAME_LENGTH, "TM/HM name too long: \2"
	dname \2, TMHM_DISPLAY_NAME_LENGTH
	DEF __tmhm_name_index__ += 1
ENDM

TMHMDisplayNames::
	tmhm_name CUT,          "CUT"
	tmhm_name FLY,          "FLY"
	tmhm_name SURF,         "SURF"
	tmhm_name STRENGTH,     "STRNGTH"
	tmhm_name FLASH,        "FLASH"
	tmhm_name MEGA_PUNCH,   "MEGPNCH"
	tmhm_name RAZOR_WIND,   "RZRWIND"
	tmhm_name SWORDS_DANCE, "SWRDANC"
	tmhm_name LIGHT_SCREEN, "LGTSCRN"
	tmhm_name MEGA_KICK,    "MEGKICK"
	tmhm_name TOXIC,        "TOXIC"
	tmhm_name HORN_DRILL,   "HRNDRIL"
	tmhm_name BODY_SLAM,    "BDYSLAM"
	tmhm_name TAKE_DOWN,    "TAKEDWN"
	tmhm_name DOUBLE_EDGE,  "DBLEDGE"
	tmhm_name BUBBLEBEAM,   "BBLBEAM"
	tmhm_name WATER_GUN,    "WATRGUN"
	tmhm_name ICE_BEAM,     "ICEBEAM"
	tmhm_name BLIZZARD,     "BLIZARD"
	tmhm_name HYPER_BEAM,   "HYPBEAM"
	tmhm_name PAY_DAY,      "PAY DAY"
	tmhm_name SUBMISSION,   "SUBMSSN"
	tmhm_name COUNTER,      "COUNTER"
	tmhm_name SEISMIC_TOSS, "SMCTOSS"
	tmhm_name RAGE,         "RAGE"
	tmhm_name MEGA_DRAIN,   "MGDRAIN"
	tmhm_name SOLARBEAM,    "SLRBEAM"
	tmhm_name DRAGON_RAGE,  "DRGRAGE"
	tmhm_name THUNDERBOLT,  "THRBOLT"
	tmhm_name THUNDER,      "THUNDER"
	tmhm_name EARTHQUAKE,   "ERQUAKE"
	tmhm_name FISSURE,      "FISSURE"
	tmhm_name DIG,          "DIG"
	tmhm_name PSYCHIC_M,    "PSYCHIC"
	tmhm_name FLAMETHROWER, "FLMTHWR"
	tmhm_name MIMIC,        "MIMIC"
	tmhm_name DOUBLE_TEAM,  "DBLTEAM"
	tmhm_name REFLECT,      "REFLECT"
	tmhm_name BIDE,         "BIDE"
	tmhm_name METRONOME,    "MTRONOM"
	tmhm_name SELFDESTRUCT, "SELFDST"
	tmhm_name EGG_BOMB,     "EGGBOMB"
	tmhm_name FIRE_BLAST,   "FIRBLST"
	tmhm_name SWIFT,        "SWIFT"
	tmhm_name SKULL_BASH,   "SKLBASH"
	tmhm_name SOFTBOILED,   "SFTBOIL"
	tmhm_name DREAM_EATER,  "DRMEATR"
	tmhm_name SKY_ATTACK,   "SKYATTK"
	tmhm_name REST,         "REST"
	tmhm_name THUNDER_WAVE, "THRWAVE"
	tmhm_name PSYWAVE,      "PSYWAVE"
	tmhm_name EXPLOSION,    "EXPLOSN"
	tmhm_name ROCK_SLIDE,   "ROKSLID"
	tmhm_name TRI_ATTACK,   "TRIATTK"
	tmhm_name SUBSTITUTE,   "SUBSTUT"
	ASSERT __tmhm_name_index__ == NUM_TM_HM, "TMHMDisplayNames needs one entry per TM/HM"
