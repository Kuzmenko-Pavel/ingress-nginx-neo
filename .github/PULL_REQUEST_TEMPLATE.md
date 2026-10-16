<!-- The title follows Conventional Commits: <type>[(scope)][!]: <description> -->

## What this pull request changes and why

## Type of change

- [ ] `feat` — new functionality
- [ ] `fix` — bug fix
- [ ] `perf`, `refactor`, `test`, `build`, `ci`, `chore`, `style`
- [ ] `docs` — documentation only
- [ ] Breaking change (`!` or a `BREAKING CHANGE:` footer in the commit)

## Checks

- [ ] A test fails without this change and passes with it; its level follows
      docs/developer-guide/testing.md#which-test (or the reason is stated above)
- [ ] `make check` passes
- [ ] `make test-e2e` passes (changes of the controller, the NGINX template or Lua code that change the handling of requests)
- [ ] Generated files regenerated (`make docs-generate`, `make helm-docs-generate`)
- [ ] Documentation updated for user-visible changes

## Related issues

<!-- fixes #<number> -->
