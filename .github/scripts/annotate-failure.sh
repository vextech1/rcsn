#!/usr/bin/env bash
# Usage: annotate-failure.sh <title> <logfile>
# Emits one ::error annotation holding the error lines and tail of a log, so a
# failed step can be diagnosed from the check-run annotations API.
title="$1"; log="$2"
{
  echo "=== ERROR LINES ==="
  grep -n -E "^e: |error:|Error:|What went wrong|FAILURE|Execution failed|Could not|not found|Unresolved|Exception|failing|AssertionError|FAIL" "$log" | head -60
  echo "=== TAIL ==="
  tail -60 "$log"
} > /tmp/summary.txt
msg=$(python3 -c "import urllib.parse;print(urllib.parse.quote(open('/tmp/summary.txt').read()[:12000],safe=' /:.,;()[]{}<>=-_\\'\"'))")
echo "::error title=${title}::${msg}"
