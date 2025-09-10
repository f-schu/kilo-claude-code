# 🤖 MANDATORY AGENT USAGE CHECKLIST

## STOP! Before proceeding with ANY task, ask yourself:

### 1. Can this be parallelized? → USE MULTIPLE AGENTS
- [ ] Multiple files to analyze? → Spawn agents for each
- [ ] Database + Visualization? → One agent per task
- [ ] Research + Implementation? → Parallel agents

### 2. Does this match an agent specialty? → USE SPECIALIST AGENTS

**ALWAYS CHECK THIS LIST:**

#### genomics-database-architect
USE WHEN:
- [ ] Designing genomics database schemas
- [ ] Writing complex DuckDB queries  
- [ ] Optimizing queries for large datasets
- [ ] Working with VCF, FASTA, or genomic data formats

#### publication-dataviz-expert  
USE WHEN:
- [ ] Creating any visualization
- [ ] Making plots for papers
- [ ] Working with matplotlib/seaborn/plotly
- [ ] Designing figure panels

#### scientific-evidence-validator
USE WHEN:
- [ ] Choosing thresholds or parameters
- [ ] Validating scientific approaches
- [ ] Checking if a method is appropriate
- [ ] Reviewing claims about data

#### ai-ml-innovation-advisor
USE WHEN:
- [ ] Pattern recognition tasks
- [ ] Clustering or classification
- [ ] Anomaly detection
- [ ] Any task that could benefit from ML

#### benchmark-evaluator
USE WHEN:
- [ ] Comparing implementations
- [ ] Creating test datasets
- [ ] Measuring performance
- [ ] Tracking improvements

#### tidy-python-developer
USE WHEN:
- [ ] Writing new Python modules
- [ ] Refactoring code
- [ ] Organizing project structure
- [ ] Creating clean, maintainable code

### 3. Task Complexity Check

If the task has **ANY** of these characteristics, USE AGENTS:
- [ ] More than 3 subtasks
- [ ] Requires different expertise areas
- [ ] Could be done in parallel
- [ ] Involves large data processing
- [ ] Needs visualization
- [ ] Requires scientific validation

## 🚨 AGENT USAGE PATTERNS

### Pattern 1: Parallel Analysis
```
"I'll use multiple agents to analyze this in parallel:
- genomics-database-architect: Design the query strategy
- publication-dataviz-expert: Create visualizations
- scientific-evidence-validator: Validate the approach"
```

### Pattern 2: Sequential Handoff
```
"First, I'll use the scientific-evidence-validator to check our approach,
then hand off to genomics-database-architect for implementation"
```

### Pattern 3: Specialized Deep Dive
```
"This requires specialized genomics knowledge, so I'll use the
genomics-database-architect agent to handle the entire task"
```

## 📝 TRIGGER PHRASES TO USE

Start your response with one of these when applicable:

1. "I'll spawn multiple agents to tackle this in parallel..."
2. "This task matches the [agent-name] specialty, so I'll delegate..."
3. "Let me distribute this work across specialized agents..."
4. "I'll use the [agent-name] to ensure we follow best practices..."

## 🔄 AGENT REMINDER HOOKS

Add these checks at each stage:

### Before Starting Any Task:
"Should I use agents for this? Let me check:
- Parallelizable? ✓/✗
- Matches specialty? ✓/✗
- Complex enough? ✓/✗"

### After Reading Requirements:
"Based on the requirements, I should use:
- [agent1] for [subtask1]
- [agent2] for [subtask2]"

### Before Implementation:
"Have I written Agent Allocation and Subagent Contracts for each selected agent?"

## ✅ Minimum Subagent Contract (use this template)

- id: short-name
- role: specialist capability
- inputs: explicit files/data/context
- outputs: concrete artifacts/paths
- success: measurable criteria to accept the subagent result
- return_format: e.g., JSON summary + file paths
- budget: time/iterations constraints

You MUST produce Agent Allocation + Subagent Contracts before implementing when the task is parallelizable or cross-domain.

## 💡 EXAMPLES FROM YOUR LAST TASK

What you did:
```
"Let me analyze the conserved OGs..."
[Proceeds to do everything sequentially]
```

What you SHOULD have done:
```
"I'll spawn multiple agents to tackle this analysis:
1. genomics-database-architect: Analyze the OG database structure and write optimal queries
2. publication-dataviz-expert: Create publication-quality visualizations
3. scientific-evidence-validator: Validate the 50% threshold approach
4. benchmark-evaluator: Create test cases for the pipeline"
```

## 🎯 RESULT: Better, Faster, More Thorough Solutions!

Remember: Agents work in parallel and bring specialized expertise. USE THEM!
