SECTION "Follower Sprites", ROMX, BANK[$1C]

; Pikachu's overworld walking sprite, ported from pokeyellow gfx/sprites/pikachu.png.
; 24 tiles (384 bytes): tiles 0-11 are standing frames (down/up/left),
; tiles 12-23 are walking frames loaded at VRAM $88C0 by LoadFollowerSprite.
PikachuFollowerSprite:: INCBIN "gfx/followers/pikachu.2bpp"
