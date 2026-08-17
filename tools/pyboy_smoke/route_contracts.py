from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class RouteContract:
    name: str
    map_constant: str
    object_file: str
    script_symbol: str
    expected_warps: tuple[tuple[int, int, int, str], ...]
    sprite_count: int
    trainer_classes: tuple[str, ...]
    trainer_events: tuple[str, ...]


ROUTE_CONTRACTS = (
    RouteContract(
        name="Underground Path West-East",
        map_constant="UNDERGROUND_PATH_WEST_EAST",
        object_file="UndergroundPathWestEast.asm",
        script_symbol="wUndergroundPathRoute5CurScript",
        expected_warps=((5, 2, 0, "WARP_NO_RETURN"), (2, 47, 0, "INDIGO_PLATEAU_LOBBY")),
        sprite_count=10,
        trainer_classes=("BIKER", "JUGGLER", "BURGLAR", "BIKER", "CUE_BALL"),
        trainer_events=tuple(
            f"EVENT_BEAT_UNDERGROUND_PATH_WEST_EAST_TRAINER_{index}"
            for index in range(5)
        ),
    ),
    RouteContract(
        name="Route 1",
        map_constant="ROUTE_1",
        object_file="Route1.asm",
        script_symbol="wRoute1CurScript",
        expected_warps=(
            (35, 10, 0, "WARP_NO_RETURN"),
            (35, 11, 0, "WARP_NO_RETURN"),
            (1, 11, 0, "INDIGO_PLATEAU_LOBBY"),
            (0, 7, 0, "INDIGO_PLATEAU_LOBBY"),
        ),
        sprite_count=12,
        trainer_classes=("YOUNGSTER", "YOUNGSTER", "YOUNGSTER", "YOUNGSTER", "JR_TRAINER_M"),
        trainer_events=tuple(f"EVENT_BEAT_ROUTE_1_TRAINER_{index}" for index in range(5)),
    ),
    RouteContract(
        name="Mt. Moon 1F",
        map_constant="MT_MOON_1F",
        object_file="MtMoon1F.asm",
        script_symbol="wMtMoon1FCurScript",
        expected_warps=(
            (35, 14, 1, "WARP_NO_RETURN"),
            (35, 15, 1, "WARP_NO_RETURN"),
            (5, 5, 0, "INDIGO_PLATEAU_LOBBY"),
            (11, 17, 0, "INDIGO_PLATEAU_LOBBY"),
            (15, 25, 0, "INDIGO_PLATEAU_LOBBY"),
        ),
        sprite_count=15,
        trainer_classes=("LASS", "BUG_CATCHER", "SUPER_NERD", "YOUNGSTER", "HIKER"),
        trainer_events=tuple(f"EVENT_BEAT_MT_MOON_1_TRAINER_{index}" for index in range(5)),
    ),
)
