# Contributing

Contributions are welcome as pull requests into `main` of
[Kuzmenko-Pavel/ingress-nginx-neo](https://github.com/Kuzmenko-Pavel/ingress-nginx-neo).

## Workflow

1. Create a branch from `main`.
2. Make the change. Run the checks:

   ```console
   make check       # lint, unit tests, generated files, chart lint and tests
   make test-e2e    # when the controller, the NGINX template or Lua code changed
   ```

   `make help` lists all targets; the [developer guide](https://kuzmenko-pavel.github.io/ingress-nginx-neo/latest/developer-guide/getting-started/)
   describes the requirements and the development environment.
3. Commit, push and open a pull request. CI runs the same targets; the **CI result** check must pass.

## Commits

Every commit follows [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/);
the release changelog is generated from the commit subjects.

```text
<type>[(scope)][!]: <description>
```

- Types: `feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `build`, `ci`, `chore`, `revert`, `style`.
- Scope (optional): the area, for example `controller`, `chart`, `plugin`, `images`, `release`.
- `!` after the type/scope or a `BREAKING CHANGE:` footer marks a breaking change.

Examples:

```text
feat(controller): support ordered real_ip_header sources
fix(plugin): find DaemonSet controller pods by default
feat(chart)!: rename values key foo to bar
```

`make code-lint-commits` checks the commits of your branch. Commits and pull request descriptions
contain no AI attribution trailers or footers (`Co-Authored-By` of an AI tool, `Generated with …`).

## Rules

- The user-facing API stays compatible: annotation prefix, IngressClass and controller value,
  ConfigMap keys, metrics, command line arguments.
- Do not edit generated files: run `make docs-generate` (annotation risks, command line arguments)
  and `make helm-docs-generate` (chart README).
- Do not write versions into files: the release tag is the only version source.
- The repository has no changelog files; release notes come from the release tag.
- Tools and image inputs are pinned in `tools/` and `images/*/build-args.env`.

Releases are described in the [release guide](https://kuzmenko-pavel.github.io/ingress-nginx-neo/latest/developer-guide/release/).

## Conduct

See [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md).
