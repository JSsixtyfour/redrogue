; AUDIO_4 (bank $33). Only Music_MeetJessieJames lives here (SHIN_IMPORT_PLAN.md
; Phase 1.3), ported from pret/pokeyellow's audio/music/meetjessiejames.asm.
; pokeyellow's own musicheaders4.asm also carries Music_SurfingPikachu,
; Music_YellowUnusedSong and Music_GBPrinter - deliberately not taken, no
; equivalent mechanic in this fork. No gameplay hook references this song yet;
; it exists so AUDIO_4 is a proven, testable bank.
Music_MeetJessieJames::
	channel_count 3
	channel 1, Music_MeetJessieJames_Ch1
	channel 2, Music_MeetJessieJames_Ch2
	channel 3, Music_MeetJessieJames_Ch3
