#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repo_root"

mapfile -t bash_files < <(find scripts tests -type f -name '*.sh' -print | sort)
for file in "${bash_files[@]}"; do
  bash -n "$file"
done
printf 'PASS: Bash syntax (%d files)\n' "${#bash_files[@]}"

bash tests/test-common.sh
python3 tests/check_docs.py
python3 tests/check_secrets.py
python3 tests/check_svg.py

if command -v ruby >/dev/null 2>&1; then
  ruby -e 'require "yaml"; ARGV.each { |file| YAML.load_file(file) }' .github/workflows/*.yml .github/dependabot.yml
  printf 'PASS: workflow YAML parses\n'
else
  printf 'SKIP: Ruby is unavailable; workflow YAML parse not run\n'
fi

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x "${bash_files[@]}"
  printf 'PASS: ShellCheck\n'
else
  printf 'SKIP: ShellCheck is unavailable locally (CI installs it)\n'
fi

git check-ignore -q scripts/00-env
git check-ignore -q backups/example.tar.bz2
printf 'PASS: secret-bearing local paths are ignored\n'
