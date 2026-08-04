# Repository operating guide

## Scope

This repository is a Samba AD DC **lab** for a fresh, dedicated Ubuntu 24.04 VM. Do not present repository code, CI, or documentation as deployment or runtime evidence.

## Safe workflow

1. Inspect `git status`, branch, remotes, instructions, and recent history.
2. Keep `scripts/00-env`, domain backups, private evidence, logs, and secrets out of Git.
3. Run `bash tests/static.sh` before and after changes.
4. Review numbered scripts in execution order and preserve rerun/failure guards.
5. Never run privileged scripts on a development workstation or unknown host.
6. Never test teardown, provisioning, restore, or credential flows in CI.

## Script conventions

- Bash with `set -euo pipefail`.
- Source `scripts/lib/common.sh`; do not source `scripts/00-env` directly.
- Validate all state before the first mutation.
- Quote expansions, use explicit paths, and use `mktemp` for privileged temporary files.
- Back up a host path with `backup_path_once` before changing it.
- Fail closed on mismatched existing state; do not use broad `|| true` around verification.
- Passwords must stay in interactive prompts, never configuration, arguments, output fixtures, or examples.
- Do not add recursive domain-data cleanup automation.

## Truth rules

Keep authored, syntax checked, linted, CI validated, deployed, runtime tested, recovery tested, and teardown tested as distinct statuses. Add evidence only from an actual isolated run, with sensitive values redacted. Never fabricate output, screenshots, versions, timings, or recovery results.

## Definition of done

- Bash syntax, parser tests, documentation links, YAML parsing, and ShellCheck pass.
- Documentation matches script order and behavior.
- DNS, time, secret, rerun, recovery, and teardown risks are explicit.
- No secret pattern, backup archive, local config, generated junk, or false claim is tracked.
- The complete diff is reviewed from both operator-safety and two-minute recruiter perspectives.
