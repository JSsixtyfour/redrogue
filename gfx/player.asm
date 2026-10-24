; RedPicFront and GreenPicFront moved to SECTION "Trainer Pics" in gfx/pics.asm
; so that every player-selectable front pic shares one bank — see the comment
; there. RedPicBack/GreenPicBack/OldManPicBack likewise share SECTION "Player Back Pics".
ShrinkPic1::  INCBIN "gfx/player/shrink1.lz"
ShrinkPic2::  INCBIN "gfx/player/shrink2.lz"
