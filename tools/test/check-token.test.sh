#!/usr/bin/env bash
# Tests tools/check-token.sh against a fake curl. No network, no real token.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../check-token.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
cat > "$tmp/bin/curl" <<'FAKE'
#!/usr/bin/env bash
# Fake curl: honours -o and -w '%{http_code}'; behaviour chosen by FAKE_MODE. Records argv.
echo "$*" >> "$FAKE_ARGV_LOG"
out=""; data=""
while [ $# -gt 0 ]; do
  case "$1" in -o) out="$2"; shift 2 ;; --data-binary) data="${2#@}"; shift 2 ;; *) shift ;; esac
done
case "$FAKE_MODE" in
  ok)
    if grep -q 'pullRequest(number' "$data"; then
      echo '{"data":{"repository":{"pullRequest":{"title":"T","url":"u","state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","headRefOid":"abc","author":{"login":"a"},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]}}}}}' > "$out"
    else
      echo '{"data":{"search":{"nodes":[{"number":1},{"number":2}]}}}' > "$out"
    fi
    printf 200 ;;
  gqlerror) echo '{"errors":[{"message":"Resource not accessible by personal access token"}]}' > "$out"; printf 200 ;;
  http401) echo '{"message":"Bad credentials"}' > "$out"; printf 401 ;;
esac
FAKE
chmod +x "$tmp/bin/curl"

secret="ghp_FAKE_TOKEN_for_tests_0000"
fail=0
LAST=""
run() { # mode expected-exit [extra script args]
  local mode="$1" want="$2" got
  shift 2
  : > "$tmp/argv.log"
  LAST="$(PATH="$tmp/bin:$PATH" FAKE_MODE="$mode" FAKE_ARGV_LOG="$tmp/argv.log" GITHUB_TOKEN="$secret" bash "$script" o r 7 "$@" 2>&1)"
  got=$?
  if [ "$got" -ne "$want" ]; then echo "FAIL $mode: exit $got, wanted $want"; echo "$LAST"; fail=1; return; fi
  if grep -q "$secret" <<<"$LAST$(cat "$tmp/argv.log")"; then echo "FAIL $mode: token leaked"; fail=1; return; fi
  echo "ok   $mode (exit $got)"
}

run ok 0 --login me
grep -q 'SUMMARY: PASS' <<<"$LAST" || { echo "FAIL ok: no PASS summary"; fail=1; }
grep -q 'statusCheckRollup field: true, mergeable field: true' <<<"$LAST" || { echo "FAIL ok: fields line"; fail=1; }
[ "$(grep -c '^OK ' <<<"$LAST")" -eq 6 ] || { echo "FAIL ok: expected 6 OK lines"; fail=1; }
run gqlerror 1 --login me
grep -q 'GraphQL error: Resource not accessible' <<<"$LAST" || { echo "FAIL gqlerror: message"; fail=1; }
run http401 1
grep -q 'HTTP 401' <<<"$LAST" || { echo "FAIL http401: message"; fail=1; }
if env -u GITHUB_TOKEN PATH="$tmp/bin:$PATH" bash "$script" o r 7 >/dev/null 2>&1; then
  echo "FAIL no token accepted"; fail=1
else
  echo "ok   no token refused"
fi
if [ "$fail" -eq 0 ]; then echo "ALL PASSED"; else echo "TESTS FAILED"; exit 1; fi
