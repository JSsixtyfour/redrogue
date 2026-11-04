; Special collection entries, in SPECIAL_* id order. Original Red Rogue text: it
; states what the game really does (SpecialFormCaps, the gift scripts).
; Limits, enforced by test_special_collection.py: name 18 tiles, found 10 per
; line, effect 18 per line and at most 5 lines. "#" renders as 4 tiles.

DEF SPECIAL_ENTRY_SIZE EQU 9
DEF SPECIAL_ENTRY_NAME EQU 3 ; the three pointers follow species, form, palette

MACRO special_entry ; id, species, form, palette (0 = the form's own), name, found, effect
	ASSERT @ - SpecialEntries == (\1) * SPECIAL_ENTRY_SIZE, "SpecialEntries out of id order"
	db \2, \3, \4
	dw \5, \6, \7
ENDM

SpecialEntries:
	special_entry SPECIAL_ARMORED_MEWTWO,    MEWTWO,     ARMORED_MEWTWO_FORM, 0,           .armoredName, .armoredFound, .armoredEffect
	special_entry SPECIAL_THICK_CLUB,        CUBONE,     0,                   0,           .clubName,    .fujiFound,    .clubEffect
	special_entry SPECIAL_LIGHT_BALL,        PIKACHU,    0,                   0,           .lightName,   .oakFound,     .lightEffect
	special_entry SPECIAL_NO_GUARD,          MACHOP,     0,                   0,           .guardName,   .dojoFound,    .guardEffect
	special_entry SPECIAL_LIMBER,            HITMONLEE,  0,                   0,           .limberName,  .dojoFound,    .limberEffect
	special_entry SPECIAL_MYSTIC,            HITMONCHAN, 0,                   0,           .mysticName,  .dojoFound,    .mysticEffect
	special_entry SPECIAL_ALWAYS_CRIT,       FARFETCHD,  0,                   0,           .critName,    .captainFound, .critEffect
	special_entry SPECIAL_QUICK_CLAW,        NIDORAN_F,  0,                   0,           .clawName,    .schoolFound,  .clawEffect
	special_entry SPECIAL_INTIMIDATE,        GROWLITHE,  0,                   0,           .fierceName,  .trashedFound, .fierceEffect
	special_entry SPECIAL_PINK,              BUTTERFREE, 0,                   PAL_PINKMON, .pinkName,    .grottoFound,  .pinkEffect
	special_entry SPECIAL_SUPER_DITTO,       DITTO,      0,                   0,           .dittoName,   .copycatFound, .dittoEffect
	special_entry SPECIAL_CRYSTAL,           ONIX,       0,                   PAL_BLUEMON, .crystalName, .caveFound,    .crystalEffect
	special_entry SPECIAL_ICE,               SNORLAX,    0,                   PAL_BLUEMON, .iceName,     .caveFound,    .iceEffect
	special_entry SPECIAL_DRAGON,            CHARMANDER, 0,                   PAL_BLACK,   .dragonName,  .oakFound,     .dragonEffect
	ASSERT @ - SpecialEntries == NUM_SPECIAL_IDENTITIES * SPECIAL_ENTRY_SIZE

.fujiFound    db "MR.FUJI's<NEXT>HOUSE@"
.oakFound     db "OAK's LAB@"
.dojoFound    db "KARATE<NEXT>DOJO@"
.captainFound db "S.S.ANNE<NEXT>CAPTAIN@"
.schoolFound  db "VIRIDIAN<NEXT>SCHOOL@"
.trashedFound db "CERULEAN<NEXT>TRASHED<NEXT>HOUSE@"
.grottoFound  db "FOREST<NEXT>GROTTO@"
.copycatFound db "COPYCAT's<NEXT>HOUSE@"
.caveFound    db "CAVE<NEXT>BASEMENT@"
.armoredFound db "GIOVANNI's<NEXT>TRADE@"

.armoredName db "ARMORED MEWTWO@"
.armoredEffect
	db   "An armored look."
	next "It fights like any"
	next "other MEWTWO.@"

.clubName db "THICK CLUB CUBONE@"
.clubEffect
	db   "Its ATTACK is"
	next "doubled. MAROWAK"
	next "keeps the club.@"

.lightName db "LIGHT BALL PIKACHU@"
.lightEffect
	db   "ATTACK and SPECIAL"
	next "are doubled, but"
	next "it can't evolve.@"

.guardName db "NO GUARD MACHOP@"
.guardEffect
	db   "Its moves and the"
	next "foe's never miss!"
	next "Lasts through its"
	next "evolutions.@"

.limberName db "LIMBER HITMONLEE@"
.limberEffect
	db   "Can't be"
	next "paralyzed.@"

.mysticName db "MYSTIC HITMONCHAN@"
.mysticEffect
	db   "Swaps its ATTACK"
	next "and SPECIAL stats.@"

.critName db "SHARP FARFETCH'D@"
.critEffect
	db   "Every hit it lands"
	next "is a critical hit."
	next "Has perfect stats.@"

.clawName db "Q.CLAW NIDORAN♀@"
.clawEffect
	db   "A 25% chance to"
	next "move first, like"
	next "a QUICK CLAW. Its"
	next "evolutions keep"
	next "it.@"

.fierceName db "FIERCE GROWLITHE@"
.fierceEffect
	db   "Lowers the foe's"
	next "ATTACK on entry."
	next "Has perfect stats"
	next "and knows QUICK"
	next "ATTACK and LICK.@"

.pinkName db "PINK BUTTERFREE@"
.pinkEffect
	db   "Its moves are"
	next "about 30% more"
	next "accurate.@"

.dittoName db "SUPER DITTO@"
.dittoEffect
	db   "Has perfect stats."
	next "SUPER TRANSFORM"
	next "copies HP too.@"

.crystalName db "CRYSTAL ONIX@"
.crystalEffect
	db   "An ICE and GROUND"
	next "type that knows"
	next "MIST or HAZE.@"

.iceName db "ICE SNORLAX@"
.iceEffect
	db   "A pure ICE type"
	next "that knows MIST"
	next "or HAZE.@"

.dragonName db "DRAGON CHARMANDER@"
.dragonEffect
	db   "A FIRE and DRAGON"
	next "type, at every"
	next "stage.@"
