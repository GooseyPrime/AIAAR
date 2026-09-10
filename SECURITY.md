# Security

## Secrets Management

- Use GitHub Actions Secrets for CI/CD credentials and tokens.
- Use environment variables (for example a local `.env` file copied from `.env.example`) for local development secrets.
- Never commit real API keys, access tokens, passwords, or private credentials to this repository.
- Commit only placeholder values in example/config files.

## Reporting Security Issues

If you discover a security issue, please open a private security advisory or contact maintainers through private channels before public disclosure.
