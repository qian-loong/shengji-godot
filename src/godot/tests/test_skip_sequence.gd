## Unit tests for skip sequence & adjacency (S1-02)
## Validates: F1 card-types.md AC5-AC8
extends GutTest


# ============================================================
# AC5: get_skip_sequence
# ============================================================

func test_skip_sequence_rank_4() -> void:
	var seq := Card.get_skip_sequence(Card.Rank.FOUR)
	assert_eq(seq.size(), 12, "should have 12 ranks")
	assert_false(seq.has(Card.Rank.FOUR), "should not contain rank 4")
	assert_eq(seq[0], Card.Rank.TWO, "first is TWO")
	assert_eq(seq[1], Card.Rank.THREE, "second is THREE")
	assert_eq(seq[2], Card.Rank.FIVE, "third is FIVE (skipped 4)")
	assert_eq(seq[11], Card.Rank.ACE, "last is ACE")


func test_skip_sequence_rank_2() -> void:
	var seq := Card.get_skip_sequence(Card.Rank.TWO)
	assert_eq(seq.size(), 12)
	assert_eq(seq[0], Card.Rank.THREE, "first is THREE")
	assert_false(seq.has(Card.Rank.TWO))


func test_skip_sequence_rank_ace() -> void:
	var seq := Card.get_skip_sequence(Card.Rank.ACE)
	assert_eq(seq.size(), 12)
	assert_eq(seq[11], Card.Rank.KING, "last is KING")
	assert_false(seq.has(Card.Rank.ACE))


# ============================================================
# AC6-AC8: is_adjacent
# ============================================================

func test_adjacent_base_sequence() -> void:
	# AC6: 3 and 4 adjacent in base sequence (rank=4, rank card participates)
	assert_true(Card.is_adjacent(Card.Rank.THREE, Card.Rank.FOUR, Card.Rank.FOUR),
		"3-4 adjacent (base)")


func test_adjacent_skip_sequence() -> void:
	# AC7: 3 and 5 adjacent in skip sequence (rank=4, skipping 4)
	assert_true(Card.is_adjacent(Card.Rank.THREE, Card.Rank.FIVE, Card.Rank.FOUR),
		"3-5 adjacent (skip, rank=4)")


func test_not_adjacent() -> void:
	# AC8: 3 and 6 not adjacent in either sequence
	assert_false(Card.is_adjacent(Card.Rank.THREE, Card.Rank.SIX, Card.Rank.FOUR),
		"3-6 not adjacent")


func test_adjacent_4_5_when_rank_4() -> void:
	# 4 and 5 adjacent in base sequence
	assert_true(Card.is_adjacent(Card.Rank.FOUR, Card.Rank.FIVE, Card.Rank.FOUR),
		"4-5 adjacent (base, rank=4)")


func test_adjacent_king_ace() -> void:
	assert_true(Card.is_adjacent(Card.Rank.KING, Card.Rank.ACE, Card.Rank.FOUR),
		"K-A adjacent")


func test_not_adjacent_ace_two() -> void:
	# A and 2 are NOT adjacent (no wrapping)
	assert_false(Card.is_adjacent(Card.Rank.ACE, Card.Rank.TWO, Card.Rank.FOUR),
		"A-2 not adjacent (no wrap)")


func test_adjacent_rank_2_skip() -> void:
	# When rank=2, skip sequence starts at 3
	# 3 and 4 are adjacent in skip sequence
	assert_true(Card.is_adjacent(Card.Rank.THREE, Card.Rank.FOUR, Card.Rank.TWO),
		"3-4 adjacent (skip, rank=2)")
	# 2 and 3 are adjacent in base sequence (rank card participates)
	assert_true(Card.is_adjacent(Card.Rank.TWO, Card.Rank.THREE, Card.Rank.TWO),
		"2-3 adjacent (base, rank=2)")
	# 3 and 5 NOT adjacent when rank=2 (skip removes 2, so seq is 3,4,5...)
	assert_false(Card.is_adjacent(Card.Rank.THREE, Card.Rank.FIVE, Card.Rank.TWO),
		"3-5 not adjacent (rank=2)")


func test_symmetry() -> void:
	# Adjacency should be symmetric
	assert_true(Card.is_adjacent(Card.Rank.FIVE, Card.Rank.THREE, Card.Rank.FOUR),
		"5-3 adjacent (reverse of 3-5)")
