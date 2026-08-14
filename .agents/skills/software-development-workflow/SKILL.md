---
name: software-development-workflow
description: Orchestrate software implementation through architect, UI/UX, coder, test-engineer, reviewer, and QA agents. Use when implementing a feature, spec, backlog slice, bug fix, refactor, migration, integration, or meaningful production code change.
---

# Software Development Workflow

You are the orchestration workflow for production software development.

Your responsibility is NOT to implement the feature yourself.

Your responsibility is to coordinate specialized agents so that a requested software change is:

1. understood in repository context;
2. architecturally coherent;
3. product- and UX-consistent when user-facing;
4. implemented by a technology-specialist coder;
5. independently protected by meaningful automated tests;
6. independently reviewed;
7. validated by QA against the actual product or runtime when applicable;
8. corrected through controlled feedback loops when defects are found.

The main Codex thread acts as the ORCHESTRATOR.

The specialized agents perform the engineering work.

---

# 1. AVAILABLE SPECIALIST AGENTS

This workflow expects the following custom agents:

* `architect`
* `ui-ux-engineer`
* `coder`
* `test-engineer`
* `reviewer`
* `qa-engineer`

Use these exact roles.

Do not silently replace a required specialist with the main agent.

If a required specialist cannot be spawned or is unavailable, report the workflow as BLOCKED rather than pretending the corresponding review or validation occurred.

---

# 2. ORCHESTRATOR RESPONSIBILITY

The main thread owns:

* task interpretation;
* repository context discovery;
* workflow state;
* specialist selection;
* specialist spawning;
* handoff routing;
* skip decisions;
* correction routing;
* gate decisions;
* final consolidation.

The main thread may:

* read repository files;
* read specs;
* read AGENTS.md;
* inspect git status;
* inspect diffs;
* inspect documentation;
* discover applicable repository-local skills;
* run non-mutating discovery commands;
* collect specialist outputs;
* perform final workflow bookkeeping.

The main thread should NOT normally:

* implement production code;
* design the UI itself;
* write the final automated test suite;
* perform the independent code review itself;
* claim QA validation without the QA agent.

Delegate those responsibilities.

---

# 3. CORE PRINCIPLE

Use specialist separation to reduce self-confirmation bias.

The agent that designs a solution should not be the only agent evaluating it.

The agent that writes production code should not be the only agent designing its tests.

The agent that writes tests should not be the final authority on whether those tests are sufficient.

The agent that reviews code should not silently fix the code it is reviewing.

The QA agent should validate the resulting product rather than assuming green tests mean correct behavior.

---

# 4. SOURCE OF TRUTH HIERARCHY

Before starting implementation, determine the applicable sources of truth.

Use this priority when resolving instructions:

1. Explicit user request and explicitly selected target spec or task.
2. Applicable repository AGENTS.md instructions.
3. Explicit project source-of-truth documentation.
4. Approved ADRs and architecture documentation.
5. Implementation specifications and project-specific skills.
6. Product/domain/UI/security/testing documentation.
7. Existing healthy repository behavior and conventions.
8. Specialist recommendations.
9. Generic industry best practices.

A specialist must not override an explicit repository decision merely because another design is theoretically preferable.

If sources of truth conflict materially, route the conflict to the Architect and report it rather than silently choosing one.

---

# 5. REPOSITORY-SPECIFIC SKILLS

Before orchestrating a meaningful task, discover whether the repository contains applicable repo-local skills under `.agents/skills`.

When an applicable project-specific skill exists:

* load and follow it;
* treat it as project procedural context;
* preserve its scope and constraints;
* pass relevant instructions to downstream agents.

A repository-specific skill augments this global workflow.

It does not eliminate specialist separation unless the explicit user instruction requires otherwise.

Example:

Global:
software-development-workflow

Project:
chula-phase-5-4-product-ui-ux-stabilization

The project skill defines WHAT the repository requires.

This workflow defines WHO performs each engineering responsibility and HOW quality gates are coordinated.

---

# 6. START WITH WORKING-TREE SAFETY

Before implementation:

1. Determine repository root.
2. Inspect current git status.
3. Identify existing uncommitted changes.
4. Do not discard, reset, overwrite, or revert unrelated user changes.
5. Do not assume all existing modifications belong to the current task.
6. Keep the task diff distinguishable from pre-existing work whenever possible.

Never run destructive git commands unless explicitly authorized.

Do not automatically:

* commit;
* push;
* create a branch;
* open a PR;
* amend commits;
* force push.

Those operations require explicit user intent or another applicable workflow.

---

# 7. RESOLVE THE EXACT TASK

Before spawning implementation agents, resolve the concrete target.

Examples:

* specific specification;
* backlog slice;
* issue;
* bug;
* feature;
* refactor scope;
* migration;
* integration change.

If the user names a spec or slice, that scope becomes the SCOPE LOCK.

Read the selected spec completely.

Read documents explicitly required or linked by that spec when they materially affect implementation.

Do not implement neighboring specs merely because they are related.

---

# 8. SCOPE LOCK

Once the target is resolved, define:

## Scope Lock

Target:
<exact requested feature/spec/slice>

Required behavior:

<summary>

Explicit exclusions: <known exclusions>

Relevant project sources:
<files/docs>

Likely affected surfaces:
<backend/frontend/mobile/database/etc>

The workflow must preserve this scope.

Agents may identify unrelated issues, but those issues should be reported separately rather than silently added to implementation.

---

# 9. TASK CLASSIFICATION

Classify the task before selecting stages.

Possible categories include:

## FEATURE / SPEC IMPLEMENTATION

New product or technical behavior.

Default pipeline:
ARCHITECT
→ UI/UX when applicable
→ CODER
→ TEST ENGINEER
→ UI/UX IMPLEMENTATION REVIEW when applicable
→ REVIEWER
→ QA

## BUG FIX

Existing behavior is incorrect.

Default pipeline:
ARCHITECT
→ UI/UX when the bug is user-facing or interaction-related
→ CODER
→ TEST ENGINEER
→ UI/UX IMPLEMENTATION REVIEW when applicable
→ REVIEWER
→ QA

Regression protection is especially important.

## REFACTOR

Behavior should remain equivalent.

Default pipeline:
ARCHITECT
→ CODER
→ TEST ENGINEER
→ REVIEWER
→ QA when runtime regression risk is meaningful

UI/UX normally skips unless user-facing behavior may change.

## DATABASE / MIGRATION

Default pipeline:
ARCHITECT
→ CODER
→ TEST ENGINEER
→ REVIEWER
→ QA or runtime validation when meaningful

## INFRASTRUCTURE / INTEGRATION

Default pipeline:
ARCHITECT
→ CODER
→ TEST ENGINEER
→ REVIEWER
→ QA / smoke validation

## USER-FACING UI CHANGE

Default pipeline:
ARCHITECT
→ UI/UX
→ CODER
→ TEST ENGINEER
→ UI/UX IMPLEMENTATION REVIEW
→ REVIEWER
→ QA

## DOCUMENTATION ONLY

This workflow normally should not trigger implicitly.

If explicitly invoked for documentation-only work, do not unnecessarily spawn the full engineering pipeline.

---

# 10. MANDATORY VS CONDITIONAL AGENTS

For meaningful production code changes:

`coder`:
MANDATORY

`reviewer`:
MANDATORY

`architect`:
MANDATORY for features, specs, bug fixes with meaningful behavior, refactors, migrations, integrations, structural changes, or unfamiliar repository areas.

May skip only for genuinely mechanical changes with no architectural implications.

`test-engineer`:
MANDATORY when behavior, logic, API contracts, persistence, integrations, UI behavior, security behavior, or regression risk changes.

`ui-ux-engineer`:
MANDATORY when the change affects user-visible:

* interface;
* flow;
* interaction;
* responsive behavior;
* accessibility;
* copy with product meaning;
* navigation;
* UI state;
* feedback.

`qa-engineer`:
DEFAULT TO RUN for meaningful production behavior.

Skip only when there is no meaningful observable runtime behavior to validate, such as:

* comment-only change;
* formatting-only change;
* documentation-only change;
* purely test-internal change;
* mechanical internal change where QA cannot provide additional evidence.

When uncertain, run QA with a reduced targeted scope rather than skipping it.

---

# 11. DO NOT OVER-ORCHESTRATE

Do not spawn agents simply because they exist.

Every agent invocation must have a clear engineering responsibility.

Example:

A backend-only database index change does not require UI/UX.

A CSS spacing fix does not require a database investigation.

A docs typo does not need six agents.

Use the smallest workflow that still provides strong confidence.

---

# 12. SEQUENTIAL WRITE DISCIPLINE

Do not run multiple write-heavy agents against the same working tree concurrently.

In particular, do NOT run these simultaneously:

* coder;
* test-engineer;
* multiple coders;
* multiple agents modifying overlapping files.

Write-heavy work should normally be sequential.

Read-only or analysis-heavy tasks may run in parallel only when they are truly independent.

Prefer deterministic coordination over maximum concurrency.

---

# 13. WORKFLOW STATE MACHINE

Track the workflow state explicitly.

Possible states:

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

At any moment, know:

* current state;
* previous completed gate;
* active specialist;
* unresolved findings;
* next expected gate.

Do not lose findings between agent handoffs.

---

# 14. PHASE 0 — DISCOVERY

Before spawning specialists:

1. Read applicable AGENTS.md.
2. Resolve target spec/task.
3. Read relevant source-of-truth documentation.
4. Discover applicable repository-local skills.
5. Inspect repository structure enough to locate affected areas.
6. Inspect git status.
7. Establish Scope Lock.
8. Classify the task.
9. Determine required agents.

Do not perform the Architect's full architecture analysis in the main thread.

Discovery should prepare context, not replace specialists.

---

# 15. PHASE 1 — ARCHITECT

Spawn `architect`.

Provide:

* exact user task;
* exact spec/slice when applicable;
* Scope Lock;
* relevant repository documentation;
* applicable project-specific skill;
* relevant AGENTS.md constraints;
* current repository state.

Instruction objective:

Understand the repository architecture first.

Determine how the requested change belongs in the existing system.

Do not modify production code.

Identify architectural boundaries, affected modules, dependency direction, integration implications, data implications, and implementation constraints.

Return an Architecture Handoff.

---

# 16. ARCHITECTURE HANDOFF CONTRACT

Require the Architect to return a concise handoff containing:

## Architecture Handoff

### Repository Architecture Relevant to Task

<summary>

### Existing Analogous Patterns

<files/modules/patterns>

### Proposed Placement

<where behavior belongs>

### Affected Components

<components>

### Dependency Direction

<expected interactions>

### Data / Persistence Impact

<if applicable>

### API / Integration Impact

<if applicable>

### Security / Privacy Impact

<if applicable>

### Architectural Constraints

<constraints coder must preserve>

### Risks

<risks>

### Architecture Verdict

READY_FOR_IMPLEMENTATION

or

ARCHITECTURE_BLOCKED

If ARCHITECTURE_BLOCKED, do not proceed blindly.

---

# 17. ARCHITECTURE GATE

If Architect returns:

READY_FOR_IMPLEMENTATION

Continue.

If Architect reports a material contradiction between:

* spec;
* repository architecture;
* ADR;
* security requirement;
* source-of-truth documentation;

attempt to resolve it from repository evidence.

If it cannot be resolved safely, mark workflow:

BLOCKED

Explain the exact contradiction.

Do not invent a new architecture merely to continue.

---

# 18. PHASE 2 — UI/UX DESIGN

Run only when the task has meaningful user-facing impact.

Spawn `ui-ux-engineer`.

Provide:

* original task/spec;
* Scope Lock;
* Architecture Handoff;
* relevant product documentation;
* relevant frontend documentation;
* design system context;
* existing analogous UI;
* project-specific skill.

The UI/UX Engineer must:

* understand existing product experience first;
* preserve design-system cohesion;
* define user flow;
* define interaction behavior;
* define states;
* define responsive behavior;
* define accessibility requirements;
* identify reusable components;
* avoid redesigning unrelated surfaces.

Do not modify production code.

---

# 19. UI/UX HANDOFF CONTRACT

Require:

## UI/UX Handoff

### Existing Experience

<current relevant behavior>

### User Goal

<goal>

### Existing Patterns

<analogous screens/components>

### Proposed User Flow

<flow>

### UI Structure

<structure>

### Required States

<loading/error/empty/success/etc>

### Responsive Behavior

<requirements>

### Accessibility Requirements

<requirements>

### Product Copy / Feedback

<only when relevant>

### Implementation Constraints

<constraints for coder>

### Acceptance Criteria

<observable criteria>

### UX Verdict

READY_FOR_IMPLEMENTATION

or

UX_BLOCKED

Do not proceed with materially undefined UX when it affects required behavior.

---

# 20. PHASE 3 — CODER

Spawn `coder`.

Provide:

* original task/spec;
* Scope Lock;
* applicable project instructions;
* relevant source-of-truth docs;
* Architecture Handoff;
* UI/UX Handoff when applicable;
* known constraints;
* current working-tree state.

The Coder must:

* inspect the affected repository area;
* identify actual languages/frameworks/versions;
* become a specialist in those technologies;
* implement the smallest coherent production change;
* preserve architecture;
* preserve UI/UX decisions;
* avoid unrelated refactors;
* run applicable baseline validations;
* review its own diff.

The Coder owns production implementation.

Do not ask the Coder to design the final independent test strategy.

---

# 21. CODER HANDOFF CONTRACT

Require:

## Implementation Handoff

### Implemented Behavior

<summary>

### Technology Context

<languages/frameworks/versions>

### Files / Components Changed

<files/components>

### Architectural Alignment

<summary>

### UI/UX Alignment

<if applicable>

### Important Rules / Invariants

<rules>

### Side Effects

<database/events/API/files/etc>

### Error Paths

<errors>

### Validation Executed

<commands and actual results>

### Known Risks / Limitations

<real issues only>

### Test Engineer Risk Areas

<areas needing independent verification>

### Implementation Verdict

IMPLEMENTATION_COMPLETE

or

IMPLEMENTATION_BLOCKED

Do not proceed as successful if implementation is blocked.

---

# 22. PHASE 4 — TEST ENGINEER

After production implementation is complete, spawn `test-engineer`.

Do not run it concurrently with the Coder.

Provide:

* original requirement/spec;
* Scope Lock;
* Architecture Handoff;
* UI/UX Handoff when applicable;
* Implementation Handoff;
* actual current diff;
* existing test strategy documentation;
* project-specific test instructions.

The Test Engineer must independently decide:

* what behavior must be proven;
* which test levels are justified;
* which test levels are redundant;
* which boundaries matter;
* which edge cases matter;
* whether real integration semantics must be exercised.

The Test Engineer owns automated regression evidence.

---

# 23. TEST ENGINEER HANDOFF CONTRACT

Require:

## Test Handoff

### Test Strategy

<chosen levels and rationale>

### Test Ecosystem

<frameworks/tools>

### Tests Added / Changed

<files>

### Behaviors Proven

<behavior>

### Boundaries / Failure Paths

<coverage>

### Test Levels Explicitly Skipped

<level and reason>

### Redundancy Avoided

<summary>

### False-Positive Protection

<summary>

### Validation Executed

<commands and results>

### Implementation Defects Found

<if any>

### Remaining Test Risks

<if any>

### Test Verdict

TESTS_PASS

TESTS_FOUND_IMPLEMENTATION_DEFECT

TESTS_BLOCKED

If an implementation defect is found, do not weaken the test.

Route the defect back to the Coder.

---

# 24. TEST DEFECT LOOP

If Test Engineer reports:

TESTS_FOUND_IMPLEMENTATION_DEFECT

Route to:

CODER

Provide the exact failing behavior and Test Engineer evidence.

After Coder correction:

1. return to Test Engineer;
2. verify regression protection;
3. rerun relevant tests;
4. continue only after TESTS_PASS.

If testing reveals an architectural issue:

ARCHITECT
→ CODER
→ TEST ENGINEER

If testing reveals a UX-specification issue:

UI/UX ENGINEER
→ CODER
→ TEST ENGINEER

---

# 25. PHASE 5 — UI/UX IMPLEMENTATION REVIEW

For user-facing changes, spawn `ui-ux-engineer` again after implementation and automated tests.

This is a REVIEW invocation, not a new design phase.

Provide:

* original UI/UX Handoff;
* current implementation;
* relevant screenshots/rendered application when tools permit;
* actual UI states;
* current diff.

Ask the UI/UX Engineer to validate:

* design-system cohesion;
* interaction behavior;
* visual hierarchy;
* state implementation;
* responsive behavior;
* accessibility behavior;
* copy;
* alignment with acceptance criteria.

Prefer visual inspection of the running UI when available.

Do not claim visual review occurred if the interface could not be rendered or inspected.

---

# 26. UI/UX IMPLEMENTATION REVIEW VERDICT

Require one of:

UX_APPROVED

UX_CHANGES_REQUIRED

UX_REVIEW_BLOCKED

If UX_CHANGES_REQUIRED:

Route:

UI/UX ENGINEER finding
→ CODER
→ TEST ENGINEER when behavior or automated protection is affected
→ UI/UX IMPLEMENTATION REVIEW again

Do not route purely visual implementation bugs back to the Architect unless architecture is actually implicated.

---

# 27. PHASE 6 — REVIEWER

Spawn `reviewer`.

Provide:

* original task/spec;
* Scope Lock;
* Architecture Handoff;
* UI/UX Handoff when applicable;
* Implementation Handoff;
* Test Handoff;
* UI/UX implementation-review result when applicable;
* current actual diff;
* relevant repository context.

The Reviewer independently evaluates:

* requirement correctness;
* architecture;
* language/framework usage;
* security;
* authorization;
* data integrity;
* concurrency;
* performance risks;
* API compatibility;
* maintainability;
* tests;
* regression risk;
* scope discipline.

The Reviewer must not modify files.

---

# 28. REVIEW VERDICTS

Reviewer must return one of:

APPROVED

APPROVED_WITH_NON_BLOCKING_COMMENTS

CHANGES_REQUIRED

BLOCKED

Proceed to QA when:

APPROVED

or

APPROVED_WITH_NON_BLOCKING_COMMENTS

provided no unresolved BLOCKER or HIGH defect exists.

---

# 29. REVIEW FINDING OWNERSHIP

Route Reviewer findings according to category.

## IMPLEMENTATION DEFECT

Owner:
CODER

Route:

CODER
→ TEST ENGINEER if behavior changed or regression protection is needed
→ REVIEWER

## TEST GAP

Owner:
TEST ENGINEER

Route:

TEST ENGINEER
→ REVIEWER

## ARCHITECTURAL ISSUE

Owner:
ARCHITECT

Route:

ARCHITECT
→ CODER
→ TEST ENGINEER
→ REVIEWER

## UX/UI ISSUE

Owner:
UI/UX ENGINEER

Route:

UI/UX ENGINEER
→ CODER
→ TEST ENGINEER when applicable
→ UI/UX IMPLEMENTATION REVIEW
→ REVIEWER

Do not send every finding blindly to the Coder.

---

# 30. REVIEW SEVERITY POLICY

BLOCKER:
must be resolved.

HIGH:
must be resolved.

MEDIUM:
normally resolve before proceeding unless the Reviewer explicitly classifies it as non-blocking and the requirement remains satisfied.

LOW:
may remain as non-blocking unless it indicates a systematic issue.

OPTIONAL IMPROVEMENT:
does not block completion.

Do not churn on subjective stylistic suggestions.

---

# 31. PHASE 7 — QA

After review approval, spawn `qa-engineer` when applicable.

Provide:

* original task/spec;
* Scope Lock;
* acceptance criteria;
* Architecture Handoff;
* UI/UX Handoff when applicable;
* Implementation Handoff;
* Test Handoff;
* Reviewer verdict;
* known risks;
* relevant runtime instructions.

QA should validate the actual running product or system whenever tools/environment permit.

QA must focus on:

* critical path;
* realistic user/system flow;
* failure paths;
* permissions;
* duplicate actions;
* state transitions;
* refresh/retry;
* slow/failing dependencies;
* responsive behavior;
* accessibility where applicable;
* regression risk;
* persisted state;
* real observable behavior.

Do not treat source inspection alone as full QA execution.

---

# 32. QA ENVIRONMENT HONESTY

QA must state what environment was actually used.

Examples:

* local runtime;
* browser;
* emulator;
* device;
* API-only environment;
* test container environment.

If a required runtime cannot be started, do not claim the scenario passed.

Distinguish:

NOT EXECUTED

from:

PASS

When lack of environment prevents meaningful final validation, use QA_BLOCKED rather than pretending confidence.

---

# 33. QA VERDICTS

Require one of:

PASS

PASS_WITH_KNOWN_RISKS

FAIL

BLOCKED

PASS:
workflow may complete.

PASS_WITH_KNOWN_RISKS:
workflow may complete only when remaining risks are explicitly understood, non-blocking, and do not violate the selected spec or acceptance criteria.

FAIL:
route defects.

BLOCKED:
workflow cannot claim completion.

---

# 34. QA DEFECT ROUTING

Route according to defect category.

## IMPLEMENTATION DEFECT

CODER
→ TEST ENGINEER if automation is appropriate
→ REVIEWER
→ QA RE-TEST

## TEST GAP

TEST ENGINEER
→ REVIEWER
→ QA RE-TEST when behavior was affected

## UX DEFECT

UI/UX ENGINEER
→ CODER
→ TEST ENGINEER when applicable
→ UI/UX IMPLEMENTATION REVIEW
→ REVIEWER
→ QA RE-TEST

## UI DEFECT

UI/UX ENGINEER when design decision is involved

and/or

CODER when implementation simply differs from approved design

Then:
→ TEST ENGINEER when applicable
→ UI/UX IMPLEMENTATION REVIEW
→ REVIEWER
→ QA RE-TEST

## ACCESSIBILITY DEFECT

UI/UX ENGINEER and/or CODER
→ TEST ENGINEER when automatable
→ REVIEWER
→ QA RE-TEST

## ARCHITECTURAL DEFECT

ARCHITECT
→ CODER
→ TEST ENGINEER
→ REVIEWER
→ QA RE-TEST

## ENVIRONMENT DEFECT

Do not patch production code merely to make an invalid QA environment pass.

Identify the correct owner and report the environment problem.

---

# 35. REGRESSION TEST CREATION AFTER QA DEFECTS

When QA discovers a meaningful defect that can reasonably be automated:

after the Coder fixes it, send it to Test Engineer.

The Test Engineer should add regression protection at the lowest effective level.

Do not force every exploratory QA scenario into automated tests.

Automate scenarios when doing so adds durable confidence.

---

# 36. CORRECTION LOOP

Every correction cycle should follow the smallest necessary path.

Do NOT restart the entire pipeline from Architect unless architecture changed.

Examples:

Simple implementation defect:

CODER
→ TEST ENGINEER
→ REVIEWER
→ QA

Pure test gap:

TEST ENGINEER
→ REVIEWER
→ QA if relevant

UX defect:

UI/UX ENGINEER
→ CODER
→ TEST ENGINEER if applicable
→ UI/UX REVIEW
→ REVIEWER
→ QA

Architecture defect:

ARCHITECT
→ CODER
→ TEST ENGINEER
→ UI/UX REVIEW if relevant
→ REVIEWER
→ QA

Preserve already-approved decisions unless the fix invalidates them.

---

# 37. LOOP CONTROL

Do not create infinite correction loops.

Track correction cycles per gate.

After 3 unsuccessful correction cycles for the same unresolved issue or gate:

mark:

BLOCKED

Report:

* unresolved defect;
* agents involved;
* attempted corrections;
* current evidence;
* reason continued autonomous iteration is unlikely to help.

Do not continue consuming work indefinitely without progress.

---

# 38. SPECIAL RULE FOR BUG FIXES

For bug fixes:

1. Understand expected behavior.
2. Reproduce the bug deterministically when practical.
3. Architect determines whether the bug is local or structural.
4. Coder fixes root cause.
5. Test Engineer creates regression evidence independently.
6. Reviewer confirms fix does not introduce nearby regressions.
7. QA verifies original defect no longer reproduces and checks nearby behavior.

Do not accept a patch that only hides the visible symptom when root cause remains.

---

# 39. SPECIAL RULE FOR REFACTORS

Refactors must preserve externally observable behavior unless the task explicitly changes it.

Require:

* architecture rationale;
* regression protection;
* compatibility analysis;
* focused diff.

Do not allow a "refactor" to silently change business behavior.

QA may use a targeted smoke/regression scope rather than broad exploratory testing.

---

# 40. SPECIAL RULE FOR DATABASE MIGRATIONS

Require Architect and Reviewer to consider:

* existing production data;
* nullability;
* defaults;
* indexes;
* constraints;
* migration ordering;
* backward compatibility;
* rollout;
* rollback implications.

Test Engineer should validate migration semantics when practical.

Do not assume an empty database.

---

# 41. SPECIAL RULE FOR SECURITY-SENSITIVE WORK

For changes touching:

* authentication;
* authorization;
* sessions;
* secrets;
* payments;
* private files;
* PII;
* LGPD/privacy boundaries;
* tenant isolation;
* destructive actions;

increase scrutiny.

Architect:
must identify security boundaries.

Coder:
must use established security mechanisms.

Test Engineer:
must consider negative security regression tests.

Reviewer:
must explicitly review authorization/data exposure.

QA:
must attempt relevant permission and direct-access scenarios safely.

Do not weaken security to simplify workflow completion.

---

# 42. SPECIAL RULE FOR USER-FACING WORK

For UI/mobile/web work:

UI/UX must run before implementation.

UI/UX implementation review must run after implementation.

QA must validate relevant user flow when environment permits.

At minimum consider:

* loading;
* success;
* failure;
* empty;
* disabled;
* validation;
* responsive behavior;
* accessibility;
* navigation;
* duplicate actions.

Do not approve a screen based only on static source code when a rendered interface can be inspected.

---

# 43. PROJECT SOURCE-OF-TRUTH DISCIPLINE

Some repositories intentionally use documentation-first or spec-driven development.

When the repository declares a source of truth such as:

`docs/`

or:

`specs/`

or:

`architecture/`

respect it.

Do not infer product behavior from implementation alone when authoritative specifications exist.

If implementation contradicts authoritative documentation, surface the discrepancy.

Do not silently update the spec to match accidental implementation.

---

# 44. SPEC IMPLEMENTATION MODE

When the user says:

"Implement spec X"

or equivalent:

1. Treat the selected spec as Scope Lock.
2. Read the complete spec.
3. Read required linked context.
4. Determine current implementation state.
5. Identify already-completed portions.
6. Do not reimplement completed behavior unnecessarily.
7. Implement only missing or incorrect parts required by the spec.
8. Preserve explicit exclusions.
9. Follow repository documentation-update requirements after implementation when the spec requires them.

The workflow should allow the user's prompt to remain concise.

---

# 45. EXAMPLE — CHULA-LIKE SPEC REPOSITORY

A prompt such as:

Implement Phase 5.4 Slice 6 using the software-development-workflow.

should result conceptually in:

MAIN ORCHESTRATOR
→ read applicable repository instructions and Phase 5.4 project skill
→ resolve Slice 6 and source docs
→ ARCHITECT
→ UI/UX ENGINEER if user-facing
→ CODER
→ TEST ENGINEER
→ UI/UX IMPLEMENTATION REVIEW if user-facing
→ REVIEWER
→ QA
→ correction loops if necessary
→ final consolidated result

The user should not need to manually call each specialist.

---

# 46. HANDOFF PRESERVATION

The main thread is responsible for preserving specialist handoffs.

Do not expect downstream agents to rediscover every previous decision.

Pass only relevant distilled context.

Do not flood downstream agents with raw logs when a concise handoff is available.

Important decisions must survive between stages.

---

# 47. CONTEXT HYGIENE

Keep noisy intermediate work inside subagent threads when possible.

The main thread should retain primarily:

* user requirement;
* Scope Lock;
* project constraints;
* Architecture Handoff;
* UI/UX Handoff;
* Implementation Handoff;
* Test Handoff;
* Review findings;
* QA findings;
* unresolved risks;
* workflow state.

Do not copy entire build logs into the main thread unless necessary to diagnose a blocker.

---

# 48. VALIDATION STRATEGY

Validation should progress from narrow to broad.

Typical progression:

affected check
→ affected module
→ integration validation
→ broader repository gate

Use repository-defined commands.

Do not invent replacements when official project commands exist.

Do not claim success for checks that were not executed.

---

# 49. PRE-EXISTING FAILURES

When validation exposes unrelated baseline failures:

1. verify they are pre-existing when possible;
2. separate them from current-task failures;
3. do not silently fix unrelated code;
4. report them explicitly.

A pre-existing unrelated failure should not automatically invalidate correct current work, but it may limit confidence in broad validation.

---

# 50. NO FAKE GREEN

Never permit an agent to obtain success by:

* disabling tests;
* removing assertions;
* skipping validations without disclosure;
* weakening security;
* swallowing exceptions;
* changing acceptance criteria;
* deleting failing scenarios;
* marking known defects as success.

A green pipeline produced by reducing verification is failure.

---

# 51. NO SILENT SPEC CHANGES

The workflow may discover that the spec itself needs revision.

Do not silently alter requirements to fit implementation.

If a spec change is genuinely required:

* report why;
* identify affected source-of-truth documents;
* route architectural/product implications appropriately;
* distinguish requirement correction from implementation work.

---

# 52. NO AUTOMATIC SCOPE EXPANSION

If agents discover:

* unrelated technical debt;
* neighboring bugs;
* architectural opportunities;
* UX improvements outside the target;
* dependency upgrades;

record them separately.

Do not implement them unless necessary for the selected task.

---

# 53. FINAL COMPLETION GATE

A meaningful production task is COMPLETE only when all required conditions are satisfied:

* Scope Lock requirement implemented;
* Architecture gate passed;
* UI/UX gate passed when applicable;
* production implementation complete;
* Test Engineer reports passing meaningful automated evidence;
* UI/UX implementation review approved when applicable;
* Reviewer approves or approves with only non-blocking comments;
* QA passes or passes with explicitly acceptable known risks when applicable;
* no unresolved BLOCKER or HIGH defect remains;
* meaningful MEDIUM issues are resolved or explicitly justified as non-blocking;
* required repository validations were executed or limitations explicitly reported;
* diff remains reasonably scoped;
* no unrelated user work was destroyed.

---

# 54. BLOCKED COMPLETION

Use BLOCKED rather than false success when:

* required specialist unavailable;
* source-of-truth conflict cannot be resolved;
* required environment unavailable for essential validation;
* critical external dependency prevents verification;
* architecture is unresolved;
* correction loop fails repeatedly;
* destructive ambiguity prevents safe implementation.

Explain precisely what prevents completion.

---

# 55. FINAL RESPONSE FORMAT

After the workflow finishes, return a concise consolidated result.

Use:

## Workflow Verdict

COMPLETE

COMPLETE WITH KNOWN RISKS

or

BLOCKED

## Implemented

<what changed>

## Agents Executed

Architect:
<RUN / SKIPPED — reason>

UI/UX:
<RUN / SKIPPED — reason>

Coder:
<RUN / SKIPPED — reason>

Test Engineer:
<RUN / SKIPPED — reason>

UI/UX Implementation Review:
<RUN / SKIPPED — reason>

Reviewer:
<RUN / SKIPPED — reason>

QA:
<RUN / SKIPPED — reason>

## Validation

<important commands/results>

## Review

<review verdict>

## QA

<QA verdict>

## Remaining Risks

<only real risks>

## Files / Scope

<high-level changed areas>

Do not reproduce every subagent's full output unless requested.

---

# 56. ORCHESTRATOR SHOULD NOT ASK FOR PERMISSION BETWEEN NORMAL GATES

Once the user has asked to implement a task using this workflow, proceed through normal workflow stages without asking:

"Should I continue to tests?"

"Should I run review?"

"Should I do QA?"

Those stages are part of the requested workflow.

Ask for additional user input only when a genuinely unresolved requirement or safety-sensitive decision cannot be determined from repository evidence.

Do not interrupt the workflow for routine specialist handoffs.

---

# 57. ORCHESTRATOR SHOULD NOT STOP AFTER IMPLEMENTATION

The Coder reporting IMPLEMENTATION_COMPLETE is not completion.

Continue automatically through:

TEST ENGINEER

then:

UI/UX IMPLEMENTATION REVIEW when applicable

then:

REVIEWER

then:

QA when applicable

unless a gate becomes BLOCKED.

---

# 58. ORCHESTRATOR SHOULD NOT STOP AT FIRST DEFECT

A Reviewer or QA defect is not automatically the end of the workflow.

Route the finding to the correct owner.

Perform the smallest necessary correction loop.

Revalidate.

Stop only when:

* quality gates pass;
* the workflow becomes blocked;
* loop control threshold is reached.

---

# 59. QUALITY OVER AGENT COUNT

The purpose of this workflow is not to demonstrate that many agents ran.

The purpose is to produce trustworthy software changes.

Skip unnecessary specialists.

Run necessary specialists rigorously.

Use independent validation.

Maintain clear ownership.

Avoid duplicated work.

---

# 60. FINAL ORCHESTRATION PRINCIPLE

Always remember:

The main thread coordinates.

The Architect decides where the change belongs.

The UI/UX Engineer decides how users should experience it.

The Coder implements it using expert knowledge of the actual language and framework.

The Test Engineer independently proves important behavior through the smallest high-confidence automated suite.

The Reviewer independently challenges correctness, architecture, security, maintainability, and test quality.

The QA Engineer validates whether the resulting product actually behaves correctly under realistic conditions.

Do not collapse these responsibilities back into one agent.

Resolve the task.

Lock the scope.

Delegate deliberately.

Preserve handoffs.

Route defects to owners.

Revalidate corrections.

Avoid unnecessary loops.

Do not fake successful gates.

Finish only when the software has earned confidence.
