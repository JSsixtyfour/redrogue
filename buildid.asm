; Build date and ID, shown at the bottom of the options screens.
;
; Reassembled by the Makefile's %.gbc rule on every link, with both strings
; passed in through -D, so it always matches the archived ROM's file name in
; builds/. It is its own object for that reason: stamping any other file would
; force that file to reassemble every build.
;
; Pinned to bank $3A beside "Options Menu", which reads these by plain label.
;
; Only debug builds display the stamp, so only they carry the strings. The
; section itself stays in every build (empty in release) because layout.link
; names it.

IF !DEF(BUILD_DATE_TEXT)
	DEF BUILD_DATE_TEXT EQUS "unknown"
ENDC
IF !DEF(BUILD_ID_TEXT)
	DEF BUILD_ID_TEXT EQUS "unknown"
ENDC

SECTION "Build ID", ROMX

IF DEF(_DEBUG)
BuildDateText::
	db "{BUILD_DATE_TEXT}@"

; Fixed width: a clean build ("1100c800") and a dirty one ("1100c800-dirty")
; would otherwise differ by 6 bytes and shift every later section in this
; bank, which tools/music_kit/import_music.py reads as its pin moving them.
DEF BUILD_ID_FIELD EQU 18 ; an 11-character hash, "-dirty" and the terminator

BuildIdText::
	db "{BUILD_ID_TEXT}@"
	ASSERT @ - BuildIdText <= BUILD_ID_FIELD, "build id is longer than BUILD_ID_FIELD"
	ds BUILD_ID_FIELD - (@ - BuildIdText), 0 ; never read: the text ends at its "@"
ENDC
