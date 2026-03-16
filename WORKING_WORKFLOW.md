# Working Workflow

**The mandatory workflow for every Claude Code session in Java Spring projects.**

Every session follows seven phases. No exceptions. No shortcuts. This document is the single source of truth for how work gets done.

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          SESSION LIFECYCLE                                │
│                                                                          │
│  ┌──────┐  ┌──────┐  ┌──────┐  ┌───────┐  ┌────────┐  ┌────────┐      │
│  │ BOOT │─▶│ PLAN │─▶│ SPEC │─▶│ BUILD │─▶│ VERIFY │─▶│ REVIEW │      │
│  │  ①   │  │  ②   │  │  ③   │  │  ④    │  │   ⑤    │  │   ⑥    │      │
│  └──────┘  └──┬───┘  └──┬───┘  └───┬───┘  └───┬────┘  └───┬────┘      │
│     ▲         │         │          │           │            │             │
│     │         │         │    ┌─────┘           │            ▼             │
│     │         │         │    │ TDD cycle       │     ┌──────────┐        │
│     │         │         │    │ per step        │     │ DELIVER  │        │
│     │         │         │    ▼                 │     │ to user  │        │
│     │         │         │  RED → GREEN         │     └──────────┘        │
│     │         │         │    → REFACTOR        │            │             │
│     │         │         │                      │            ▼             │
│  ┌──────┐    │         │                      │     ┌──────────┐        │
│  │LEARN │◀───┴─────────┴──────────────────────┴─────│  END     │        │
│  │  ⑦   │             SessionEnd hook               └──────────┘        │
│  └──────┘                                                                │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Table of Contents

- [Phase 1: BOOT](#phase-1-boot)
- [Phase 2: PLAN](#phase-2-plan)
- [Phase 3: SPEC](#phase-3-spec)
- [Phase 4: BUILD](#phase-4-build)
- [Phase 5: VERIFY](#phase-5-verify)
- [Phase 6: REVIEW](#phase-6-review)
- [Phase 7: LEARN](#phase-7-learn)
- [Enforcement Rules](#enforcement-rules)
- [Appendix B: Hook-to-Phase Mapping](#appendix-b-hook-to-phase-mapping)
- [Appendix C: Error Recovery](#appendix-c-error-recovery)

---

## Phase 1: BOOT

**Trigger:** Automatic — `SessionStart` hook (`scripts/hooks/session-start.sh`)
**Agent:** None (hooks handle this)
**Output:** Loaded context, environment report, active TODOs/blockers

### Process

1. Detect project type from `build.gradle` / `pom.xml` (WebFlux, MVC, Monorepo, Maven)
2. Load `PROJECT_GUIDELINES.md` if present — project-specific rules override all defaults
3. Query `claude-mem` — load last 5 session summaries, active instincts (confidence ≥ 0.5), unresolved issues
4. Report environment: Java version, build tool, git branch, uncommitted changes
5. Print active TODOs and blockers from session files and guidelines

### Boot Checklist

| Step | Source | Required |
|------|--------|----------|
| Detect project type | `build.gradle` / `pom.xml` | Yes |
| Load guidelines | `PROJECT_GUIDELINES.md` | Yes (skip if missing) |
| Query claude-mem | `.claude/sessions/`, instincts | Yes |
| Report environment | System commands | Yes |
| Print TODOs/blockers | Session files | If any exist |

---

## Phase 2: PLAN

**Trigger:** `/plan` command or automatically when receiving a new task
**Agent:** `planner` (opus) — see `agents/planner.md`
**Input:** User task description
**Output:** Approved implementation plan with risk assessment
**Gate:** User confirms plan before any code is written

### Process

1. Restate requirements — clarify what is being built in concrete terms
2. Identify affected files/modules (controllers, services, repositories, DTOs, tests)
3. Break down into steps — each step is one verifiable unit of work
4. Risk assessment: HIGH (breaking changes, auth, data migration) / MEDIUM (new integration, schema change) / LOW (internal refactor)
5. Choose architecture approach: Hexagonal / CQRS / Event-driven / Layered
6. **WAIT FOR USER CONFIRM** — do not touch any code until user says "proceed"
7. `/checkpoint create "plan-approved"`

### Plan Output Format

```markdown
# Implementation Plan: [Feature Name]

## Requirements
- [Concrete requirement 1]
- [Concrete requirement 2]

## Affected Components
| Component | File | Change Type |
|-----------|------|-------------|
| Controller | OrderController.java | New endpoint |
| Service | OrderService.java | New method |

## Implementation Steps

### Step 1: [Description]
- Files: path/to/file.java
- Action: What to do
- Test: What test covers this

## Risk Assessment: [HIGH/MEDIUM/LOW]
- [Risk]: [Mitigation]

## Architecture: [Hexagonal / CQRS / Event-driven / Layered]

⏸️ **WAITING FOR CONFIRMATION** — Proceed? (yes / modify / reject)
```

### Skip Conditions

| Condition | Example |
|-----------|---------|
| Change is ≤ 5 lines of code | Fix null check, update constant |
| Single file affected | One config file, one typo |
| No architectural impact | No new dependencies, no schema change |
| No risk of breaking existing tests | Pure addition or cosmetic fix |

When in doubt, plan.

---

## Phase 3: SPEC

**Trigger:** `/spec` command after plan approval
**Agent:** spec-writer (opus) — see `commands/spec.md`
**Input:** Approved implementation plan
**Output:** Approved behavioral spec with scenarios mapped to test methods
**Gate:** User approves spec before any implementation code is written

### Process

1. Detect task type from plan signals: REST Endpoint / Domain Logic / Messaging / Database Migration / Background Job
2. Generate spec using type-specific template (inputs, outputs, contracts, error cases)
3. Task Decomposition — break spec into discrete implementation tasks, one per step in the plan
4. Map each scenario to one or more test method signatures
5. **WAIT FOR USER APPROVAL**
   - Approve → `/checkpoint create "spec-approved"`
   - Revise → update spec based on feedback
   - Reject → return to `/plan`

### Spec Output Format

| Section | Description |
|---------|-------------|
| **Inputs** | What goes in — request body, command fields, event payload |
| **Outputs / Side Effects** | What comes out — response, state changes, events published |
| **Contracts / Invariants** | What must always hold — validation, ordering, consistency |
| **Error Cases** | What can go wrong — trigger condition and expected behavior |
| **Scenarios** | ≥1 happy path + ≥2 failure/edge cases — concrete and testable |

### Spec → TDD Mapping

```
Spec Scenario                          → Test Method
─────────────────────────────────────────────────────
Happy path: valid order created        → shouldCreateOrderWhenValidInput()
Validation: blank customer ID          → shouldReturn400WhenCustomerIdBlank()
Conflict: duplicate order              → shouldReturn409WhenOrderExists()
Auth: missing token                    → shouldReturn401WhenNoAuthToken()
```

### Skip Conditions

| Condition | Example |
|-----------|---------|
| Change is ≤ 5 lines of code | Fix null check, update constant |
| Single file affected | One config file, one typo |
| No new observable behavior | Rename, reformat, comment fix |
| No architectural impact | No new dependencies, no schema change |

When in doubt, spec.

---

## Phase 4: BUILD

**Trigger:** User approves spec (or skip conditions met for trivial changes)
**Agent:** `tdd-guide` (sonnet) — see `agents/tdd-guide.md`
**Input:** Approved spec with test method signatures
**Output:** Passing tests + implementation code, one checkpoint per step
**Gate:** All tests green, no `.block()` in `src/main/`, before proceeding to VERIFY

### TDD Cycle Per Step

For each step in the approved plan, using the approved spec as test specification:

1. **RED** — Write test first (JUnit 5 + Mockito for unit, `@SpringBootTest` + Testcontainers for integration, `StepVerifier` for reactive)
2. **Run test** — confirm it FAILS (`./gradlew test --tests "ClassName.methodName"`)
3. **GREEN** — Write minimal implementation to make the test pass
4. **Run test** — confirm it PASSES; if FAIL → `/build-fix` (invokes `build-error-resolver`)
5. **REFACTOR** — extract methods, remove duplication, improve naming; run tests again
6. `/checkpoint create "step-N-done"`

### Build Rules

| Rule | Rationale |
|------|-----------|
| Test FIRST, always | Catch regressions immediately. Tests define the contract. |
| Minimal implementation | Don't gold-plate. Make the test pass, then refactor. |
| No `.block()` in reactive code | Blocks the event loop. Use `StepVerifier` for testing. |
| No `Thread.sleep()` in tests | Use `StepVerifier.withVirtualTime()` or `Awaitility`. |
| No `subscribe()` inside chains | Causes fire-and-forget. Chain with `flatMap` / `then`. |
| Checkpoint after each step | Enables rollback and progress tracking. |

### Test Writing Examples

**Unit Test (Service Layer)**

```java
@ExtendWith(MockitoExtension.class)
class OrderServiceTest {

    @Mock private OrderRepository orderRepository;
    @InjectMocks private OrderService orderService;

    @Test
    void shouldCreateOrderWithPendingStatus() {
        var command = new CreateOrderCommand("CUST-001", List.of(item1, item2));
        var expected = Order.create(command);
        when(orderRepository.save(any())).thenReturn(Mono.just(expected));

        StepVerifier.create(orderService.create(command))
            .assertNext(order -> {
                assertThat(order.getStatus()).isEqualTo("PENDING");
                assertThat(order.getCustomerId()).isEqualTo("CUST-001");
            })
            .verifyComplete();
    }
}
```

**Integration Test (API Layer)**

```java
@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT)
@Testcontainers
class OrderApiIntegrationTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15");

    @Autowired private WebTestClient webTestClient;

    @Test
    void shouldCreateOrderViaApi() {
        var request = new CreateOrderRequest("CUST-001", List.of(item1));

        webTestClient.post()
            .uri("/api/orders")
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(request)
            .exchange()
            .expectStatus().isCreated()
            .expectBody()
            .jsonPath("$.orderId").isNotEmpty()
            .jsonPath("$.status").isEqualTo("PENDING");
    }
}
```

---

## Phase 5: VERIFY

**Trigger:** All build steps complete, or manually via `/verify`
**Agent:** None (automated pipeline)
**Input:** Completed implementation
**Output:** Verification report with PASS/FAIL verdict
**Gate:** All checks must pass before proceeding to REVIEW

### Verification Modes

| Mode | Command | Checks | When to Use |
|------|---------|--------|-------------|
| Quick | `/verify quick` | Build + Compile | Mid-development sanity check |
| Pre-commit | `/verify pre-commit` | Build + Tests + Debug audit | Before committing |
| Full | `/verify` or `/verify full` | All checks + Security scan | Default — end of implementation |
| Gate | `/verify gate` | Full + blocks on any failure | CI/CD enforcement |

### Verification Pipeline

1. **Build Check** — `./gradlew clean build -x test` — FAIL → stop, fix build errors first
2. **Compile Check** — `./gradlew compileJava compileTestJava` — report all errors with `file:line`
3. **Full Test Suite** — `./gradlew test jacocoTestReport` — coverage must be ≥ 80%, all tests must PASS
4. **Reactive Safety Scan** — grep `src/main/` for `.block()`, `Thread.sleep()`, orphan `.subscribe()` — any match is CRITICAL
5. **Security Scan** — hardcoded secrets, `./gradlew dependencyCheckAnalyze`, debug statements
6. **Diff Review** — `git diff --stat` — verify only planned files changed

### Verification Gates

| Check | Pass Criteria | On Failure |
|-------|---------------|------------|
| Build | Exit code 0 | STOP — fix before continuing |
| Compile | Zero errors | STOP — fix all compilation errors |
| Tests | 100% pass, ≥80% coverage | Fix failing tests, improve coverage |
| Reactive | Zero `.block()` / `Thread.sleep()` / orphan `.subscribe()` in `src/main/` | CRITICAL — must fix before review |
| Security | No hardcoded secrets, no HIGH/CRITICAL CVEs | BLOCK — must fix before review |
| Debug | No `System.out.println` / `printStackTrace` | WARNING — remove before commit |
| Diff | Only planned files changed | Review unintended changes |

---

## Phase 6: REVIEW

**Trigger:** Verification passes
**Agent:** `code-reviewer` + `security-reviewer` (sonnet), plus conditional reviewers
**Input:** Verified, passing implementation
**Output:** Review report with APPROVE / WARNING / BLOCK verdict
**Gate:** No BLOCK verdict before delivering to user

### Review Chain

**Always runs:**
1. **Code Reviewer** — quality, readability, naming, DRY/SOLID, error handling, test quality, spec adherence
2. **Security Reviewer** — OWASP Top 10, secrets in code, injection, auth/authz correctness, dependency CVEs

**Conditional reviewers:**

| Reviewer | Triggers When |
|----------|---------------|
| Spring WebFlux Reviewer | `*Controller.java`, `*Handler.java`, or `*WebFlux*` changed |
| Spring Boot Reviewer | `*Config.java`, `application*.yml`, `build.gradle` changed |
| Database Reviewer | `*Repository.java`, `*.sql`, `changelog*`, `migration*` changed |
| Performance Reviewer | High-throughput paths, batch operations, or N+1 risk detected |
| Architect | New packages created, >5 files across modules changed, domain boundary touched |

### Review Report Format

```markdown
# Code Review Report

## Summary
| Reviewer | Verdict | Issues |
|----------|---------|--------|
| Code Reviewer | ✅ APPROVE | 0 critical, 0 high, 2 suggestions |
| Security Reviewer | ✅ APPROVE | 0 critical, 0 high |
| WebFlux Reviewer | ⚠️ WARNING | 1 medium (missing timeout) |

## Overall Verdict: ⚠️ WARNING

## Issues

### [MEDIUM] Missing timeout on external service call
**File:** `PaymentService.java:78`
**Issue:** WebClient call without timeout — risks thread exhaustion
**Fix:** `.timeout(Duration.ofSeconds(5))` after `.bodyToMono(...)`
```

### After Review: Delivery Protocol

- **APPROVE** → Deliver summary to user: "Implementation complete. Review passed. Ready for your final review."
- **WARNING** → Deliver summary + issue list: "Implementation complete with warnings. See issues below."
- **BLOCK** → Fix blocking issues → re-run VERIFY → re-run REVIEW. Do NOT deliver blocked code to user.

**CRITICAL RULE: The agent does NOT commit.** The agent delivers completed, reviewed code. The user does the final review and commits manually. This is non-negotiable.

---

## Phase 7: LEARN

**Trigger:** Automatic — `SessionEnd` hook (`scripts/hooks/session-end.sh`, `evaluate-session.sh`)
**Agent:** None (hooks handle this)
**Input:** Session history (≥10 messages triggers full evaluation)
**Output:** Session summary + new/updated instincts saved to `claude-mem`

### Process

1. Evaluate session — what was built, what patterns emerged, what bugs were fixed, what corrections the user made
2. Extract instincts by type:
   - Bug fixed → anti-pattern instinct
   - New pattern discovered → pattern instinct
   - User correction → correction instinct
3. Save to `claude-mem`: session summary, new instincts (initial confidence 0.3–0.5), files modified
4. Update confidence scores: confirmed instinct +0.1, contradicted −0.1, below 0.1 → mark for removal

### Instinct Lifecycle

Instincts grow in confidence when confirmed each session and fade when contradicted:

- **Discovered** (conf: 0.3) → confirmed → **Active** (conf: 0.5+) → confirmed → **Promoted** via `/evolve` to skill
- **Contradicted** instinct loses 0.1 per session → below 0.1 → removed

Use `/instinct status` to see current instincts. Use `/evolve` to promote high-confidence clusters to skills.

### Compaction Preservation

When compacting context, the `pre-compact.sh` hook saves current session state. When manually compacting, preserve:
- Current phase and last checkpoint name
- Modified files list
- Approved plan and spec summary
- Failing tests (if any)

---

## Enforcement Rules

These rules are non-negotiable. They prevent the most common workflow violations.

### Hard Blocks

| Violation | Action | Exception |
|-----------|--------|-----------|
| Writing code without `/plan` | **STOP** — run `/plan` first | Bug fix ≤ 5 lines, typo, config-only change |
| Writing code without approved spec | **STOP** — run `/spec` first | Bug fix ≤ 5 lines, no new behavior |
| Committing without `/verify` | **BLOCK** — run `/verify` first | None |
| Skipping tests for new code | **BLOCK** — write tests first | None |
| `.block()` in reactive production code | **CRITICAL** — must fix immediately | Test code only (still discouraged) |
| Agent attempts `git commit` | **BLOCK** — only user commits | None |

### Enforcement Flow

```
Code change detected
    │
    ├── Was /plan run? ─── NO ──▶ STOP. "Run /plan first." (unless trivial fix)
    │       YES
    │       │
    ├── Was /spec run and approved? ── NO ──▶ STOP. "Run /spec first." (unless trivial fix)
    │       YES
    │       │
    ├── Were tests written first? ── NO ──▶ BLOCK. "Write tests first."
    │       YES
    │       │
    ├── Do tests pass? ── NO ──▶ Fix with /build-fix
    │       YES
    │       │
    ├── Was /verify run? ── NO ──▶ BLOCK. "Run /verify before review."
    │       YES
    │       │
    ├── Any .block() in src/main/? ── YES ──▶ CRITICAL. Fix now.
    │       NO
    │       │
    └── Proceed to REVIEW
```

### Reactive Safety Rules

| Pattern | Why It's Forbidden | Alternative |
|---------|--------------------|-------------|
| `.block()` | Blocks the event loop thread, defeats reactive purpose | Chain with `flatMap`, `map`, `then` |
| `Thread.sleep()` | Blocks thread, wastes resources | `Mono.delay()`, `delayElement()` |
| `.subscribe()` inside a chain | Fire-and-forget, loses error context | `flatMap`, `then`, `concatWith` |
| `Mono.just(blockingCall())` | Executes blocking call on event loop | `Mono.fromCallable(blockingCall).subscribeOn(Schedulers.boundedElastic())` |

---

## Appendix B: Hook-to-Phase Mapping

| Hook | Script | Phase | Fires When |
|------|--------|-------|------------|
| `SessionStart` | `session-start.sh` | ① BOOT | New session begins |
| `PreToolUse` | `suggest-compact.sh` | ④ BUILD | Before each tool call (monitors count) |
| `PostToolUse` | `java-compile-check.sh` | ④ BUILD | After Java file edits |
| `PostToolUse` | `java-format.sh` | ④ BUILD | After Java file edits |
| `Stop` | `check-debug-statements.sh` | ⑤ VERIFY | Session stopping — final audit |
| `Stop` | `evaluate-session.sh` | ⑦ LEARN | Session stopping — extract patterns |
| `PreCompact` | `pre-compact.sh` | Any | Before context compaction |
| `SessionEnd` | `session-end.sh` | ⑦ LEARN | Session ending — persist state |

## Appendix C: Error Recovery

| Error | Recovery Path |
|-------|---------------|
| Build fails during VERIFY | Run `/build-fix` → re-run `/verify` |
| Test fails after implementation | Check test logic → fix implementation → re-run test |
| Coverage below 80% | Write additional tests for uncovered paths → re-run |
| `.block()` detected in production code | Replace with reactive alternative → re-verify |
| Review returns BLOCK | Fix all critical/high issues → re-run `/verify` → re-run review |
| Context too large (>50 tool calls) | `/checkpoint create` → `/compact` → continue from checkpoint |
| Session crashes mid-work | Next session BOOT loads last checkpoint and session state from claude-mem |

---

_This workflow is enforced, not optional. Every phase exists for a reason. Skip nothing. Trust the process._
