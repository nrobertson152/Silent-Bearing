## Creates the simulation for a boat: the wartime World, or ModernWorld for
## the near-future boats.

const GameData := preload("res://scripts/data.gd")
const ModernWorld := preload("res://scripts/sim/modern_world.gd")
const World := preload("res://scripts/sim/world.gd")


static func create(nat: Dictionary, spec: Dictionary, demo := false) -> World:
	if GameData.is_modern(nat):
		return ModernWorld.new(nat, spec, demo)
	return World.new(nat, spec, demo)
