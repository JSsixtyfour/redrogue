; These routines manage gradual fading
; (e.g., entering a doorway)
LoadGBPal::
	rfarjp LoadGBPal_

GBFadeInFromBlack::
	rfarjp GBFadeInFromBlack_

GBFadeOutToWhite::
	rfarjp GBFadeOutToWhite_

GBFadeOutToBlack::
	rfarjp GBFadeOutToBlack_

GBFadeInFromWhite::
	rfarjp GBFadeInFromWhite_

FadePal1:: dc 3,3,3,3, 3,3,3,3, 3,3,3,3
FadePal2:: dc 3,3,3,2, 3,3,3,2, 3,3,2,0
FadePal3:: dc 3,3,2,1, 3,2,1,0, 3,2,1,0
FadePal4:: dc 3,2,1,0, 3,1,0,0, 3,2,0,0
;              rBGP     rOBP0    rOBP1
FadePal5:: dc 3,2,1,0, 3,1,0,0, 3,2,0,0
FadePal6:: dc 2,1,0,0, 2,0,0,0, 2,1,0,0
FadePal7:: dc 1,0,0,0, 1,0,0,0, 1,0,0,0
FadePal8:: dc 0,0,0,0, 0,0,0,0, 0,0,0,0
