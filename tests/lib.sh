# Minimal assertion helpers for the shell tests.
TESTS_RUN=0
TESTS_FAILED=0

pass() { TESTS_RUN=$((TESTS_RUN + 1)); printf '  ok   %s\n' "$1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; return 0; }

assert_eq() { # expected actual name
  if [ "$1" = "$2" ]; then pass "$3"; else fail "$3" "expected [$1] got [$2]"; fi
}
assert_contains() { # haystack needle name
  case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "missing [$2] in output: $1" ;; esac
}
assert_not_contains() { # haystack needle name
  case "$1" in *"$2"*) fail "$3" "found [$2] in output: $1" ;; *) pass "$3" ;; esac
}
finish() {
  echo "$TESTS_RUN tests, $TESTS_FAILED failed"
  [ "$TESTS_FAILED" -eq 0 ]
}
