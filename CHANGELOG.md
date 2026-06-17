# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- OIDC connector: retain the `rootCAs`-aware HTTP client when `providerDiscoveryOverrides` is set. Previously the overridden provider was rebuilt with a background context, so RFC 8693 token exchange verified the JWKS against the system trust store and failed with `x509: certificate signed by unknown authority` for issuers served behind a custom CA.

## [2.43.1-gs3] - 2026-02-20

### Fixed

- Fix double group prefix being applied when connector group prefix is already present.

[Unreleased]: https://github.com/giantswarm/dex/compare/v2.43.1-gs3...HEAD
[2.43.1-gs3]: https://github.com/giantswarm/dex/compare/v2.43.1-gs2...v2.43.1-gs3
