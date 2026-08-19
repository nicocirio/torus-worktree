#!/usr/bin/env bats
#
# relative_time is a shared helper behind CREATED/LAST COMMIT (used by both
# `list` and `remove --select`), not tied to one subcommand — so it gets its
# own file rather than living in list.bats or select_interactive.bats.
#
# It's extracted and eval'd directly instead of exercised end-to-end:
# proving the old week/month/year buckets stay gone means checking gaps of
# 9+/30+/365+ days, and faking a worktree directory's *birth time* that far
# back isn't something `touch` can do (immutable metadata on APFS). The
# function is a pure epoch-in/string-out helper, so testing it directly is
# equivalent and far faster.

load test_helper

load_relative_time() {
  eval "$(sed -n '/^relative_time() {/,/^}/p' "$WT")"
}

@test "relative_time: just now, minutes, hours, then always plain days" {
  load_relative_time
  now="$(date +%s)"
  [ "$(relative_time "$now")" = "just now" ]
  [ "$(relative_time $((now - 300)))" = "5 minutes ago" ]
  [ "$(relative_time $((now - 60)))" = "1 minute ago" ]
  [ "$(relative_time $((now - 3600)))" = "1 hour ago" ]
  [ "$(relative_time $((now - 7200)))" = "2 hours ago" ]
  [ "$(relative_time $((now - 86400)))" = "1 day ago" ]
  [ "$(relative_time $((now - 777600)))" = "9 days ago" ]
}

@test "relative_time: two gaps that used to collide in the same 'week' bucket now differ" {
  load_relative_time
  now="$(date +%s)"
  nine_days="$(relative_time $((now - 777600)))"
  thirteen_days="$(relative_time $((now - 1123200)))"
  [ "$nine_days" = "9 days ago" ]
  [ "$thirteen_days" = "13 days ago" ]
  [ "$nine_days" != "$thirteen_days" ]
}

@test "relative_time: never rounds up to weeks, months, or years" {
  load_relative_time
  now="$(date +%s)"
  for secs in 604800 1209600 5000000 70000000; do
    result="$(relative_time $((now - secs)))"
    [[ "$result" == *" days ago" || "$result" == "1 day ago" ]]
    [[ "$result" != *week* && "$result" != *month* && "$result" != *year* ]]
  done
  # ~2 years: still a plain day count, not "2 years ago"
  [ "$(relative_time $((now - 70000000)))" = "810 days ago" ]
}
