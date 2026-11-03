# Sling Who roster + formula-derived target — live acceptance (ga-rghou)

Date: 2026-11-03
City: `bright-lights` (`/home/roman/bright-lights`), local, gc 1.5.1
Scope: preview/dry-run only; no work was created, launched or mutated.

## What was checked

1. The `T` (Who) candidate list offers every configured agent, including
   agents with no observed status/session row.
2. The list names agents only in the qualified form gc accepts from the city
   root; the bare `gc.run-operator` never appears.
3. build-basic + an `hw-` work bead derives `hello-world/gc.run-operator` as
   the Who default, tagged `formula-run-target`.
4. gc accepts the derived qualified route from the city root in a dry run.

## Evidence

### Interactive picker (fresh Emacs in tmux, `emacs -nw -Q`)

`completing-read` over `gascity-agents-roster-candidates
(gascity-agents-roster 'cached)` with `default-directory` pinned to the
city. `*Completions*` listed the full configured roster (23 candidates at
capture time; live pool instances come and go), including:

```
hello-world/gc.run-operator
hello-world/gc.run-operator-2
hello-world/gc.implementation-worker
hello-world/gc.requirements-planner
hello-world/pi
...
```

`hello-world/gc.run-operator` is the configured template (state
`configured`); the numbered names are its live pool instances. No bare
`gc.run-operator` row was offered.

### Derivation over the live store (batch Emacs, real gc reads)

```
rows=24   (live pool instances vary between runs)
has hello-world/gc.run-operator: t
has bare gc.run-operator: nil
annotation: "hello-world · configured"
formula run target: "gc.run-operator"
derived: (:target "hello-world/gc.run-operator" :source formula-run-target)
header: Run build-basic against bead hw-aij, drained by hello-world/gc.run-operator
```

`gascity-sling--formula-run-target` over the live build-basic recipe (38
steps, 24 carrying `gc.run_target`) picked `gc.run-operator` (10 steps; every
other lane target 1–2 steps). The rig memo resolved `hw-aij` → `hello-world`.

### gc dry run of the derived route

```
$ gc --city /home/roman/bright-lights sling hello-world/gc.run-operator hw-aij --dry-run
Target:
  Session config: hello-world/gc.run-operator (min=0 max=unlimited)
  Sling query: bd update {} --set-metadata gc.routed_to=hello-world/gc.run-operator
Work:
  Bead:   hw-aij — "Build a python hello world program"
No side effects executed (--dry-run).
```

Exit status 0. This is the qualified form the picker/derivation now surface;
the bare `gc.run-operator` fails from the city root on gc 1.5.1.

## Notes / residual risks

- The live build-basic formula carries ten distinct binding-qualified
  `gc.run_target`s, so the literal "exactly one distinct target" reading
  cannot derive from it. The implemented rule is the strict plurality (the
  target coordinating the most steps) — build-basic → `gc.run-operator`,
  every other lane 1–2 steps. A tie is ambiguous and derives nothing
  (fail-soft, gc stays the authority).
- The Agents table stays observed-only by design; the roster used by the
  Who picker and the footer is the superset. Language templates therefore
  appear in `T` but not in the Agents table until they have live state.
- `<rig>/gc.run-operator` is offered because `gc agent list` reports it as a
  live config; no per-rig synthesis was added.
