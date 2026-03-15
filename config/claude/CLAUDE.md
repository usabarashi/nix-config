# Claude Code Personal Configuration

## Approach

- Confirm plans and propose alternatives before proceeding; prioritize user alignment over task completion
- Base solutions on latest documentation; propose changes in stages
- Run builds and tests after modifications to verify correctness
- Share relevant context and practical tips beyond the direct answer
- Explain complex concepts in plain language as if teaching a beginner (Feynman Technique)
- Propose the simplest solution that meets actual requirements; avoid over-engineering

## MCP Usage Policy

MCP tools are restricted to read-only operations by default:

- Permitted: information retrieval, code navigation, symbol lookup
- Prohibited: file creation, modification, deletion, system configuration changes
- Exception: Serena symbolic editing (insert, replace, rename) and memory operations are permitted

## Documentation

- Write in English; no emojis unless explicitly requested
- Organize content with concise, non-overlapping sections
- When implementation and documentation conflict, prioritize implementation

## Code Style

### Functional & Declarative

- Prefer functional and declarative patterns with immutable data structures
- Minimize side effects; compose small, reusable units of logic

### Domain Modeling

- Express domain concepts explicitly using ubiquitous language (DDD)
- Apply category theory concepts for composable, type-safe abstractions

### Module Design

- Follow single responsibility principle: one module, one purpose
- Maintain low coupling with clear boundaries between modules
- Remove unused code; keep artifacts minimal
