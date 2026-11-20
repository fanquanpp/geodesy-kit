extends SceneTree

func _initialize() -> void:
	var P = load("res://core/topics/photogrammetry.gd")
	var ext_true := {"f": 100.0, "Xs": 0.0, "Ys": 0.0, "Zs": 100.0,
			"phi_deg": 0.0, "omega_deg": 0.0, "kappa_deg": 180.0}
	var noise := [0.002, -0.001, 0.003, 0.001, -0.002, 0.002, 0.0, -0.003, 0.001, 0.002]
	var pts := [[0.0, 0.0, 0.0], [40.0, 0.0, 0.0], [0.0, 30.0, 0.0], [40.0, 30.0, 0.0], [20.0, 15.0, 45.0]]
	var recs := PackedStringArray()
	var i := 0
	for pt: Array in pts:
		var img: Array = P.project(ext_true, pt)
		recs.append("%s,%s,%s,%s,%s" % [str(pt[0]), str(pt[1]), str(pt[2]),
				str(float(img[0]) + float(noise[i * 2])), str(float(img[1]) + float(noise[i * 2 + 1]))])
		i += 1
	print("controls: ", ";".join(recs))
	var r: Dictionary = P.resection({"f": 100.0, "controls": ";".join(recs)})
	print("ok=", r.get("ok"), " err=", r.get("error"))
	if bool(r.get("ok", false)):
		print("value=", r.get("value"))
	quit(0)
