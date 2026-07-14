# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- GitHub connector: refresh expiring upstream user access tokens. The connector now persists GitHub's refresh token and expiry in `connectorData` and renews the upstream token on refresh, instead of rebuilding the oauth2 client with only the original access token. Fixes forced re-login after ~8h for GitHub App-backed connectors (GitHub App user-to-server tokens expire after 8 hours). Cherry-pick of upstream [dexidp/dex#4845](https://github.com/dexidp/dex/pull/4845) (`e8aaa98b`). Note: existing sessions only benefit after the user logs in once post-rollout, as older `connectorData` has no upstream refresh token.

## [2.43.1-gs4] - 2026-06-17

### Fixed

- OIDC connector: retain the `rootCAs`-aware HTTP client when `providerDiscoveryOverrides` is set. Previously the overridden provider was rebuilt with a background context, so RFC 8693 token exchange verified the JWKS against the system trust store and failed with `x509: certificate signed by unknown authority` for issuers served behind a custom CA.

## [2.43.1-gs3] - 2026-02-20

### Fixed

- Fix double group prefix being applied when connector group prefix is already present.

[Unreleased]: https://github.com/giantswarm/dex/compare/v2.43.1-gs4...HEAD
[2.43.1-gs4]: https://github.com/giantswarm/dex/compare/v2.43.1-gs3...v2.43.1-gs4
[2.43.1-gs3]: https://github.com/giantswarm/dex/compare/v2.43.1-gs2...v2.43.1-gs3
