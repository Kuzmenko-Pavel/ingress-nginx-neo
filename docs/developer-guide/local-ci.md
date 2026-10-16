# Running CI workflows locally

[act](https://github.com/nektos/act) reads `.github/workflows/*.yaml`, builds the job graph and runs
the jobs in Docker containers similar to the GitHub runners. It is useful when a workflow changes,
not the code. Before a push it shows which jobs a pull request runs, what a job receives from the
previous ones (`needs`, outputs) and how the matrix expands.

act is not a gate and not a way to run the checks. The gate is [CI](ci.md), a pull request without
a green **CI result** is not merged. Lint, tests and builds run as make targets, act adds nothing to
them.

## Installation

act is not part of the make contract and is optional, see
[installing act](https://nektosact.com/installation/). The commands below use the runner image
`catthehacker/ubuntu:act-latest`, it has the tools the jobs expect.

Every command has `-W .github/workflows/ci.yaml`. act looks a job up by its id in all workflows of
the repository, and the id `docs` exists in both `ci.yaml` and `release.yaml`. Without `-W` the
command `act -j docs` also runs the release chain.

## Job graph

```console
act pull_request -W .github/workflows/ci.yaml -l
```

Prints every job with its stage, id and events.

## Path filters on a real pull request

The `changes` job takes the changed files of a pull request from the GitHub API by its number, so
act needs an event with the number and a token:

```console
gh pr view <N> --json number,baseRefName,baseRefOid,headRefName,headRefOid \
  --jq '{pull_request:{number:.number,base:{ref:.baseRefName,sha:.baseRefOid},head:{ref:.headRefName,sha:.headRefOid}}}' \
  > "$TMPDIR/pr.json"
act pull_request -W .github/workflows/ci.yaml -e "$TMPDIR/pr.json" -j changes \
  -P ubuntu-latest=catthehacker/ubuntu:act-latest -s GITHUB_TOKEN="$(gh auth token)"
```

The output has the line `changes=[...]` with the matched groups, the result of each group and the
matrices `k8s-versions` and `e2e-variants`. The groups and the jobs that depend on them are
described in [CI](ci.md#when-jobs-run). The filter sees the files of the pull request on GitHub.
Changes that are not pushed yet are not taken into account.

## Jobs without artifacts

The jobs `helm`, `generated`, `docs` and `security` receive nothing from other jobs except the
outputs of `changes` and run completely:

```console
act pull_request -W .github/workflows/ci.yaml -e "$TMPDIR/pr.json" -j helm \
  -P ubuntu-latest=catthehacker/ubuntu:act-latest -s GITHUB_TOKEN="$(gh auth token)"
```

act does not clone the repository, it copies the local working tree into the container, uncommitted
changes included. The event only sets the pull request for the path filter.

## Limitations

Lint, Unit tests, Build images, E2E and Chart e2e do not work under act. They receive images from
Dependency images through workflow artifacts, and this does not work in act 0.2.89:
- the reusable workflow `deps.yaml` is called without `secrets:`. GitHub passes `GITHUB_TOKEN` to it
  by itself, act does not, so `Log in to GHCR` fails with `Password required`
- the act artifact server does not accept `upload-artifact@v7` and `download-artifact@v8`
  ([nektos/act#6022](https://github.com/nektos/act/issues/6022),
  [#6114](https://github.com/nektos/act/issues/6114),
  [#6173](https://github.com/nektos/act/issues/6173)). `secrets: inherit` in the calls of
  `deps.yaml` removes the first error but not this one, so the workflows do not have it

CI checks these jobs, and locally the same make targets check their logic.
