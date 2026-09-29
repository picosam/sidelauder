#!/bin/sh
# S16: end-to-end cost of one adapter call, spawned the way the app will spawn
# it (spec §8.1.2): an empty environment except PATH = node's directory plus
# /usr/bin:/bin. Prints one line per mode with milliseconds; no names, no paths.
#
# Usage: spikes/s16/endtoend.sh <node> <claude-multiprofile executable> [runs]
node="$1"; cmp="$2"; runs="${3:-20}"
adapter="$(cd "$(dirname "$0")/../.." && pwd)/App/Sidelauder/upstream-status.mjs"
path="$(dirname "$node"):/usr/bin:/bin"
for mode in default --full; do
  arg=""; [ "$mode" = "--full" ] && arg="--full"
  ms=""
  i=0
  while [ "$i" -lt "$runs" ]; do
    s=$(/usr/bin/perl -MTime::HiRes=time -e 'printf "%.3f", time')
    env -i PATH="$path" "$node" "$adapter" "$cmp" $arg > /dev/null || { echo "run failed: $mode"; exit 1; }
    e=$(/usr/bin/perl -MTime::HiRes=time -e 'printf "%.3f", time')
    ms="$ms $(echo "($e - $s) * 1000" | bc)"
    i=$((i + 1))
  done
  echo "$mode:$ms" | /usr/bin/perl -ne 'my ($m, $r) = split /:/; my @v = sort { $a <=> $b } split " ", $r;
    printf "%s runs=%d first=%.0f min=%.0f median=%.0f p95=%.0f max=%.0f ms\n", $m, scalar @v,
      (split " ", $r)[0], $v[0], $v[int(@v/2)], $v[int(@v*0.95)-1 < 0 ? 0 : int(@v*0.95)-1], $v[-1];'
done
