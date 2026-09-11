# Security policy

## Sensitive reports

Do not open a public issue containing provider tokens, browser cookies, CLI
authentication files, account payloads, Apple signing material, or personal
identifiers. Use the repository's **Security → Report a vulnerability** form;
the publication gate requires GitHub private vulnerability reporting to be
enabled before this policy is published.

## Data boundary

Usage is designed to keep credentials owned by installed provider CLIs. The
public repository and its CI must never contain real credentials, signed app
artifacts, provisioning profiles, notarization material, cached provider
responses, or diagnostic payloads.

## Supported source

Security fixes target the latest commit on the public `main` branch. Compiled
applications are not currently distributed from this repository.
