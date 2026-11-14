# Fork contract

`pierou/watt` is a fork of [`ZimengXiong/watt`](https://github.com/ZimengXiong/watt) (MIT). The
point of this file is that **upstream stays cheap to merge, indefinitely** — so work here can move
at its own pace without waiting on a maintainer, and without the fork drifting into a state where
merging upstream is a rewrite.

Remotes: `origin` → `pierou/watt` (push here), `upstream` → `zimengxiong/watt` (fetch only; nothing
here ever pushes to it).

## The five rules

**1. `main` = `upstream/main` + a short, *listed* stack.** Run `git log --oneline upstream/main..main`
before adding anything. If that list is growing unbounded, the stack is a rewrite-in-progress, not a
fork — split it into PRs instead.

**2. Anything intended for upstream starts at `upstream/main`, never at `main`.**

```bash
git fetch upstream
git switch -c feature/x upstream/main
git cherry-pick <the commits on main that make up the feature>   # tree-only, not history
```

That keeps the PR diff free of fork-only work, which is the difference between a PR a maintainer
can read and one they cannot. `fix/repo-health` (PR #1) was cut this way.

**3. Never rebase or force-push a branch that is an open PR's head.** Reviewers cite SHAs. Fix
feedback by adding commits; the squash-on-merge is the maintainer's call, not ours.

**4. Sync often and in small pieces.** `git fetch upstream && git merge upstream/main` on `main`
after any upstream release. `rerere.enabled` and `merge.conflictstyle=zdiff3` are set on this clone
(`git config --local`), so a conflict resolved twice is resolved automatically the second time and
the diff shows the common prefix. Merging upstream into `main` is never a threat to fork work — the
fork commits stay.

**5. When a PR is merged upstream, do not delete the local branch until the next sync proves it.**
If upstream squashes, the SHAs differ and the content merge has to be re-resolved once; if it
merges, the commits are already in `main`'s history and the sync is a near no-op.

## What is fork-only, and what is on loan to upstream

| on `main` | status | upstream vehicle |
|---|---|---|
| `fix(build)` — signing override, release guards, `install` split, `pipefail`, README | **offered** | PR #1 (`fix/repo-health`) |
| `chore(ci)` — `.github/workflows/ci.yml` | **offered** | PR #1 |
| Time-of-use `Tariff` model, `Money`/`Currency`, `WattTests` target + 19 tests | planned PR | PR #2 (model only, no UI) |
| tariff panel + settings views | planned | after PR #2 — open a discussion before a design PR |
| pinnable floating panel (`WattApp.swift`) | **fork-only until asked** | likely a design opinion; treat as ours |
| `MARKETING_VERSION 1.6.0` | fork-only | versioning is upstream's call |
| `FORK.md` and the README pointer to it | fork-only | this file is about carrying a fork; upstream has nothing to fork |
| correctness fixes (energy accrual after sleep, cost-of-past semantics, `@MainActor`, DST transitions, US-only rate lookup) | not yet written | each on its own branch from `upstream/main` |

A row moves from *fork-only* to *offered* by cherry-picking it onto a branch cut from
`upstream/main` — never by merging `main` into anything.

## Two things that must not drift silently

- **Identity.** Bundle id `com.watt.app`, UserDefaults keys `com.watt.*`, and the LaunchDaemon label
  `com.watt.powermetrics` are shared with an installed upstream copy. Changing any of them is a
  migration, not a rename — and keeping them means both apps fight over one daemon.
- **Published numbers.** Anything that changes what the panel displays (rates, totals, the currency
  symbol) changes what a user believes they are paying. Those commits want a test in the same
  commit, because the suite is the only thing that makes them reviewable.

## Check and sync

```bash
git log --oneline upstream/main..main          # the fork's whole footprint
git log --oneline main..upstream/main          # what upstream has that we lack
git fetch upstream && git merge upstream/main  # routine
git cherry-pick --no-commit <sha> && git diff --cached --stat   # preview an upstream-bound slice
```
