extends Node
func run():
	var a: int = Net.name_to_idx["Oxford Circus"]
	var p := StationPlan.for_station(a)
	var d := p.dijkstra("esc0_top")
	print("from esc0_top: bot=", d["esc0_bot"], " landing0=", d["landing0"], " hall_paid=", d["hall_paid"])
	var d2 := p.dijkstra("hall_paid")
	print("from hall_paid: top=", d2["esc0_top"], " bot=", d2["esc0_bot"])
	print("adj bot: ", p.adj[p.node_idx["esc0_bot"]])
