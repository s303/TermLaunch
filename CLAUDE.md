# TermLaunch

## Releasing

When asked to release (or "ship", "bump the version"), invoke the `release` skill. It runs in a clean subagent that cannot see this conversation, so pass what it needs as args: `[version] [release notes]`.

- Version: only if the user named one; otherwise omit (the skill bumps +0.01).
- Release notes: 1-3 concise lines summarizing the user-visible work done in this session since the last release. If the user dictated notes or a version, pass those unchanged.
