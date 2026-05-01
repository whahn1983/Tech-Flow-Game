# Contributing to Tech Flow Runner

> Tech Flow Runner is proprietary software owned by whahn1983. Contributions are
> welcomed via pull request, but by submitting a contribution you agree that the
> code becomes part of the project under the terms in `LICENSE`.

## Getting set up

```bash
git clone https://github.com/whahn1983/Tech-Flow-Game.git
cd Tech-Flow-Game
npm install      # installs dev dependencies (eslint, prettier, husky, lint-staged)
npm test         # runs the unit test suite
node server.js   # http://localhost:8080
```

The PHP backend can be served from any LAMP stack (`leaderboard.php` is the
entry point). PHP 8.2+ with `pdo_sqlite` and `mbstring` extensions enabled is
recommended.

## Branches

- `main` is the release branch.
- Feature work happens on short-lived branches (`feature/<name>`,
  `fix/<name>`, `chore/<name>`).
- Open a PR against `main` and let CI run before requesting review.

## Code style

- **Prettier** formats JavaScript, JSON, CSS, and Markdown. Run
  `npm run format:fix` before committing.
- **ESLint** lints JavaScript. Run `npm run lint`.
- **PHP** follows the existing 4-space indent / snake_case style in
  `leaderboard.php`.
- The pre-commit hook (Husky + lint-staged) runs Prettier and ESLint on staged
  files. To enable it locally, run `npm run prepare` once after install.

## Tests

- Unit tests live in `tests/` and use the [Node test runner](https://nodejs.org/api/test.html).
- Run all tests: `node --test tests/server.test.js` (or `npm test`).
- Add tests for new server-side logic — name sanitization, validation,
  leaderboard sorting, nonce/rate-limit handling.

## Commit messages

Follow the existing style in the log:

```
<type>: <short summary>

<optional longer description>
```

Types in active use: `feat`, `fix`, `chore`, `docs`, `refactor`, `security`,
`perf`, `test`.

## Security issues

If you discover a security issue, **please do not file a public issue.**
Open a [private security advisory](https://github.com/whahn1983/Tech-Flow-Game/security/advisories/new)
or contact whahn1983 directly.

## Pull request checklist

- [ ] CI is green (`syntax`, `lint`, `prettier --check`, tests).
- [ ] If you added user-facing behavior, you smoke-tested in a browser.
- [ ] If you added or changed leaderboard-server logic, you added a unit test.
- [ ] You updated `CHANGELOG.md` under `[Unreleased]`.
