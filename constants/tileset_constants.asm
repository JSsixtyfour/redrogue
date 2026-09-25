; tileset ids
; Tilesets indexes (see data/tilesets/tileset_headers.asm)
	const_def
	const OVERWORLD    ; 0
	const REDS_HOUSE_1 ; 1
	const MART         ; 2
	const FOREST       ; 3
	const REDS_HOUSE_2 ; 4
	const DOJO         ; 5
	const POKECENTER   ; 6
	const GYM          ; 7
	const HOUSE        ; 8
	const FOREST_GATE  ; 9
	const MUSEUM       ; 10
	const UNDERGROUND  ; 11
	const GATE         ; 12
	const SHIP         ; 13
	const SHIP_PORT    ; 14
	const CEMETERY     ; 15
	const INTERIOR     ; 16
	const CAVERN       ; 17
	const LOBBY        ; 18
	const MANSION      ; 19
	const LAB          ; 20
	const CLUB         ; 21
	const FACILITY     ; 22
	const PLATEAU      ; 23
	const DORM         ; 24
DEF NUM_TILESETS EQU const_value

; Every tileset owns vChars2 tiles $00-$5F. DORM alone also owns $60-$78, the
; font_extra glyph slots no text needs (pret wiki "Expanding Tilesets
; Technique", applied to one tileset). Six of those slots still hold live
; glyphs and are baked into dorm.png at the same IDs: <COLON> $6D, the quotes
; $70-$73 and the ellipsis $75. Only $79-$7F (box borders and space) stay
; font_extra's. See LoadTilesetTilePatternData_ / LoadTextBoxTilePatterns_.
DEF NUM_TILESET_TILES          EQU $60
DEF NUM_EXTENDED_TILESET_TILES EQU $79
