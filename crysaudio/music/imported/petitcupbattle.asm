; Converted from petit cup 1-3.mid (update of 2026-11-26) by the Red Rogue music test kit (pokemid v0.9, Crystal engine).
; kit-engine: crysaudio pokered-crysaudio 9753183a
; Size-optimized by tools/music_kit/song_optimize.py (2026-11-26): same notes, lengths
; and channel state, verified frame by frame with tools/music_kit/song_audio_compare.py.
Music_PetitCupBattle::
	channel_count 3
	channel 1, Music_PetitCupBattle_Ch1
	channel 2, Music_PetitCupBattle_Ch2
	channel 3, Music_PetitCupBattle_Ch3

Music_PetitCupBattle_Ch1::
	tempo 110
	vibrato 0, 0, 0
	duty_cycle 2
	note_type 2, 9, 0
	octave 3
	note B_, 6
	note A#, 6
	note A_, 6
	note G#, 6
	note A#, 6
	note A_, 6
	note G#, 6
	note G_, 6
	note A_, 6
	note G#, 6
	note G_, 6
	note F#, 6
	sound_call Music_PetitCupBattle_Sub11
	note A_, 12
	volume_envelope 10, 0
	octave 4
	sound_call Music_PetitCupBattle_Sub25
	sound_call Music_PetitCupBattle_Sub25
	note C_, 12
	note_type 3, 10, 0
	note D_, 15
	rest 1
	note_type 2, 10, 0
	note C_, 12
	note C_, 12
	rest 12
	sound_call Music_PetitCupBattle_Sub25
	note C_, 12
	rest 12
	volume_envelope 9, 0
	note C_, 12
	rest 12
	note C_, 12
	rest 12
	note C_, 12
	note_type 3, 10, 0
	note C_, 8
	note C_, 8
	rest 8
	note D_, 8
	rest 8
	note C_, 8
	rest 8
	note D_, 8
	rest 8
	note C_, 8
	rest 8
	note C_, 8
	note D_, 8
	note D_, 16
	note D_, 4
	note D_, 4
.mainloop:
	note_type 3, 10, 0
	octave 3
	note E_, 8
	note C#, 8
	note E_, 8
	note F#, 16
	note F#, 15
	rest 1
	note A_, 8
	note A_, 8
	note G#, 16
	note F#, 4
	note E_, 4
	note F#, 16
	octave 2
	note B_, 16
	volume_envelope 8, 0
	sound_call Music_PetitCupBattle_Sub14
	note G#, 8
	note B_, 8
	note G_, 8
	volume_envelope 10, 0
	note F_, 8
	note G_, 8
	note A_, 8
	note A#, 16
	note A_, 8
	note A#, 8
	note A#, 8
	octave 4
.loop0:
	note C_, 4
	octave 3
	note B_, 4
	note A#, 4
	octave 4
	note C_, 4
	rest 8
	sound_loop 2, .loop0
	note C_, 4
	note C_, 4
	rest 16
	note_type 2, 7, 0
	octave 3
	note G#, 12
	rest 12
	note G#, 12
	rest 12
	note G#, 12
	rest 12
	volume_envelope 8, 0
	note G#, 12
	rest 12
	note B_, 12
	rest 12
	volume_envelope 7, 0
	note B_, 11
	rest 13
	note B_, 12
	note_type 3, 10, 0
	octave 4
	note C#, 16
	octave 3
	note E_, 8
	note C#, 8
	note E_, 8
	note F#, 16
	note F#, 16
	note A_, 8
	note A_, 8
	note G#, 16
	note F#, 4
	note G#, 4
	note A_, 15
	rest 16
	rest 1
	volume_envelope 8, 0
	octave 2
	sound_call Music_PetitCupBattle_Sub14
	note F#, 8
	volume_envelope 10, 0
	note G_, 8
	note B_, 8
	note F_, 8
	note C_, 8
	note A_, 8
	note C_, 8
	note F_, 8
	note C_, 8
	note A_, 8
	note F_, 8
	note G_, 16
	note F_, 16
	note E_, 16
	note D_, 16
	volume_envelope 7, 0
	octave 2
	note A_, 8
	octave 3
	note C#, 8
	volume_envelope 8, 0
	note E_, 8
	note C#, 8
	note E_, 8
	note A_, 8
	note E_, 8
	note A_, 8
	octave 4
	note C#, 8
	volume_envelope 7, 0
	octave 3
	note A_, 8
	note E_, 8
	note A_, 8
	note E_, 8
	note C#, 8
	note E_, 8
	note C#, 8
	octave 2
	note A_, 8
	rest 8
	volume_envelope 8, 0
.loop1:
	sound_call Music_PetitCupBattle_Sub16
	sound_loop 3, .loop1
	note A_, 15
	rest 16
	rest 1
	octave 3
.loop2:
	note C_, 15
	rest 16
	rest 1
	sound_loop 3, .loop2
	octave 2
	sound_call Music_PetitCupBattle_Sub16
	volume_envelope 11, 0
	octave 3
	note A_, 4
	note B_, 4
	octave 4
	note C_, 4
	note D_, 4
	note E_, 8
	note D_, 8
	note C_, 8
	octave 3
	note B_, 8
	volume_envelope 9, 0
	octave 4
	note F_, 8
	note E_, 8
	note D_, 8
	note C_, 8
	octave 3
	note B_, 8
	note A_, 8
	note G_, 8
	note F_, 8
	note G_, 8
	note A_, 8
	note B_, 8
	octave 4
	note C_, 8
	octave 3
	note B_, 8
	note G_, 8
	octave 4
	note D_, 8
	octave 3
	note G_, 8
	note B_, 8
	note G_, 8
	octave 4
	note D_, 8
	octave 3
	note B_, 8
	octave 4
	note D_, 8
	octave 3
	note A_, 8
	octave 4
	note D_, 8
	octave 3
	note A_, 8
	note B_, 8
	note E_, 8
	note B_, 8
	note E_, 8
	volume_envelope 8, 0
	note A_, 8
	note E_, 8
	note A_, 8
	note E_, 8
	note G_, 8
	note E_, 8
	note G_, 8
	note E_, 8
	note F#, 8
	note D_, 8
	note E_, 8
	rest 8
	note E_, 8
	note F#, 8
	rest 8
	note F#, 8
.loop3:
	note G_, 8
	note D_, 8
	sound_loop 4, .loop3
	note B_, 8
	note G_, 8
	note B_, 8
	sound_call Music_PetitCupBattle_Sub28
	note G_, 8
	octave 4
	note C#, 8
	octave 3
	note A_, 8
	note G_, 8
	note E_, 8
	note C#, 8
	note E_, 8
	note A_, 8
	octave 4
	note C#, 8
	note E_, 8
	note C#, 8
	note E_, 8
	note D_, 8
	note C#, 8
	octave 3
	note A#, 8
	note F#, 8
	note A#, 8
	sound_call Music_PetitCupBattle_Sub29
	sound_call Music_PetitCupBattle_Sub29
	note B_, 8
	note G_, 8
	rest 8
	note G_, 8
	rest 8
	note G_, 8
	note D_, 8
	note G_, 8
	volume_envelope 10, 0
	note G_, 16
	note A_, 8
	note G_, 16
	note F#, 8
	note E_, 8
	note F#, 8
	volume_envelope 8, 0
	sound_call Music_PetitCupBattle_Sub30
	sound_call Music_PetitCupBattle_Sub30
	volume_envelope 9, 0
	octave 4
	note C#, 8
	octave 3
	note A_, 8
	rest 8
	note A_, 8
	rest 8
	note A_, 8
	rest 8
	note A_, 8
	note_type 12, 10, 0
	note A_, 4
	octave 4
	note C#, 12
	octave 3
	note F#, 6
	note F_, 10
	note D_, 6
	note C#, 6
	note C#, 4
	note_type 4, 8, 0
	note F#, 13
	note_type 2, 8, 0
	rest 10
	note F#, 11
	rest 13
	note F#, 11
	rest 13
	note E_, 12
	note F#, 12
	sound_call Music_PetitCupBattle_Sub31
	note C_, 11
	rest 13
	sound_call Music_PetitCupBattle_Sub23
	sound_call Music_PetitCupBattle_Sub23
	note C_, 11
	rest 13
	note_type 6, 8, 0
	note D_, 11
	note_type 2, 8, 0
	rest 15
	octave 2
	sound_call Music_PetitCupBattle_Sub32
	sound_call Music_PetitCupBattle_Sub32
	sound_call Music_PetitCupBattle_Sub33
	sound_call Music_PetitCupBattle_Sub33
	volume_envelope 9, 0
	octave 3
	sound_call Music_PetitCupBattle_Sub34
	sound_call Music_PetitCupBattle_Sub34
	sound_call Music_PetitCupBattle_Sub31
	note F#, 11
	rest 13
	note F#, 12
	note C#, 12
	note E_, 12
	note A_, 12
	octave 4
	note C#, 12
	note D_, 12
	note A_, 12
	note G#, 12
	note A_, 12
	note D_, 12
	note D_, 12
	note F#, 12
	note A_, 12
	note D_, 12
	note A_, 12
	note G#, 12
	note A_, 12
	octave 5
	note D_, 12
	octave 4
	note A_, 12
	note F#, 12
	note A_, 12
	note E_, 12
	note B_, 12
	note A#, 12
	note B_, 12
	note E_, 12
	note E_, 12
	note G#, 12
	note B_, 12
	volume_envelope 8, 0
	note E_, 12
	note B_, 12
	note A#, 12
	note B_, 12
	rest 12
	note B_, 12
	note G#, 12
	note B_, 12
	volume_envelope 9, 0
	octave 3
	note A_, 12
	octave 4
	note E_, 12
	note D_, 12
.loop4:
	note E_, 12
	octave 3
	note A_, 12
	octave 4
	note E_, 12
	note C#, 12
	sound_loop 2, .loop4
	note E_, 12
	octave 3
	note A_, 12
	octave 4
	note E_, 12
	octave 3
	note A_, 12
	octave 4
	note E_, 12
	octave 3
	note F#, 12
	octave 4
	note D_, 12
	note C#, 12
	note D_, 12
	octave 3
	note F#, 12
	octave 4
	note D_, 12
	octave 3
	note A_, 12
	octave 4
	note C#, 12
	octave 3
	note F#, 12
	octave 4
	note D_, 12
	note C#, 12
	note D_, 12
	note F#, 12
	octave 3
	note A_, 12
	note_type 12, 10, 0
	note D_, 4
	octave 2
	note A_, 4
	rest 12
	note_type 3, 10, 0
	note A_, 15
	note_type 12, 10, 0
	rest 14
	note_type 3, 10, 0
	rest 1
	note A_, 8
	octave 3
	note D_, 8
	note E_, 8
	sound_loop 0, .mainloop

Music_PetitCupBattle_Ch2::
	vibrato 0, 0, 0
	duty_cycle 3
	note_type 4, 9, 0
	octave 4
	note G_, 3
	note F#, 3
	note F_, 3
	note E_, 3
	note G_, 3
	note F_, 3
	note E_, 3
	note D#, 3
	note G_, 3
	note E_, 3
	note D#, 3
	note D_, 3
	note G_, 3
	note D#, 3
	note D_, 3
	note C#, 3
	note G_, 3
	note D_, 3
	note C#, 3
	note C_, 3
	note G_, 3
	note C#, 3
	note C_, 3
	octave 3
	note B_, 3
	octave 4
	note G_, 3
	note C_, 3
	octave 3
	note B_, 3
	note A#, 3
	octave 4
	note G_, 3
	octave 3
	note B_, 3
	note A#, 3
	note A_, 3
	octave 4
	note A_, 6
	volume_envelope 10, 0
	sound_call Music_PetitCupBattle_Sub26
	sound_call Music_PetitCupBattle_Sub26
	note G_, 6
	note A_, 12
	note G_, 6
	sound_call Music_PetitCupBattle_Sub26
	note G_, 6
	rest 12
	volume_envelope 9, 0
	note D_, 2
	note D#, 2
	note_type 8, 10, 0
	note E_, 1
	note G_, 14
	rest 1
	note_type 12, 9, 0
	octave 3
	note A_, 16
	note E_, 16
.mainloop:
	note_type 3, 10, 0
	octave 3
	note A_, 8
	note E_, 8
	note A_, 8
	note B_, 16
	octave 4
	note D_, 16
	note C#, 8
	note D_, 8
	note C#, 16
	octave 3
	note B_, 4
	note A_, 4
	note B_, 16
	note_type 16, 10, 0
	note E_, 15
	rest 12
	note_type 4, 10, 0
	note A#, 6
	octave 4
	note C_, 6
	note D_, 6
	note D#, 12
	note D_, 6
	note D#, 6
	note D#, 6
.loop5:
	note F_, 3
	note E_, 3
	note D#, 3
	note F_, 3
	rest 6
	sound_loop 2, .loop5
	note F_, 3
	note F_, 3
	note F_, 2
	note G_, 2
	note A_, 2
	note B_, 3
	note A#, 3
	note A_, 3
	note B_, 3
	rest 6
	note E_, 3
	note D#, 3
	note D_, 3
	note E_, 3
	rest 6
	octave 3
	note B_, 3
	octave 4
	note C#, 3
	note D_, 3
	note E_, 3
	rest 6
	note D#, 3
	note E_, 3
	note A_, 3
	note E_, 3
	note D#, 3
	note D_, 3
	note C#, 6
	note G_, 6
	note A_, 12
	octave 3
	note A_, 6
	note E_, 6
	note A_, 6
	note B_, 12
	octave 4
	note D_, 12
	note C#, 6
	note D_, 6
	note C#, 12
	octave 3
	note B_, 3
	octave 4
	note C#, 3
	note D_, 12
	note_type 24, 10, 0
	note E_, 10
	rest 6
	note E_, 1
	note D_, 1
	note C_, 2
	octave 3
	note B_, 1
	note A_, 1
	note G_, 2
	octave 4
	note C_, 1
	note D_, 1
	note E_, 2
	note D_, 2
	note C_, 2
	octave 3
	note B_, 2
	note A_, 10
	rest 8
	note E_, 2
	rest 2
	note E_, 2
	rest 2
	note E_, 2
	rest 2
	sound_call Music_PetitCupBattle_Sub35
	note A_, 1
	note E_, 1
	note F#, 1
	note D_, 1
	note E_, 10
	rest 4
	sound_call Music_PetitCupBattle_Sub35
	octave 4
	note C_, 1
	octave 3
	note B_, 1
	note A_, 1
	note G_, 1
	note_type 7, 9, 0
	octave 5
	note C_, 13
	note_type 1, 9, 0
	rest 5
	note_type 6, 9, 0
	octave 4
	note B_, 11
	rest 1
	note A_, 4
	note F_, 4
	octave 5
	note C_, 4
	octave 4
	note B_, 4
	note A_, 4
	note_type 13, 9, 0
	note G_, 14
	note_type 1, 9, 0
	rest 10
	note_type 24, 10, 0
	octave 3
	note F_, 4
	note G_, 4
	volume_envelope 8, 0
	octave 4
	note C#, 10
	rest 6
	volume_envelope 10, 0
	octave 3
	note B_, 8
	octave 4
	note E_, 4
	note F#, 4
	note E_, 8
	volume_envelope 11, 0
	note G_, 2
	note A_, 1
	note G_, 1
	note F#, 1
	note E_, 1
	note D_, 1
	note E_, 1
	volume_envelope 10, 0
	note F#, 3
	note D_, 10
	rest 1
	octave 3
	note B_, 1
	octave 4
	note F#, 1
	note G_, 3
	note D_, 10
	rest 1
	octave 3
	note B_, 1
	octave 4
	note G_, 1
	note G#, 3
	note E_, 10
	rest 1
	note E_, 1
	note G#, 1
	note A_, 8
	volume_envelope 11, 0
	note C#, 2
	note E_, 6
	volume_envelope 10, 0
	note D_, 3
	note C_, 5
	octave 3
	note B_, 3
	note A_, 3
	note G_, 2
	note D_, 10
	rest 7
.loop6:
	note F_, 1
	rest 1
	note G_, 1
	rest 1
	sound_loop 3, .loop6
	note A_, 3
	note_type 3, 12, 0
	sound_call Music_PetitCupBattle_Sub4
	volume_envelope 11, 0
	sound_call Music_PetitCupBattle_Sub2
	octave 3
	note B_, 4
	note A_, 16
	note_type 3, 11, 0
	sound_call Music_PetitCupBattle_Sub4
	sound_call Music_PetitCupBattle_Sub2
	note E_, 4
	note D_, 16
	volume_envelope 10, 0
	octave 3
	note D_, 4
	rest 12
	note D_, 4
	rest 14
	note D_, 2
	note F#, 2
	note G_, 2
	sound_loop 0, .mainloop

Music_PetitCupBattle_Ch3::
	vibrato 0, 0, 0
	note_type 2, 2, 6
	octave 3
	sound_call Music_PetitCupBattle_Sub11
	note D#, 6
	note D_, 6
	note C#, 6
	note C_, 6
	note D_, 6
	note C#, 6
	note C_, 6
	octave 2
	note B_, 6
	octave 3
	note C#, 6
	note C_, 6
	octave 2
	note B_, 6
	note A#, 6
.loop7:
	sound_call Music_PetitCupBattle_Sub0
	sound_loop 8, .loop7
.loop8:
	sound_call Music_PetitCupBattle_Sub10
	octave 2
	sound_loop 3, .loop8
	sound_call Music_PetitCupBattle_Sub10
.mainloop:
	note_type 3, 2, 6
	sound_call Music_PetitCupBattle_Sub1
	sound_call Music_PetitCupBattle_Sub1
	octave 2
	note F#, 8
	octave 3
	note F#, 8
.loop9:
	sound_call Music_PetitCupBattle_Sub8
	sound_loop 4, .loop9
	octave 2
	note E_, 8
	octave 3
	note E_, 8
	octave 2
	note A#, 8
	octave 3
	note F_, 8
	octave 2
	note A#, 8
	octave 3
	note F_, 8
	octave 2
	note A#, 8
	octave 3
	note D_, 8
	note D#, 8
	note E_, 8
	sound_call Music_PetitCupBattle_Sub36
	sound_call Music_PetitCupBattle_Sub36
	note E_, 8
	sound_call Music_PetitCupBattle_Sub15
	note A_, 8
	sound_call Music_PetitCupBattle_Sub15
	sound_call Music_PetitCupBattle_Sub28
	note E_, 8
	note G_, 8
	note A_, 16
	sound_call Music_PetitCupBattle_Sub1
	sound_call Music_PetitCupBattle_Sub1
	octave 2
	note F#, 8
	octave 3
	note F#, 8
	sound_call Music_PetitCupBattle_Sub8
	sound_call Music_PetitCupBattle_Sub24
	octave 3
	note E_, 8
	octave 2
	note E_, 8
	octave 3
	note E_, 8
	sound_call Music_PetitCupBattle_Sub24
	note A_, 8
	sound_call Music_PetitCupBattle_Sub37
	sound_call Music_PetitCupBattle_Sub37
.loop10:
	note G_, 8
	octave 3
	note G_, 8
	octave 2
	sound_loop 3, .loop10
	note G_, 8
	octave 3
	note G_, 8
	sound_call Music_PetitCupBattle_Sub1
	octave 2
	note A_, 8
	octave 3
	note G_, 4
	note G#, 4
	sound_call Music_PetitCupBattle_Sub1
	octave 2
	note A_, 8
	note G_, 8
.loop11:
	sound_call Music_PetitCupBattle_Sub3
	octave 2
	sound_loop 3, .loop11
	note A_, 8
	octave 3
	note C#, 8
	note D_, 8
	note E_, 8
.loop12:
	sound_call Music_PetitCupBattle_Sub13
	sound_loop 3, .loop12
	octave 2
	sound_call Music_PetitCupBattle_Sub3
	octave 2
	sound_call Music_PetitCupBattle_Sub3
.loop13:
	sound_call Music_PetitCupBattle_Sub13
	sound_loop 3, .loop13
	sound_call Music_PetitCupBattle_Sub6
	note B_, 8
	sound_call Music_PetitCupBattle_Sub6
	note B_, 8
	note A_, 8
	sound_call Music_PetitCupBattle_Sub22
	note G_, 8
	sound_call Music_PetitCupBattle_Sub22
	note F#, 8
	sound_call Music_PetitCupBattle_Sub22
	note E_, 8
	octave 4
	note C#, 8
	note E_, 8
	octave 3
	note F#, 8
	sound_call Music_PetitCupBattle_Sub6
	note F#, 8
	sound_call Music_PetitCupBattle_Sub6
	note F#, 8
	note A_, 8
	sound_call Music_PetitCupBattle_Sub22
	note A_, 8
	octave 4
	note C#, 8
	note E_, 8
	octave 3
	note G#, 8
	note A#, 8
	sound_call Music_PetitCupBattle_Sub22
	note A#, 8
	octave 4
	note C#, 8
	note E_, 8
.loop14:
	sound_call Music_PetitCupBattle_Sub17
	sound_loop 4, .loop14
	octave 3
	note F#, 8
.loop15:
	sound_call Music_PetitCupBattle_Sub18
	sound_loop 4, .loop15
.loop16:
	sound_call Music_PetitCupBattle_Sub19
	sound_loop 4, .loop16
.loop17:
	sound_call Music_PetitCupBattle_Sub20
	sound_loop 4, .loop17
	note D_, 8
	note F#, 8
	note A_, 8
	note F_, 16
	note A_, 8
	octave 4
	note C_, 8
	octave 3
	note A_, 8
	note G_, 8
	note B_, 8
	octave 4
	note D_, 8
	octave 3
	note A_, 16
	note G_, 8
	note A_, 8
	octave 2
	note A_, 8
	octave 3
	sound_call Music_PetitCupBattle_Sub38
	sound_call Music_PetitCupBattle_Sub38
.loop18:
	sound_call Music_PetitCupBattle_Sub21
	sound_loop 4, .loop18
.loop19:
	sound_call Music_PetitCupBattle_Sub5
	sound_loop 4, .loop19
	note E_, 8
	sound_call Music_PetitCupBattle_Sub15
	note E_, 8
	octave 4
	note E_, 8
	octave 3
	note G#, 8
	sound_call Music_PetitCupBattle_Sub9
	note E_, 8
	sound_call Music_PetitCupBattle_Sub7
	note G_, 8
	note E_, 8
	sound_call Music_PetitCupBattle_Sub12
	octave 2
	note A_, 8
	octave 3
	sound_call Music_PetitCupBattle_Sub7
	note A_, 8
.loop20:
	sound_call Music_PetitCupBattle_Sub39
	sound_call Music_PetitCupBattle_Sub5
	sound_loop 2, .loop20
	note E_, 8
	sound_call Music_PetitCupBattle_Sub15
	note E_, 8
	octave 4
	note E_, 8
	octave 3
	note B_, 8
	sound_call Music_PetitCupBattle_Sub9
	note C#, 8
	sound_call Music_PetitCupBattle_Sub7
	note G_, 8
	note C#, 8
	sound_call Music_PetitCupBattle_Sub12
	rest 8
	octave 3
	sound_call Music_PetitCupBattle_Sub7
	note A_, 8
	sound_call Music_PetitCupBattle_Sub27
	sound_call Music_PetitCupBattle_Sub27
	note D_, 8
	note C_, 8
	note D_, 8
	note C_, 8
	sound_loop 0, .mainloop

Music_PetitCupBattle_Sub0:
	note A_, 6
	octave 3
	note E_, 6
	octave 4
	note C_, 12
	octave 2
	note A_, 6
	octave 3
	note E_, 6
	octave 4
	note D_, 12
	octave 2
	sound_ret

Music_PetitCupBattle_Sub1:
	octave 2
	note A_, 8
	octave 3
	note A_, 8
	octave 2
	note A_, 8
	octave 3
	note A_, 8
	octave 2
	note A_, 8
	octave 3
	note A_, 8
	sound_ret

Music_PetitCupBattle_Sub2:
	octave 3
	note B_, 14
	rest 2
	note B_, 14
	rest 2
	note B_, 8
	note G#, 8
	octave 4
	note E_, 16
	duty_cycle 3
	octave 3
	note G_, 8
	note E_, 8
	rest 8
	note G_, 4
	note G_, 4
	note G_, 8
	note E_, 8
	octave 4
	note C#, 16
	rest 8
	note C#, 16
	note C#, 4
	note C#, 4
	note C#, 8
	octave 3
	note B_, 8
	octave 4
	note C#, 8
	note E_, 8
	note_type 12, 11, 0
	note D_, 12
	sound_ret

Music_PetitCupBattle_Sub3:
	note A_, 8
	octave 3
	note C#, 8
	note E_, 8
	note C#, 8
	octave 2
	note A_, 8
	octave 3
	note C#, 8
	note E_, 8
	note C#, 8
	sound_ret

Music_PetitCupBattle_Sub4:
	note A_, 8
	note A_, 8
	rest 8
	note A_, 4
	note A_, 4
	note A_, 8
	note F#, 8
	octave 4
	note D_, 16
	octave 3
	note A_, 8
	note F#, 8
	note A_, 8
	note F#, 8
	note A_, 8
	note F#, 8
	octave 4
	note D_, 16
	octave 3
	note B_, 8
	note B_, 8
	rest 8
	note B_, 4
	note B_, 4
	note B_, 8
	note G#, 8
	octave 4
	note E_, 16
	duty_cycle 2
	sound_ret

Music_PetitCupBattle_Sub5:
	note D_, 8
	octave 4
	note D_, 8
	octave 3
	note A_, 8
	octave 4
	note D_, 8
	octave 3
	sound_ret

Music_PetitCupBattle_Sub6:
	note G_, 8
	note B_, 8
	octave 4
	note D_, 8
	octave 3
	note B_, 8
	note G_, 8
	note B_, 8
	octave 4
	note D_, 8
	octave 3
	sound_ret

Music_PetitCupBattle_Sub7:
	note A_, 8
	octave 2
	note A_, 8
	octave 3
	note A_, 8
	note E_, 8
	note A_, 8
	octave 2
	note A_, 8
	octave 3
	sound_ret

Music_PetitCupBattle_Sub8:
	octave 2
	note E_, 8
	octave 3
	note E_, 8
	octave 2
	note E_, 8
	octave 3
	note E_, 8
	sound_ret

Music_PetitCupBattle_Sub9:
	octave 4
	note E_, 8
	octave 3
	note E_, 8
	octave 4
	note E_, 8
	octave 2
	note B_, 8
	octave 4
	note E_, 8
	octave 3
	note E_, 8
	octave 4
	note E_, 8
	octave 2
	note B_, 8
	octave 4
	note E_, 8
	octave 2
	note A_, 8
	octave 3
	note A_, 8
	sound_ret

Music_PetitCupBattle_Sub10:
	note A_, 12
	octave 3
	note A_, 6
	note E_, 6
	octave 2
	note A_, 12
	octave 3
	note A_, 6
	note E_, 6
	sound_ret

Music_PetitCupBattle_Sub11:
	note G#, 6
	note G_, 6
	note F#, 6
	note F_, 6
	note G_, 6
	note F#, 6
	note F_, 6
	note E_, 6
	note F#, 6
	note F_, 6
	note E_, 6
	note D#, 6
	note F_, 6
	note E_, 6
	note D#, 6
	note D_, 6
	note E_, 6
	note D#, 6
	note D_, 6
	note C#, 6
	sound_ret

Music_PetitCupBattle_Sub12:
	note G_, 8
	octave 2
	note A_, 8
	octave 3
	note G_, 8
	note E_, 8
	note G_, 8
	note D_, 8
	octave 4
	note D_, 8
	octave 3
	note D_, 8
	octave 4
	note D_, 8
	rest 8
	note D_, 8
	octave 3
	note D_, 8
	octave 4
	note D_, 8
	sound_ret

Music_PetitCupBattle_Sub13:
	note F_, 8
	note A_, 8
	octave 4
	note C_, 8
	octave 3
	note A_, 8
	sound_ret

Music_PetitCupBattle_Sub14:
	note E_, 8
	note G#, 8
	note B_, 8
	octave 3
	note D_, 8
	note E_, 8
	note D_, 8
	octave 2
	note B_, 8
	note G#, 8
	note E_, 8
	note G#, 8
	note B_, 8
	octave 3
	note D_, 8
	note E_, 8
	sound_ret

Music_PetitCupBattle_Sub15:
	octave 4
	note E_, 8
	octave 3
	note G#, 8
	octave 4
	note E_, 8
	octave 3
	sound_ret

Music_PetitCupBattle_Sub16:
	note A_, 15
	rest 16
	rest 1
	note A_, 15
	rest 16
	rest 1
	sound_ret

Music_PetitCupBattle_Sub17:
	octave 3
	note F#, 8
	note B_, 8
	note F#, 8
	octave 2
	note B_, 8
	sound_ret

Music_PetitCupBattle_Sub18:
	note G_, 8
	note D_, 8
	octave 2
	note G_, 8
	octave 3
	note D_, 8
	sound_ret

Music_PetitCupBattle_Sub19:
	note E_, 8
	octave 2
	note B_, 8
	note G#, 8
	note B_, 8
	octave 3
	sound_ret

Music_PetitCupBattle_Sub20:
	note A_, 8
	note E_, 8
	octave 2
	note A_, 8
	octave 3
	note E_, 8
	sound_ret

Music_PetitCupBattle_Sub21:
	note D_, 4
	note C#, 4
	note C_, 8
	note D_, 8
	note C_, 4
	note C#, 4
	sound_ret

Music_PetitCupBattle_Sub22:
	octave 4
	note C#, 8
	note E_, 8
	note C#, 8
	octave 3
	sound_ret

Music_PetitCupBattle_Sub23:
	note C_, 11
	rest 13
	note C_, 12
	volume_envelope 7, 0
	octave 2
	note A_, 12
	volume_envelope 8, 0
	octave 3
	sound_ret

Music_PetitCupBattle_Sub24:
	octave 2
	note G#, 8
	octave 3
	note E_, 8
	octave 2
	note B_, 8
	octave 3
	note E_, 8
	octave 2
	note G#, 8
	sound_ret

Music_PetitCupBattle_Sub25:
	note C_, 11
	rest 13
	note C_, 11
	rest 13
	note C_, 11
	rest 13
	sound_ret

Music_PetitCupBattle_Sub26:
	note G_, 6
	rest 6
	note G_, 6
	rest 6
	note G_, 6
	rest 6
	sound_ret

Music_PetitCupBattle_Sub27:
	note D_, 8
	note C_, 8
	note D_, 8
	note C_, 8
	note D_, 4
	note C#, 4
	note C_, 8
	note D_, 8
	note C_, 8
	sound_ret

Music_PetitCupBattle_Sub28:
	note G_, 8
	octave 4
	note D_, 8
	octave 3
	note G_, 8
	octave 4
	note D_, 8
	octave 3
	sound_ret

Music_PetitCupBattle_Sub29:
	note B_, 8
	note F#, 8
	rest 8
	note F#, 8
	rest 8
	note F#, 8
	note D_, 8
	note F#, 8
	sound_ret

Music_PetitCupBattle_Sub30:
	note B_, 8
	note G#, 8
	rest 8
	note G#, 8
	rest 8
	note G#, 8
	note E_, 8
	note G#, 8
	sound_ret

Music_PetitCupBattle_Sub31:
	note F#, 11
	rest 13
	note F#, 11
	rest 13
	note F#, 11
	rest 13
	note F#, 11
	rest 13
	sound_ret

Music_PetitCupBattle_Sub32:
	note A_, 11
	rest 13
	note A_, 11
	rest 13
	note A_, 11
	rest 13
	note A_, 11
	rest 13
	sound_ret

Music_PetitCupBattle_Sub33:
	note B_, 11
	rest 13
	note B_, 11
	rest 13
	note B_, 11
	rest 13
	note B_, 11
	rest 13
	sound_ret

Music_PetitCupBattle_Sub34:
	note C#, 11
	rest 13
	note C#, 11
	rest 13
	note C#, 11
	rest 13
	note C#, 11
	rest 13
	sound_ret

Music_PetitCupBattle_Sub35:
	note C#, 1
	note D_, 1
	note E_, 2
	note F#, 1
	note E_, 1
	rest 1
	note A_, 2
	note B_, 1
	sound_ret

Music_PetitCupBattle_Sub36:
	note F_, 8
	octave 4
	note F_, 8
	octave 2
	note F_, 8
	octave 4
	note F_, 8
	octave 3
	sound_ret

Music_PetitCupBattle_Sub37:
	note F_, 8
	octave 3
	note F_, 8
	octave 2
	note F_, 8
	octave 3
	note F_, 8
	octave 2
	sound_ret

Music_PetitCupBattle_Sub38:
	note D_, 8
	note F#, 8
	note A_, 8
	note F#, 8
	note D_, 8
	note F#, 8
	note A_, 8
	note F#, 8
	sound_ret

Music_PetitCupBattle_Sub39:
	note D_, 8
	octave 4
	note D_, 8
	octave 3
	note F#, 8
	octave 4
	note D_, 8
	octave 3
	sound_ret
