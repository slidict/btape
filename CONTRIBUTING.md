# Contributing to btape

Thanks for taking the time to contribute! This document covers how to set up
a development environment, the expectations for pull requests, and how
releases are cut.

## Getting started

You can develop either directly with Ruby or inside the provided container.

### Local Ruby

Chromium must be installed and discoverable by Ferrum.

```sh
bundle install
bundle exec rake spec
bundle exec rake rubocop
```

### Container (dip or wip)

```sh
dip provision
dip test

wip up
wip dispatch rake spec
```

## Before opening a pull request

- `bundle exec rake spec` passes.
- `bundle exec rake rubocop` passes (or `rubocop -A` for auto-fixable
  offenses).
- New behavior is covered by a spec under `spec/`.
- README / command docs are updated if user-facing behavior changed.

## Commit and PR conventions

Releases are generated automatically from merged pull requests
(`.github/release-drafter.yml`), which groups changes by **PR label**. Please
add one of the following labels to your PR:

| Label   | Used for                                   |
| ------- | ------------------------------------------- |
| `feat`  | New features                                 |
| `fix`   | Bug fixes                                    |
| `chore` | Maintenance with no user-facing effect       |
| `ci`    | CI/workflow changes                          |
| `docs`  | Documentation only                           |
| `build` | Build system / dependency changes            |
| `perf`  | Performance improvements                     |
| `test`  | Test-only changes                            |

Keep the PR title short and descriptive — it's used as the changelog entry
(e.g. `fix: handle relative Output paths on Windows`). Conventional Commit
style prefixes in the title are welcome but not required as long as the
label is set correctly.

Guidelines for the PR itself:

- Keep pull requests focused on a single change; split unrelated work into
  separate PRs.
- Fill out the pull request template, including a short rationale ("why")
  and a test plan.
- Link related issues with `Closes #123` / `Refs #123` where applicable.
- Squash fixups locally where reasonable; CI runs on every push so a clean
  history isn't required, but a readable one is appreciated.

## Reporting bugs / requesting features

Please use the issue templates under **New Issue**. Include the `.tape`
file (or minimal repro) and Ruby/Chromium versions for bug reports.

## Code style

RuboCop config lives in `.rubocop.yml`. CI runs the same checks
(`bundle exec rake rubocop`) across Ruby 3.2–4.0, so please run it locally
before pushing.

## License

By contributing, you agree that your contributions will be licensed under
the [MIT License](LICENSE) that covers this project.
