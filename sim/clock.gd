extends RefCounted
class_name SimClock

## The only delta the simulation is allowed to consume.
## Presentation code may accumulate real frame time; sim/step never reads it.

const HZ := 60
const DT := 1.0 / 60.0
