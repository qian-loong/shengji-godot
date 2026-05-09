## Unit tests for DeckManager (S1-05)
## Validates: F2 deck-management.md AC1-AC4
extends GutTest


func test_generate_1_deck() -> void:
	var cards := DeckManager.generate_deck(1)
	assert_eq(cards.size(), 54, "1 deck = 54 cards")
	# Count unique cards (ignoring deck_id)
	var unique := {}
	for c: Card in cards:
		unique[c.to_string_repr()] = true
	assert_eq(unique.size(), 54, "all 54 should be unique in 1 deck")


func test_generate_2_deck() -> void:
	var cards := DeckManager.generate_deck(2)
	assert_eq(cards.size(), 108, "2 decks = 108 cards")
	# Each card should appear exactly twice
	var counts := {}
	for c: Card in cards:
		var key := c.to_string_repr()
		counts[key] = counts.get(key, 0) + 1
	for key: String in counts:
		assert_eq(counts[key], 2, "%s should appear exactly 2 times" % key)


func test_shuffle_same_seed() -> void:
	var cards1 := DeckManager.generate_deck(2)
	var cards2 := DeckManager.generate_deck(2)
	DeckManager.shuffle(cards1, 42)
	DeckManager.shuffle(cards2, 42)
	var same := true
	for i: int in range(cards1.size()):
		if not cards1[i].equals(cards2[i]):
			same = false
			break
	assert_true(same, "same seed should produce same order")


func test_shuffle_different_seed() -> void:
	var cards1 := DeckManager.generate_deck(2)
	var cards2 := DeckManager.generate_deck(2)
	DeckManager.shuffle(cards1, 42)
	DeckManager.shuffle(cards2, 99)
	var same := true
	for i: int in range(cards1.size()):
		if not cards1[i].equals(cards2[i]):
			same = false
			break
	assert_false(same, "different seeds should produce different order")


func test_deal_2_deck() -> void:
	var cards := DeckManager.generate_deck(2)
	DeckManager.shuffle(cards, 1)
	var result := DeckManager.deal(cards, 25, 8)
	var hands: Array = result["hands"]
	var bottom: Array = result["bottom"]
	assert_eq(hands.size(), 4, "should have 4 hands")
	for i: int in range(4):
		assert_eq(hands[i].size(), 25, "player %d should have 25 cards" % i)
	assert_eq(bottom.size(), 8, "bottom should have 8 cards")
	# Total should be 108
	var total := bottom.size()
	for i: int in range(4):
		total += hands[i].size()
	assert_eq(total, 108, "total should be 108")


func test_deal_1_deck() -> void:
	var cards := DeckManager.generate_deck(1)
	DeckManager.shuffle(cards, 1)
	var result := DeckManager.deal(cards, 12, 6)
	var hands: Array = result["hands"]
	var bottom: Array = result["bottom"]
	for i: int in range(4):
		assert_eq(hands[i].size(), 12, "player %d should have 12 cards" % i)
	assert_eq(bottom.size(), 6, "bottom should have 6 cards")
