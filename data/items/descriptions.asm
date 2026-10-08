; Bag / mart item descriptions, drawn by PrintItemDescription
; (custom_functions/item_descriptions.asm). Two lines of at most 14 tiles;
; '#' prints as four (POKé). TMs/HMs are not listed: they show their move's
; type, PP, power and accuracy instead.
; Write each entry from the item's real effect in this ROM, not vanilla's.

ItemDescriptions:
; Recovery pocket. Heal amounts are ItemUseMedicine's base values (a Bridge
; effect can scale them by 110%).
	item_desc POTION,        "Restores 20 HP", "to one #MON"
	item_desc SUPER_POTION,  "Restores 50 HP", "to one #MON"
	item_desc HYPER_POTION,  "Restores 200HP", "to one #MON"
	item_desc MAX_POTION,    "Heals all HP",   "to one #MON"
	item_desc FULL_RESTORE,  "Fully heals HP", "and all status"
	item_desc FRESH_WATER,   "Restores 50 HP", "to one #MON"
	item_desc SODA_POP,      "Restores 60 HP", "to one #MON"
	item_desc LEMONADE,      "Restores 80 HP", "to one #MON"
	item_desc ANTIDOTE,      "Cures poison",   "of one #MON"
	item_desc BURN_HEAL,     "Cures a burn",   "of one #MON"
	item_desc ICE_HEAL,      "Thaws out a",    "frozen #MON"
	item_desc AWAKENING,     "Cures sleep",    "of one #MON"
	item_desc PARLYZ_HEAL,   "Ends paralysis", "of one #MON"
	item_desc FULL_HEAL,     "Cures every",    "status problem"
	item_desc REVIVE,        "Revives with",   "half its HP"
	item_desc MAX_REVIVE,    "Revives with",   "full HP"
	item_desc ETHER,         "Restores 10 PP", "of one move"
	item_desc MAX_ETHER,     "Fully restores", "PP of one move"
	item_desc ELIXER,        "Restores 10 PP", "of all moves"
	item_desc MAX_ELIXER,    "Refills PP of",  "all moves"
	item_desc POKE_FLUTE,    "Wakes up all",   "asleep #MON"

; Key items pocket (condensed from BattleItemInfoTable). The tier shows on
; the label row above.
	item_desc LEFTOVERS,     "Heals party HP", "after battles"
	item_desc PP_TONIC,      "Restores PP",    "after battles"
	item_desc KO_DEFIANCE,   "Last #MON",      "revives on KO"
	item_desc SHINY_CHARM,   "Raises odds of", "shiny #MON"
	item_desc AMULET_COIN,   "Earn more",      "prize money"
	item_desc TURN_REWIND,   "Undoes the",     "last turn"
	item_desc RARE_SCOPE,    "Rarer wild",     "#MON appear"
	item_desc RARE_LENS,     "Raises rarity",  "of items found"
	item_desc DV_BOOSTER,    "Caught #MON",    "get better DVs"
	item_desc STAT_BOOSTER,  "More stat EXP",  "from battles"
	item_desc DOOR_DICE,     "Rerolls the",    "lobby doors"
	item_desc MON_DICE,      "Rerolls the",    "reward #MON"
	item_desc ITEM_DICE,     "Rerolls the",    "stage items"
	item_desc ELEMENT_PRISM, "Boosts moves",   "of its type"

; Stat pocket
	item_desc MOON_STONE,    "Makes certain",  "#MON evolve"
	item_desc FIRE_STONE,    "Makes certain",  "#MON evolve"
	item_desc THUNDER_STONE, "Makes certain",  "#MON evolve"
	item_desc WATER_STONE,   "Makes certain",  "#MON evolve"
	item_desc LEAF_STONE,    "Makes certain",  "#MON evolve"
	item_desc SUN_STONE,     "Makes certain",  "#MON evolve"
	item_desc DUSK_STONE,    "Makes certain",  "#MON evolve"
	item_desc ICE_STONE,     "Makes certain",  "#MON evolve"
	item_desc MIST_STONE,    "Evolves into",   "any next form" ; MistStoneChooseEvolution
	item_desc HP_UP,         "Raises max HP",  "of one #MON"
	item_desc PROTEIN,       "Raises ATTACK",  "of one #MON"
	item_desc IRON,          "Raises DEFENSE", "of one #MON"
	item_desc CARBOS,        "Raises SPEED",   "of one #MON"
	item_desc CALCIUM,       "Raises SPECIAL", "of one #MON"
	item_desc RARE_CANDY,    "Raises level",   "of one #MON"
	item_desc PP_UP,         "Raises max PP",  "of one move"
	item_desc M_GENE,        "Rerolls DVs to", "above average"
	item_desc M_TOME,        "Maxes stat EXP", "of one #MON"

; Valuables pocket: no use, they only sell
	item_desc PEARL,         "A small pearl",  "Sell at a mart"
	item_desc BIG_PEARL,     "A large pearl",  "Sell at a mart"
	item_desc NUGGET,        "A lump of gold", "Sell at a mart"
	item_desc BIG_NUGGET,    "Big gold lump",  "Sell at a mart"

; Sold in marts (data/items/marts.asm) but never kept in a pocket
	item_desc POKE_BALL,     "Throw to catch", "a wild #MON"
	item_desc GREAT_BALL,    "Good odds to",   "catch #MON"
	item_desc ULTRA_BALL,    "Great odds to",  "catch #MON"
	item_desc MASTER_BALL,   "Always catches", "a wild #MON"
	item_desc ESCAPE_ROPE,   "Use to escape",  "from dungeons"
	item_desc REPEL,         "Repels weak",    "foes 100 steps"
	item_desc SUPER_REPEL,   "Repels weak",    "foes 200 steps"
	item_desc MAX_REPEL,     "Repels weak",    "foes 250 steps"
	item_desc X_ACCURACY,    "Your moves",     "always hit"
	item_desc GUARD_SPEC,    "Stops stat",     "drops by foes"
	item_desc DIRE_HIT,      "Raises your",    "critical rate"
	item_desc X_ATTACK,      "Raises ATTACK",  "in battle"
	item_desc X_DEFEND,      "Raises DEFENSE", "in battle"
	item_desc X_SPEED,       "Raises SPEED",   "in battle"
	item_desc X_SPECIAL,     "Raises SPECIAL", "in battle"
	item_desc POKE_DOLL,     "Flee from any",  "wild battle"
	item_desc BICYCLE,       "Ride it to",     "move faster"
	db -1
