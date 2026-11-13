extends RefCounted
class_name SimCommand

## Game_test@33f4be8 src/sim/command.ts.
## External input for one tick. Movement reads throttle, turn and strafe.
## Combat reads aim, fire, slot, secondaries and lock.


static func idle() -> Dictionary:
	return {
		"throttle": 0.0,
		"turn": 0.0,
		"strafe": 0.0,
		"aim": null,
		"fire": false,
		"slot": 0,
		"secondaries": true,
		"lock": null,
	}


static func merge(partial: Dictionary) -> Dictionary:
	var command := idle()
	for key in partial.keys():
		command[key] = partial[key]
	return command
