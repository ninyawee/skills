---
name: bbt
description: The art of black-box testing — make software easy to test, cover bugs with a test before fixing, stub external seams, and generate tests with AI. Use when writing or expanding an E2E/integration test suite, deciding a testing strategy, adding tests to legacy or tightly-coupled code, stubbing third-party services, fixing a reproducible bug, or having an AI agent generate tests.
---

# Black-Box Testing

Drive the app from the outside; assert on what it does. Based on Thai Pangsakulyanont's
"Move Fast While Maintaining Quality" (CityJS SG 2026).

## The two principles

1. **Make software easy to test.** Testability is a feature of the *app*, not the test. Once
   writing a new automated test is easier than testing by hand, the suite grows on its own — no
   coverage mandate needed.
2. **Cover the bug with a test before fixing it.** Write a failing test that reproduces the bug
   *first* — it locks the regression, and the friction of writing it reveals the testability gap
   to close. Before any fix ask: "How do I cover this with a test?" and "What must improve to
   make that easy?"

## Four levers for testability

| Lever | Meaning |
|---|---|
| Alternative pathways | Test-only routes / scenario APIs that reach a state the UI would take many steps to build. |
| Concurrent testers | Tests and people run at once without colliding — isolate by tenant/account/trigger ID. |
| Easy scenario setup | One call drops the app into a precise, named state. |
| Targetable UI | Semantic locators (roles, labels, test ids) over brittle CSS. |

## Stub external services — never test the real third party

Cheapest first: official **sandbox** env → official **emulator** → community **simulator** →
**custom simulator** (a tiny mock you control, e.g. `mockapis`) → make the **connection optional**
in test mode. Stub at the seam, drive the real app.

## Legacy / tightly-coupled code

Black-box beats unit tests here: an app has *dozens* of external connection points to stub vs
*hundreds* of interdependent internal units. Treat the app as a box, stub the seams, assert
behavior — don't untangle internals first.

## Page Object pattern — survive UI churn

Centralize every selector in one layer so a UI change updates one file, not dozens of tests.
Tests are a safety net: too loose misses bugs, too tight chokes velocity. Keep test bodies
readable; keep selectors in page objects.

## Generating tests with AI agents

Loop: **start small** (one test) → **steer** (corrective feedback) → **iterate** (next test,
richer context) → **scale** (once quality holds) → **consolidate** (have the AI write learnings
into reusable rules). Always make the agent study existing test infrastructure first.

Three tics to correct:

| AI tendency | Steer toward |
|---|---|
| Outdated framework syntax | Current API — point at live docs / existing tests. |
| Raw CSS selectors | Semantic locators (`getByRole`, `getByLabel`, test ids). |
| Workarounds inside the test | Improving the *app's* testability instead. |

For UI changes: reuse existing page objects; let the AI hardcode interactions first, then
refactor into page objects — not both at once.

## Scenario-setup API pattern

For complex or concurrent-state tests, expose dedicated test-scenario endpoints (one per
situation) instead of building state through the UI:

```
POST /api/scenarios/<ScenarioName>  → { triggerIds: [...] }
```

Keep it maintainable with a pipeline, not discipline:
backend auto-generates an **OpenAPI** spec → **openapi-typescript** generates a typed client →
shared **scenario-utils** keep each endpoint ~10 lines → the setup call returns **trigger IDs**
so a test can fire competing actions and assert the race outcome.

Restrict scenario endpoints to non-production environments.
