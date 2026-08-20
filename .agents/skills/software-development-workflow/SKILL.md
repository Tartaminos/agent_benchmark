---
name: software-development-workflow
description: Orchestrate meaningful production software changes through architect, UI/UX, coder, test-engineer, reviewer, and QA agents with explicit gates, compact handoffs, context slicing, and correction routing.
---

# Software Development Workflow

The main Codex thread is the ORCHESTRATOR. It coordinates specialized agents; specialists perform their owned engineering work. The goal is a scoped, coherent implementation with independent automated testing, review, runtime validation when applicable, controlled correction loops, and minimal non-transitive context between agents.

---

# 1. ORCHESTRATOR AND SPECIALIST OWNERSHIP

Use these exact roles:

- `architect` — architecture, placement, boundaries, dependency direction.
- `ui-ux-engineer` — user experience before implementation and UI/UX review after.
- `coder` — production implementation.
- `test-engineer` — independent automated regression evidence.
- `reviewer` — independent implementation/diff and test review.
- `qa-engineer` — realistic runtime/product validation.

The orchestrator owns task/repository discovery, source-of-truth resolution, Scope Lock, agent applicability/spawning, workflow state, context ledger, context slicing, handoff preservation, correction routing, gate decisions, and final consolidation. It may inspect repository evidence and run non-mutating discovery needed for coordination.

It must not silently replace a required specialist or perform that specialist's owned work. If a required specialist is unavailable, its required gate is BLOCKED.

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

Discover applicable skills under `.agents/skills`. Project skills add repository procedure and constraints; they do not collapse specialist ownership unless higher-priority instructions say so.

When a spec/slice is selected, read it completely plus materially required linked context. Authoritative documentation outranks accidental implementation. Do not silently alter requirements or source-of-truth to fit code.

If material source conflicts cannot be resolved from repository evidence, route to `architect`; if no safe resolution exists, BLOCKED.

---

# 3. WORKING-TREE SAFETY

Before write work, inspect repository root/status and identify pre-existing changes. Keep the task diff distinguishable where practical. Never discard, reset, revert, overwrite, or silently absorb unrelated user work.

Do not automatically commit, push, create a branch/PR, amend, force-push, or run destructive git commands. These require explicit user intent or another applicable workflow.

Write-heavy specialists touching the same tree run sequentially. Never run `coder` and `test-engineer`, multiple coders, or overlapping write agents concurrently. Independent read-only work may parallelize when safe.

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

Scope Lock is binding. Unrelated findings are reported separately unless necessary for safe task completion; do not silently expand implementation.

Discovery also resolves applicable instructions/skills, source docs, affected repository areas, git state, task modifiers, and required agents. It prepares context; it does not replace specialist analysis.

Discovery is progressive and question-driven. Start with the nearest relevant implementation, one healthy analogous pattern when useful, and directly relevant tests/configuration. Stop once the active specialist can support its owned decisions with concrete evidence and no material unresolved ambiguity. Expand one dependency/boundary ring only to answer a specific unresolved question or material risk; do not scan additional areas merely for completeness. Do not impose a fixed file-count limit when more evidence is genuinely required.

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
- `architect`: mandatory for features/specs, meaningful bugs/refactors, migrations, integrations, structural/unfamiliar work, or material architecture/security/data impact. Skip only genuinely mechanical work with no architectural consequence.
- `test-engineer`: mandatory when behavior, logic, contracts, persistence, integrations, security, UI behavior, or regression risk changes.
- `ui-ux-engineer`: mandatory for meaningful user-visible flow, interaction, responsive/accessibility behavior, navigation, copy, UI states, or feedback changes.
- `qa-engineer`: default for meaningful observable runtime/product behavior. Skip only when it cannot add evidence, such as docs/comments/formatting, purely test-internal changes, or genuinely mechanical internal changes.

When uncertain about QA, prefer targeted QA over skipping. Use the smallest pipeline that preserves independent confidence.

---

# 6. WORKFLOW STATE MACHINE AND CONTEXT LEDGER

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

Preserve current state, last passed gate, active specialist, unresolved findings, correction count, and next required gate.

Also maintain a canonical Workflow Context Ledger containing, as applicable:

- Scope Lock;
- authoritative source references;
- accepted architecture decisions;
- accepted UI/UX decisions;
- current implementation state;
- automated-test evidence;
- UI/UX implementation-review result;
- reviewer findings;
- QA evidence;
- current repository/diff/runtime state;
- unresolved findings;
- accepted residual risks.

Full specialist handoffs belong to the ledger. Specialists do not receive the ledger itself; each invocation receives a consumer-specific Context Slice derived from it.

The ledger is orchestration state, not a repository artifact. Do not create a persistent ledger file unless explicitly requested.

Normal progression follows the applicable pipeline. A failed gate enters CORRECTION and routes to the earliest owned decision/work that must change. Resume from the earliest invalidated gate; never restart unaffected earlier gates. A blocked required gate prevents completion.

After the user invokes this workflow, progress automatically through all applicable gates and correction loops. Do not ask permission between routine stages. `IMPLEMENTATION_COMPLETE` is not workflow completion. Stop only at COMPLETE or BLOCKED.

---

# 7. HANDOFF RECORDS AND CONTEXT SLICES

Each specialist owns the detailed schema of its output. The orchestrator preserves full handoffs in the Workflow Context Ledger, interprets their verdicts, and builds downstream Context Slices without silently rewriting specialist decisions.

Expected records:

- `architect` → Architecture Handoff.
- `ui-ux-engineer` design invocation → UI/UX Handoff.
- `coder` → Implementation Handoff.
- `test-engineer` → Test Handoff.
- `ui-ux-engineer` implementation-review invocation → UI/UX review verdict/findings.
- `reviewer` → Review Handoff.
- `qa-engineer` → QA Handoff.

A full handoff is a canonical workflow record, not the default prompt for the next specialist.

Handoffs are compact by default. Put the verdict first, use short field/value lines or bullets, prefer references over copied evidence, omit irrelevant optional fields or mark them once as `None`, and do not repeat Scope Lock or upstream context. Successful gates stay terse; spend detail on findings, blockers, residual risks, non-obvious decisions, and executed evidence. Never compress away information required for routing, revalidation, or safety.

Build each invocation from this generic Context Slice shape, omitting empty or irrelevant fields:

## Context Slice

### Scope
<only task behavior relevant to this specialist>

### Constraints
<only authoritative/upstream decisions this specialist must preserve>

### Source References
<paths, symbols, docs, commits, diffs, or runtime references to inspect when needed>

### Current State
<only implementation/diff/runtime state relevant to this gate>

### Open Findings
<only unresolved findings this specialist owns or must revalidate>

### Evidence / Risks
<only evidence or residual risks required for this gate>

Do not infer or fabricate a handoff/verdict that its responsible specialist did not produce.

---

# 8. GATE SEMANTICS

Interpret specialist verdicts exactly as follows.

Architecture:
- `READY_FOR_IMPLEMENTATION` → continue.
- `ARCHITECTURE_BLOCKED` → resolve or BLOCKED.

UI/UX design:
- `READY_FOR_IMPLEMENTATION` → continue.
- `UX_BLOCKED` → resolve required product/UX ambiguity or BLOCKED.

Implementation:
- `IMPLEMENTATION_COMPLETE` → continue.
- `IMPLEMENTATION_BLOCKED` → resolve or BLOCKED.

Automated testing:
- `TESTS_PASS` → continue.
- `TESTS_FOUND_IMPLEMENTATION_DEFECT` → route IMPLEMENTATION DEFECT.
- `TESTS_BLOCKED` → resolve the blocker or BLOCKED.

UI/UX implementation review:
- `UX_APPROVED` → continue.
- `UX_CHANGES_REQUIRED` → route UX/UI ISSUE.
- `UX_REVIEW_BLOCKED` → restore required evidence/environment or BLOCKED.

Reviewer:
- `APPROVED` → continue.
- `APPROVED_WITH_NON_BLOCKING_COMMENTS` → continue when no blocking finding remains.
- `CHANGES_REQUIRED` → route findings by owner.
- `BLOCKED` → resolve or BLOCKED.

QA:
- `PASS` → eligible for completion.
- `PASS_WITH_KNOWN_RISKS` → eligible only when residual risk is explicitly non-blocking and compatible with Scope Lock/source-of-truth/acceptance criteria.
- `FAIL` → route defects.
- `BLOCKED` → cannot complete.

No gate passes because another specialist believes it is probably fine.

---

# 9. DEFECT OWNERSHIP AND CORRECTION ROUTING

Route from the earliest ownership that must change.

**IMPLEMENTATION DEFECT — CODER**
CODER → TEST ENGINEER when behavior/regression protection is affected → UI/UX REVIEW when user-facing behavior is affected → REVIEWER → QA when applicable.

**TEST GAP — TEST ENGINEER**
TEST ENGINEER → REVIEWER → QA when runtime behavior needs revalidation.

**ARCHITECTURAL ISSUE/DEFECT — ARCHITECT**
ARCHITECT → CODER → TEST ENGINEER → UI/UX REVIEW when relevant → REVIEWER → QA.

**UX/UI ISSUE or DEFECT**
UI/UX ENGINEER owns product/design decisions; CODER owns implementation divergence from approved UX. Route from the responsible owner, then through affected downstream gates.

**ENVIRONMENT DEFECT**
Route to the appropriate environment/infrastructure owner. Never patch production merely to make an invalid test/QA environment pass.

For specialized finding labels such as accessibility defects, route by root cause: product/design decision → UI/UX ENGINEER; implementation divergence → CODER; missing durable automated protection → TEST ENGINEER.

After correction, rerun only invalidated and required downstream gates. Preserve approved upstream decisions unless the correction invalidates them.

For correction invocations, build a Correction Slice instead of replaying historical context:

## Correction Slice

### Finding
<specific unresolved finding>

### Evidence
<minimum reproduction/evidence>

### Affected Behavior / Constraint
<what must remain true>

### Current State
<affected files/diff/runtime state>

### Required Outcome
<what this specialist must correct or clarify>

For re-review, pass previous blocking findings, the correction delta, affected validation/test evidence, and only upstream decisions invalidated by the correction. For QA retest, pass the original defect/reproduction, expected corrected behavior, corrected delta, nearby regression target, runtime instructions, and relevant new automated evidence.

---

# 10. TASK MODIFIERS

Task modifiers change gate applicability or required confidence, not specialist ownership.

**BUG FIX**
Require root-cause correction and regression evidence. QA retests the original failure when QA applies.

**REFACTOR**
Externally observable behavior remains unchanged unless explicitly requested. Emphasize compatibility/regression evidence; QA may be targeted.

**DATABASE / MIGRATION**
Treat as architecture, persistence, compatibility, and regression-sensitive work.

**INFRASTRUCTURE / INTEGRATION**
Treat as architecture, contract, failure-mode, and runtime-sensitive work.

**SECURITY-SENSITIVE**
Require explicit scrutiny at all applicable architecture, implementation, testing, review, and QA gates. Never reduce security requirements to obtain workflow completion.

**USER-FACING**
Require UI/UX design and UI/UX implementation review for meaningful user-facing behavior. Run QA when executable observable product behavior exists.

**SPEC IMPLEMENTATION**
The selected spec/slice is Scope Lock. Implement only required missing/incorrect behavior and preserve explicit exclusions.

---

# 11. CONTEXT SLICING

Context is not transitive. Do not forward information merely because an upstream specialist received or produced it. Rebuild every invocation from the Workflow Context Ledger for the current consumer.

Prefer primary/normative context over previous-agent interpretation. For independent gates, pass the original constraint and relevant evidence rather than another agent's conclusion that the constraint was satisfied.

Prefer pointers over copied payload when the specialist can inspect the source directly. Use repository paths, symbols, ADR/spec references, commit/diff references, and runtime instructions instead of reproducing large source documents, diffs, logs, or prior handoffs inline.

Do not resend information that the specialist can cheaply discover locally unless it is an authoritative decision, required constraint, unresolved finding, or evidence needed for the gate. Do not promote raw exploration notes into downstream context unless they became a decision, constraint, finding, risk, or required evidence.

Use these primary consumer slices:

- **Architect** — architecture-relevant Scope Lock, authoritative source references, task modifiers, affected surfaces, relevant repository state.
- **UI/UX Design** — user-facing scope/product references plus only architecture constraints that affect observable behavior, available capabilities, permissions, integrations/runtime states, or UX risk.
- **Coder** — implementation scope plus architecture placement/boundaries/constraints and applicable data/API/security impact; UI/UX flow, required states, responsive/accessibility requirements, copy/feedback, implementation constraints, and acceptance criteria.
- **Test Engineer** — required behavior, test-relevant architecture invariants, applicable UI/UX acceptance criteria/states, implementation behavior, changed surfaces, rules/invariants, side effects, error paths, known risks, test risk areas, and relevant validation evidence.
- **UI/UX Implementation Review** — full approved UI/UX Handoff when useful as the normative comparison record, plus user-facing implementation delta, changed UI references, render/runtime instructions, and unresolved UX/UI findings. Do not add unrelated handoffs by default.
- **Reviewer** — scope/exclusions, normative architecture constraints, applicable UI/UX acceptance criteria/implementation constraints and review verdict, implementation orientation/known risks, relevant Test Handoff evidence, and current diff/repository references. Prefer the actual diff over the Coder's interpretation of alignment.
- **QA** — observable required behavior/acceptance criteria, relevant product flow/states/permissions, concise implementation delta, runtime/environment/test-data instructions, and only remaining test/review/implementation risks that affect runtime validation.

Do not forward historical findings wholesale. Pass only:
1. unresolved findings owned by the current specialist;
2. resolved findings this gate must specifically revalidate;
3. residual risks that materially affect this specialist's work.

Use three slice modes:

**INITIAL SLICE** — scope, constraints, source references, relevant upstream decisions, current state, and open relevant risks.

**REVIEW SLICE** — scope, normative expectations, current implementation state, relevant independent evidence, and remaining findings/risks.

**CORRECTION SLICE** — specific finding, evidence, affected behavior/constraint, correction state, and required outcome.

Preserve full handoffs in the ledger even when only a slice is forwarded. Context reduction must not discard canonical decisions or evidence needed by later gates.

---

# 12. VALIDATION INTEGRITY

A gate passes only from evidence actually produced by its responsible specialist.

Never convert NOT EXECUTED, unavailable evidence, a confirmed unrelated baseline failure, or deliberately weakened verification into success.

Separate confirmed pre-existing failures from current-task failures and preserve their effect on confidence.

Never alter Scope Lock, source-of-truth, acceptance criteria, security expectations, or valid verification merely to obtain a green workflow.

---

# 13. LOOP CONTROL, COMPLETION, AND BLOCKING

Track correction attempts per unresolved issue/gate. After 3 unsuccessful cycles for the same issue, return BLOCKED with the issue, specialists involved, attempted corrections, current evidence, and why further autonomous iteration is unlikely to help.

COMPLETE requires every applicable condition:

- Scope Lock satisfied.
- required Architecture/UI/UX design gates passed.
- `IMPLEMENTATION_COMPLETE`.
- `TESTS_PASS` when Test Engineer is required.
- `UX_APPROVED` when UI/UX implementation review is required.
- Reviewer `APPROVED` or acceptable `APPROVED_WITH_NON_BLOCKING_COMMENTS`.
- QA `PASS` or acceptable `PASS_WITH_KNOWN_RISKS` when QA is required.
- no unresolved BLOCKER/HIGH finding.
- material MEDIUM findings resolved or explicitly accepted as non-blocking by the responsible gate.
- required validation executed or limitations disclosed.
- scope remains reasonable and unrelated user work is intact.

Use BLOCKED rather than false success when any essential required gate cannot safely complete, including unavailable specialist/environment/dependency, unresolved source/architecture conflict, destructive ambiguity, or exhausted correction loop.

---

# 14. FINAL WORKFLOW HANDOFF

Return a concise consolidated result, not every specialist's full output.

## Workflow Verdict
`COMPLETE` | `COMPLETE_WITH_KNOWN_RISKS` | `BLOCKED`

Use `COMPLETE_WITH_KNOWN_RISKS` only for explicit accepted non-blocking residual risks compatible with Scope Lock, source-of-truth, required gates, and acceptance criteria.

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

Keep the final workflow handoff compact: summarize successful gates, expand only material limitations/findings/risks, and never replay specialist handoffs. Do not stop after implementation or the first defect. Route, correct, and revalidate until COMPLETE or BLOCKED.
