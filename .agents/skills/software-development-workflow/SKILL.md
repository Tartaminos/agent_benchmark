---
name: software-development-workflow
description: Orchestrate meaningful production software changes through architect, UI/UX, coder, test-engineer, reviewer, and QA agents with explicit gates, handoffs, and correction routing.
---

# Software Development Workflow

The main Codex thread is the ORCHESTRATOR. It coordinates specialized agents; specialists
perform their owned engineering work. The goal is a scoped, coherent implementation with
independent automated testing, review, runtime validation when applicable, and controlled
correction loops.

---

# 1. ORCHESTRATOR AND SPECIALIST OWNERSHIP

Use these exact roles:

- `architect` — architecture, placement, boundaries, dependency direction.
- `ui-ux-engineer` — user experience before implementation and UI/UX review after.
- `coder` — production implementation.
- `test-engineer` — independent automated regression evidence.
- `reviewer` — independent implementation/diff and test review.
- `qa-engineer` — realistic runtime/product validation.

The orchestrator owns task/repository discovery, source-of-truth resolution, Scope Lock,
agent applicability/spawning, workflow state, handoff preservation, correction routing, gate
decisions, and final consolidation. It may inspect repository evidence and run non-mutating
discovery needed for coordination.

It must not silently replace a required specialist or perform that specialist's owned work.
If a required specialist is unavailable, its required gate is BLOCKED. Keep implementation,
automated testing, review, and runtime validation independently owned.

---

# 2. SOURCE OF TRUTH

Resolve instructions in this order:

1. Explicit user request and selected target spec/task.
2. Applicable repository `AGENTS.md`.
3. Explicit project source-of-truth documentation.
4. Approved ADRs and architecture documentation.
5. Implementation specs and applicable repository-local skills.
6. Product/domain/UI/security/testing documentation.
7. Existing healthy repository behavior and conventions.
8. Specialist recommendations.
9. Generic industry practices.

Discover applicable skills under `.agents/skills`. Project skills add repository procedure and
constraints; they do not collapse specialist ownership unless higher-priority instructions say so.

When a spec/slice is selected, read it completely plus materially required linked context.
Authoritative documentation outranks accidental implementation. Do not silently alter
requirements/source-of-truth to fit code.

If material source conflicts cannot be resolved from repository evidence, route to `architect`;
if no safe resolution exists, BLOCKED.

---

# 3. WORKING-TREE SAFETY

Before write work, inspect repository root/status and identify pre-existing changes. Keep the
task diff distinguishable where practical. Never discard, reset, revert, overwrite, or silently
absorb unrelated user work.

Do not automatically commit, push, create a branch/PR, amend, force-push, or run destructive git
commands. These require explicit user intent or another applicable workflow.

Write-heavy specialists touching the same tree run sequentially. Never run `coder` and
`test-engineer`, multiple coders, or overlapping write agents concurrently. Independent
read-only work may parallelize when safe.

---

# 4. SCOPE LOCK AND DISCOVERY

Before production specialists, define:

## Scope Lock
### Target
<exact feature/spec/slice/bug/refactor/migration/integration>
### Required Behavior
<required observable/technical behavior>
### Explicit Exclusions
<known out-of-scope behavior>
### Authoritative Sources
<files/docs/specs/skills>
### Likely Affected Surfaces
<backend/frontend/mobile/database/integrations/etc>

Scope Lock is binding. Unrelated findings are reported separately unless necessary for safe task
completion; do not silently expand implementation.

Discovery also resolves applicable instructions/skills, source docs, affected repository areas,
git state, task modifiers, and required agents. It prepares context; it does not replace
specialist analysis.

---

# 5. PIPELINE AND AGENT APPLICABILITY

Canonical pipeline:

ARCHITECT when required
→ UI/UX DESIGN when user-facing
→ CODER
→ TEST ENGINEER when test-relevant behavior changed
→ UI/UX IMPLEMENTATION REVIEW when UI/UX design ran
→ REVIEWER
→ QA when runtime/product validation adds evidence

Applicability:

- `coder`: mandatory for production implementation.
- `reviewer`: mandatory for meaningful production changes.
- `architect`: mandatory for features/specs, meaningful bugs/refactors, migrations,
  integrations, structural/unfamiliar work, or material architecture/security/data impact.
  Skip only genuinely mechanical work with no architectural consequence.
- `test-engineer`: mandatory when behavior, logic, contracts, persistence, integrations,
  security, UI behavior, or regression risk changes.
- `ui-ux-engineer`: mandatory for meaningful user-visible flow, interaction, responsive/
  accessibility behavior, navigation, copy, UI states, or feedback changes.
- `qa-engineer`: default for meaningful observable runtime/product behavior. Skip only when it
  cannot add evidence (for example docs/comments/formatting, purely test-internal, or genuinely
  mechanical internal changes).

When uncertain about QA, prefer targeted QA over skipping. Do not invoke specialists merely
because they exist; use the smallest pipeline that preserves independent confidence.

---

# 6. WORKFLOW STATE MACHINE

Track exactly one state:

DISCOVERY
ARCHITECTURE
UX_DESIGN
IMPLEMENTATION
AUTOMATED_TESTING
UX_IMPLEMENTATION_REVIEW
CODE_REVIEW
QA
CORRECTION
COMPLETE
BLOCKED

Preserve current state, last passed gate, active specialist, unresolved findings, correction
count, and next required gate.

Normal progression follows the applicable pipeline. A failed gate enters CORRECTION and routes
to the earliest owned decision/work that must change. Resume from the earliest invalidated gate;
never restart unaffected earlier gates. A blocked required gate prevents completion.

After the user invokes this workflow, progress automatically through all applicable gates and
correction loops. Do not ask permission between routine stages. `IMPLEMENTATION_COMPLETE` is
not workflow completion. Stop only at COMPLETE or BLOCKED.

---

# 7. SPECIALIST HANDOFF CONTRACTS

Pass each specialist only relevant distilled task/Scope Lock, authoritative constraints,
required upstream handoffs, current repository/diff state, and unresolved findings.

## Architect
Require **Architecture Handoff**:
- Repository Architecture Relevant to Task
- Existing Analogous Patterns
- Proposed Placement
- Affected Components
- Dependency Direction
- Data / Persistence Impact
- API / Integration Impact
- Security / Privacy Impact
- Architectural Constraints
- Risks
- Architecture Verdict: `READY_FOR_IMPLEMENTATION` | `ARCHITECTURE_BLOCKED`

## UI/UX Design
Run when applicable. Require **UI/UX Handoff**:
- Existing Experience
- User Goal
- Existing Patterns
- Proposed User Flow
- UI Structure
- Required States
- Responsive Behavior
- Accessibility Requirements
- Product Copy / Feedback
- Implementation Constraints
- Acceptance Criteria
- UX Verdict: `READY_FOR_IMPLEMENTATION` | `UX_BLOCKED`

## Coder
Require **Implementation Handoff**:
- Implemented Behavior
- Technology Context
- Files / Components Changed
- Architectural Alignment
- UI/UX Alignment
- Important Rules / Invariants
- Side Effects
- Error Paths
- Validation Executed
- Known Risks / Limitations
- Test Engineer Risk Areas
- Implementation Verdict: `IMPLEMENTATION_COMPLETE` | `IMPLEMENTATION_BLOCKED`

## Test Engineer
Run after implementation, never concurrently with Coder. Require **Test Handoff**:
- Test Strategy
- Test Ecosystem
- Tests Added / Changed
- Behaviors Proven
- Boundaries / Failure Paths
- Test Levels Explicitly Skipped
- Redundancy Avoided
- False-Positive Protection
- Validation Executed
- Implementation Defects Found
- Remaining Test Risks
- Test Verdict: `TESTS_PASS` | `TESTS_FOUND_IMPLEMENTATION_DEFECT` | `TESTS_BLOCKED`

Never accept weakening a test as resolution of a production defect.

## UI/UX Implementation Review
When UI/UX design ran, invoke `ui-ux-engineer` again after implementation/testing using the
approved handoff plus actual implementation/diff and rendered evidence when available. Require:
`UX_APPROVED` | `UX_CHANGES_REQUIRED` | `UX_REVIEW_BLOCKED`.

Never claim visual inspection when required UI could not actually be rendered/inspected.

## Reviewer
Require **Review Handoff**:
- Review Verdict: `APPROVED` | `APPROVED_WITH_NON_BLOCKING_COMMENTS` |
  `CHANGES_REQUIRED` | `BLOCKED`
- Change Summary
- Findings
- Test Assessment
- Architecture Assessment
- Security / Data Integrity Assessment
- Remaining Risks

Reviewer remains read-only.

## QA
Run after acceptable Reviewer verdict when applicable. Require **QA Handoff**:
- QA Verdict: `PASS` | `PASS_WITH_KNOWN_RISKS` | `FAIL` | `BLOCKED`
- Feature / Scope Validated
- Environment
- Scenarios Executed
- Critical Path
- Failure / Edge / Security Scenarios
- Responsive / Accessibility
- Regression Scope
- Defects Found
- Test Gaps
- Remaining Risks

QA must name the actual environment. For individual scenarios, `NOT EXECUTED` is not `PASS`.
If missing environment prevents meaningful required final validation, verdict is `BLOCKED`.

---

# 8. GATE SEMANTICS

Architecture:
- `READY_FOR_IMPLEMENTATION` → continue.
- `ARCHITECTURE_BLOCKED` → resolve or BLOCKED.

UI/UX design:
- `READY_FOR_IMPLEMENTATION` → continue.
- `UX_BLOCKED` → resolve required UX/product ambiguity or BLOCKED.

Implementation:
- `IMPLEMENTATION_COMPLETE` → continue.
- `IMPLEMENTATION_BLOCKED` → resolve or BLOCKED.

Testing:
- `TESTS_PASS` → continue.
- `TESTS_FOUND_IMPLEMENTATION_DEFECT` → route IMPLEMENTATION DEFECT.
- `TESTS_BLOCKED` → resolve test/environment/context blocker or BLOCKED.

UI/UX review:
- `UX_APPROVED` → continue.
- `UX_CHANGES_REQUIRED` → route UX/UI ISSUE.
- `UX_REVIEW_BLOCKED` → restore evidence/environment or BLOCKED.

Reviewer:
- `APPROVED` → continue.
- `APPROVED_WITH_NON_BLOCKING_COMMENTS` → continue only with no unresolved BLOCKER/HIGH.
- `CHANGES_REQUIRED` → route findings by owner.
- `BLOCKED` → resolve missing decision/evidence/context or BLOCKED.

Reviewer severity:
- BLOCKER/HIGH: must resolve.
- MEDIUM: normally resolve unless explicitly justified non-blocking while requirements hold.
- LOW/OPTIONAL IMPROVEMENT: may remain non-blocking.

QA:
- `PASS` → eligible for completion.
- `PASS_WITH_KNOWN_RISKS` → eligible only for explicit non-blocking risk compatible with Scope
  Lock/source-of-truth/acceptance criteria.
- `FAIL` → route defects.
- `BLOCKED` → cannot complete.

No gate passes because another agent believes it is probably fine.

---

# 9. DEFECT OWNERSHIP AND CORRECTION ROUTING

Route from the earliest ownership that must change.

**IMPLEMENTATION DEFECT — CODER**
CODER → TEST ENGINEER when behavior/regression protection is affected → UI/UX REVIEW when
user-facing behavior is affected → REVIEWER → QA when applicable.

**TEST GAP — TEST ENGINEER**
TEST ENGINEER → REVIEWER → QA only when runtime behavior needs revalidation.

**ARCHITECTURAL ISSUE/DEFECT — ARCHITECT**
ARCHITECT → CODER → TEST ENGINEER → UI/UX REVIEW when relevant → REVIEWER → QA.

**UX/UI ISSUE or DEFECT**
UI/UX ENGINEER owns design/product decisions; CODER owns implementation divergence from an
approved design. Route as needed:
UI/UX ENGINEER → CODER → TEST ENGINEER when applicable → UI/UX REVIEW → REVIEWER → QA.

**ACCESSIBILITY DEFECT**
UI/UX ENGINEER and/or CODER depending on cause → TEST ENGINEER when durable automation is
appropriate → REVIEWER → QA.

**ENVIRONMENT DEFECT**
Route to the appropriate environment/infrastructure owner. Never patch production merely to
make an invalid test/QA environment pass.

After correction rerun only invalidated and required downstream gates. Preserve approved upstream
decisions unless the fix invalidates them.

If QA finds a meaningful automatable defect, add regression protection through Test Engineer
after the production fix. Do not force every exploratory scenario into automation.

---

# 10. TASK MODIFIERS

Task type changes emphasis, not ownership.

**BUG FIX**
Reproduce when practical; fix root cause; require regression evidence; Reviewer checks nearby
risk; QA retests the original failure when applicable.

**REFACTOR**
Preserve externally observable behavior unless explicitly changed; emphasize compatibility,
focused diff, and regression protection. QA may be targeted.

**DATABASE / MIGRATION**
Account for existing data, nullability/defaults, constraints/indexes, sequencing,
compatibility, rollout, and rollback. Never assume an empty database.

**INFRASTRUCTURE / INTEGRATION**
Emphasize contracts, failure behavior, runtime/deployment implications, and smoke validation.

**SECURITY-SENSITIVE**
For authentication, authorization, sessions, secrets, payments, private files, PII/privacy,
tenant isolation, or destructive actions, require explicit scrutiny of relevant security
boundaries across applicable gates. Never weaken security to complete the workflow.

**USER-FACING**
UI/UX design and UI/UX implementation review are required for meaningful user-facing behavior.
QA validates the real flow when possible, including relevant states, failure/recovery,
responsive/accessibility behavior, navigation, and duplicate actions.

**SPEC IMPLEMENTATION**
Selected spec/slice is Scope Lock. Read it fully, identify already-complete behavior, implement
only missing/incorrect required portions, preserve exclusions, and follow required documentation
procedure without broadening scope.

---

# 11. HANDOFF AND CONTEXT HYGIENE

Preserve decisions/findings across gates; do not force downstream agents to rediscover them.

Pass the smallest relevant set of task/Scope Lock, source constraints, required handoffs, current
diff/tree state, unresolved findings/accepted risks, and runtime instructions when needed.
Prefer distilled handoffs over raw logs. Do not lose findings or flood agents with irrelevant
history.

---

# 12. VALIDATION INTEGRITY

Use repository-defined validation commands, generally narrow relevant checks before broader
module/integration/repository gates.

Never claim a validation, runtime scenario, visual review, or test passed unless it ran.

For unrelated baseline failures, verify they are pre-existing when practical, separate them from
current-task failures, do not silently fix them, and report how they limit confidence.

Never obtain green status by disabling/skipping tests without disclosure, weakening assertions/
security/validation, swallowing failures, deleting failing scenarios, changing acceptance
criteria/specs to fit code, or labeling known defects as success.

---

# 13. LOOP CONTROL, COMPLETION, AND BLOCKING

Track correction attempts per unresolved issue/gate. After 3 unsuccessful cycles for the same
issue, return BLOCKED with the issue, specialists involved, attempted corrections, current
evidence, and why further autonomous iteration is unlikely to help.

COMPLETE requires every applicable condition:

- Scope Lock satisfied.
- required Architecture/UI/UX design gates passed.
- `IMPLEMENTATION_COMPLETE`.
- `TESTS_PASS` when Test Engineer is required.
- `UX_APPROVED` when UI/UX implementation review is required.
- Reviewer `APPROVED` or acceptable `APPROVED_WITH_NON_BLOCKING_COMMENTS`.
- QA `PASS` or acceptable `PASS_WITH_KNOWN_RISKS` when QA is required.
- no unresolved BLOCKER/HIGH.
- material MEDIUM findings resolved or explicitly justified non-blocking.
- required repository validation executed or limitations disclosed.
- scope remains reasonable and unrelated user work is intact.

Use BLOCKED rather than false success when any essential required gate cannot safely complete,
including unavailable specialist/environment/dependency, unresolved source/architecture conflict,
destructive ambiguity, or exhausted correction loop.

---

# 14. FINAL WORKFLOW HANDOFF

Return a concise consolidated result, not every specialist's full output.

## Workflow Verdict
`COMPLETE` | `COMPLETE_WITH_KNOWN_RISKS` | `BLOCKED`

Use `COMPLETE_WITH_KNOWN_RISKS` only for explicit accepted non-blocking residual risks compatible
with Scope Lock, source-of-truth, required gates, and acceptance criteria.

## Implemented
<what changed>

## Agents Executed
- Architect: <RUN / SKIPPED — reason>
- UI/UX: <RUN / SKIPPED — reason>
- Coder: <RUN / SKIPPED — reason>
- Test Engineer: <RUN / SKIPPED — reason>
- UI/UX Implementation Review: <RUN / SKIPPED — reason>
- Reviewer: <RUN / SKIPPED — reason>
- QA: <RUN / SKIPPED — reason>

## Validation
<important results/limitations>

## Review
<verdict/findings>

## QA
<verdict/environment or SKIPPED — reason>

## Remaining Risks
<real residual risks only>

## Files / Scope
<changed areas and scope status>

Do not stop after implementation or the first defect. Route, correct, and revalidate until
COMPLETE or BLOCKED.
