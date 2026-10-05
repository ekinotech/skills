#!/usr/bin/env bash
# Locate a local clone of the MR's project and fetch the MR head + target branch,
# read-only: only `git fetch` touches the repo; the working tree, index, and current
# branch are never modified.
#
# Usage: resolve-mr-code-context.sh <mr_web_url> <target_branch> <source_branch> <iid> <head_sha>
#
# Lookup order: the current directory's repo, then a bounded search (maxdepth 4)
# under EKINO_REVIEW_MR_SEARCH_ROOTS (colon-separated) or common project roots in $HOME.
# A repo matches when one of its remotes points at the same host + project path.
#
# Output (key=value lines):
#   MODE=local  REPO_DIR=<path>  REMOTE=<name>  TARGET_FETCHED=yes|no
#   MODE=api    REASON=<why local mode is unavailable>

set -u

MR_WEB_URL="${1:-}"
TARGET_BRANCH="${2:-}"
SOURCE_BRANCH="${3:-}"
IID="${4:-}"
HEAD_SHA="${5:-}"

if [ -z "$MR_WEB_URL" ] || [ -z "$TARGET_BRANCH" ] || [ -z "$SOURCE_BRANCH" ] || [ -z "$IID" ] || [ -z "$HEAD_SHA" ]; then
  echo "usage: $0 <mr_web_url> <target_branch> <source_branch> <iid> <head_sha>" >&2
  exit 2
fi

# https://host/group/sub/proj/-/merge_requests/12 -> host/group/sub/proj (lowercased)
WANT="$(printf '%s\n' "$MR_WEB_URL" | sed -nE 's#^https?://([^/]+)/(.+)/-/merge_requests/.*#\1/\2#p' | tr '[:upper:]' '[:lower:]')"
if [ -z "$WANT" ]; then
  echo "MODE=api"
  echo "REASON=cannot parse project path from web_url: $MR_WEB_URL"
  exit 0
fi

# Normalize a remote URL to host/path (no scheme, user, port, or .git suffix).
#   git@host:group/proj.git | ssh://git@host:2222/group/proj.git | https://host/group/proj
normalize_remote() {
  printf '%s\n' "$1" | sed -E \
    -e 's#^[a-z+]+://##' \
    -e 's#^[^@/]+@##' \
    -e 's#^([^/:]+):[0-9]+/#\1/#' \
    -e 's#^([^/:]+):#\1/#' \
    -e 's#\.git/?$##' \
    -e 's#/$##' | tr '[:upper:]' '[:lower:]'
}

# Print the name of the first remote of repo $1 that matches WANT.
matching_remote() {
  git -C "$1" remote -v 2>/dev/null | awk '$3 == "(fetch)" { print $1, $2 }' |
    while read -r name url; do
      if [ "$(normalize_remote "$url")" = "$WANT" ]; then
        echo "$name"
        return 0
      fi
    done
}

REPO_DIR=""
REMOTE=""

# 1. Current directory's repo.
if top="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  r="$(matching_remote "$top")"
  if [ -n "$r" ]; then REPO_DIR="$top"; REMOTE="$r"; fi
fi

# 2. Bounded search of local project roots.
if [ -z "$REPO_DIR" ]; then
  if [ -n "${EKINO_REVIEW_MR_SEARCH_ROOTS:-}" ]; then
    IFS=':' read -r -a roots <<<"$EKINO_REVIEW_MR_SEARCH_ROOTS"
  else
    roots=("$HOME/Projects" "$HOME/projects" "$HOME/code" "$HOME/Code" "$HOME/src" \
      "$HOME/dev" "$HOME/Developer" "$HOME/workspace" "$HOME/git" "$HOME/repos" "$HOME/work")
  fi

  seen=" "
  for root in "${roots[@]}"; do
    [ -n "$REPO_DIR" ] && break
    [ -d "$root" ] || continue
    # Skip roots already searched (e.g. ~/projects == ~/Projects on case-insensitive disks).
    inode="$(ls -di "$root" 2>/dev/null | awk '{print $1}')"
    case "$seen" in *" $inode "*) continue ;; esac
    seen="$seen$inode "

    while IFS= read -r gitdir; do
      repo="$(dirname "$gitdir")"
      r="$(matching_remote "$repo")"
      if [ -n "$r" ]; then REPO_DIR="$repo"; REMOTE="$r"; break; fi
    done < <(find "$root" -maxdepth 4 \
      \( -name node_modules -o -name vendor -o -name .venv -o -name Library \) -prune \
      -o -name .git -print -prune 2>/dev/null)
  done
fi

if [ -z "$REPO_DIR" ]; then
  echo "MODE=api"
  echo "REASON=no local clone with a remote matching $WANT"
  exit 0
fi

# 3. Fetch, never blocking on a credential prompt or an unreachable SSH port.
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes -o ConnectTimeout=10"
git_fetch() {
  git -C "$REPO_DIR" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=20 fetch --quiet "$REMOTE" "$@" 2>/dev/null
}

# Target branch: needed for drift checks; its absence does not block local mode.
TARGET_FETCHED=no
git_fetch "$TARGET_BRANCH" && TARGET_FETCHED=yes

# MR head: refs/merge-requests/<iid>/head also covers fork MRs, but GitLab prunes it for
# old merged/closed MRs, so fall back to the source branch.
if ! git -C "$REPO_DIR" rev-parse --verify --quiet "${HEAD_SHA}^{commit}" >/dev/null; then
  git_fetch "refs/merge-requests/$IID/head" || git_fetch "$SOURCE_BRANCH" || true
fi

# 4. The MR's exact head commit must now exist locally.
if ! git -C "$REPO_DIR" rev-parse --verify --quiet "${HEAD_SHA}^{commit}" >/dev/null; then
  echo "MODE=api"
  echo "REASON=head_sha $HEAD_SHA not available after fetch in $REPO_DIR (remote $REMOTE)"
  exit 0
fi

echo "MODE=local"
echo "REPO_DIR=$REPO_DIR"
echo "REMOTE=$REMOTE"
echo "TARGET_FETCHED=$TARGET_FETCHED"
exit 0
