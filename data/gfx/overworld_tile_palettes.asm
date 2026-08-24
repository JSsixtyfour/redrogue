; Shin Red import Phase 3 (CGB color). Per-tileset, per-tile-ID palette register
; assignment, ported verbatim from shinpokered's OverworldTilePalPointers /
; PalSettings_* (custom_functions/func_enhancedcolor.asm). Red Rogue's tileset
; constants (constants/tileset_constants.asm) are index-identical to
; shinpokered's for OVERWORLD($00) through PLATEAU($17), which is what makes
; this a 1:1 port rather than a redesign - see ShinRed_Import.md Phase 3.0b.
;
; MakeOverworldBGMapAttributes consumes this table directly from the CGB helper
; bank. Keep this section in that same ROM bank unless the reads are converted
; to a bank-aware copy.
;
; Each PalSettings_* table has one byte per tile ID ($00-$5F, i.e. every block
; in a tileset) naming which of the 8 CGB background palette registers colors
; that tile. A value of 8 is shinpokered's own "wild card": resolved at
; runtime to a town-specific palette (their PalSettings_TownSpecialPal /
; TownSpecialPal mechanism). That resolver has NOT been ported - it is a
; separate, not-yet-scoped piece of work. Until it exists, treat any 8 in
; these tables as an open item rather than a working feature.
;
; Several tilesets share one table because they share their tile IDs' meaning
; (e.g. MART and POKECENTER, DOJO and GYM) - preserved exactly as shinpokered
; defines them, via shared labels.

OverworldTilePalPointers::
	dw PalSettings_OVERWORLD    ; 0
	dw PalSettings_REDS_HOUSE_1 ; 1
	dw PalSettings_MART         ; 2
	dw PalSettings_FOREST       ; 3
	dw PalSettings_REDS_HOUSE_2 ; 4
	dw PalSettings_DOJO         ; 5
	dw PalSettings_POKECENTER   ; 6
	dw PalSettings_GYM          ; 7
	dw PalSettings_HOUSE        ; 8
	dw PalSettings_FOREST_GATE  ; 9
	dw PalSettings_MUSEUM       ; 10
	dw PalSettings_UNDERGROUND  ; 11
	dw PalSettings_GATE         ; 12
	dw PalSettings_SHIP         ; 13
	dw PalSettings_SHIP_PORT    ; 14
	dw PalSettings_CEMETERY     ; 15
	dw PalSettings_INTERIOR     ; 16
	dw PalSettings_CAVERN       ; 17
	dw PalSettings_LOBBY        ; 18
	dw PalSettings_MANSION      ; 19
	dw PalSettings_LAB          ; 20
	dw PalSettings_CLUB         ; 21
	dw PalSettings_FACILITY     ; 22
	dw PalSettings_PLATEAU      ; 23
	; DORM (24) is a Red Rogue addition (project_room_decoration_system) with
	; no shinpokered equivalent. PLACEHOLDER ONLY: points at the neutral
	; OVERWORLD table so the pointer table's shape is correct (NUM_TILESETS
	; entries) ahead of the engine landing. A real PalSettings_DORM needs
	; hand-authoring against DORM's actual tile IDs - ShinRed_Import.md Phase
	; 3.0b assigns that to Opus, not this mechanical pass.
	dw PalSettings_OVERWORLD    ; 24 DORM - PLACEHOLDER, not authored

ASSERT (@ - OverworldTilePalPointers) / 2 == NUM_TILESETS, "OverworldTilePalPointers entry count must track NUM_TILESETS (constants/tileset_constants.asm) - add a new dw row (and its PalSettings_* table) whenever a tileset is added"

; Assign a color register to be used for each tile in every tileset.
; A value of 8 is a "wild card" to set the color register based on the current
; town through MakeOverworldBGMapAttributes.townColor.
PalSettings_OVERWORLD:
;	00	01	02	03	04	05	06	07	08	09	0A	0B	0C	0D	0E	0F
	db	3,	6,	6,	1,	6,	8,	8,	8,	8,	8,	3,	6,	6,	3,	6,	3
;	10	11	12	13	14	15	16	17	18	19	1A	1B	1C	1D	1E	1F
	db	3,	6,	8,	6,	7,	8,	8,	8,	8,	8,	3,	6,	6,	3,	6,	3
;	20	21	22	23	24	25	26	27	28	29	2A	2B	2C	2D	2E	2F
	db	3,	3,	3,	3,	6,	8,	8,	6,	8,	8,	3,	3,	4,	4,	4,	3
;	30	31	32	33	34	35	36	37	38	39	3A	3B	3C	3D	3E	3F
	db	4,	6,	6,	6,	6,	6,	6,	6,	8,	4,	3,	3,	6,	4,	4,	3
;	40	41	42	43	44	45	46	47	48	49	4A	4B	4C	4D	4E	4F
	db	4,	4,	0,	0,	7,	7,	6,	6,	6,	6,	3,	3,	8,	8,	3,	3
;	50	51	52	53	54	55	56	57	58	59	5A	5B	5C	5D	5E	5F
	db	4,	4,	4,	8,	6,	6,	6,	6,	6,	6,	8,	0,	8,	8,	3,	3

PalSettings_REDS_HOUSE_1:
PalSettings_REDS_HOUSE_2:
;	00	01	02	03	04	05	06	07	08	09	0A	0B	0C	0D	0E	0F
	db	6,	3,	3,	3,	2,	3,	7,	7,	4,	4,	6,	6,	6,	6,	3,	3
;	10	11	12	13	14	15	16	17	18	19	1A	1B	1C	1D	1E	1F
	db	3,	3,	3,	3,	2,	3,	7,	7,	6,	6,	6,	6,	6,	6,	3,	3
;	20	21	22	23	24	25	26	27	28	29	2A	2B	2C	2D	2E	2F
	db	3,	3,	6,	6,	6,	6,	6,	6,	6,	6,	6,	6,	6,	6,	6,	6
;	30	31	32	33	34	35	36	37	38	39	3A	3B	3C	3D	3E	3F
	db	6,	6,	6,	6,	6,	6,	6,	6,	6,	6,	6,	6,	6,	3,	3,	6
;	40	41	42	43	44	45	46	47	48	49	4A	4B	4C	4D	4E	4F
	db	6,	6,	3,	3,	4,	4,	6,	6,	6,	6,	6,	6,	6,	6,	6,	6
;	50	51	52	53	54	55	56	57	58	59	5A	5B	5C	5D	5E	5F
	db	6,	6,	6,	6,	6,	6,	6,	6,	6,	6,	6,	6,	6,	3,	3,	3

PalSettings_FOREST:
;	00	01	02	03	04	05	06	07	08	09	0A	0B	0C	0D	0E	0F
	db	4,	3,	6,	6,	4,	4,	4,	4,	6,	6,	3,	3,	6,	6,	6,	6
;	10	11	12	13	14	15	16	17	18	19	1A	1B	1C	1D	1E	1F
	db	0,	0,	6,	6,	7,	4,	4,	4,	6,	6,	3,	3,	6,	6,	6,	6
;	20	21	22	23	24	25	26	27	28	29	2A	2B	2C	2D	2E	2F
	db	4,	6,	6,	4,	4,	4,	4,	4,	6,	6,	6,	6,	6,	6,	6,	6
;	30	31	32	33	34	35	36	37	38	39	3A	3B	3C	3D	3E	3F
	db	4,	6,	6,	3,	4,	6,	6,	3,	6,	4,	6,	6,	6,	6,	6,	6
;	40	41	42	43	44	45	46	47	48	49	4A	4B	4C	4D	4E	4F
	db	3,	3,	3,	3,	6,	6,	6,	6,	6,	6,	6,	3,	3,	6,	6,	6
;	50	51	52	53	54	55	56	57	58	59	5A	5B	5C	5D	5E	5F
	db	6,	6,	6,	6,	4,	4,	4,	4,	6,	6,	6,	6,	6,	6,	4,	4

PalSettings_MART:
PalSettings_POKECENTER:
;	00	01	02	03	04	05	06	07	08	09	0A	0B	0C	0D	0E	0F
	db	3,	4,	1,	1,	6,	6,	3,	3,	6,	3,	6,	4,	2,	3,	6,	6
;	10	11	12	13	14	15	16	17	18	19	1A	1B	1C	1D	1E	1F
	db	6,	4,	1,	1,	6,	6,	3,	6,	5,	5,	3,	4,	2,	6,	6,	6
;	20	21	22	23	24	25	26	27	28	29	2A	2B	2C	2D	2E	2F
	db	4,	4,	6,	6,	0,	0,	0,	0,	6,	6,	0,	0,	7,	7,	7,	7
;	30	31	32	33	34	35	36	37	38	39	3A	3B	3C	3D	3E	3F
	db	4,	4,	6,	6,	0,	0,	3,	0,	6,	3,	6,	6,	3,	0,	7,	7
;	40	41	42	43	44	45	46	47	48	49	4A	4B	4C	4D	4E	4F
	db	3,	3,	3,	3,	3,	3,	3,	3,	3,	3,	6,	6,	6,	6,	5,	5
;	50	51	52	53	54	55	56	57	58	59	5A	5B	5C	5D	5E	5F
	db	3,	3,	3,	3,	3,	3,	3,	3,	3,	6,	0,	0,	3,	3,	3,	3

PalSettings_DOJO:
PalSettings_GYM:
;	00	01	02	03	04	05	06	07	08	09	0A	0B	0C	0D	0E	0F
	db	3,	6,	6,	1,	6,	7,	5,	6,	6,	7,	7,	6,	6,	3,	3,	3
;	10	11	12	13	14	15	16	17	18	19	1A	1B	1C	1D	1E	1F
	db	7,	6,	6,	6,	7,	6,	5,	6,	6,	7,	7,	6,	6,	3,	3,	6
;	20	21	22	23	24	25	26	27	28	29	2A	2B	2C	2D	2E	2F
	db	6,	6,	3,	3,	3,	3,	3,	3,	0,	3,	3,	4,	4,	4,	4,	4
;	30	31	32	33	34	35	36	37	38	39	3A	3B	3C	3D	3E	3F
	db	6,	6,	3,	3,	7,	3,	3,	3,	6,	3,	7,	3,	2,	2,	7,	6
;	40	41	42	43	44	45	46	47	48	49	4A	4B	4C	4D	4E	4F
	db	4,	4,	7,	7,	7,	7,	7,	7,	3,	3,	3,	3,	2,	2,	3,	3
;	50	51	52	53	54	55	56	57	58	59	5A	5B	5C	5D	5E	5F
	db	4,	4,	7,	7,	7,	3,	7,	7,	6,	6,	6,	3,	3,	3,	3,	3

PalSettings_HOUSE:
;	00	01	02	03	04	05	06	07	08	09	0A	0B	0C	0D	0E	0F
	db	6,	3,	3,	3,	1,	3,	7,	7,	4,	4,	4,	4,	4,	4,	6,	6
;	10	11	12	13	14	15	16	17	18	19	1A	1B	1C	1D	1E	1F
	db	3,	3,	3,	3,	1,	3,	7,	7,	6,	6,	6,	6,	3,	3,	6,	6
;	20	21	22	23	24	25	26	27	28	29	2A	2B	2C	2D	2E	2F
	db	3,	3,	2,	6,	6,	6,	6,	6,	6,	6,	4,	4,	6,	6,	6,	6
;	30	31	32	33	34	35	36	37	38	39	3A	3B	3C	3D	3E	3F
	db	6,	6,	6,	6,	6,	6,	6,	6,	6,	6,	6,	6,	6,	6,	6,	6
;	40	41	42	43	44	45	46	47	48	49	4A	4B	4C	4D	4E	4F
	db	6,	6,	3,	3,	3,	3,	6,	6,	6,	6,	6,	6,	6,	6,	6,	6
;	50	51	52	53	54	55	56	57	58	59	5A	5B	5C	5D	5E	5F
	db	6,	6,	6,	6,	6,	6,	6,	6,	6,	6,	6,	6,	6,	6,	3,	3

PalSettings_FOREST_GATE:
PalSettings_MUSEUM:
PalSettings_GATE:
;	00	01	02	03	04	05	06	07	08	09	0A	0B	0C	0D	0E	0F
	db	6,	4,	3,	3,	7,	4,	4,	4,	4,	4,	3,	3,	3,	3,	3,	3
;	10	11	12	13	14	15	16	17	18	19	1A	1B	1C	1D	1E	1F
	db	3,	3,	3,	3,	7,	4,	4,	4,	4,	7,	3,	3,	3,	3,	3,	3
;	20	21	22	23	24	25	26	27	28	29	2A	2B	2C	2D	2E	2F
	db	3,	3,	3,	3,	3,	6,	6,	7,	7,	6,	6,	6,	7,	7,	7,	4
;	30	31	32	33	34	35	36	37	38	39	3A	3B	3C	3D	3E	3F
	db	7,	7,	6,	6,	3,	6,	6,	7,	7,	3,	7,	6,	7,	7,	7,	3
;	40	41	42	43	44	45	46	47	48	49	4A	4B	4C	4D	4E	4F
	db	3,	3,	3,	3,	3,	3,	7,	7,	1,	3,	1,	3,	3,	3,	2,	2
;	50	51	52	53	54	55	56	57	58	59	5A	5B	5C	5D	5E	5F
	db	3,	3,	3,	3,	3,	3,	3,	3,	3,	3,	3,	3,	3,	3,	7,	3

PalSettings_UNDERGROUND:
;	00	01	02	03	04	05	06	07	08	09	0A	0B	0C	0D	0E	0F
	db	3,	2,	7,	1,	1,	7,	7,	7,	7,	7,	7,	1,	1,	0,	0,	0
;	10	11	12	13	14	15	16	17	18	19	1A	1B	1C	1D	1E	1F
	db	3,	7,	7,	1,	1,	1,	7,	7,	1,	0,	0,	0,	0,	0,	0,	0
;	20	21	22	23	24	25	26	27	28	29	2A	2B	2C	2D	2E	2F
	db	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0
;	30	31	32	33	34	35	36	37	38	39	3A	3B	3C	3D	3E	3F
	db	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0
;	40	41	42	43	44	45	46	47	48	49	4A	4B	4C	4D	4E	4F
	db	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0
;	50	51	52	53	54	55	56	57	58	59	5A	5B	5C	5D	5E	5F
	db	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0

PalSettings_SHIP:
;	00	01	02	03	04	05	06	07	08	09	0A	0B	0C	0D	0E	0F
	db	3,	3,	7,	7,	6,	3,	3,	7,	7,	3,	3,	3,	3,	7,	0,	0
;	10	11	12	13	14	15	16	17	18	19	1A	1B	1C	1D	1E	1F
	db	3,	0,	7,	7,	7,	3,	3,	7,	7,	3,	3,	3,	3,	7,	0,	0
;	20	21	22	23	24	25	26	27	28	29	2A	2B	2C	2D	2E	2F
	db	3,	3,	0,	6,	0,	3,	3,	3,	3,	3,	3,	0,	3,	3,	5,	5
;	30	31	32	33	34	35	36	37	38	39	3A	3B	3C	3D	3E	3F
	db	7,	7,	0,	3,	0,	3,	0,	3,	3,	3,	3,	3,	3,	3,	5,	5
;	40	41	42	43	44	45	46	47	48	49	4A	4B	4C	4D	4E	4F
	db	3,	3,	7,	7,	3,	3,	3,	3,	7,	7,	6,	3,	3,	3,	3,	3
;	50	51	52	53	54	55	56	57	58	59	5A	5B	5C	5D	5E	5F
	db	3,	3,	3,	3,	7,	7,	3,	3,	7,	7,	3,	3,	3,	3,	3,	3

PalSettings_SHIP_PORT:
;	00	01	02	03	04	05	06	07	08	09	0A	0B	0C	0D	0E	0F
	db	7,	0,	7,	7,	7,	7,	7,	7,	7,	7,	6,	7,	7,	7,	7,	7
;	10	11	12	13	14	15	16	17	18	19	1A	1B	1C	1D	1E	1F
	db	7,	7,	7,	7,	7,	7,	7,	7,	7,	7,	7,	7,	7,	7,	7,	7
;	20	21	22	23	24	25	26	27	28	29	2A	2B	2C	2D	2E	2F
	db	7,	7,	7,	7,	7,	7,	7,	7,	7,	7,	7,	7,	7,	7,	7,	7
;	30	31	32	33	34	35	36	37	38	39	3A	3B	3C	3D	3E	3F
	db	7,	3,	6,	7,	7,	7,	7,	7,	7,	7,	6,	6,	6,	7,	7,	7
;	40	41	42	43	44	45	46	47	48	49	4A	4B	4C	4D	4E	4F
	db	7,	7,	7,	7,	7,	7,	7,	7,	6,	6,	6,	6,	6,	7,	7,	7
;	50	51	52	53	54	55	56	57	58	59	5A	5B	5C	5D	5E	5F
	db	0,	7,	7,	7,	7,	7,	0,	0,	6,	6,	7,	7,	7,	7,	7,	7

PalSettings_CEMETERY:
;	00	01	02	03	04	05	06	07	08	09	0A	0B	0C	0D	0E	0F
	db	3,	2,	6,	3,	3,	3,	3,	6,	6,	3,	3,	3,	3,	6,	6,	4
;	10	11	12	13	14	15	16	17	18	19	1A	1B	1C	1D	1E	1F
	db	4,	3,	6,	3,	3,	3,	3,	6,	6,	3,	3,	3,	3,	6,	6,	4
;	20	21	22	23	24	25	26	27	28	29	2A	2B	2C	2D	2E	2F
	db	4,	4,	7,	4,	3,	3,	6,	2,	6,	6,	2,	2,	2,	2,	2,	2
;	30	31	32	33	34	35	36	37	38	39	3A	3B	3C	3D	3E	3F
	db	4,	4,	4,	4,	3,	6,	6,	2,	6,	6,	2,	2,	2,	3,	3,	2
;	40	41	42	43	44	45	46	47	48	49	4A	4B	4C	4D	4E	4F
	db	3,	3,	4,	3,	6,	6,	6,	3,	6,	6,	3,	3,	3,	3,	7,	6
;	50	51	52	53	54	55	56	57	58	59	5A	5B	5C	5D	5E	5F
	db	3,	3,	4,	6,	6,	2,	3,	4,	3,	4,	3,	3,	0,	0,	0,	0

PalSettings_INTERIOR:
;	00	01	02	03	04	05	06	07	08	09	0A	0B	0C	0D	0E	0F
	db	3,	3,	3,	7,	7,	3,	3,	3,	3,	3,	3,	3,	3,	3,	3,	3
;	10	11	12	13	14	15	16	17	18	19	1A	1B	1C	1D	1E	1F
	db	3,	6,	6,	2,	2,	3,	3,	3,	3,	3,	3,	3,	3,	3,	3,	7
;	20	21	22	23	24	25	26	27	28	29	2A	2B	2C	2D	2E	2F
	db	7,	6,	6,	2,	2,	7,	7,	3,	3,	3,	3,	3,	3,	6,	6,	3
;	30	31	32	33	34	35	36	37	38	39	3A	3B	3C	3D	3E	3F
	db	7,	2,	2,	2,	3,	7,	7,	3,	3,	3,	3,	3,	3,	3,	3,	6
;	40	41	42	43	44	45	46	47	48	49	4A	4B	4C	4D	4E	4F
	db	6,	2,	2,	2,	2,	7,	4,	4,	6,	6,	6,	6,	6,	6,	6,	6
;	50	51	52	53	54	55	56	57	58	59	5A	5B	5C	5D	5E	5F
	db	3,	6,	6,	1,	1,	1,	1,	6,	6,	6,	6,	6,	6,	3,	3,	3

PalSettings_CAVERN:
;	00	01	02	03	04	05	06	07	08	09	0A	0B	0C	0D	0E	0F
	db	3,	3,	6,	6,	3,	6,	3,	3,	3,	3,	3,	3,	3,	3,	3,	3
;	10	11	12	13	14	15	16	17	18	19	1A	1B	1C	1D	1E	1F
	db	6,	6,	6,	6,	7,	6,	6,	6,	3,	3,	3,	3,	3,	3,	3,	3
;	20	21	22	23	24	25	26	27	28	29	2A	2B	2C	2D	2E	2F
	db	3,	5,	3,	3,	3,	6,	6,	3,	6,	6,	6,	3,	3,	3,	3,	3
;	30	31	32	33	34	35	36	37	38	39	3A	3B	3C	3D	3E	3F
	db	3,	6,	7,	7,	7,	7,	7,	7,	7,	7,	7,	7,	3,	6,	6,	6
;	40	41	42	43	44	45	46	47	48	49	4A	4B	4C	4D	4E	4F
	db	6,	6,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0
;	50	51	52	53	54	55	56	57	58	59	5A	5B	5C	5D	5E	5F
	db	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0

PalSettings_LOBBY:
;	00	01	02	03	04	05	06	07	08	09	0A	0B	0C	0D	0E	0F
	db	3,	4,	3,	3,	0,	7,	4,	2,	2,	7,	3,	3,	3,	3,	3,	3
;	10	11	12	13	14	15	16	17	18	19	1A	1B	1C	1D	1E	1F
	db	3,	7,	3,	3,	0,	7,	4,	2,	2,	7,	3,	3,	3,	3,	3,	3
;	20	21	22	23	24	25	26	27	28	29	2A	2B	2C	2D	2E	2F
	db	2,	4,	7,	7,	7,	7,	7,	7,	5,	7,	3,	3,	3,	3,	3,	3
;	30	31	32	33	34	35	36	37	38	39	3A	3B	3C	3D	3E	3F
	db	7,	7,	7,	7,	7,	7,	7,	2,	5,	7,	3,	3,	3,	3,	7,	4
;	40	41	42	43	44	45	46	47	48	49	4A	4B	4C	4D	4E	4F
	db	3,	3,	3,	3,	7,	3,	7,	7,	4,	4,	3,	7,	7,	7,	7,	7
;	50	51	52	53	54	55	56	57	58	59	5A	5B	5C	5D	5E	5F
	db	3,	3,	3,	3,	7,	7,	3,	3,	4,	4,	3,	2,	7,	7,	3,	0

PalSettings_MANSION:
;	00	01	02	03	04	05	06	07	08	09	0A	0B	0C	0D	0E	0F
	db	3,	3,	7,	7,	4,	7,	1,	1,	4,	4,	3,	3,	3,	3,	3,	1
;	10	11	12	13	14	15	16	17	18	19	1A	1B	1C	1D	1E	1F
	db	3,	7,	7,	7,	4,	5,	1,	1,	6,	6,	3,	3,	3,	3,	1,	1
;	20	21	22	23	24	25	26	27	28	29	2A	2B	2C	2D	2E	2F
	db	7,	1,	6,	6,	3,	3,	6,	6,	5,	6,	1,	1,	3,	6,	6,	6
;	30	31	32	33	34	35	36	37	38	39	3A	3B	3C	3D	3E	3F
	db	1,	1,	6,	6,	3,	3,	6,	6,	5,	6,	6,	6,	6,	3,	3,	6
;	40	41	42	43	44	45	46	47	48	49	4A	4B	4C	4D	4E	4F
	db	3,	3,	3,	3,	4,	4,	6,	6,	1,	1,	1,	1,	3,	3,	1,	3
;	50	51	52	53	54	55	56	57	58	59	5A	5B	5C	5D	5E	5F
	db	6,	1,	1,	1,	1,	7,	7,	5,	1,	1,	1,	1,	1,	1,	3,	0

PalSettings_LAB:
;	00	01	02	03	04	05	06	07	08	09	0A	0B	0C	0D	0E	0F
	db	3,	1,	3,	3,	3,	3,	6,	6,	6,	6,	3,	3,	3,	3,	3,	3
;	10	11	12	13	14	15	16	17	18	19	1A	1B	1C	1D	1E	1F
	db	6,	6,	3,	3,	3,	3,	6,	6,	3,	3,	3,	3,	7,	7,	3,	3
;	20	21	22	23	24	25	26	27	28	29	2A	2B	2C	2D	2E	2F
	db	6,	6,	6,	6,	7,	7,	3,	7,	6,	6,	6,	6,	4,	4,	6,	6
;	30	31	32	33	34	35	36	37	38	39	3A	3B	3C	3D	3E	3F
	db	6,	6,	6,	6,	5,	5,	3,	7,	3,	3,	6,	7,	4,	4,	6,	6
;	40	41	42	43	44	45	46	47	48	49	4A	4B	4C	4D	4E	4F
	db	6,	6,	6,	6,	6,	3,	3,	7,	6,	6,	3,	3,	5,	5,	7,	3
;	50	51	52	53	54	55	56	57	58	59	5A	5B	5C	5D	5E	5F
	db	6,	6,	6,	6,	6,	3,	3,	7,	7,	7,	3,	3,	3,	0,	0,	0

PalSettings_CLUB:
;	00	01	02	03	04	05	06	07	08	09	0A	0B	0C	0D	0E	0F
	db	0,	6,	6,	6,	0,	1,	6,	1,	1,	0,	4,	0,	0,	7,	0,	3
;	10	11	12	13	14	15	16	17	18	19	1A	1B	1C	1D	1E	1F
	db	1,	6,	6,	6,	0,	7,	7,	2,	2,	3,	4,	0,	0,	7,	3,	3
;	20	21	22	23	24	25	26	27	28	29	2A	2B	2C	2D	2E	2F
	db	7,	7,	7,	7,	7,	7,	7,	7,	0,	0,	7,	7,	0,	0,	0,	0
;	30	31	32	33	34	35	36	37	38	39	3A	3B	3C	3D	3E	3F
	db	1,	1,	1,	1,	5,	5,	1,	3,	3,	3,	3,	3,	3,	3,	3,	4
;	40	41	42	43	44	45	46	47	48	49	4A	4B	4C	4D	4E	4F
	db	3,	3,	4,	4,	4,	4,	4,	3,	3,	3,	3,	3,	0,	0,	0,	0
;	50	51	52	53	54	55	56	57	58	59	5A	5B	5C	5D	5E	5F
	db	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0

PalSettings_FACILITY:
;	00	01	02	03	04	05	06	07	08	09	0A	0B	0C	0D	0E	0F
	db	3,	3,	6,	3,	3,	4,	4,	6,	3,	6,	6,	3,	3,	6,	6,	6
;	10	11	12	13	14	15	16	17	18	19	1A	1B	1C	1D	1E	1F
	db	3,	3,	6,	3,	7,	4,	4,	6,	3,	6,	6,	3,	3,	6,	6,	6
;	20	21	22	23	24	25	26	27	28	29	2A	2B	2C	2D	2E	2F
	db	2,	2,	1,	5,	3,	3,	6,	2,	6,	6,	7,	7,	7,	7,	7,	2
;	30	31	32	33	34	35	36	37	38	39	3A	3B	3C	3D	3E	3F
	db	2,	2,	1,	3,	3,	6,	6,	2,	6,	6,	7,	7,	7,	3,	3,	2
;	40	41	42	43	44	45	46	47	48	49	4A	4B	4C	4D	4E	4F
	db	3,	3,	1,	3,	6,	6,	5,	7,	5,	5,	3,	3,	3,	3,	3,	6
;	50	51	52	53	54	55	56	57	58	59	5A	5B	5C	5D	5E	5F
	db	3,	3,	1,	6,	6,	3,	3,	7,	3,	7,	3,	3,	7,	7,	3,	7

PalSettings_PLATEAU:
;	00	01	02	03	04	05	06	07	08	09	0A	0B	0C	0D	0E	0F
	db	3,	6,	6,	7,	7,	3,	3,	4,	4,	6,	6,	6,	6,	7,	7,	7
;	10	11	12	13	14	15	16	17	18	19	1A	1B	1C	1D	1E	1F
	db	7,	6,	7,	0,	7,	3,	3,	4,	4,	6,	6,	6,	6,	6,	6,	6
;	20	21	22	23	24	25	26	27	28	29	2A	2B	2C	2D	2E	2F
	db	7,	7,	6,	3,	6,	7,	7,	6,	7,	7,	6,	6,	4,	4,	3,	3
;	30	31	32	33	34	35	36	37	38	39	3A	3B	3C	3D	3E	3F
	db	3,	3,	6,	6,	6,	6,	6,	6,	6,	6,	6,	6,	6,	8,	8,	8
;	40	41	42	43	44	45	46	47	48	49	4A	4B	4C	4D	4E	4F
	db	8,	8,	8,	8,	8,	4,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0
;	50	51	52	53	54	55	56	57	58	59	5A	5B	5C	5D	5E	5F
	db	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0
