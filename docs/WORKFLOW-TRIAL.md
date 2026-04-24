# Workflow Trial -- Build 50 era

**Started:** 2026-04-21
**Revisit:** 2026-04-28

The goal: reduce the rate at which Claude skips steps, makes unverified claims, or over-ships. Instead of building a full mechanical enforcement system up front, try a minimal set of guardrails for one week, then decide from evidence.

## What is in effect now

### Mechanical (git hooks, already installed)

1. **Pre-commit hook** -- `scripts/hooks/pre-commit`.
   Rejects any commit that bumps `CURRENT_PROJECT_VERSION` in `project.yml` unless every required doc file is staged in the same commit.
   - Required files: `CHANGELOG.md`, `docs/changelog.html`, `docs/features.html`, `docs/index.html`, `docs/User-Guide.md`, `docs/TESTING-CHECKLIST.md`, `docs/APPSTORE-METADATA.md`, `TESTING.md`
   - Install on a new machine with `bash scripts/hooks/install-hooks.sh`
   - Bypass (`--no-verify`) is disallowed by Claude's system rules.

### Soft (memory rules Claude loads each session)

2. **Never skip SDLC steps** -- `feedback_never_skip_sdlc.md`. All 18 pre-TestFlight steps in `CLAUDE.md` are mandatory; escape hatches ("if applicable", "if new features") are removed.
3. **Update all docs** -- `feedback_update_all_docs.md`. Every build must touch the 8 required doc files, even if the change is a dated no-op note.
4. **Verify before asserting** -- `feedback_verify_before_asserting.md`. No factual claim about state without the proving command output in the same turn. "You sure?" means re-think, test, prove -- not reassure.
5. **No em dashes** -- `feedback_no_em_dashes.md`.
6. **No auto TestFlight** -- `feedback_no_auto_testflight.md`.
7. **No auto messages** -- `feedback_no_auto_messages.md`.
8. **Merge main before PR** -- `feedback_merge_main_before_pr.md`.
9. **Fix all issues** -- `feedback_fix_all_issues.md`.
10. **Restore entitlements** -- `feedback_xcodegen_entitlements.md`.

### Documentation (reference material, not enforcement)

11. `CLAUDE.md` Pre-TestFlight Checklist -- rewritten to 18 mandatory steps with no escape hatches.

## What is deferred

Not building unless evidence during the week shows it is needed:

- `scripts/ship.sh` -- interactive ship runner. Big lift; redundant with pre-commit hook for the Build 50 failure mode.
- Pre-push hook -- blocks build-bump pushes that fail full ship checks. Redundant with pre-commit hook unless Claude finds a way around it.
- `scripts/testflight.sh` -- wrapper that refuses TestFlight upload from an unpushed commit. Nice-to-have; no active incident.
- `scripts/state.sh` + session-close memory rule -- end-of-session state summary. Soft reinforcement of rule 4.
- `WORKFLOW.md` at repo root with action tier table -- helpful but overlaps with `CLAUDE.md`.

## What to watch for during the week

Track anything that matches:

- [ ] Claude skipped a doc file on a version bump (hook should have caught it; if it did not, why?)
- [ ] Claude asserted state without same-turn proof (e.g. "branches are in sync", "hook is live") and user had to challenge
- [ ] Claude said "yes" to "you sure?" without running a fresh test
- [ ] Claude used an em dash in any output
- [ ] Claude proposed or ran a TestFlight upload without explicit approval
- [ ] Claude posted to GitHub / Slack / anywhere without approval
- [ ] Claude chose a cherry-picked example that made a rule look tidier than it is
- [ ] Claude bypassed a hook with `--no-verify`

## Decision tree for the revisit (2026-04-28)

**If zero incidents and no new friction:**
- Leave the current setup alone. Revisit again in a month.

**If one or two incidents, all in categories the mechanical hooks can catch:**
- Add the deferred pre-push hook + ship.sh. The hook bite has proven real.

**If one or two incidents, all verbal / reasoning (rule 4):**
- Tighten the memory rule further. Consider adding a "proof template" Claude must use for state claims. Do not add tooling.

**If more than two incidents or any repeat offender from today:**
- Build the full hybrid (ship.sh, pre-push, testflight.sh, state.sh, WORKFLOW.md).
- Also consider shrinking typical build size. Build 50 stacked 9 tester fixes + 2 PRs; smaller builds reduce surface area for mistakes.

## What the workflow looks like day-to-day

### User asks for a one-off fix (small, no ship)

1. User: "Fix the thing."
2. Claude: edits files, runs tests, shows the diff.
3. Commit directly on `develop`. No PR needed for tiny fixes.
4. User reviews next time they pull or when it lands in the next TestFlight bundle.

No hooks fire (no version bump). No ship checks.

### User asks to ship a build

1. User: "Let's ship Build 51."
2. Claude runs through `CLAUDE.md` pre-TestFlight checklist manually (steps 1 to 18).
3. When Claude stages `project.yml` with the version bump + all required docs, the **pre-commit hook** lets the commit through. If any doc is missing, the hook rejects and Claude has to fix before retrying.
4. Claude merges develop to main via PR (user approval to merge).
5. Claude tags the release.
6. User explicitly approves TestFlight upload.
7. Claude archives + uploads.

If Claude tries to ship with stale docs, the hook stops it at commit time. If Claude claims "all docs updated" without verification, rule 4 says Claude must prove it in the same turn (with a `git diff --stat` or similar).

### User asks Claude to do something irreversible

1. Anything in the "confirm before acting" tier -- merge PR, push tag, force-push, TestFlight upload, post a comment, send a message -- Claude asks first.
2. User gives explicit yes or no.
3. No blanket authorization for a class of actions. One yes = one action.

### User challenges a Claude claim ("you sure?")

1. Claude re-reads the claim -- not just re-runs the check.
2. Claude asks: is the framing right? Is the premise right? Did the earlier proof actually prove the claim, or something adjacent?
3. Claude picks a test that could disprove the claim, not one that confirms it.
4. Claude pastes the command output.
5. If the claim is wrong, Claude corrects it and propagates the correction back into the relevant memory or rule (per rule 7 of `feedback_verify_before_asserting.md`).

### End of a multi-step session

1. Claude summarizes in two or three sentences: what landed, what is in what state, what is pending.
2. For ship-adjacent sessions, Claude paste the output of `git ls-remote origin refs/heads/main refs/heads/develop` + latest tag, so the state is explicit and verifiable.
3. User knows where to pick up next time without reverse-engineering the conversation.

## Success criteria for the week

The minimum bar: zero incidents in the "Claude skipped a required doc on a version bump" category. The pre-commit hook enforces this, so the only way this fails is a bypass or a hook bug.

The stretch bar: zero incidents in the verbal class (claims without proof, "yes" to "you sure?" without re-testing). That one rides on soft enforcement and is the real test.
