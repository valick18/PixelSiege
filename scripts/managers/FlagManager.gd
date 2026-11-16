extends Node
# FlagManager: захоплення прапора (CTF), повернення, рахунок, кінець матчу. Працює на хості.

var g


func drop_flag_of(id: int) -> void:
	if not g.multiplayer.is_server() or g.flags.is_empty():
		return
	for t in 2:
		if g.flags[t].carrier == id:
			g.flags[t].carrier = 0
			g.flags[t].home = false
			g.flags[t].pos = g.world.drop_pos(g.flags[t].pos)
			g.c_flags.rpc(g.flags)


func rows() -> Array:
	var out := []
	for id in g.st:
		if Net.players.has(id):
			out.append([Net.players[id].name, Net.players[id].team, g.st[id].k, g.st[id].d, g.st[id].c])
	return out


func tick() -> void:
	var changed := false
	for t in 2:
		var f = g.flags[t]
		if f.carrier != 0:
			var c = g.player_node(f.carrier)
			if c:
				f.pos = c.position + Vector2(0, 10)
			continue
		for id in g.st:
			if g.st[id].dead_until > 0.0 or not Net.players.has(id):
				continue
			var q = g.player_node(id)
			if q == null or q.position.distance_to(f.pos) > 26.0:
				continue
			if int(Net.players[id].team) != t:
				f.carrier = id
				f.home = false
				changed = true
				break
			elif not f.home:
				f.pos = g.world.flag_pos(t)
				f.home = true
				changed = true
				break
	for id in g.st:
		if g.st[id].dead_until > 0.0 or not Net.players.has(id):
			continue
		var team: int = Net.players[id].team
		var enemy := 1 - team
		if g.flags[enemy].carrier != id or not g.flags[team].home:
			continue
		var q = g.player_node(id)
		if q and q.position.distance_to(g.flags[team].pos) < 30.0:
			g.flags[enemy].carrier = 0
			g.flags[enemy].home = true
			g.flags[enemy].pos = g.world.flag_pos(enemy)
			g.score[team] += 1
			g.st[id].c = int(g.st[id].c) + 1
			changed = true
			if g.score[team] >= g.WIN_SCORE:
				g.winner = team
				g.match_over = true
				end_match()
			g.c_score.rpc(g.score, g.winner, rows())
	if changed:
		g.c_flags.rpc(g.flags)


func end_match() -> void:
	await get_tree().create_timer(10.0).timeout
	if is_inside_tree():
		g.new_match.rpc(randi())
