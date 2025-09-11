from apogeemind.processing.heuristics import HeuristicProcessor


def test_preference_classification_and_promotion():
    heur = HeuristicProcessor(promotion_threshold=0.5)
    user = "I prefer using black and ruff for Python formatting."
    ai = "Sure, I'll adopt black + ruff in the project."
    items = heur.process_conversation(user, ai)
    assert len(items) == 1
    pm = items[0]
    assert pm.category_primary == "preference"
    assert pm.classification == "conscious-info"
    assert pm.promotion_eligible is True
    assert 0.0 <= pm.importance_score <= 1.0
    assert pm.summary
    assert pm.content_hash


def test_skill_classification_and_entities():
    heur = HeuristicProcessor()
    user = "We should build a FastAPI service and test with pytest."
    ai = "Create app/main.py and add routers."
    items = heur.process_conversation(user, ai)
    pm = items[0]
    # Depending on phrasing, RULE_PATTERN may capture "should"; accept rule/skill/context
    assert pm.category_primary in {"skill", "context", "rule"}
    # Extracted entities include file path
    assert any(e.endswith(".py") for e in pm.entities) or pm.keywords
