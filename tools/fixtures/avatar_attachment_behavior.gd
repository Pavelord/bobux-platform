extends Node3D
@export var counter: int = 7
func increment() -> int:
	counter += 1
	return counter
