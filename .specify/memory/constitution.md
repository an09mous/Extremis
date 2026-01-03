<!--
SYNC IMPACT REPORT
==================
Version Change: 0.0.0 → 1.0.0 (MAJOR - initial constitution ratification)

Added Principles:
- I. Modularity & Separation of Concerns
- II. Code Quality & Best Practices
- III. Extensibility & Testability
- IV. User Experience Excellence
- V. Documentation Synchronization
- VI. Testing Discipline
- VII. Regression Prevention

Added Sections:
- Quality Standards (Section 2)
- Development Workflow (Section 3)
- Governance

Templates Status:
✅ .specify/templates/plan-template.md - Constitution Check section compatible
✅ .specify/templates/spec-template.md - Requirements section compatible
✅ .specify/templates/tasks-template.md - Phase structure compatible

Follow-up TODOs: None
==================
-->

# Extremis Constitution

## Core Principles

### I. Modularity & Separation of Concerns

Code MUST be highly modular to ensure addition or modification of functionality is straightforward.

- Components MUST exhibit loose coupling: minimal dependencies between modules
- Components MUST exhibit high cohesion: each module has a single, well-defined responsibility
- New features MUST be addable without modifying unrelated code paths
- Shared functionality MUST be extracted into reusable utilities or services
- Circular dependencies between modules are PROHIBITED

**Rationale**: Modular architecture reduces cognitive load, enables parallel development, and isolates change impact.

### II. Code Quality & Best Practices

All code MUST follow the best practices of Swift and established design principles.

- Code MUST adhere to Swift API Design Guidelines and SwiftLint rules
- SOLID principles MUST guide class and protocol design
- Functions MUST be short, focused, and do one thing well
- Naming MUST be descriptive and self-documenting
- Magic numbers and hardcoded strings MUST be replaced with named constants
- Code duplication MUST be eliminated through appropriate abstractions
- All public APIs MUST have clear documentation comments

**Rationale**: High code quality reduces bugs, improves maintainability, and accelerates onboarding.

### III. Extensibility & Testability

Architecture MUST prioritize extensibility, testability, and performance optimization.

- New providers, extractors, and UI components MUST be addable via protocol conformance
- Dependencies MUST be injectable to enable unit testing with mocks
- Business logic MUST be separated from UI and I/O concerns
- Performance-critical paths MUST be profiled and optimized
- Async operations MUST use Swift Concurrency (async/await, actors) correctly
- Memory management MUST avoid retain cycles and unnecessary allocations

**Rationale**: Extensible, testable code enables confident refactoring and feature iteration.

### IV. User Experience Excellence

The application MUST deliver the smoothest, most intuitive user experience possible.

- UI interactions MUST feel instant (<100ms perceived latency)
- Visual feedback MUST accompany all user actions
- Error states MUST be communicated clearly with actionable guidance
- Keyboard shortcuts MUST be discoverable and consistent
- Accessibility MUST be supported (VoiceOver, keyboard navigation)
- UI MUST be visually polished with attention to alignment, spacing, and typography
- Animation and transitions MUST be smooth (60fps) and purposeful

**Rationale**: Exceptional UX differentiates the product and drives user adoption.

### V. Documentation Synchronization

README and documentation MUST always reflect current functionality.

- README.md MUST be updated when features are added, changed, or removed
- Feature documentation MUST include usage examples
- Architecture documentation MUST stay current with structural changes
- API keys, setup steps, and requirements MUST be accurate
- Outdated documentation is treated as a bug with HIGH priority

**Rationale**: Accurate documentation reduces support burden and improves developer experience.

### VI. Testing Discipline

Tests MUST cover complex code paths and edge cases to raise the quality bar.

- Complex business logic MUST have unit tests
- Edge cases identified in specs MUST have corresponding test coverage
- Integration points (LLM providers, system APIs) MUST have contract tests
- Test names MUST clearly describe the scenario being tested
- Tests MUST be deterministic and not rely on external state
- Flaky tests MUST be fixed or removed immediately

**Rationale**: Strategic testing catches regressions early and documents expected behavior.

### VII. Regression Prevention

Code changes MUST be made with extra care to prevent regressions to existing functionality.

- Before modifying code, the existing behavior MUST be understood thoroughly
- Changes MUST be minimal and focused on the stated objective
- Unrelated "improvements" during bug fixes are PROHIBITED
- All user-facing flows MUST be manually verified after changes
- Breaking changes MUST be explicitly documented and communicated
- When in doubt, add a test before making the change

**Rationale**: Preventing regressions maintains user trust and product stability.

## Quality Standards

All contributions MUST meet these minimum quality gates:

- **Build**: Code MUST compile without warnings
- **Lint**: Code MUST pass SwiftLint with zero violations
- **Tests**: All existing tests MUST pass
- **Manual QA**: Core user flows (hotkey invocation, text generation, insertion) MUST work
- **Memory**: No memory leaks in Instruments for standard usage patterns
- **Performance**: UI MUST remain responsive during LLM streaming

Complexity MUST be justified. If a simpler solution exists, it MUST be preferred unless specific requirements demand otherwise.

## Development Workflow

### Code Review Requirements

- All changes MUST be reviewed before merging
- Reviewers MUST verify principle compliance (modularity, quality, UX)
- Reviewers MUST run the application and test affected flows
- Feedback MUST be addressed or explicitly discussed before approval

### Change Process

1. Understand the existing code thoroughly before modification
2. Make the minimal change required to achieve the goal
3. Verify no regressions in related functionality
4. Update documentation if behavior changes
5. Add tests for complex or edge-case logic

### Quality Gates

Before any merge:
- [ ] Build succeeds without warnings
- [ ] All tests pass
- [ ] Manual QA of affected user flows complete
- [ ] Documentation updated (if applicable)
- [ ] No regressions identified

## Governance

This constitution supersedes all other development practices for the Extremis project. All pull requests and code reviews MUST verify compliance with these principles.

### Amendment Procedure

1. Propose change with rationale in a dedicated PR
2. Document impact on existing code and templates
3. Obtain explicit approval from project maintainers
4. Update version according to semantic versioning:
   - MAJOR: Principle removal or incompatible redefinition
   - MINOR: New principle or materially expanded guidance
   - PATCH: Clarifications, wording improvements

### Compliance Review

Periodic reviews SHOULD assess:
- Codebase adherence to principles
- Documentation accuracy
- Test coverage of complex paths
- Regression incident analysis

**Version**: 1.0.0 | **Ratified**: 2026-01-03 | **Last Amended**: 2026-01-03
