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
	special_entry SPECIAL_PSYCHIC,           PSYDUCK,    0,                   PAL_PURPLEMON, .psychicName, .warpFound,  .psychicEffect
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
.warpFound    db "THE<NEXT>FACILITY@"

.armoredName db "ARMORED MEWTWO@"
.armoredEffect
	db "Armor meant to"
	next "restrain MEWTWO."
	next "It was"
	next "unsuccessful.@"

.clubName db "THICK CLUB CUBONE@"
.clubEffect
	db "A CUBONE with a"
	next "large club,"
	next "doubling its"
	next "ATTACK."

.lightName db "LIGHT BALL PIKACHU@"
.lightEffect
	db "A strong willed"
	next "PIKACHU with"
	next "double the normal"
	next "SPECIAL and"
	next "ATTACK strength.@"

.guardName db "NO GUARD MACHOP@"
.guardEffect
	text "Its moves never"
	next "miss, but neither"
	next "do its opponents.@"

.limberName db "LIMBER HITMONLEE@"
.limberEffect
	db "A HITMONLEE that"
	next "cannot be"
	next "PARALYZED.@"

.mysticName db "MYSTIC HITMONCHAN@"
.mysticEffect
	db "A HITMONCHAN that"
	next "swaps its ATTACK"
	next "power for"
	next "SPECIAL.@"

.critName db "LUCKY DUCK@"
.critEffect
	db "Every move it"
	next "lands is a"
	next "critical hit.@"

.clawName db "QUICK NIDORAN♀@"
.clawEffect
	db "A NIDORAN♀ with a"
	next "25% chance to"
	next "always go first.@"

.fierceName db "INT. GROWLITHE@"
.fierceEffect
	db "Lowers the"
	next "opponents ATTACK"
	next "on entry.@"

.pinkName db "PINK BUTTERFREE@"
.pinkEffect
	db "BUTTERFREE that"
	next "has 30% more"
	next "accurate moves.@"

.dittoName db "SUPER DITTO@"
.dittoEffect
	db "Knows SUPER"
	next "TRANSFORM, coping"
	next "all opponent's"
	next "stats.@"

.crystalName db "CRYSTAL ONIX@"
.crystalEffect
	db "A rare ICE type"
	next "ONIX.@"

.iceName db "SNOWLAX@"
.iceEffect
	db "A rare ICE type"
	next "SNORLAX.@"

.dragonName db "DRAGON CHARMANDER@"
.dragonEffect
	db "Has DRAGON type"
	next "instead of"
	next "FLYING.@"

.psychicName db "PSYCHIC PSYDUCK@"
.psychicEffect
	db "An abandoned"
	next "experimental"
	next "#MON with"
	next "heightened"
	next "PSYCHIC powers."
