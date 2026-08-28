_RunPaletteCommand:
	; Enhanced overworld palettes are valid only when SetPal_Overworld installs
	; them below. Clear the transient state before dispatching any palette
	; command so menus and other non-overworld screens use their normal path.
	ld hl, wRogueFlagsBitfield2
	res 3, [hl]

	call GetPredefRegisters
	ld a, b
	cp SET_PAL_DEFAULT
	jr nz, .not_default
	ld a, [wDefaultPaletteCommand]
.not_default
	cp SET_PAL_PARTY_MENU_HP_BARS
	jp z, UpdatePartyMenuBlkPacket
	ld l, a
	ld h, 0
	add hl, hl
	ld de, SetPalFunctions
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld de, SendSGBPackets
	push de
	jp hl

SetPal_BattleBlack:
	ld hl, PalPacket_Black
	ld de, BlkPacket_Battle
	ret

; uses PalPacket_Empty to build a packet based on mon IDs and health color
SetPal_Battle:
	ld hl, PalPacket_Empty
	ld de, wPalPacket
	ld bc, $10
	call CopyData
	ld a, [wPlayerBattleStatus3]
	ld hl, wBattleMonSpecies
	call DeterminePaletteID
	ld b, a
	ld a, [wEnemyBattleStatus3]
	ld hl, wEnemyMonSpecies2
	call DeterminePaletteID
	ld c, a
	ld hl, wPalPacket + 1
	ld a, [wPlayerHPBarColor]
	add PAL_GREENBAR
	ld [hli], a
	inc hl
	ld a, [wEnemyHPBarColor]
	add PAL_GREENBAR
	ld [hli], a
	inc hl
	ld a, b
	ld [hli], a
	inc hl
	ld a, c
	ld [hl], a
	; Shiny (func_shiny.asm) runs FIRST so that a ghost or type variant below
	; simply overwrites it. Ordering is what gives those two systems priority -
	; NOT an override test. An earlier version compared wPalPacket+5 against the
	; original palette still supposedly in b, which is wrong: `farcall` expands
	; to `ld b, BANK(...)`, so b is destroyed before the callee even runs and
	; the compare was reading a bank number. Player only - enemies can never be
	; shiny (see func_shiny.asm).
	ld de, wBattleMon
	farcall IsShiny
	jr z, .playerNotShiny
	ld a, [wPalPacket + 5]
	call ShinyPaletteConvert
	ld [wPalPacket + 5], a
.playerNotShiny
	; Ghost variant (func_ghost_variant.asm): recolor the player (+5) / enemy (+7)
	; mon palette slot to purple if that mon is a ghost variant. de-input (farcall
	; clobbers hl); must run after +5/+7 are written above.
	ld de, wBattleMon
	farcall IsGhostVariant
	jr z, .playerNotGhostVariant
	ld a, PAL_PURPLEMON
	ld [wPalPacket + 5], a
.playerNotGhostVariant
	; Type variant (func_special_form.asm): blue/gray by stored MON_TYPE2.
	; Palette comes back in e (a can't survive the farcall).
	ld de, wBattleMon
	farcall GetTypeVariantPalette
	ld a, e
	and a
	jr z, .playerNotTypeVariant
	ld [wPalPacket + 5], a
.playerNotTypeVariant
	ld de, wEnemyMon
	farcall IsGhostVariant
	jr z, .enemyNotGhostVariant
	ld a, PAL_PURPLEMON
	ld [wPalPacket + 7], a
.enemyNotGhostVariant
	ld de, wEnemyMon
	farcall GetTypeVariantPalette
	ld a, e
	and a
	jr z, .enemyNotTypeVariant
	ld [wPalPacket + 7], a
.enemyNotTypeVariant
	ld hl, wPalPacket
	ld de, BlkPacket_Battle
	ld a, SET_PAL_BATTLE
	ld [wDefaultPaletteCommand], a
	ret

SetPal_TownMap:
	ld hl, PalPacket_TownMap
	ld de, BlkPacket_WholeScreen
	ret

; uses PalPacket_Empty to build a packet based the mon ID
SetPal_StatusScreen:
	ld hl, PalPacket_Empty
	ld de, wPalPacket
	ld bc, $10
	call CopyData
	ld a, [wCurPartySpecies]
	cp NUM_POKEMON_INDEXES + 1
	jr c, .pokemon
	ld a, $1 ; not pokemon
.pokemon
	call DeterminePaletteIDOutOfBattle
	push af
	ld hl, wPalPacket + 1
	ld a, [wStatusScreenHPBarColor]
	add PAL_GREENBAR
	ld [hli], a
	inc hl
	pop af
	ld [hl], a
	; Shiny (func_shiny.asm) runs FIRST so ghost/type variant below overwrites
	; it - same ordering rule and same reason as SetPal_Battle above.
	ld de, wLoadedMon
	farcall IsShiny
	jr z, .notShiny
	ld a, [wPalPacket + 3]
	call ShinyPaletteConvert
	ld [wPalPacket + 3], a
.notShiny
	; Ghost variant: purple palette for the status-screen mon (+3) if it's a variant.
	ld de, wLoadedMon
	farcall IsGhostVariant
	jr z, .notGhostVariant
	ld a, PAL_PURPLEMON
	ld [wPalPacket + 3], a
.notGhostVariant
	; Type variant (func_special_form.asm): blue/gray by stored MON_TYPE2.
	; Palette comes back in e (a can't survive the farcall).
	ld de, wLoadedMon
	farcall GetTypeVariantPalette
	ld a, e
	and a
	jr z, .notTypeVariant
	ld [wPalPacket + 3], a
.notTypeVariant
	ld hl, wPalPacket
	ld de, BlkPacket_StatusScreen
	ret

; ============================================================
; ShinyPaletteConvert — map a mon's normal palette to its shiny one.
;
; Ported from shinpokered's ShinyDVConvert (custom_functions/func_shiny.asm in
; that repo). The key idea, and the reason no new SGB palette data is needed:
; a shiny mon REUSES another existing mon palette rather than getting a
; bespoke one. The ten mon palettes are permuted in a single cycle
; (MEW->YELLOW->BROWN->RED->PINK->CYAN->GREEN->BLUE->PURPLE->GRAY->MEW).
; Shin implements this as a cp/jr chain; a table is the same mapping in far
; fewer bytes, since PAL_MEWMON..PAL_GRAYMON are contiguous here.
;
; INPUT:  a = normal palette id
; OUTPUT: a = shiny palette id, or a unchanged if it is not a mon palette
;         (DeterminePaletteIDOutOfBattle can return non-mon palettes for the
;         "not a pokemon" case, so the range guard is load-bearing).
; CLOBBERS: de, hl
; ============================================================
ShinyPaletteConvert:
	sub PAL_MEWMON
	cp PAL_GRAYMON - PAL_MEWMON + 1
	jr c, .isMonPalette
	add PAL_MEWMON                 ; out of range - hand back what we were given
	ret
.isMonPalette
	ld e, a
	ld d, 0
	ld hl, ShinyPaletteMap
	add hl, de
	ld a, [hl]
	ret

; Indexed by (normal palette - PAL_MEWMON). Order must match the PAL_*MON
; constant block in constants/palette_constants.asm.
ShinyPaletteMap:
	db PAL_YELLOWMON  ; PAL_MEWMON
	db PAL_PURPLEMON  ; PAL_BLUEMON
	db PAL_PINKMON    ; PAL_REDMON
	db PAL_GREENMON   ; PAL_CYANMON
	db PAL_GRAYMON    ; PAL_PURPLEMON
	db PAL_REDMON     ; PAL_BROWNMON
	db PAL_BLUEMON    ; PAL_GREENMON
	db PAL_CYANMON    ; PAL_PINKMON
	db PAL_BROWNMON   ; PAL_YELLOWMON
	db PAL_MEWMON     ; PAL_GRAYMON

SetPal_PartyMenu:
	ld hl, PalPacket_PartyMenu
	ld de, wPartyMenuBlkPacket
	ret

SetPal_Pokedex:
	ld hl, PalPacket_Pokedex
	ld de, wPalPacket
	ld bc, $10
	call CopyData
	ld a, [wCurPartySpecies]
	call DeterminePaletteIDOutOfBattle
	ld hl, wPalPacket + 3
	ld [hl], a
	ld hl, wPalPacket
	ld de, BlkPacket_Pokedex
	ret

SetPal_Slots:
	ld hl, PalPacket_Slots
	ld de, BlkPacket_Slots
	ret

SetPal_TitleScreen:
	ld hl, PalPacket_Titlescreen
	ld de, BlkPacket_Titlescreen
	ret

; used mostly for menus and the Oak intro
SetPal_Generic:
	ld hl, PalPacket_Generic
	ld de, BlkPacket_WholeScreen
	ret

SetPal_NidorinoIntro:
	ld hl, PalPacket_NidorinoIntro
	ld de, BlkPacket_NidorinoIntro
	ret

SetPal_GameFreakIntro:
	ld hl, PalPacket_GameFreakIntro
	ld de, BlkPacket_GameFreakIntro
	ld a, SET_PAL_GENERIC
	ld [wDefaultPaletteCommand], a
	ret

; uses PalPacket_Empty to build a packet based on the current map
SetPal_Overworld:
	; ShinRed handles the enhanced overworld as a complete alternate palette
	; command: build and transfer attributes, install the enhanced palettes, and
	; skip SendSGBPackets. Keep that work in its existing far bank so this tight
	; palette bank only owns the mode dispatch.
	ldh a, [hGBC]
	and a
	jr z, .normalColors
	ld a, [wOptions2]
	bit BIT_ENHANCED_COLORS, a
	jr z, .normalColors
	farcall LoadEnhancedOverworldPaletteCommand
	pop de ; discard the SendSGBPackets return address pushed by _RunPaletteCommand
	ret
.normalColors
	ld hl, PalPacket_Empty
	ld de, wPalPacket
	ld bc, $10
	call CopyData
	ld a, [wCurMapTileset]
	cp CEMETERY
	jr z, .PokemonTowerOrAgatha
	cp CAVERN
	jr z, .caveOrBruno
	cp FACILITY
	jr z, .facilityTileset
	ldh a, [hCurMap]
	cp PROCEDURAL_FOREST
	jr z, .procForest    ; force a green forest palette; without this the
	                     ; procedural forest ($F2, dungeon-range map ID) falls
	                     ; through to wLastMap = Pallet Town = PAL_PALLET (blue).
	                     ; Mirrors how CAVERN is special-cased to PAL_CAVE.
	cp FIRST_INDOOR_MAP
	jr c, .townOrRoute
	cp CERULEAN_CAVE_2F
	jr c, .normalDungeonOrBuilding
	cp CERULEAN_CAVE_1F + 1
	jr c, .caveOrBruno
	cp LORELEIS_ROOM
	jr z, .Lorelei
	cp BRUNOS_ROOM
	jr z, .caveOrBruno
.normalDungeonOrBuilding
	ld a, [wLastMap] ; town or route that current dungeon or building is located
.townOrRoute
	cp NUM_CITY_MAPS
	jr c, .town
	ld a, PAL_ROUTE - 1
.town
	inc a ; a town's palette ID is its map ID + 1
	ld hl, wPalPacket + 1
	ld [hld], a
	ld de, BlkPacket_WholeScreen
	ld a, SET_PAL_OVERWORLD
	ld [wDefaultPaletteCommand], a
	ret
.PokemonTowerOrAgatha
	ld a, PAL_GRAYMON - 1
	jr .town
.caveOrBruno
	ld a, PAL_CAVE - 1
	jr .town
.procForest
	ld a, PAL_VIRIDIAN - 1  ; +1 in .town → PAL_VIRIDIAN (the green forest palette)
	jr .town
.facilityTileset
	; FACILITY tileset. The procedural facility ($F3) gets a randomized
	; Mansion/PowerPlant palette (sProcFacilityPalette, rolled at Pallet Town
	; entry). Other FACILITY maps (Power Plant, Pokemon Mansion) keep their
	; normal location palette — add their map IDs here to opt them in.
	ldh a, [hCurMap]
	cp PROCEDURAL_FACILITY
	jr z, .facilityRandom
	jr .normalDungeonOrBuilding
.facilityRandom
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ld a, BANK(sProcFacilityStagingBuffer)  ; facility SRAM is bank 1
	ld [rRAMB], a
	ld a, [sProcFacilityPalette]
	ld b, a
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ld a, b
	and a
	jr nz, .facilityMansion
	ld a, PAL_ROUTE - 1     ; 0 = PowerPlant (greenish route palette)
	jr .town
.facilityMansion
	ld a, PAL_CINNABAR - 1  ; 1 = Mansion (reddish Cinnabar palette)
	jr .town
.Lorelei
	xor a
	jr .town

; used when a Pokemon is the only thing on the screen
; such as evolution, trading and the Hall of Fame
SetPal_PokemonWholeScreen:
	push bc
	ld hl, PalPacket_Empty
	ld de, wPalPacket
	ld bc, $10
	call CopyData
	pop bc
	ld a, c
	and a
	ld a, PAL_BLACK
	jr nz, .next
	ld a, [wWholeScreenPaletteMonSpecies]
	call DeterminePaletteIDOutOfBattle
.next
	ld [wPalPacket + 1], a
	ld hl, wPalPacket
	ld de, BlkPacket_WholeScreen
	ret

SetPal_TrainerCard:
	ld hl, BlkPacket_TrainerCard
	ld de, wTrainerCardBlkPacket
	ld bc, $40
	call CopyData
	ld de, BadgeBlkDataLengths
	ld hl, wTrainerCardBlkPacket + 2
	ld a, [wObtainedBadges]
	ld c, NUM_BADGES
.badgeLoop
	srl a
	push af
	jr c, .haveBadge
; The player doesn't have the badge, so zero the badge's blk data.
	push bc
	ld a, [de]
	ld c, a
	xor a
.zeroBadgeDataLoop
	ld [hli], a
	dec c
	jr nz, .zeroBadgeDataLoop
	pop bc
	jr .nextBadge
.haveBadge
; The player does have the badge, so skip past the badge's blk data.
	ld a, [de]
.skipBadgeDataLoop
	inc hl
	dec a
	jr nz, .skipBadgeDataLoop
.nextBadge
	pop af
	inc de
	dec c
	jr nz, .badgeLoop
	ld hl, PalPacket_TrainerCard
	ld de, wTrainerCardBlkPacket
	ret

SetPalFunctions:
; entries correspond to SET_PAL_* constants
	dw SetPal_BattleBlack
	dw SetPal_Battle
	dw SetPal_TownMap
	dw SetPal_StatusScreen
	dw SetPal_Pokedex
	dw SetPal_Slots
	dw SetPal_TitleScreen
	dw SetPal_NidorinoIntro
	dw SetPal_Generic
	dw SetPal_Overworld
	dw SetPal_PartyMenu
	dw SetPal_PokemonWholeScreen
	dw SetPal_GameFreakIntro
	dw SetPal_TrainerCard

; The length of the blk data of each badge on the Trainer Card.
; The Rainbow Badge has 3 entries because of its many colors.
BadgeBlkDataLengths:
	db 6     ; Boulder Badge
	db 6     ; Cascade Badge
	db 6     ; Thunder Badge
	db 6 * 3 ; Rainbow Badge
	db 6     ; Soul Badge
	db 6     ; Marsh Badge
	db 6     ; Volcano Badge
	db 6     ; Earth Badge

DeterminePaletteID:
	bit TRANSFORMED, a ; a is battle status 3
	ld a, PAL_GRAYMON  ; if the mon has used Transform, use Ditto's palette
	ret nz
	ld a, [hl]
DeterminePaletteIDOutOfBattle:
	ld [wPokedexNum], a
	and a ; is the mon index 0?
	jr z, .skipDexNumConversion
	push bc
	predef IndexToPokedex
	pop bc
	ld a, [wPokedexNum]
.skipDexNumConversion
	ld e, a
	ld d, 0
	ld hl, MonsterPalettes ; not just for Pokemon, Trainers use it too
	add hl, de
	ld a, [hl]
	ret

InitPartyMenuBlkPacket:
	ld hl, BlkPacket_PartyMenu
	ld de, wPartyMenuBlkPacket
	ld bc, $30
	jp CopyData

UpdatePartyMenuBlkPacket:
; Update the blk packet with the palette of the HP bar that is
; specified in [wWhichPartyMenuHPBar].
	ld hl, wPartyMenuHPBarColors
	ld a, [wWhichPartyMenuHPBar]
	ld e, a
	ld d, 0
	add hl, de
	ld e, l
	ld d, h
	ld a, [de]
	and a
	ld e, (1 << 2) | 1 ; green
	jr z, .next
	dec a
	ld e, (2 << 2) | 2 ; yellow
	jr z, .next
	ld e, (3 << 2) | 3 ; red
.next
	push de
	ld hl, wPartyMenuBlkPacket + 8 + 1
	ld bc, 6
	ld a, [wWhichPartyMenuHPBar]
	call AddNTimes
	pop de
	ld [hl], e
	ret

SendSGBPacket:
;check number of packets
	ld a, [hl]
	and $07
	ret z
; store number of packets in B
	ld b, a
.loop2
; save B for later use
	push bc
; disable ReadJoypad to prevent it from interfering with sending the packet
	ld a, 1
	ldh [hDisableJoypadPolling], a
; send RESET signal (P14=LOW, P15=LOW)
	xor a ; JOYP_SGB_START
	ldh [rJOYP], a
; set P14=HIGH, P15=HIGH
	ld a, JOYP_SGB_FINISH
	ldh [rJOYP], a
;load length of packets (16 bytes)
	ld b, 16
.nextByte
;set bit counter (8 bits per byte)
	ld e, 8
; get next byte in the packet
	ld a, [hli]
	ld d, a
.nextBit0
	bit 0, d
; if 0th bit is not zero set P14=HIGH, P15=LOW (send bit 1)
	ld a, JOYP_SGB_ONE
	jr nz, .next0
; else (if 0th bit is zero) set P14=LOW, P15=HIGH (send bit 0)
	ld a, JOYP_SGB_ZERO
.next0
	ldh [rJOYP], a
; must set P14=HIGH,P15=HIGH between each "pulse"
	ld a, JOYP_SGB_FINISH
	ldh [rJOYP], a
; rotation will put next bit in 0th position (so  we can always use command
; "bit 0, d" to fetch the bit that has to be sent)
	rr d
; decrease bit counter so we know when we have sent all 8 bits of current byte
	dec e
	jr nz, .nextBit0
	dec b
	jr nz, .nextByte
; send bit 0 as a "stop bit" (end of parameter data)
	ld a, JOYP_SGB_ZERO
	ldh [rJOYP], a
; set P14=HIGH,P15=HIGH
	ld a, JOYP_SGB_FINISH
	ldh [rJOYP], a
	xor a
	ldh [hDisableJoypadPolling], a
; wait for about 70000 cycles
	call Wait7000
; restore (previously pushed) number of packets
	pop bc
	dec b
; return if there are no more packets
	ret z
; else send 16 more bytes
	jr .loop2

LoadSGB:
	xor a
	ld [wOnSGB], a
	call CheckSGB
	ret nc
	ld a, 1
	ld [wOnSGB], a
	ld a, [wOnCGB]
	and a
	jr z, .notCGB
	ret
.notCGB
	di
	call PrepareSuperNintendoVRAMTransfer
	ei
	ld a, 1
	ld [wCopyingSGBTileData], a
	ld de, ChrTrnPacket
	ld hl, SGBBorderGraphics
	call CopyGfxToSuperNintendoVRAM
	ld a, 2
	ld [wCopyingSGBTileData], a
	ld de, PctTrnPacket
	ld hl, BorderPalettes
	call CopyGfxToSuperNintendoVRAM
	xor a
	ld [wCopyingSGBTileData], a
	ld de, PalTrnPacket
	ld hl, SuperPalettes
	call CopyGfxToSuperNintendoVRAM
	call ClearVram
	ld hl, MaskEnCancelPacket
	jp SendSGBPacket

PrepareSuperNintendoVRAMTransfer:
	ld hl, .packetPointers
	ld c, 9
.loop
	push bc
	ld a, [hli]
	push hl
	ld h, [hl]
	ld l, a
	call SendSGBPacket
	pop hl
	inc hl
	pop bc
	dec c
	jr nz, .loop
	ret

.packetPointers
; Only the first packet is needed.
	dw MaskEnFreezePacket
	dw DataSndPacket1
	dw DataSndPacket2
	dw DataSndPacket3
	dw DataSndPacket4
	dw DataSndPacket5
	dw DataSndPacket6
	dw DataSndPacket7
	dw DataSndPacket8

CheckSGB:
; Returns whether the game is running on an SGB in carry.
	ld hl, MltReq2Packet
	di
	call SendSGBPacket
	ld a, 1
	ldh [hDisableJoypadPolling], a
	ei
	call Wait7000
	ldh a, [rJOYP]
	and JOYP_SGB_MLT_REQ
	cp JOYP_SGB_MLT_REQ
	jr nz, .isSGB
	ld a, JOYP_SGB_ZERO
	ldh [rJOYP], a
	ldh a, [rJOYP]
	ldh a, [rJOYP]
	call Wait7000
	call Wait7000
	ld a, JOYP_SGB_FINISH
	ldh [rJOYP], a
	call Wait7000
	call Wait7000
	ld a, JOYP_SGB_ONE
	ldh [rJOYP], a
	ldh a, [rJOYP]
	ldh a, [rJOYP]
	ldh a, [rJOYP]
	ldh a, [rJOYP]
	ldh a, [rJOYP]
	ldh a, [rJOYP]
	call Wait7000
	vc_hook Unknown_network_reset
	call Wait7000
	ld a, JOYP_SGB_FINISH
	ldh [rJOYP], a
	ldh a, [rJOYP]
	ldh a, [rJOYP]
	ldh a, [rJOYP]
	call Wait7000
	call Wait7000
	ldh a, [rJOYP]
	and JOYP_SGB_MLT_REQ
	cp JOYP_SGB_MLT_REQ
	jr nz, .isSGB
	call SendMltReq1Packet
	and a
	ret
.isSGB
	call SendMltReq1Packet
	scf
	ret

SendMltReq1Packet:
	ld hl, MltReq1Packet
	call SendSGBPacket
	jp Wait7000

CopyGfxToSuperNintendoVRAM:
	di
	push de
	call DisableLCD
	ld a, $e4
	ldh [rBGP], a
	ld de, vChars1
	ld a, [wCopyingSGBTileData]
	and a
	jr z, .standardCopy
	dec a
	jr z, .borderTiles
	call CopySGBTilemapPals
	jr .next
.borderTiles
	call CopySGBBorderTiles
	jr .next
.standardCopy
	ld bc, 256 tiles
	call CopyData
.next
	ld hl, vBGMap0
	ld de, TILEMAP_WIDTH - SCREEN_WIDTH
	ld a, $80
	ld c, (256 + SCREEN_WIDTH - 1) / SCREEN_WIDTH ; enough rows to fit 256 tiles
.loop
	ld b, SCREEN_WIDTH
.innerLoop
	ld [hli], a
	inc a
	dec b
	jr nz, .innerLoop
	add hl, de
	dec c
	jr nz, .loop
	ld a, LCDC_DEFAULT
	ldh [rLCDC], a
	pop hl
	call SendSGBPacket
	xor a
	ldh [rBGP], a
	ei
	ret

Wait7000:
; Each loop takes 9 cycles so this routine actually waits 63000 cycles.
	ld de, 7000
.loop
	nop
	nop
	nop
	dec de
	ld a, d
	or e
	jr nz, .loop
	ret

SendSGBPackets:
	ld a, [wOnCGB]
	and a
	jr z, .notCGB
	push de
	call InitCGBPalettes
	pop de ; the ATTR_BLK packet; must be DE, farcall clobbers HL
	farcall LoadCGBScreenAttributesForBlkPacket
	; ShinRed waits for the newly installed palette and attribute state to be
	; presented before returning to the caller. Without this, BGB can remain on
	; the cleared frame using the previous screen's colors until the next menu
	; input supplies another frame boundary.
	ldh a, [rLCDC]
	and LCDC_ENABLE
	ret z
	call Delay3
	ret
.notCGB
	push de
	call SendSGBPacket
	pop hl
	jp SendSGBPacket

; Bill's PC keeps its screen-specific packets in its own bank. The caller
; copies both to this fixed WRAM buffer because Bankswitch uses hl for the
; destination routine address and therefore cannot pass a ROM/WRAM pointer.
SendBillsPCPackets::
	ld hl, wTextBoxBuffer
	jp SendSGBPackets

InitCGBPalettes:
; ShinRed's palette initialization contract, compacted into one four-entry loop.
; Each selected base palette is transformed through the current DMG BGP, OBP0,
; and OBP1 patterns before reaching hardware. DMGPalToGBCPal also maintains the
; wLast* caches, so repeated menu transitions cannot skip a required update.
; Red Rogue keeps the palette workspace in manually managed WRAM bank 2, hence
; the interrupt and rSVBK save/restore around the complete operation.
	ldh a, [rIE]
	push af
	xor a
	ldh [rIE], a
	ldh a, [rSVBK]
	push af
	ld a, 2
	ldh [rSVBK], a

	inc hl ; skip PAL_SET command byte
	ld c, 0 ; active palette index
.palLoop
	ld a, [hli] ; palette ID, low byte
	inc hl ; high byte is always zero
	push hl ; packet cursor
	call GetGBCBasePalAddress ; de = selected CGB base palette

	push de
	ld hl, w2GBCBasePalPointers
	ld b, 0
	add hl, bc
	add hl, bc
	ld [hl], e
	inc hl
	ld [hl], d
	pop de

	xor a ; CONVERT_BGP
	call DMGPalToGBCPal
	ld a, c
	call TransferCurBGPData
	ld a, CONVERT_OBP0
	call DMGPalToGBCPal
	ld a, c
	call TransferCurOBPData
	ld a, CONVERT_OBP1
	call DMGPalToGBCPal
	ld a, c
	add 4
	call TransferCurOBPData

	pop hl
	inc c
	ld a, c
	cp 4
	jr c, .palLoop

	ld a, 1
	ldh [rSVBK], a
	pop af
	ldh [rSVBK], a
	pop af
	ldh [rIE], a
	ret
    
    DMGPalToGBCPal::	;gbcnote - new function
; Populate wGBCPal with colors from a base palette, selected using one of the
; DMG palette registers.
; Input:
; a = which DMG palette register
; de = address of GBC base palette
	and a
	jr nz, .notBGP
	ld a, [rBGP]
	ld [wLastBGP], a
	jr .convert
.notBGP
	dec a
	jr nz, .notOBP0
	ld a, [rOBP0]
	ld [wLastOBP0], a
	jr .convert
.notOBP0
	ld a, [rOBP1]
	ld [wLastOBP1], a
.convert
;"A" now holds the palette data

DEF NUM_COLORS = 4
;"A" now holds the palette data
DEF color_index = 0
	REPT NUM_COLORS
		ld b, a	;"B" now holds the palette data
		and %11	;"A" now has just the value for the shade of palette color 0
		call .GetColorAddress
		push de
		;get the palett color value in de
		ld a, [hli]
		ld e, a
		ld a, [hl]
		ld d, a
		;now load the value that HL points to into wGBCPal offset by the loop
		ld a, e
		ld [wGBCPal + color_index * 2], a
		ld a, d
		ld [wGBCPal + color_index * 2 + 1], a
		pop de

		IF color_index < (NUM_COLORS + -1)
			ld a, b	;restore the palette data back into "A"
			;rotate the palette data bits twice to the right so the next color in line becomes color 0
			rrca
			rrca
		ENDC
DEF color_index = color_index + 1
	ENDR
	ret
.GetColorAddress:
	add a	;double the value of the shade in "A"
	ld l, a	;load 2x shade value into "L"
	xor a	;zero "A"
	ld h, a	;and load it to "H", so HL is now [00|2x shade]
	add hl, de	;HL now holds the base palette address offset by 2x shade in bytes (base, base+2, base+4, or base+6)
	ret

TransferCurBGPData::
; a = indexed offset of wGBCBasePalPointers
	push de
	;multiply index by 8 since each index represents 8 bytes worth of data
	add a
	add a
	add a
	or $80 ; set auto-increment bit of rBGPI
	ld [rBGPI], a
	ld de, rBGPD
	ld hl, wGBCPal
	ld a, [rLCDC]
	and LCDC_ENABLE
	jr nz, .lcdEnabled
	rept NUM_COLORS
	call TransferPalColorLCDDisabled
	endr
	jr .done
.lcdEnabled
	rept NUM_COLORS
	call TransferPalColorLCDEnabled
	endr
.done
	pop de
	ret	
    
    BufferBGPPal::
; Copy wGBCPal to palette a in wBGPPalsBuffer.
; a = indexed offset of wGBCBasePalPointers
	push de
	;multiply index by 8 since each index represents 8 bytes worth of data
	add a
	add a
	add a
	ld l, a
	xor a
	ld h, a
	ld de, wBGPPalsBuffer
	add hl, de	;hl now points to wBGPPalsBuffer + 8*index
	ld de, wGBCPal
	ld c, PAL_SIZE
.loop	;copy the 8 bytes of wGBCPal to its indexed spot in wBGPPalsBuffer
	ld a, [de]
	ld [hli], a
	inc de
	dec c
	jr nz, .loop
	pop de
	ret
	
TransferBGPPals::
; Transfer the buffered BG palettes.
	ld a, [rLCDC]
	and LCDC_ENABLE
	jr z, .lcdDisabled
	; have to wait until LCDC is disabled
	; LCD should only ever be disabled during the V-blank period to prevent hardware damage
	di	;disable interrupts
.waitLoop
	ld a, [rLY]
	cp 144	;V-blank can be confirmed when the value of LY is greater than or equal to 144
	jr c, .waitLoop
.lcdDisabled
	call .DoTransfer
	ei	;enable interrupts
	ret
.DoTransfer:
	xor a
	or $80 ; set the auto-increment bit of rBPGI
	ld [rBGPI], a
	ld de, rBGPD
	ld hl, wBGPPalsBuffer
	ld c, 4 * PAL_SIZE
.loop
	ld a, [hli]
	ld [de], a
	dec c
	jr nz, .loop
;GBCnote - the version for non-enhanced GBC colors should white out BGP 4-7 since it is not used. prevents problems.
	ld c, 2 * PAL_SIZE
.loop2
	ld a, $ff
	ld [de], a
	ld a, $7f
	ld [de], a
	dec c
	jr nz, .loop2
	ret

TransferCurOBPData:
; a = indexed offset of wGBCBasePalPointers
	push de
	;multiply index by 8 since each index represents 8 bytes worth of data
	add a
	add a
	add a
	or $80 ; set auto-increment bit of OBPI
	ld [rOBPI], a
	ld de, rOBPD
	ld hl, wGBCPal
	ld a, [rLCDC]
	and LCDC_ENABLE
	jr nz, .lcdEnabled
	rept NUM_COLORS
	call TransferPalColorLCDDisabled
	endr
	jr .done
.lcdEnabled
	rept NUM_COLORS
	call TransferPalColorLCDEnabled
	endr
.done
	pop de
	ret	

TransferPalColorLCDEnabled:
; Transfer a palette color while the LCD is enabled.
; In case we're already in H-blank or V-blank, wait for it to end. This is a
; precaution so that the transfer doesn't extend past the blanking period.
	ld a, [rSTAT]
	and %10 ; mask for non-V-blank/non-H-blank STAT mode
	jr z, TransferPalColorLCDEnabled	;repeat if still in h-blank or v-blank
; Wait for H-blank or V-blank to begin.
.notInBlankingPeriod
	ld a, [rSTAT]
	and %10 ; mask for non-V-blank/non-H-blank STAT mode
	jr nz, .notInBlankingPeriod
; fall through
TransferPalColorLCDDisabled:
; Transfer a palette color while the LCD is disabled.
	ld a, [hli]
	ld [de], a
	ld a, [hli]
	ld [de], a
	ret

; Banked bodies for the HOME UpdateGBCPal_* entry stubs. Keep the hardware and
; no-change gates from Shin Red, then tail-call the conversion routines in this
; same section.
UpdateGBCPal_BGP_::
	ldh a, [hGBC]
	and a
	ret z
	ldh a, [rBGP]
	ld b, a
	ldh a, [rIE]
	push af
	xor a
	ldh [rIE], a
	ldh a, [rSVBK]
	push af
	ld a, 2
	ldh [rSVBK], a
	ld a, [wLastBGP]
	ld c, a
	ld a, 1
	ldh [rSVBK], a
	pop af
	ldh [rSVBK], a
	pop af
	ldh [rIE], a
	ld a, c
	cp b
	ret z
	jp _UpdateGBCPal_BGP

UpdateGBCPal_OBP0_::
	ldh a, [hGBC]
	and a
	ret z
	ldh a, [rOBP0]
	ld b, a
	ldh a, [rIE]
	push af
	xor a
	ldh [rIE], a
	ldh a, [rSVBK]
	push af
	ld a, 2
	ldh [rSVBK], a
	ld a, [wLastOBP0]
	ld c, a
	ld a, 1
	ldh [rSVBK], a
	pop af
	ldh [rSVBK], a
	pop af
	ldh [rIE], a
	ld a, c
	cp b
	ret z
	ld d, CONVERT_OBP0
	jp _UpdateGBCPal_OBP

UpdateGBCPal_OBP1_::
	ldh a, [hGBC]
	and a
	ret z
	ldh a, [rOBP1]
	ld b, a
	ldh a, [rIE]
	push af
	xor a
	ldh [rIE], a
	ldh a, [rSVBK]
	push af
	ld a, 2
	ldh [rSVBK], a
	ld a, [wLastOBP1]
	ld c, a
	ld a, 1
	ldh [rSVBK], a
	pop af
	ldh [rSVBK], a
	pop af
	ldh [rIE], a
	ld a, c
	cp b
	ret z
	ld d, CONVERT_OBP1
	jp _UpdateGBCPal_OBP
	
_UpdateGBCPal_BGP::
;use a different function if doing enhanced GBC overworld palettes
	ld a, [wOptions2]
	bit BIT_ENHANCED_COLORS, a
	jr z, .notEnhancedGBC
	ld hl, wRogueFlagsBitfield2
	bit 3, [hl]
	jr z, .notEnhancedGBC
	ldh a, [rIE]
	push af
	xor a
	ldh [rIE], a
	ldh a, [rSVBK]
	push af
	ld a, 2
	ldh [rSVBK], a
	callfar UpdateEnhancedGBCPal_BGP
	ld a, 1
	ldh [rSVBK], a
	pop af
	ldh [rSVBK], a
	pop af
	ldh [rIE], a
	ret
.notEnhancedGBC
	
;;We're on a GBC and this stuff takes a while. Switch to double speed mode if not already.
;	ld a, [rKEY1]
;	bit 7, a
;	ld a, $ff
;	jr nz, .doublespeed	
;	predef SetCPUSpeed
;	xor a
;.doublespeed
;	push af

	;prevent the BGmap from updating during vblank 
	;because this is going to take a frame or two in order to fully run
	;otherwise a partial update (like during a screen whiteout) can be distracting
	ld hl, wRogueFlagsBitfield2
	set 6, [hl]
	ldh a, [rIE]
	push af
	xor a
	ldh [rIE], a
	ldh a, [rSVBK]
	push af
	ld a, 2
	ldh [rSVBK], a

	ld bc, $0000	;BC is going to track the index
.loop	
	ld hl, wGBCBasePalPointers
	push bc
	rlc c
	add hl, bc
	ld a, [hli]
	ld e, a
	ld a, [hl]
	ld d, a
	xor a ; CONVERT_BGP
	call DMGPalToGBCPal
	pop bc
	push bc
	ld a, c
	call BufferBGPPal	; Copy wGBCPal to palette indexed in wBGPPalsBuffer.
	pop bc
	inc c
	ld a, c
	cp NUM_ACTIVE_PALS
	jr c, .loop

; commenting this out and doing a proper loop to save space
;index = 0
;	REPT NUM_ACTIVE_PALS
;		ld a, [wGBCBasePalPointers + index * 2]
;		ld e, a
;		ld a, [wGBCBasePalPointers + index * 2 + 1]
;		ld d, a
;		xor a ; CONVERT_BGP
;		call DMGPalToGBCPal
;		ld a, index
;		call BufferBGPPal	; Copy wGBCPal to palette indexed in wBGPPalsBuffer.
;index = index + 1
;	ENDR

	call TransferBGPPals	;Transfer wBGPPalsBuffer contents to rBGPD
	ld a, 1
	ldh [rSVBK], a
	pop af
	ldh [rSVBK], a
	pop af
	ldh [rIE], a
	ld hl, wRogueFlagsBitfield2	;re-allow BGmap updates
	res 6, [hl]
	
;	pop af
;	inc a
;	ret z	;return now if 2x cpu mode was already active at the start of this function
;	;otherwise return to single cpu mode and return
;	predef SingleCPUSpeed
	ret    
    
 _UpdateGBCPal_OBP::
;use a different function if doing enhanced GBC overworld palettes
	ld a, [wOptions2]
	bit BIT_ENHANCED_COLORS, a
	jr z, .notEnhancedGBC
	ld hl, wRogueFlagsBitfield2
	bit 3, [hl]
	jr z, .notEnhancedGBC
	ldh a, [rIE]
	push af
	xor a
	ldh [rIE], a
	ldh a, [rSVBK]
	push af
	ld a, 2
	ldh [rSVBK], a
	callfar UpdateEnhancedGBCPal_OBP
	ld a, 1
	ldh [rSVBK], a
	pop af
	ldh [rSVBK], a
	pop af
	ldh [rIE], a
	ret
.notEnhancedGBC

;;We're on a GBC and this stuff takes a while. Switch to double speed mode if not already.
;	ld a, [rKEY1]
;	bit 7, a
;	ld a, $ff
;	jr nz, .doublespeed	
;	predef SetCPUSpeed
;	xor a
;.doublespeed
;	push af

; d then c = CONVERT_OBP0 or CONVERT_OBP1
	ld a, d
	ld c, a
	ldh a, [rIE]
	push af
	xor a
	ldh [rIE], a
	ldh a, [rSVBK]
	push af
	ld a, 2
	ldh [rSVBK], a

	ld de, $0000	;DE is going to track the index
.loop
	ld hl, wGBCBasePalPointers
	push de
	rlc e
	add hl, de

	ld a, [hli]
	ld e, a
	ld a, [hl]
	ld d, a
	ld a, c
	call DMGPalToGBCPal
	ld a, c
	dec a
	rlca
	rlca

	pop de
	add e
	;OBP0: a = 0, 1, 2, or 3
	;OBP1: a = 4, 5, 6, or 7
	call TransferCurOBPData	;this preserves DE

	inc e
	ld a, e
	cp NUM_ACTIVE_PALS
	jr c, .loop
	ld a, 1
	ldh [rSVBK], a
	pop af
	ldh [rSVBK], a
	pop af
	ldh [rIE], a
	
; commenting this out and doing a proper loop to save space
;index = 0
;	REPT NUM_ACTIVE_PALS
;		ld a, [wGBCBasePalPointers + index * 2]
;		ld e, a
;		ld a, [wGBCBasePalPointers + index * 2 + 1]
;		ld d, a
;		ld a, c
;		call DMGPalToGBCPal
;		ld a, c
;		dec a
;		rlca
;		rlca
;
;		IF index > 0
;			IF index == 1
;				inc a
;			ELSE
;				add index
;			ENDC
;		ENDC
;		;OBP0: a = 0, 1, 2, or 3
;		;OBP1: a = 4, 5, 6, or 7
;		call TransferCurOBPData
;index = index + 1
;	ENDR

;	pop af
;	inc a
;	ret z	;return now if 2x cpu mode was already active at the start of this function
;	;otherwise return to single cpu mode and return
;	predef SingleCPUSpeed
	ret
	
;gbcnote - new function
TranslatePalPacketToBGMapAttributes::
; translate the SGB pals for blk packets into something usable for the GBC
	push hl
	pop de
	ld hl, PalPacketPointers
	ld a, [hli]
	ld c, a
.loop
	ld a, e
.innerLoop
	cp [hl]
	jr z, .checkHighByte
	inc hl
	inc hl
	dec c
	jr nz, .innerLoop
	ret
.checkHighByte
; the low byte of pointer matched, so check the high byte
	inc hl
	ld a, d
	cp [hl]
	jr z, .foundMatchingPointer
	inc hl
	dec c
	jr nz, .loop
	ret
.foundMatchingPointer
	push de
	ld d, c
	callfar LoadBGMapAttributes
	pop de
	ret   
    
    ;gbcnote - pointers from pokemon yellow
PalPacketPointers::
	db (palPacketPointersEnd - palPacketPointers) / 2
palPacketPointers:
	dw BlkPacket_WholeScreen
	dw BlkPacket_Battle
	dw BlkPacket_StatusScreen
	dw BlkPacket_Pokedex
	dw BlkPacket_Slots
	dw BlkPacket_Titlescreen
	dw BlkPacket_NidorinoIntro
	dw wPartyMenuBlkPacket
	dw wTrainerCardBlkPacket
	dw BlkPacket_GameFreakIntro
	dw wPalPacket
	dw UnknownPacket_72751
palPacketPointersEnd:

CopySGBBorderTiles:
; SGB tile data is stored in a 4BPP planar format.
; Each tile is 32 bytes. The first 16 bytes contain bit planes 1 and 2, while
; the second 16 bytes contain bit planes 3 and 4.
; This function converts 2BPP planar data into this format by mapping
; 2BPP colors 0-3 to 4BPP colors 0-3. 4BPP colors 4-15 are not used.
	ld b, 128
.tileLoop
; Copy bit planes 1 and 2 of the tile data.
	ld c, TILE_SIZE
.copyLoop
	ld a, [hli]
	ld [de], a
	inc de
	dec c
	jr nz, .copyLoop

; Zero bit planes 3 and 4.
	ld c, 16
	xor a
.zeroLoop
	ld [de], a
	inc de
	dec c
	jr nz, .zeroLoop

	dec b
	jr nz, .tileLoop
	ret

CopySGBTilemapPals:
; Copy the trimmed border tilemap, filling the GB screen and omitted tail with
; zeroes while leaving the source pointer ready for the three SGB palettes.
	ld bc, (6 + SCREEN_WIDTH + 6) * 5 * 2
	call CopyData
	ld b, SCREEN_HEIGHT
.loop
	push bc
	ld bc, 6 * 2
	call CopyData
	ld bc, SCREEN_WIDTH * 2
	call ClearBytes
	ld bc, 6 * 2
	call CopyData
	pop bc
	dec b
	jr nz, .loop
	ld bc, (6 + SCREEN_WIDTH + 6) * 5 * 2
	call CopyData
	ld bc, $100
	call ClearBytes
	ld bc, 3 * 16 * COLOR_SIZE
	call CopyData
	ret

ClearBytes::
; Clear bc bytes at de.
.loop
	xor a
	ld [de], a
	inc de
	dec bc
	ld a, c
	or b
	jr nz, .loop
	ret
    
 GetGBCBasePalAddress:: ;gbcnote - new function
; Input: a = palette ID
; Output: de = palette address
	push hl
	ld l, a
	xor a
	ld h, a
	add hl, hl
	add hl, hl
	add hl, hl
	ld de, CGBPalettes
	add hl, de
	ld a, l
	ld e, a
	ld a, h
	ld d, a
	pop hl
	ret   
    ;gbcnote - This function loads the palette for a given pokemon index in wcf91 into a specified palette register on the GBC
;d = CONVERT_OBP0, CONVERT_OBP1, or CONVERT_BGP
;e = palette register # (0 to 7)
TransferMonPal:
	ldh a, [hGBC]
	and a
	ret z 
	push bc
	ld c, e
	ld b, d
	ld a, [wCurItem]
	cp VICTREEBEL+1
	jr c, .isMon
	sub VICTREEBEL+1
.back	
	call GetGBCBasePalAddress
	ldh a, [rIE]
	push af
	xor a
	ldh [rIE], a
	ldh a, [rSVBK]
	push af
	ld a, 2
	ldh [rSVBK], a
	ld a, b
	call DMGPalToGBCPal
	ld a, b
	and a
	jr z, .do_bgp
	ld a, c
	call TransferCurOBPData
	jr .done
.do_bgp
	ld a, c
	call TransferCurBGPData

.done
	ld a, 1
	ldh [rSVBK], a
	pop af
	ldh [rSVBK], a
	pop af
	ldh [rIE], a
	pop bc
	ret
.isMon	
	call DeterminePaletteIDOutOfBattle
	jr .back
    
;joenote - This is a function specifically for translating the default pokeyellow pals into the GBC color buffer
;DE is passed-in containing the address of a pal pattern...like FadePal4 or something
BufferAllPokeyellowColorsGBC:
	ldh a, [rIE]
	push af
	xor a
	ldh [rIE], a
	ldh a, [rSVBK]
	push af
	ld a, 2
	ldh [rSVBK], a
	call .BGP0to3Loop
	call .OBP0to3Loop
	call .OBP4to7Loop
	ld a, 1
	ldh [rSVBK], a
	pop af
	ldh [rSVBK], a
	pop af
	ldh [rIE], a
	ret	
	
.BGP0to3Loop
	ld hl, w2GBCFullPalBuffer
	xor a
.BGP0to3Loop_back
	call .readwriteinc
	cp 16
	jr c, .BGP0to3Loop_back
	ret

.OBP0to3Loop
	ld hl, w2GBCFullPalBuffer+64
	ld a, 32
	inc de	;increment to the rOBP0 portion of the pattern
.OBP0to3Loop_back
	call .readwriteinc
	cp 48
	jr c, .OBP0to3Loop_back
	ret

.OBP4to7Loop
	ld hl, w2GBCFullPalBuffer+96
	ld a, 48
	inc de	;already incremented to the rOBP0 portion, so now increment to the rOBP1 portion of the pattern
.OBP4to7Loop_back
	call .readwriteinc
	cp 64
	jr c, .OBP4to7Loop_back
	ret

.readwriteinc
	ld [w2GBCColorControl], a
	; All saved registers belong to the bank-2 stack. Switch to bank 1 only for
	; the ROM/gamma calls, then return to bank 2 before restoring them.
	push bc
	push de
	push hl
	ld c, a ; carry the color index into bank 1 without reading bank-2 WRAM there
	ld a, 1
	ldh [rSVBK], a
	call .ReadMasterPals	;get the color into DE
	predef GBCGamma
	ld a, 2
	ldh [rSVBK], a
	pop hl
	ld a, d
	ld [hli], a		;buffer high byte
	ld a, e
	ld [hli], a		;buffer low byte	
	pop de
	pop bc
	ld a, [w2GBCColorControl]
	inc a
	ret

.ReadMasterPals
;first grab the correct base palette from GBCEnhancedOverworldPalettes
;the offset of the correct pointer corresponds to double the value of bits 2, 3, and 4 of the wGBCColorControl value
	push de ;need the value in DE for later because it holds the pal pattern like FadePal4 or something

	and %00011100
	rrca
	rrca
	ld de, $0000
	add a
	add a
	add a
	ld e, a

	ld hl, GBCEnhancedOverworldPalettes
	ld a, [hCurMap]
	cp SEAFOAM_ISLANDS_1F
	jr z, .isColdCavern
	cp SEAFOAM_ISLANDS_B1F
	jr c, .notColdCavern
	cp SEAFOAM_ISLANDS_B4F + 1
	jr nc, .notColdCavern
.isColdCavern	
	ld hl, GBCEnhancedOverworldPalettes_ColdCavern
.notColdCavern

	ld a, [wMapPalOffset]
	cp 6
	jr nz, .notdark
	ld hl, GBCEnhancedOverworldPalettes_DarkCavern
.notdark

	add hl, de
	pop de ;get the pal pattern back
	ld a, [de]
	;now put the pattern in E and make D zero
	ld d, 0
	ld e, a

; c carried the bank-2 color index into this bank-1 phase
	ld a, c
	and %00000011
	jr z, .zero
	cp 1
	jr z, .one
	cp 2
	jr z, .two
	cp 3
	jr z, .three
	
;roll the bits to get the correct base pal color number for the hardware pal color number
.zero
	sla e
	rl d
	sla e
	rl d
.one
	sla e
	rl d
	sla e
	rl d
.two
	sla e
	rl d
	sla e
	rl d
.three
	sla e
	rl d
	sla e
	rl d

;mask out all but the last two bits of D to get the base pal color number in A
	ld a, d
	and %00000011
	
;colors are 2 bytes, so double A to make it an offset and store back into DE
	add a
	ld d, 0
	ld e, a

;add DE to HL to make HL point to the desired base pal color number
	add hl, de

;load the low byte of the color
	ld a, [hli]
	ld e, a
;load the high byte of the color
	ld a, [hli]
	ld d, a
	
	ret

INCLUDE "data/sgb/sgb_packets.asm"

INCLUDE "data/pokemon/palettes.asm"

INCLUDE "data/sgb/sgb_palettes.asm"
INCLUDE "data/gfx/cgb_palettes.asm"

INCLUDE "data/sgb/sgb_border.asm"
