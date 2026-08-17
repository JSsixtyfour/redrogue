; Silph Co B1F follower data. Kept with the overworld movement data rather than
; embedded in the map script, matching the organization used by Silph Co 1F.

; Palm: (16,1) -> (16,2) -> (1,2).
RLEList_SilphCoB1FPalmToDorm:
	db NPC_MOVEMENT_DOWN, 1
	db NPC_MOVEMENT_LEFT, 15
	db -1

; Player: (16,0) -> (16,2) -> (2,2). Simulated joypad RLE executes in reverse.
RLEList_SilphCoB1FPlayerToDorm:
	; Executed last: keep control active while Palm settles on his final tile.
	db NO_INPUT, 1
	db PAD_LEFT, 14
	db PAD_DOWN, 2
	db -1

; Ascend only after the dorm stop, then walk right on y=1.
; Palm: (1,2) -> (1,1) -> (7,1).
RLEList_SilphCoB1FPalmToCreditExchange:
	db NPC_MOVEMENT_UP, 1
	db NPC_MOVEMENT_RIGHT, 6
	db -1

; Player waits two beats while Palm gets around him, follows to (6,1), then
; waits one final beat while Palm settles. This source executes in reverse.
RLEList_SilphCoB1FPlayerToCreditExchange:
	db NO_INPUT, 1
	db PAD_RIGHT, 4
	db PAD_UP, 1
	db NO_INPUT, 2
	db -1

; Palm/player remain one tile apart on y=1.
RLEList_SilphCoB1FPalmToVR:
	db NPC_MOVEMENT_RIGHT, 4
	db -1

RLEList_SilphCoB1FPlayerToVR:
	db NO_INPUT, 1
	db PAD_RIGHT, 4
	db -1

; Palm needs one tile step. The player needs two UP inputs after the textbox:
; one clears the settled standing state and one enters the warp. The source's
; leading NO_INPUT executes last and keeps the NPC movement alive until warp.
RLEList_SilphCoB1FPalmEnterVR:
	db NPC_MOVEMENT_UP, 1
	db -1

RLEList_SilphCoB1FPlayerEnterVR:
	db NO_INPUT, 1
	db PAD_UP, 2
	db -1
