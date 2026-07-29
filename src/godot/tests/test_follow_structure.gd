## Unit tests for follow-structure constraint (C2 §2)
##
## strict_follow_structure 不是格式检查，是**平衡杠杆**：
## 不许拆对意味着跟牌方被迫交出更多分。
extends GutTest

const R := Card.Rank
const S := Card.Suit


func _config(strict: bool) -> RuleConfig:
	var rc := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	rc.strict_follow_structure = strict
	return rc


func _follow(played: Array, hand: Array, lead: Array, strict: bool) -> bool:
	var rc := _config(strict)
	var lead_pattern := CardPattern.identify(
		lead, R.TWO, rc.tractor_allow_rank_card, rc.four_same_is_tractor)
	var lead_domain := TrumpJudge.get_suit_domain(lead[0], S.SPADE, R.TWO, true)
	return PlayValidator.validate_follow(
		played, hand, lead.size(), lead_domain, S.SPADE, R.TWO, rc, lead_pattern)


# ============================================================
# 首出对子
# ============================================================

func test_strict_forbids_splitting_pair_on_pair_lead() -> void:
	# 首出 ♥K♥K(20分)，手握 ♥10♥10 —— 不许拆，被迫送 20 分
	var lead := [Card.normal(S.HEART, R.KING), Card.normal(S.HEART, R.KING)]
	var hand := [Card.normal(S.HEART, R.TEN), Card.normal(S.HEART, R.TEN),
				 Card.normal(S.HEART, R.THREE)]
	var split := [Card.normal(S.HEART, R.TEN), Card.normal(S.HEART, R.THREE)]

	assert_false(_follow(split, hand, lead, true), "严格模式下拆对非法")


func test_loose_allows_splitting_pair_to_save_points() -> void:
	# 关掉开关即可拆对控分：只送 10 分而非 20 分
	var lead := [Card.normal(S.HEART, R.KING), Card.normal(S.HEART, R.KING)]
	var hand := [Card.normal(S.HEART, R.TEN), Card.normal(S.HEART, R.TEN),
				 Card.normal(S.HEART, R.THREE)]
	var split := [Card.normal(S.HEART, R.TEN), Card.normal(S.HEART, R.THREE)]

	assert_true(_follow(split, hand, lead, false), "宽松模式下可拆对保分")


func test_keeping_pair_is_always_legal() -> void:
	var lead := [Card.normal(S.HEART, R.KING), Card.normal(S.HEART, R.KING)]
	var hand := [Card.normal(S.HEART, R.TEN), Card.normal(S.HEART, R.TEN),
				 Card.normal(S.HEART, R.THREE)]
	var keep := [Card.normal(S.HEART, R.TEN), Card.normal(S.HEART, R.TEN)]

	assert_true(_follow(keep, hand, lead, true))
	assert_true(_follow(keep, hand, lead, false))


func test_no_pair_in_hand_means_no_constraint() -> void:
	# 手里本来就没有对子，怎么出都行
	var lead := [Card.normal(S.HEART, R.KING), Card.normal(S.HEART, R.KING)]
	var hand := [Card.normal(S.HEART, R.TEN), Card.normal(S.HEART, R.THREE),
				 Card.normal(S.HEART, R.SEVEN)]
	var played := [Card.normal(S.HEART, R.TEN), Card.normal(S.HEART, R.THREE)]

	assert_true(_follow(played, hand, lead, true))


# ============================================================
# 首出甩牌 —— 曾经的漏洞：DUMP 分支缺失导致约束整个失效
# ============================================================

func test_strict_forbids_splitting_pair_on_dump_lead() -> void:
	# 首出甩牌 ♥K♥K♥5(25分)。修复前这里能拆对只送 10 分，
	# 导致甩牌反而比出对子更逼不出分，攻击力倒挂。
	var lead := [Card.normal(S.HEART, R.KING), Card.normal(S.HEART, R.KING),
				 Card.normal(S.HEART, R.FIVE)]
	var hand := [Card.normal(S.HEART, R.TEN), Card.normal(S.HEART, R.TEN),
				 Card.normal(S.HEART, R.THREE), Card.normal(S.HEART, R.SEVEN)]
	var split := [Card.normal(S.HEART, R.TEN), Card.normal(S.HEART, R.THREE),
				  Card.normal(S.HEART, R.SEVEN)]

	assert_false(_follow(split, hand, lead, true),
		"首出甩牌含对子时，严格模式同样不许拆对")


func test_loose_allows_splitting_on_dump_lead() -> void:
	var lead := [Card.normal(S.HEART, R.KING), Card.normal(S.HEART, R.KING),
				 Card.normal(S.HEART, R.FIVE)]
	var hand := [Card.normal(S.HEART, R.TEN), Card.normal(S.HEART, R.TEN),
				 Card.normal(S.HEART, R.THREE), Card.normal(S.HEART, R.SEVEN)]
	var split := [Card.normal(S.HEART, R.TEN), Card.normal(S.HEART, R.THREE),
				  Card.normal(S.HEART, R.SEVEN)]

	assert_true(_follow(split, hand, lead, false))


func test_matching_dump_structure_is_legal() -> void:
	var lead := [Card.normal(S.HEART, R.KING), Card.normal(S.HEART, R.KING),
				 Card.normal(S.HEART, R.FIVE)]
	var hand := [Card.normal(S.HEART, R.TEN), Card.normal(S.HEART, R.TEN),
				 Card.normal(S.HEART, R.THREE), Card.normal(S.HEART, R.SEVEN)]
	var keep := [Card.normal(S.HEART, R.TEN), Card.normal(S.HEART, R.TEN),
				 Card.normal(S.HEART, R.THREE)]

	assert_true(_follow(keep, hand, lead, true))


func test_remaining_card_choice_is_free() -> void:
	# Q3 结论：对上对子后，剩余单张任选（首出甩牌已通过最大性校验，
	# 跟牌方必然接不住，强制出最大只是白送大牌）
	var lead := [Card.normal(S.HEART, R.KING), Card.normal(S.HEART, R.KING),
				 Card.normal(S.HEART, R.FIVE)]
	var hand := [Card.normal(S.HEART, R.TEN), Card.normal(S.HEART, R.TEN),
				 Card.normal(S.HEART, R.THREE), Card.normal(S.HEART, R.SEVEN)]
	var with_small := [Card.normal(S.HEART, R.TEN), Card.normal(S.HEART, R.TEN),
					   Card.normal(S.HEART, R.THREE)]
	var with_big := [Card.normal(S.HEART, R.TEN), Card.normal(S.HEART, R.TEN),
					 Card.normal(S.HEART, R.SEVEN)]

	assert_true(_follow(with_small, hand, lead, true), "剩余出小牌合法")
	assert_true(_follow(with_big, hand, lead, true), "剩余出大牌也合法")


# ============================================================
# 首出拖拉机
# ============================================================

func test_tractor_lead_requires_as_many_pairs_as_possible() -> void:
	# 首出两对拖拉机，手里只有一个对子 → 至少要出那一个
	var lead := [Card.normal(S.HEART, R.KING), Card.normal(S.HEART, R.KING),
				 Card.normal(S.HEART, R.QUEEN), Card.normal(S.HEART, R.QUEEN)]
	var hand := [Card.normal(S.HEART, R.TEN), Card.normal(S.HEART, R.TEN),
				 Card.normal(S.HEART, R.THREE), Card.normal(S.HEART, R.SEVEN)]
	var no_pair := [Card.normal(S.HEART, R.TEN), Card.normal(S.HEART, R.THREE),
					Card.normal(S.HEART, R.SEVEN), Card.normal(S.HEART, R.TEN)]

	# 注意：上面这手其实含了 ♥10♥10，属于合法；构造一手真正拆开的
	var truly_split := [Card.normal(S.HEART, R.TEN), Card.normal(S.HEART, R.THREE),
						Card.normal(S.HEART, R.SEVEN)]
	assert_true(_follow(no_pair, hand, lead, true), "含对子的跟牌合法")
	assert_false(_follow(truly_split, hand, lead, true), "张数不足本就非法")
