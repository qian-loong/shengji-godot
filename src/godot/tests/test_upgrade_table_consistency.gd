## Unit tests for RuleConfig upgrade-table consistency (F3 §2.4)
##
## upgrade_threshold 与 upgrade_table 描述同一件事的两面，必须自洽。
extends GutTest


func test_build_table_reproduces_classic_preset() -> void:
	var preset := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)

	var built := RuleConfig.build_upgrade_table(80, preset.max_reachable_score())

	assert_eq(built, preset.upgrade_table, "门槛 80 应生成经典预设的表")


func test_build_table_reproduces_competitive_preset() -> void:
	# 2 副牌不截断：250 档超过 total_score(200)，但末墩打对子扣底能放大到那里
	var preset := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_COMPETITIVE)

	var built := RuleConfig.build_upgrade_table(100, preset.max_reachable_score())

	assert_eq(built, preset.upgrade_table, "门槛 100 应生成竞技预设的表")


func test_two_decks_have_no_score_cap() -> void:
	# 扣底倍数可 ≥2，final_score 能突破 total_score
	var preset := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)

	assert_eq(preset.max_reachable_score(), 0, "2 副牌不设上限")


func test_single_deck_caps_at_total_score() -> void:
	# 1 副牌凑不出对子 ⇒ 扣底倍数恒为 1 ⇒ final_score ≤ total_score
	var preset := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_QUICK)

	assert_eq(preset.max_reachable_score(), 100, "1 副牌封顶在 total_score")


func test_build_table_truncates_unreachable_tiers_for_single_deck() -> void:
	# quick 门槛 60，[120,1,3] 档在 1 副牌下永远够不到
	var built := RuleConfig.build_upgrade_table(60, 100)

	for row: Array in built:
		assert_true(int(row[0]) <= 100,
			"不应生成够不到的档位，实际有 %d" % int(row[0]))


func test_build_table_without_cap_keeps_all_tiers() -> void:
	var built := RuleConfig.build_upgrade_table(60, 0)

	assert_eq(built.size(), 7, "不传上限时应生成完整 7 档")


func test_all_presets_are_self_consistent() -> void:
	for preset: int in [
		RuleConfig.ConfigSource.PRESET_CLASSIC,
		RuleConfig.ConfigSource.PRESET_COMPETITIVE,
		RuleConfig.ConfigSource.PRESET_QUICK,
	]:
		var config := RuleConfig.from_preset(preset as RuleConfig.ConfigSource)
		var errors := config.validate()
		assert_eq(errors, [] as Array[String],
			"预设 %d 自身应通过校验，实际: %s" % [preset, str(errors)])


func test_threshold_disagreeing_with_table_is_rejected() -> void:
	# 这正是 threshold_100 矩阵用例踩的坑：只改门槛没改表
	var config := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	config.upgrade_threshold = 100  # 表仍是 80 档

	var errors := config.validate()

	assert_gt(errors.size(), 0, "门槛与表失配应被拦下")
	var joined := " ".join(errors)
	assert_true(joined.contains("disagrees"), "错误信息应指出失配，实际: %s" % joined)


func test_set_upgrade_threshold_keeps_table_in_sync() -> void:
	var config := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)

	config.set_upgrade_threshold(100)

	assert_eq(config.upgrade_threshold, 100)
	assert_eq(config.get_attack_threshold(), 100, "表的攻方首档应同步到 100")
	assert_eq(config.validate(), [] as Array[String], "同步修改后应自洽")


func test_get_attack_threshold_finds_lowest_attack_tier() -> void:
	var config := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)

	assert_eq(config.get_attack_threshold(), 80)
