# Tasks: Human-in-Loop Tool Approval

**Feature**: 011-tool-approval
**Generated**: 2026-01-20
**Updated**: 2026-01-21 (Phase 1 scope reduction - rules deferred to Phase 2)
**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md) | **Data Model**: [data-model.md](./data-model.md)

## Scope Note

**Phase 1 (Current)**: Session-based approval only
- All tools require manual approval unless remembered for session
- "Remember for session" checkbox stores approvals in-memory
- No persistent rules system

**Phase 2 (Future)**: Auto-approval rules
- Allow/Deny rules with glob patterns
- Persistent rules storage in UserDefaults
- Rules management UI in Preferences

---

## Task Legend

- `[ ]` - Not started
- `[x]` - Completed
- `[D]` - Deferred to Phase 2
- Task ID format: `T{phase}.{sequence}` (e.g., T1.1, T2.3)
- Priority: P1 (must have), P2 (should have), P3 (nice to have)
- Story: US1, US2, US3, or INFRA (infrastructure/setup)

---

## Phase 1: Setup & Infrastructure

> Prepare the codebase for the new feature. No functional changes yet.

- [x] **T1.1** [P1] [INFRA] Create feature branch `011-tool-approval` from main
- [x] **T1.2** [P1] [INFRA] Add new source files to project structure
- [x] **T1.3** [P1] [INFRA] Update test script to include new test file

---

## Phase 2: Foundational Models & Storage

### 2.1 Core Enumerations (Simplified for Phase 1)

- [D] **T2.1** ApprovalRuleType enum - **DEFERRED TO PHASE 2**
- [D] **T2.2** ApprovalRuleScope enum - **DEFERRED TO PHASE 2**
- [x] **T2.3** ApprovalState enum (simplified - no rule-based states)
- [x] **T2.4** ApprovalAction enum (simplified - no auto-approve/deny)

### 2.2 Core Entities

- [D] **T2.5** ApprovalRule struct - **DEFERRED TO PHASE 2**
- [x] **T2.6** ToolApprovalRequest struct
- [x] **T2.7** ApprovalDecision struct
- [x] **T2.8** SessionApprovalMemory class

### 2.3 Preferences Integration

- [D] **T2.9** Extend Preferences with approval rules - **DEFERRED TO PHASE 2**
- [D] **T2.10** Add UserDefaults accessors for rules - **DEFERRED TO PHASE 2**

### 2.4 Extended ToolCallState

- [x] **T2.11** Extend ToolCallState enum with approval states

### 2.5 Unit Tests

- [D] **T2.12** ApprovalRule pattern matching tests - **DEFERRED TO PHASE 2**

---

## Phase 3: Core Approval Flow (P1)

### 3.1 ToolApprovalManager Service

- [x] **T3.1** Implement ToolApprovalManager skeleton (without rules)
- [D] **T3.2** Rule loading and indexing - **DEFERRED TO PHASE 2**
- [x] **T3.3** Implement requestApproval (session memory only)
- [D] **T3.4** wouldAutoApprove method - **DEFERRED TO PHASE 2**
- [x] **T3.5** recordDecision method
- [x] **T3.6** clearDecisionLog method

### 3.2-3.6 Integration & UI

- [x] **T3.7-T3.19** All other Phase 3 tasks completed

---

## Phase 4: Auto-Approval Rules - **ENTIRE PHASE DEFERRED TO PHASE 2**

All tasks T4.1 - T4.10 deferred.

---

## Phase 5: Session Memory (P3)

- [x] **T5.1-T5.6** Session memory integration completed
- [ ] **T5.7** Clear session approvals action - **DEFERRED (not critical)**
- [x] **T5.8** Session memory unit tests

---

## Phase 6: Polish & QA

- [x] **T6.1-T6.2** Accessibility
- [ ] **T6.3-T6.4** Error handling (in progress)
- [D] **T6.5** Rule matching optimization - **DEFERRED TO PHASE 2**
- [ ] **T6.6-T6.8** Performance and QA
- [x] **T6.9-T6.10** Documentation

---

## Files to Modify for Phase 1 Scope Reduction

1. `ToolApprovalModels.swift` - Remove ApprovalRuleType, ApprovalRuleScope, ApprovalRule, ToolApprovalConstants
2. `ToolApprovalManager.swift` - Remove denyRules, allowRules, rule methods
3. `Preferences.swift` - Remove approvalRules property
4. `UserDefaultsHelper.swift` - Remove approvalRules accessors
5. `ConnectorsTab.swift` - Remove rules UI (ToolApprovalSettingsSection, AddApprovalRuleSheet, etc.)
6. `ToolApprovalManagerTests.swift` - Remove rule-related tests
