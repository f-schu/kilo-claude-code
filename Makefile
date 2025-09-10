.PHONY: plan

# Usage:
#   make plan scope="Fix drop order for genome tables" \
#            non_goals="don't refactor unrelated modules" \
#            constraints="prod data unaffected, time<30m" \
#            acceptance="unit tests green, drop order correct" \
#            ttl=45
plan:
	@bash scripts/mkplan.sh "$(scope)" "$(non_goals)" "$(constraints)" "$(acceptance)" "$(ttl)"

