# scenes/calculators/cogo/b1_resection.gd —— B1 后方交会（三已知点 + 两观测角，危险圆检核）
extends "res://scenes/calculators/cogo/cogo_calc_base.gd"

const CORE := preload("res://core/cogo/intersections.gd")

func _init() -> void:
	_entry_id = "b1_resection"
	_example_inputs = {
		"x_a_m": "2000", "y_a_m": "1200",
		"x_b_m": "1000", "y_b_m": "1000",
		"x_c_m": "1500", "y_c_m": "2000",
		"alpha_deg": "103.324531", "beta_deg": "118.495639",
	}

func get_title() -> String:
	return "后方交会（危险圆检核）（B1）"

func get_description() -> String:
	return "在待定点 P 上向三个已知点 A、B、C 观测水平角 α=∠APB、β=∠BPC（顺时针：PA 顺转 α 到 PB，PB 顺转 β 到 PC）。A、B、C 须按顺时针方向顺序对应观测角。危险圆（四点共圆）自动检出并给出中文警告。"

func _build_rows() -> void:
	add_input_row("已知点 A x（东，m）", "x_a_m", "2000")
	add_input_row("已知点 A y（北，m）", "y_a_m", "1200")
	add_input_row("已知点 B x（东，m）", "x_b_m", "1000")
	add_input_row("已知点 B y（北，m）", "y_b_m", "1000")
	add_input_row("已知点 C x（东，m）", "x_c_m", "1500")
	add_input_row("已知点 C y（北，m）", "y_c_m", "2000")
	add_input_row("观测角 α = ∠APB", "alpha_deg", "103.324531（或 103 19 28）")
	add_input_row("观测角 β = ∠BPC", "beta_deg", "118.495639（或 118 29 44）")

func run() -> Dictionary:
	var bad: Array = []
	var xa := num_field(_fields["x_a_m"], "已知点 A x", bad)
	var ya := num_field(_fields["y_a_m"], "已知点 A y", bad)
	var xb := num_field(_fields["x_b_m"], "已知点 B x", bad)
	var yb := num_field(_fields["y_b_m"], "已知点 B y", bad)
	var xc := num_field(_fields["x_c_m"], "已知点 C x", bad)
	var yc := num_field(_fields["y_c_m"], "已知点 C y", bad)
	var al := ang_field(_fields["alpha_deg"], "观测角 α", bad)
	var be := ang_field(_fields["beta_deg"], "观测角 β", bad)
	if not bad.is_empty():
		return fail_input(bad)
	return CORE.b1_resection({
		"x_a_m": xa, "y_a_m": ya, "x_b_m": xb, "y_b_m": yb,
		"x_c_m": xc, "y_c_m": yc,
		"alpha_deg": al, "beta_deg": be,
	})
