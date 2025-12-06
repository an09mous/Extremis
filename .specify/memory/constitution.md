<!--
SYNC IMPACT REPORT
==================
Version change: 0.0.0 → 1.0.0 (Initial constitution)
Modified principles: N/A (New)
Added sections:
  - I. Modularity First
  - II. Code Quality Excellence
  - III. User Experience Primacy
  - Quality Gates
  - Development Workflow
Removed sections: None
Templates requiring updates:
  - .specify/templates/plan-template.md ✅ (compatible)
  - .specify/templates/spec-template.md ✅ (compatible)
  - .specify/templates/tasks-template.md ✅ (compatible)
Follow-up TODOs: None
-->

# Extremis Constitution

## Core Principles

### I. Modularity First

Every component MUST be designed for independence and composability:

- **Single Responsibility**: Each module, class, or function MUST have one clear purpose
- **Loose Coupling**: Components MUST communicate through well-defined interfaces, not implementation details
- **High Cohesion**: Related functionality MUST be grouped together; unrelated code MUST be separated
- **Dependency Injection**: Dependencies MUST be injected, not hardcoded, enabling easy testing and swapping
- **Plugin Architecture**: Features SHOULD be implemented as pluggable modules where applicable
- **No Circular Dependencies**: Module dependencies MUST form a directed acyclic graph (DAG)

**Rationale**: Modular code enables parallel development, easier maintenance, independent testing, and confident refactoring without cascading failures.

### II. Code Quality Excellence

All code MUST meet the highest quality standards:

- **Clean Code**: Code MUST be self-documenting with meaningful names; comments explain "why", not "what"
- **DRY Principle**: Duplication MUST be eliminated through proper abstraction
- **SOLID Principles**: Object-oriented code MUST follow SOLID principles
- **Error Handling**: All error paths MUST be explicitly handled; no silent failures
- **Type Safety**: Strong typing MUST be used where the language supports it
- **Testing**: Critical paths MUST have unit tests; integration tests for component boundaries
- **Code Reviews**: All changes MUST be reviewed before merge
- **Linting & Formatting**: Automated tools MUST enforce consistent style

**Rationale**: Top-notch code quality reduces bugs, improves maintainability, and enables developers to work confidently across the codebase.

### III. User Experience Primacy

Every user-facing decision MUST prioritize exceptional experience:

- **Smooth Flows**: User journeys MUST be intuitive with minimal friction and cognitive load
- **Visual Polish**: UI MUST be aesthetically pleasing with consistent design language
- **Responsive Design**: Interfaces MUST work seamlessly across all target devices/platforms
- **Performance**: Interactions MUST feel instant (<100ms feedback, <1s operations)
- **Accessibility**: Design MUST be inclusive and meet accessibility standards
- **Error Recovery**: Users MUST always have a clear path forward; helpful error messages required
- **Progressive Disclosure**: Complexity MUST be revealed gradually based on user needs

**Rationale**: Superior UX creates loyal users, reduces support burden, and differentiates the product in the market.

## Quality Gates

Before any code is merged, it MUST pass:

1. **Modularity Check**: No new circular dependencies; coupling metrics within thresholds
2. **Code Quality Check**: Linting passes; test coverage maintained; no critical static analysis issues
3. **UX Review**: User-facing changes reviewed for flow smoothness and visual consistency
4. **Performance Check**: No degradation in key performance metrics

## Development Workflow

1. **Design First**: For significant changes, design the modular structure before coding
2. **Incremental Development**: Build features in small, testable increments
3. **Continuous Integration**: All changes trigger automated quality checks
4. **Documentation**: Public APIs and complex logic MUST be documented

## Governance

This constitution supersedes all other development practices. Any conflicts between convenience and these principles MUST be resolved in favor of the principles.

**Amendment Process**:
- Amendments require documented justification
- Breaking changes to principles require migration plan
- All team members MUST be notified of amendments

**Compliance**:
- All PRs MUST verify compliance with these principles
- Technical debt that violates principles MUST be tracked and prioritized
- Exceptions require explicit documentation and approval

**Version**: 1.0.0 | **Ratified**: 2025-12-06 | **Last Amended**: 2025-12-06
