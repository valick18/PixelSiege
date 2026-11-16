extends Node
# SaveManager: періодичне збереження стану матчу (seed, рахунок, зміни блоків, споруди) у user://match_save.json.

const INTERVAL := 30.0
var g
var t := INTERVAL


func tick(dt: float) -> void:
	t -= dt
	if t <= 0.0:
		t = INTERVAL
		save_match()


func save_match() -> void:
	var arr := []
	for c in g.edits:
		arr.append([c.x, c.y, g.edits[c][0], g.edits[c][1]])
	var st_arr := []
	for c in g.structs:
		st_arr.append([c.x, c.y, g.structs[c].type, g.structs[c].team])
	var data := {"server": Net.server_name, "seed": Net.world_seed, "size": Net.map_size, "score": g.score, "edits": arr, "structs": st_arr, "store": g.store, "trees": g.world.trees}
	var f := FileAccess.open("user://match_save.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
