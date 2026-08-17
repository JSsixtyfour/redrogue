from __future__ import annotations

from dataclasses import dataclass
from enum import Enum


class RewardGate(Enum):
    STANDARD_FIVE_TRAINERS = "standard_five_trainers"
    NUGGET_BRIDGE = "nugget_bridge"
    SS_ANNE_ROOMS = "ss_anne_rooms"


@dataclass(frozen=True)
class RouteContract:
    name: str
    map_constant: str
    object_file: str
    script_symbol: str
    trainer_event_prefix: str | None
    reward_gate: RewardGate = RewardGate.STANDARD_FIVE_TRAINERS
    standard_object_slots: bool = True
    miniboss_eligible: bool = False

    @property
    def trainer_events(self) -> tuple[str, ...]:
        if self.trainer_event_prefix is None:
            return ()
        return tuple(f"{self.trainer_event_prefix}{index}" for index in range(5))


def route(name, map_constant, object_file, script_symbol, trainer_event_prefix,
          *, reward_gate=RewardGate.STANDARD_FIVE_TRAINERS,
          standard_object_slots=True, miniboss_eligible=False):
    return RouteContract(name, map_constant, object_file, script_symbol,
                         trainer_event_prefix, reward_gate,
                         standard_object_slots, miniboss_eligible)


ROUTE_CONTRACTS = (
    route("Route 1", "ROUTE_1", "Route1.asm", "wRoute1CurScript", "EVENT_BEAT_ROUTE_1_TRAINER_", miniboss_eligible=True),
    route("Route 3", "ROUTE_3", "Route3.asm", "wRoute3CurScript", "EVENT_BEAT_ROUTE_3_TRAINER_", miniboss_eligible=True),
    route("Route 5", "ROUTE_5", "Route5.asm", "wRoute5CurScript", "EVENT_BEAT_ROUTE_5_TRAINER_"),
    route("Route 6", "ROUTE_6", "Route6.asm", "wRoute6CurScript", "EVENT_BEAT_ROUTE_6_TRAINER_"),
    route("Route 9", "ROUTE_9", "Route9.asm", "wRoute9CurScript", "EVENT_BEAT_ROUTE_9_TRAINER_", miniboss_eligible=True),
    route("Route 12", "ROUTE_12", "Route12.asm", "wRoute12CurScript", "EVENT_BEAT_ROUTE_12_TRAINER_"),
    route("Route 13", "ROUTE_13", "Route13.asm", "wRoute13CurScript", "EVENT_BEAT_ROUTE_13_TRAINER_"),
    route("Route 15", "ROUTE_15", "Route15.asm", "wRoute15CurScript", "EVENT_BEAT_ROUTE_15_TRAINER_"),
    route("Underground Path West-East", "UNDERGROUND_PATH_WEST_EAST", "UndergroundPathWestEast.asm", "wUndergroundPathRoute5CurScript", "EVENT_BEAT_UNDERGROUND_PATH_WEST_EAST_TRAINER_", miniboss_eligible=True),
    route("Route 24", "ROUTE_24", "Route24.asm", "wRoute24CurScript", "EVENT_BEAT_ROUTE_24_TRAINER_", reward_gate=RewardGate.NUGGET_BRIDGE),
    route("Route 25", "ROUTE_25", "Route25.asm", "wRoute25CurScript", "EVENT_BEAT_ROUTE_25_TRAINER_", miniboss_eligible=True),
    route("Viridian Forest", "VIRIDIAN_FOREST", "ViridianForest.asm", "wViridianForestCurScript", "EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_", miniboss_eligible=True),
    route("Diglett's Cave", "DIGLETTS_CAVE", "DiglettsCave.asm", "wDiglettsCaveCurScript", "EVENT_BEAT_DIGLETTS_CAVE_TRAINER_", miniboss_eligible=True),
    route("Mt. Moon 1F", "MT_MOON_1F", "MtMoon1F.asm", "wMtMoon1FCurScript", "EVENT_BEAT_MT_MOON_1_TRAINER_", miniboss_eligible=True),
    route("Rock Tunnel 1F", "ROCK_TUNNEL_1F", "RockTunnel1F.asm", "wRockTunnel1FCurScript", "EVENT_BEAT_ROCK_TUNNEL_1_TRAINER_", miniboss_eligible=True),
    route("Rocket Hideout B1F", "ROCKET_HIDEOUT_B1F", "RocketHideoutB1F.asm", "wRocketHideoutB1FCurScript", "EVENT_BEAT_ROCKET_HIDEOUT_1_TRAINER_", miniboss_eligible=True),
    route("Pokemon Tower 2F", "POKEMON_TOWER_2F", "PokemonTower2F.asm", "wPokemonTower2FCurScript", "EVENT_BEAT_POKEMON_TOWER_2F_TRAINER_", miniboss_eligible=True),
    route("Pokemon Tower 7F", "POKEMON_TOWER_7F", "PokemonTower7F.asm", "wPokemonTower7FCurScript", "EVENT_BEAT_POKEMONTOWER_7_TRAINER_", miniboss_eligible=True),
    route("SS Anne B1F", "SS_ANNE_B1F", "SSAnneB1F.asm", "wSSAnneB1FCurScript", None, reward_gate=RewardGate.SS_ANNE_ROOMS, standard_object_slots=False),
    route("Power Plant", "POWER_PLANT", "PowerPlant.asm", "wPowerPlantCurScript", "EVENT_BEAT_POWER_PLANT_TRAINER_", miniboss_eligible=True),
    route("Pokemon Mansion 1F", "POKEMON_MANSION_1F", "PokemonMansion1F.asm", "wPokemonMansion1FCurScript", "EVENT_BEAT_MANSION_1_TRAINER_", miniboss_eligible=True),
    route("Seafoam Islands 1F", "SEAFOAM_ISLANDS_1F", "SeafoamIslands1F.asm", "wSeafoamIslands1FCurScript", "EVENT_BEAT_SEAFOAM_ISLANDS_1F_TRAINER_", miniboss_eligible=True),
)
