#!/usr/bin/env bash
set -euo pipefail

compiler=$1
result_dir=$2
source_dir=$(cd -- "$(dirname -- "$0")/zeroization-residue" && pwd)
mkdir -p "$result_dir"
result_dir=$(cd -- "$result_dir" && pwd)

compile() {
  "$compiler" -std=c11 -msse2 -mno-avx -msahf -fno-stack-protector \
    -Wall -Wextra -Werror -O2 "$@"
}

compile -DCES_FUNCTION=ces_unprotected -c "$source_dir/function.c" \
  -o "$result_dir/control.o"
compile -c "$source_dir/probe.S" -o "$result_dir/probe.o"
for level in 0 2; do
  for frame in omit keep; do
    frame_flag=-fomit-frame-pointer
    if [[ "$frame" == keep ]]; then
      frame_flag=-fno-omit-frame-pointer
    fi
    compile -O"$level" "$frame_flag" -DCES_FUNCTION=ces_protected \
      -DCES_PROTECTED -c "$source_dir/function.c" \
      -o "$result_dir/protected.o"
    compile -DCES_HAVE_PROTECTED "$source_dir/driver.c" \
      "$result_dir/control.o" "$result_dir/protected.o" "$result_dir/probe.o" \
      -o "$result_dir/probe"
    "$result_dir/probe" >"$result_dir/O$level-$frame.log"
    cat "$result_dir/O$level-$frame.log"
  done
done
