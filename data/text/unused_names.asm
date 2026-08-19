; Referenced only as a dead NamePointers slot (home/names2.asm, index UNUSED_NAME)
; that nothing in the codebase ever selects (no writer of wNameListType uses
; UNUSED_NAME). The symbol must still exist for that table to link, so this is a
; stub rather than a deletion. The original vanilla Japanese badge/ranking name
; data it replaced (UnusedBadgeNames' 8 badge names, and UnusedRankingNames,
; which had zero references at all) was removed 2026-08-19 to reclaim ROM space.
UnusedBadgeNames::
	db "@"
