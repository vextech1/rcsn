#!/usr/bin/env bash
# Usage: annotate-failure.sh <title> <logfile>
# Emits one ::error annotation holding the error lines and tail of a log, so a
# failed step can be diagnosed from the check-run annotations API.
title="$1"; log="$2"
{
  # Mocha's pass/fail summary (with the names of failing tests) goes first:
  # the annotation is truncated, and the summary is otherwise buried under
  # thousands of Firestore stream lines.
  echo "=== TEST SUMMARY ==="
  awk '/ passing/{f=1} f' "$log" | grep -v -E "GrpcConnection|evaluation error|^false for" | head -40
  echo "=== ERROR LINES ==="
  grep -v -E "GrpcConnection|evaluation error|^false for" "$log" | grep -n -E "^e: |error:|Error:|What went wrong|FAILURE|Execution failed|Could not|not found|Unresolved|Exception|failing|AssertionError|FAIL" | head -40
  echo "=== TAIL ==="
  grep -v -E "GrpcConnection|evaluation error|^false for" "$log" | tail -50
} > /tmp/summary.txt
msg=$(python3 -c "import urllib.parse;print(urllib.parse.quote(open('/tmp/summary.txt').read()[:12000],safe=' /:.,;()[]{}<>=-_\\'\"'))")
echo "::error title=${title}::${msg}"
