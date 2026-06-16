#!/usr/bin/env bash
set -Eeuo pipefail

VISIBILITY="${1:-public}"

case "$VISIBILITY" in
  public|private) ;;
  *)
    echo "Usage: $0 [public|private]" >&2
    exit 1
    ;;
esac

if [[ ! -d .git ]]; then
  git init
  git branch -M main
fi

if ! command -v gh >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    brew install gh
  else
    echo "GitHub CLI is missing and Homebrew is unavailable." >&2
    exit 1
  fi
fi

if ! gh auth status >/dev/null 2>&1; then
  gh auth login --web --git-protocol ssh
fi

gh auth setup-git

if ! git config user.name >/dev/null; then
  login="$(gh api user --jq .login)"
  name="$(gh api user --jq '.name // .login')"
  git config --global user.name "$name"
  user_id="$(gh api user --jq .id)"
  git config --global user.email "${user_id}+${login}@users.noreply.github.com"
fi

git add .
git commit -m "docs: publish Danzee homelab build and automation" || true

OWNER="$(gh api user --jq .login)"
REPO_NAME="$(basename "$PWD")"
FULL_NAME="$OWNER/$REPO_NAME"

if gh repo view "$FULL_NAME" >/dev/null 2>&1; then
  git remote remove origin 2>/dev/null || true
  git remote add origin "git@github.com:$FULL_NAME.git"
  git push -u origin main
else
  gh repo create "$FULL_NAME" \
    "--$VISIBILITY" \
    --source=. \
    --remote=origin \
    --push \
    --description "Security-conscious Ubuntu homelab with Docker, k3s, Tailscale, Ollama and encrypted USB backups"
fi

gh repo view "$FULL_NAME" --web
