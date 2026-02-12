# Repository Guidelines

## Project Structure & Module Organization
Core Solidity contracts live in `src/` (`StaticATokenLM.sol`, `StaticATokenFactory.sol`, `StataOracle.sol`), with shared interfaces under `src/interfaces/`.
Tests are in `tests/` and follow Foundry conventions (`*.t.sol`, plus shared fixtures like `TestBase.sol`).
Deployment and upgrade scripts live in `scripts/` (`Deploy.s.sol`, `DeployUpgrade.s.sol`).
Security artifacts are stored in `audits/`.
Third-party dependencies are vendored in `lib/`; generated outputs are in `out/` and `cache/`.

## Build, Test, and Development Commands
- `cp .env.example .env`: initialize local environment variables.
- `forge install`: install/update Foundry dependencies.
- `forge build --sizes` or `make build`: compile contracts and report bytecode sizes.
- `forge test -vvv` or `make test`: run the full test suite with verbose logs.
- `forge test --match-test test_name`: run a focused test while iterating.
- `npm run lint`: format codebase via Prettier (Solidity plugin enabled).

## Coding Style & Naming Conventions
Use Solidity `^0.8.10` patterns already used in `src/`.
Formatting is enforced by Prettier (`.prettierrc`): 2-space indentation, 100-char line width, single quotes, no tabs.
Name contracts/libraries in `PascalCase` (for example, `StaticATokenFactory`), interfaces with `I` prefix (for example, `IStaticATokenLM`), and constants in `UPPER_SNAKE_CASE`.
Keep new modules in focused files; prefer explicit imports over wildcard imports.

## Testing Guidelines
Use Foundry (`forge-std/Test.sol`) for unit, fork, and fuzz tests.
Name test files `FeatureName.t.sol`; name test methods `test_*` and negative-path tests `testFail_*` when appropriate.
Many tests fork live networks, so ensure required RPC env vars in `foundry.toml` are set.
Every behavior change should include happy-path and revert-path coverage.

## Commit & Pull Request Guidelines
Follow the existing commit style: `type: short description` (for example, `fix:`, `feat:`, `test:`, `chore:`, `refactor:`), optionally with issue/PR refs like `(#45)`.
PRs should include:
- clear problem/solution summary,
- linked issue(s),
- test evidence (commands run and results),
- notes on storage layout/interface changes and deployment impact when relevant.

## Security & Configuration Tips
Never commit secrets (`.env`, private keys, API keys).
For scripts, validate chain aliases and explorer keys in `foundry.toml` before broadcasting; use dry-run options first when available.
