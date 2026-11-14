#!/usr/bin/env bash
# Check that a GitHub token can run Mergeable's five inbox searches and the PR-status query.
# Usage: GITHUB_TOKEN=... tools/check-token.sh <owner> <repo> <pr-number> [--login <login>]
# The token is read from the environment only. It is sent through curl's stdin config,
# so it never appears in argv, output or logs.
set -euo pipefail

usage() { echo "usage: GITHUB_TOKEN=... $0 <owner> <repo> <pr-number> [--login <login>]" >&2; exit 2; }

command -v curl >/dev/null || { echo "error: curl is required" >&2; exit 2; }
command -v jq >/dev/null || { echo "error: jq is required (brew install jq / apt-get install jq)" >&2; exit 2; }
[ -n "${GITHUB_TOKEN:-}" ] || { echo "error: set GITHUB_TOKEN in the environment" >&2; exit 2; }

login=""
pos=()
while [ $# -gt 0 ]; do
  case "$1" in
    --login) [ $# -ge 2 ] || usage; login="$2"; shift 2 ;;
    -*) usage ;;
    *) pos+=("$1"); shift ;;
  esac
done
[ ${#pos[@]} -eq 3 ] || usage
owner="${pos[0]}"; repo="${pos[1]}"; number="${pos[2]}"
[[ "$number" =~ ^[0-9]+$ ]] || { echo "error: pr-number must be an integer" >&2; exit 2; }

# Copied from MergeableCore/Sources/MergeableCore/Queries.swift
summary_fields='id number title url updatedAt isDraft state mergeable headRefOid baseRefName reviewDecision author{login} repository{name owner{login}} commits(last:1){nodes{commit{statusCheckRollup{state}}}} comments{totalCount} lastComment: comments(last:1){nodes{author{login}}} reviews{totalCount} lastReview: reviews(last:1){nodes{state author{login}}}'
search_query="query(\$q:String!){search(query:\$q,type:ISSUE,first:50){nodes{... on PullRequest{${summary_fields}}}}}"
pr_status_query='query($owner:String!,$repo:String!,$number:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$number){title url state isDraft mergeable headRefOid author{login} commits(last:1){nodes{commit{statusCheckRollup{state}}}}}}}'

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fails=0
total=0

# gql <label> <query> <jq-args...>; leaves the response body in $tmp/resp.json
gql() {
  local label="$1" query="$2"; shift 2
  local code msg
  total=$((total + 1))
  jq -n --arg query "$query" "$@" '{query:$query, variables:($ARGS.named|del(.query))}' > "$tmp/req.json"
  code="$(printf 'header = "Authorization: Bearer %s"\n' "$GITHUB_TOKEN" |
    curl -sS -K - -o "$tmp/resp.json" -w '%{http_code}' \
      -H 'Accept: application/vnd.github+json' -H 'Content-Type: application/json' \
      --data-binary "@$tmp/req.json" https://api.github.com/graphql 2>"$tmp/curl.err")" || {
    echo "FAIL  $label: curl error: $(head -c 200 "$tmp/curl.err")"; fails=$((fails + 1)); return 1; }
  if [ "$code" != "200" ]; then
    msg="$(jq -r '.message // empty' "$tmp/resp.json" 2>/dev/null || true)"
    echo "FAIL  $label: HTTP $code${msg:+ - $msg}"; fails=$((fails + 1)); return 1
  fi
  if ! jq -e . "$tmp/resp.json" >/dev/null 2>&1; then
    echo "FAIL  $label: response was not JSON"; fails=$((fails + 1)); return 1
  fi
  if jq -e '(.errors // []) | length > 0' "$tmp/resp.json" >/dev/null; then
    msg="$(jq -r '.errors[0].message' "$tmp/resp.json")"
    echo "FAIL  $label: GraphQL error: $msg"; fails=$((fails + 1)); return 1
  fi
  return 0
}

base="is:pr is:open archived:false"
searches=("review-requested:@me" "author:@me" "assignee:@me" "mentions:@me")
if [ -n "$login" ]; then searches+=("user:$login"); else echo "SKIP  search user:<login> (pass --login <login>)"; fi

for s in "${searches[@]}"; do
  if gql "search $s" "$search_query" --arg q "$base $s"; then
    n="$(jq '.data.search.nodes | length' "$tmp/resp.json")"
    echo "OK    search $s ($n PRs)"
  fi
done

if gql "pr-status $owner/$repo#$number" "$pr_status_query" --arg owner "$owner" --arg repo "$repo" --argjson number "$number"; then
  pr="$(jq -c '.data.repository.pullRequest' "$tmp/resp.json")"
  if [ "$pr" = "null" ]; then
    echo "FAIL  pr-status $owner/$repo#$number: pull request not found or not visible to this token"
    fails=$((fails + 1))
  else
    echo "OK    pr-status $owner/$repo#$number"
    has_rollup="$(jq -r '.data.repository.pullRequest.commits.nodes[0].commit | has("statusCheckRollup")' "$tmp/resp.json")"
    has_merge="$(jq -r '.data.repository.pullRequest | has("mergeable")' "$tmp/resp.json")"
    echo "      statusCheckRollup field: $has_rollup, mergeable field: $has_merge"
    jq '.data.repository.pullRequest | {title, state, isDraft, mergeable, statusCheckRollup: .commits.nodes[0].commit.statusCheckRollup}' "$tmp/resp.json"
    if [ "$has_rollup" != "true" ] || [ "$has_merge" != "true" ]; then
      echo "FAIL  pr-status: missing statusCheckRollup or mergeable"
      fails=$((fails + 1))
    fi
  fi
fi

echo "---"
if [ "$fails" -gt 0 ]; then
  echo "SUMMARY: FAIL ($fails problem(s) across $total calls)"
  exit 1
fi
echo "SUMMARY: PASS ($total of $total calls OK)"
