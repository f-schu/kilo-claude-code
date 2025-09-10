#!/bin/bash
# Agent usage reminder hook - triggers before task execution

# Colors for output
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}🤖 AGENT CHECK - STOP AND THINK!${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
echo -e "${BLUE}Ask yourself:${NC}"
echo -e "  1. Can this task be ${GREEN}parallelized${NC}? → Use multiple agents"
echo -e "  2. Does this need ${GREEN}specialized expertise${NC}? → Use specialist agents"
echo -e "  3. Is this ${GREEN}complex${NC} (>3 subtasks)? → Distribute to agents"
echo
echo -e "${BLUE}Available Specialist Agents:${NC}"
echo -e "  • ${GREEN}genomics-database-architect${NC} - DuckDB, genomics queries, VCF/FASTA"
echo -e "  • ${GREEN}publication-dataviz-expert${NC} - Visualizations, plots, figures"
echo -e "  • ${GREEN}scientific-evidence-validator${NC} - Validate approaches, check thresholds"
echo -e "  • ${GREEN}ai-ml-innovation-advisor${NC} - ML, pattern recognition, clustering"
echo -e "  • ${GREEN}benchmark-evaluator${NC} - Testing, performance, comparisons"
echo -e "  • ${GREEN}tidy-python-developer${NC} - Clean Python code, refactoring"
echo
echo -e "${YELLOW}💡 Remember: Agents work in PARALLEL and bring EXPERTISE!${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

# Always exit 0 so we don't block execution
exit 0