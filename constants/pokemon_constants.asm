; pokemon ids
; indexes for:
; - MonsterNames (see data/pokemon/names.asm)
; - EvosMovesPointerTable (see data/pokemon/evos_moves.asm)
; - CryData (see data/pokemon/cries.asm)
; - PokedexOrder (see data/pokemon/dex_order.asm)
; - PokedexEntryPointers (see data/pokemon/dex_entries.asm)
	const_def
	const NO_MON             ; $00
	const RHYDON             ; $01
	const KANGASKHAN         ; $02
	const NIDORAN_M          ; $03
	const CLEFAIRY           ; $04
	const SPEAROW            ; $05
	const VOLTORB            ; $06
	const NIDOKING           ; $07
	const SLOWBRO            ; $08
	const IVYSAUR            ; $09
	const EXEGGUTOR          ; $0A
	const LICKITUNG          ; $0B
	const EXEGGCUTE          ; $0C
	const GRIMER             ; $0D
	const GENGAR             ; $0E
	const NIDORAN_F          ; $0F
	const NIDOQUEEN          ; $10
	const CUBONE             ; $11
	const RHYHORN            ; $12
	const LAPRAS             ; $13
	const ARCANINE           ; $14
	const MEW                ; $15
	const GYARADOS           ; $16
	const SHELLDER           ; $17
	const TENTACOOL          ; $18
	const GASTLY             ; $19
	const SCYTHER            ; $1A
	const STARYU             ; $1B
	const BLASTOISE          ; $1C
	const PINSIR             ; $1D
	const TANGELA            ; $1E
	const_skip               ; $1F
	const_skip               ; $20
	const GROWLITHE          ; $21
	const ONIX               ; $22
	const FEAROW             ; $23
	const PIDGEY             ; $24
	const SLOWPOKE           ; $25
	const KADABRA            ; $26
	const GRAVELER           ; $27
	const CHANSEY            ; $28
	const MACHOKE            ; $29
	const MR_MIME            ; $2A
	const HITMONLEE          ; $2B
	const HITMONCHAN         ; $2C
	const ARBOK              ; $2D
	const PARASECT           ; $2E
	const PSYDUCK            ; $2F
	const DROWZEE            ; $30
	const GOLEM              ; $31
	const_skip               ; $32
	const MAGMAR             ; $33
	const_skip               ; $34
	const ELECTABUZZ         ; $35
	const MAGNETON           ; $36
	const KOFFING            ; $37
	const_skip               ; $38
	const MANKEY             ; $39
	const SEEL               ; $3A
	const DIGLETT            ; $3B
	const TAUROS             ; $3C
	const_skip               ; $3D
	const_skip               ; $3E
	const_skip               ; $3F
	const FARFETCHD          ; $40
	const VENONAT            ; $41
	const DRAGONITE          ; $42
	const_skip               ; $43
	const_skip               ; $44
	const_skip               ; $45
	const DODUO              ; $46
	const POLIWAG            ; $47
	const JYNX               ; $48
	const MOLTRES            ; $49
	const ARTICUNO           ; $4A
	const ZAPDOS             ; $4B
	const DITTO              ; $4C
	const MEOWTH             ; $4D
	const KRABBY             ; $4E
	const_skip               ; $4F
	const_skip               ; $50
	const_skip               ; $51
	const VULPIX             ; $52
	const NINETALES          ; $53
	const PIKACHU            ; $54
	const RAICHU             ; $55
	const_skip               ; $56
	const_skip               ; $57
	const DRATINI            ; $58
	const DRAGONAIR          ; $59
	const KABUTO             ; $5A
	const KABUTOPS           ; $5B
	const HORSEA             ; $5C
	const SEADRA             ; $5D
	const_skip               ; $5E
	const_skip               ; $5F
	const SANDSHREW          ; $60
	const SANDSLASH          ; $61
	const OMANYTE            ; $62
	const OMASTAR            ; $63
	const JIGGLYPUFF         ; $64
	const WIGGLYTUFF         ; $65
	const EEVEE              ; $66
	const FLAREON            ; $67
	const JOLTEON            ; $68
	const VAPOREON           ; $69
	const MACHOP             ; $6A
	const ZUBAT              ; $6B
	const EKANS              ; $6C
	const PARAS              ; $6D
	const POLIWHIRL          ; $6E
	const POLIWRATH          ; $6F
	const WEEDLE             ; $70
	const KAKUNA             ; $71
	const BEEDRILL           ; $72
	const_skip               ; $73
	const DODRIO             ; $74
	const PRIMEAPE           ; $75
	const DUGTRIO            ; $76
	const VENOMOTH           ; $77
	const DEWGONG            ; $78
	const_skip               ; $79
	const_skip               ; $7A
	const CATERPIE           ; $7B
	const METAPOD            ; $7C
	const BUTTERFREE         ; $7D
	const MACHAMP            ; $7E
	const_skip               ; $7F
	const GOLDUCK            ; $80
	const HYPNO              ; $81
	const GOLBAT             ; $82
	const MEWTWO             ; $83
	const SNORLAX            ; $84
	const MAGIKARP           ; $85
	const_skip               ; $86
	const_skip               ; $87
	const MUK                ; $88
	const_skip               ; $89
	const KINGLER            ; $8A
	const CLOYSTER           ; $8B
	const_skip               ; $8C
	const ELECTRODE          ; $8D
	const CLEFABLE           ; $8E
	const WEEZING            ; $8F
	const PERSIAN            ; $90
	const MAROWAK            ; $91
	const_skip               ; $92
	const HAUNTER            ; $93
	const ABRA               ; $94
	const ALAKAZAM           ; $95
	const PIDGEOTTO          ; $96
	const PIDGEOT            ; $97
	const STARMIE            ; $98
	const BULBASAUR          ; $99
	const VENUSAUR           ; $9A
	const TENTACRUEL         ; $9B
	const_skip               ; $9C
	const GOLDEEN            ; $9D
	const SEAKING            ; $9E
	const_skip               ; $9F
	const_skip               ; $A0
	const_skip               ; $A1
	const_skip               ; $A2
	const PONYTA             ; $A3
	const RAPIDASH           ; $A4
	const RATTATA            ; $A5
	const RATICATE           ; $A6
	const NIDORINO           ; $A7
	const NIDORINA           ; $A8
	const GEODUDE            ; $A9
	const PORYGON            ; $AA
	const AERODACTYL         ; $AB
	const_skip               ; $AC
	const MAGNEMITE          ; $AD
	const_skip               ; $AE
	const_skip               ; $AF
	const CHARMANDER         ; $B0
	const SQUIRTLE           ; $B1
	const CHARMELEON         ; $B2
	const WARTORTLE          ; $B3
	const CHARIZARD          ; $B4
	const_skip               ; $B5
	const_skip               ; $B6 was FOSSIL_KABUTOPS - retired, see below
	const_skip               ; $B7 was FOSSIL_AERODACTYL - retired, see below
	const_skip               ; $B8 was MON_GHOST - retired, see below
	const ODDISH             ; $B9
	const GLOOM              ; $BA
	const VILEPLUME          ; $BB
	const BELLSPROUT         ; $BC
	const WEEPINBELL         ; $BD
	const VICTREEBEL         ; $BE

DEF NUM_POKEMON_INDEXES EQU const_value - 1

; starters
DEF STARTER1 EQU CHARMANDER
DEF STARTER2 EQU SQUIRTLE
DEF STARTER3 EQU BULBASAUR

; placeholder species ($1F is unused) used in the rival's trainer party data
; to mark the slot that should be dynamically replaced with wRivalStarter.
;
; This is the ONLY surviving placeholder. PLACEHOLDER_POKEBALL ($20),
; PLACHOLDER_GREATBALL ($32), PLACEHOLDER_ULTRABALL ($34),
; PLACEHOLDER_MASTERBALL ($38) and PLACEHOLDER_LEGENDARY ($3D) were deleted
; 2026-09-03: each had exactly one reference tree-wide (its own DEF), the
; trainer system having long since diverged past them. Their five index holes
; are now free for real species.
;
; $1F stays. The party format is `db $FF, level, species, ..., 0`, so $00 is
; the terminator and every other byte value becomes a real species once the
; index space fills - there is no spare sentinel to move it to. Reclaiming it
; would mean marking the rival's ace positionally in the party reader, which is
; not worth one slot.
DEF RIVAL_STARTER_PLACEHOLDER EQU $1F

; $B6/$B7 (FOSSIL_KABUTOPS, FOSSIL_AERODACTYL) were retired 2026-09-03. They
; existed only for the Pewter Museum fossil display, and MUSEUM_1F is not in
; Red Rogue's stage pool (custom_functions/random_stage_selection.asm), so the
; feature was unreachable.
;
; MON_GHOST ($B8) is DELIBERATELY KEPT and must not be retired with them:
; POKEMON_TOWER_2F and POKEMON_TOWER_7F ARE live stages in that same pool, and
; IsGhostBattle (engine/battle/core.asm) fires on any POKEMON_TOWER map when the
; player has no SILPH_SCOPE, rendering the enemy through MON_GHOST.

; ghost Marowak in Pokémon Tower
DEF RESTLESS_SOUL EQU MAROWAK
