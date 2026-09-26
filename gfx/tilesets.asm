SECTION "Tilesets 1", ROMX

Overworld_GFX::     INCBIN "gfx/tilesets/overworld.2bpp"
Overworld_Block::   INCBIN "gfx/blocksets/overworld.bst"

; LoadTilesetTilePatternData always copies $600 bytes. Mini Saffron's artwork
; is $5e0 bytes, so preserve Overworld's stable following $20 bytes as its
; final two tile slots rather than letting the compact private blockset become
; graphics.
MiniSaffron_GFX::
	INCBIN "gfx/tilesets/minisaffron.2bpp"
	INCBIN "gfx/blocksets/overworld.bst", 0, $20
MiniSaffron_Block:: INCBIN "gfx/blocksets/minisaffron.bst"

RedsHouse1_GFX::
RedsHouse2_GFX::    INCBIN "gfx/tilesets/reds_house.2bpp"
RedsHouse1_Block::
RedsHouse2_Block::  INCBIN "gfx/blocksets/reds_house.bst"

House_GFX::         INCBIN "gfx/tilesets/house.2bpp"
House_Block::       INCBIN "gfx/blocksets/house.bst"
Mansion_GFX::       INCBIN "gfx/tilesets/mansion.2bpp"
Mansion_Block::     INCBIN "gfx/blocksets/mansion.bst"
Interior_GFX::      INCBIN "gfx/tilesets/interior.2bpp"
Interior_Block::    INCBIN "gfx/blocksets/interior.bst"
Plateau_GFX::       INCBIN "gfx/tilesets/plateau.2bpp"
Plateau_Block::     INCBIN "gfx/blocksets/plateau.bst"


SECTION "Tilesets 2", ROMX

Dojo_GFX::
Gym_GFX::           INCBIN "gfx/tilesets/gym.2bpp"
Dojo_Block::
Gym_Block::         INCBIN "gfx/blocksets/gym.bst"

Mart_GFX::
Pokecenter_GFX::    INCBIN "gfx/tilesets/pokecenter.2bpp"
Mart_Block::
Pokecenter_Block::  INCBIN "gfx/blocksets/pokecenter.bst"

ForestGate_GFX::
Museum_GFX::
Gate_GFX::          INCBIN "gfx/tilesets/gate.2bpp"
ForestGate_Block::
Museum_Block::
Gate_Block::        INCBIN "gfx/blocksets/gate.bst"

Forest_GFX::        INCBIN "gfx/tilesets/forest.2bpp"
Forest_Block::      INCBIN "gfx/blocksets/forest.bst"

; Underground moved here from "Tilesets 3" (ROMX $1B) on 2026-09-25: that bank
; was exactly full and the Ship tileset/blockset growth pushed it 80 bytes over.
; Same bank-safety argument as Facility below: the tileset header stores
; BANK(Underground_GFX), and GFX + Block stay together in one bank.
Underground_GFX::   INCBIN "gfx/tilesets/underground.2bpp"
Underground_Block:: INCBIN "gfx/blocksets/underground.bst"


SECTION "Tilesets 3", ROMX

Cemetery_GFX::      INCBIN "gfx/tilesets/cemetery.2bpp"
Cemetery_Block::    INCBIN "gfx/blocksets/cemetery.bst"
Cavern_GFX::        INCBIN "gfx/tilesets/cavern.2bpp"
Cavern_Block::      INCBIN "gfx/blocksets/cavern.bst"
Lobby_GFX::         INCBIN "gfx/tilesets/lobby.2bpp"
Lobby_Block::       INCBIN "gfx/blocksets/lobby.bst"
Ship_GFX::          INCBIN "gfx/tilesets/ship.2bpp"
Ship_Block::        INCBIN "gfx/blocksets/ship.bst"
Lab_GFX::           INCBIN "gfx/tilesets/lab.2bpp"
Lab_Block::         INCBIN "gfx/blocksets/lab.bst"
Club_GFX::          INCBIN "gfx/tilesets/club.2bpp"
Club_Block::        INCBIN "gfx/blocksets/club.bst"


SECTION "Tilesets 4", ROMX

ShipPort_GFX::      INCBIN "gfx/tilesets/ship_port.2bpp"
ShipPort_Block::    INCBIN "gfx/blocksets/ship_port.bst"
; dorm.png is 128 slots; $00-$78 load (constants/tileset_constants.asm).
;   free for art: $60-$6C, $6E-$6F, $74, $76-$78 (19 tiles)
;   RESERVED, live text glyphs, keep byte-identical to font_extra:
;     $6D <COLON>, $70-$73 quotes, $75 ellipsis
;   $79-$7F are text-box borders, never loaded from here.
Dorm_GFX::          INCBIN "gfx/tilesets/dorm.2bpp"
Dorm_Block::        INCBIN "gfx/blocksets/dorm.bst"


; Facility lives alone in its own bank. It was in "Tilesets 2" (ROMX $1A) until
; 2026-09-16, ending flush at $7fb0 with 80 bytes left in that bank, which is
; five blocks. The procedural generator keeps needing new structural blocks
; (the wall end caps, and the 12 corner caps after them), so the pair was moved
; somewhere it can grow instead of being rationed. Both consumers switch to
; BANK(Facility_GFX) before reading: LoadCurrentMapView writes wTilesetBank to
; rROMB before DrawTileBlock dereferences wTilesetBlocksPtr, and
; LoadTilesetTilePatternData goes through FarCopyData2. Facility_Coll is in
; ROM0 at $1848 and is always mapped, so it neither moves nor cares.
;
; _GFX must stay immediately before _Block: LoadTilesetTilePatternData always
; copies $600 bytes regardless of the artwork's real size, and facility.2bpp is
; exactly $600, so the copy stops precisely where the blockset begins.
SECTION "Tilesets 5", ROMX

Facility_GFX::      INCBIN "gfx/tilesets/facility.2bpp"
Facility_Block::    INCBIN "gfx/blocksets/facility.bst"
