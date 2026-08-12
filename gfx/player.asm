; RedPicFront and GreenPicFront moved to SECTION "Trainer Pics" in gfx/pics.asm
; so that every player-selectable front pic shares one bank — see the comment
; there. RedPicBack/GreenPicBack/OldManPicBack likewise share SECTION "Pics 4".
ShrinkPic1::  INCBIN "gfx/player/shrink1.pic"
ShrinkPic2::  INCBIN "gfx/player/shrink2.pic"
