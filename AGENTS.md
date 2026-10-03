# AGENTS.md

Guidance for coding agents working in this repository. The canonical design and
architecture live in `docs/`; this file says where to look and what is easy to
get wrong.

## Project

Tijara Tides is a multiplayer maritime trading game: Elixir/Phoenix with a
LiveView UI, a Tauri desktop client that connects to the same server, and
PostgreSQL storage. One `GameServer` process owns the world, and every command
or tick commits atomically.

| Path | Contents |
|---|---|
| `lib/tijara_tides/domain` | Pure game rules: typed models, `*World` roots that own tables, `Services.*` coordinators |
| `lib/tijara_tides/use_cases` | Command workflows, queries and read models, persistence ports |
| `lib/tijara_tides/infrastructure` | `GameServer`, PostgreSQL adapters, runtime |
| `lib/tijara_tides_web` | LiveView and components; calls use cases only |
| `priv/repo/migrations`, `priv/gettext` | Schema; English and Arabic catalogues |
| `src-tauri`, `test/desktop` | Desktop client and its tests |

## Read first

- [docs/architecture.md](docs/architecture.md), especially
  [Change and verification rules](docs/architecture.md#change-and-verification-rules).
  Those rules are requirements for new code.
- [docs/DESIGN.md](docs/DESIGN.md) for gameplay intent and
  [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md) for what is built.
- [docs/testing-and-coverage.md](docs/testing-and-coverage.md),
  [docs/database.md](docs/database.md) and
  [docs/localization.md](docs/localization.md).

`ARCHITECTURE.md` at the root is only a pointer to `docs/architecture.md`.

## Commands

```sh
mix setup                          # dependencies and assets
mix phx.server                     # run locally on port 4000
mix precommit                      # format check, forced compile with warnings as errors, gettext check, tests
python3 scripts/test-game-db.py    # full suite including database tests, on a disposable PostgreSQL cluster
python3 scripts/test-game-db.py --control-sweep  # CI-only: press every rendered command control
mix test path/to/file_test.exs     # one file (database tests are excluded without the script)
scripts/check-local.sh             # automatic docs-only or full local validation
scripts/check-local.sh --full      # force all local gates
```

Enable the tracked hooks once per clone with `git config core.hooksPath .githooks`.

## Before committing

- Code, tooling, policy, configuration and mixed changes require `mix precommit`
  and `python3 scripts/test-game-db.py`. `scripts/check-local.sh --full` includes
  both plus the remaining local gates.
- Pure documentation changes may use `scripts/check-local.sh` instead. It selects
  a fast path only when every outgoing commit and tracked working/index change
  affects regular, non-executable Markdown under `docs/`, `README.md` or
  `ARCHITECTURE.md`. It checks whitespace, generated documents and `test/docs`;
  ordinary compilation may still occur. It skips full gameplay/database suites,
  coverage, Gettext, desktop/Rust checks, assets and release builds. Stage new
  documents first. Policy files such as `AGENTS.md`, unknown baselines, unusual
  file modes, untracked files and empty change sets select full validation.
- Compile and test output contain zero warnings. Count them; a green suite can
  still hide a warning that names a real defect.
- For runtime message changes, run `mix gettext.extract`. Never run
  `mix gettext.merge`: it deletes translations for messages looked up at runtime.
  Keep the Arabic catalogue complete and check it with
  `python3 scripts/check-gettext-catalogues.py`.
- Generated artifacts (`priv/game/catalogue.json`, `docs/ports.md`,
  `docs/ship-instructions.md`, `docs/ux-inventory.md`) come from scripts in
  `scripts/gen-*.py`. Regenerate them; never edit them by hand.
  `scripts/check-generated.py` verifies them.
- Update the documentation for any contract you change in the same commit.

## Rules that are easy to break

The full list and the tests that enforce it are in `docs/architecture.md`.

- A raise or database constraint reachable from a tick or a commit pauses the
  whole world for every player. Validate player input in the domain with the
  same measure the constraint uses (code points, not graphemes), reject control
  characters, and never trust an identifier the client chose.
- Each table has one owning `*World` root, and only that module writes its rows.
  A new table gets its owner added to the boundary tests in `test/docs/`.
- `*World` roots never call `Services.*`; coordinators sequence roots.
- A transition releases everything it invalidates in the same commit. Do not add
  reconcile sweeps to command dispatch. In test builds `TijaraTides.SettledCheck`
  checks this after every command and tick; extend it for new invariants.
- Queries must not re-derive a rule a command enforces. Call the same domain
  function, and add a contract test showing the offered value is accepted and
  one more is refused (see `test/tijara_tides/use_cases/*_offers_test.exs`).
- Mutations are explicit puts and deletes recorded in the `ChangeSet`. To find
  what a transition touched, read the `ChangeSet`; do not scan the world.
- Domain row codecs write complete rows; the persistence adapter never invents
  a domain value.
- After adding a guard, oracle or regression test, break the behavior it
  protects once and confirm a test fails.

## Documentation style

Markdown prose is hard-wrapped near 80 columns. Edit a whole paragraph and
rewrap it; splicing a sentence into wrapped lines leaves ragged text.

## Git and safety

- Commit on the current branch; create a branch only when asked.
- Pushes require a clean checkout. The pre-push hook gives `scripts/check-local.sh`
  each remote ref's prior commit, so classification includes all outgoing commits,
  including changes later reverted. New branches, non-fast-forward ranges,
  unavailable remote commits and non-branch refs select full validation. Manual
  checks default to the branch's upstream; `--base <commit>` can specify a known
  range, and `--full` always runs every gate. Never use `--no-verify` for doc changes.
- CI retains full validation for every push and pull request.
- Local validation never touches deployed storage. Database tests use only the
  disposable cluster from `scripts/test-game-db.py`; do not point tests at
  `DATABASE_URL`.
