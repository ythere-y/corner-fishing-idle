extends SceneTree
func _init():
	var sp = ProcFishSpecies.from_catch("crucian", 0, -1.0)
	print("species ok: ", sp != null, "  type: ", sp.get_class() if sp != null else "null")
	var pf = ProcFish.new()
	print("fish ok: ", pf != null, "  type: ", pf.get_class() if pf != null else "null")
	quit()
