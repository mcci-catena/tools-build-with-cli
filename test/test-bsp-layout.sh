#!/bin/bash

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/tools-build-with-cli-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

run_setup() {
    local data="$1"
    mkdir -p "$data/packages/mcci/hardware/stm32" "$data/packages/mcci/tools/arm-none-eabi-gcc/test/bin" "$data/local-core"
    touch "$data/packages/mcci/tools/arm-none-eabi-gcc/test/bin/arm-none-eabi-gcc"
    chmod +x "$data/packages/mcci/tools/arm-none-eabi-gcc/test/bin/arm-none-eabi-gcc"
    (
        source "$ROOT/build-with-cli-lib.sh"
        OPTVERBOSE=0
        BSP_MCCI="$data/packages/mcci"
        BSP_CORE="$BSP_MCCI/hardware/stm32/"
        LOCAL_BSP_CORE="$data/local-core"
        PRIVATE_KEY_UNLOCKED=""
        ACTIVE_BSP_LINK=""
        SAVE_BSP_CORE=""
        BSP_LOCK_DIR=""
        trap '_cleanup_trap' EXIT
        _setupBsp
    )
}

empty="$TEST_ROOT/empty"
mkdir -p "$empty/packages/mcci/hardware/stm32-2.8.0"
if run_setup "$empty" 2>"$empty.err"; then
    fail "empty BSP directory succeeded"
fi
grep -q "No installed BSP version" "$empty.err" || fail "empty layout error was unclear"
grep -q "stm32-2.8.0" "$empty.err" || fail "empty layout did not name the saved BSP"
[[ ! -e "$empty/packages/mcci/hardware/stm32/*" ]] || fail "empty layout created a '*' entry"
[[ ! -d "$empty/packages/mcci/.tools-build-with-cli.lock" ]] || fail "empty layout left its lock"

multiple="$TEST_ROOT/multiple"
mkdir -p "$multiple/packages/mcci/hardware/stm32/2.7.0" "$multiple/packages/mcci/hardware/stm32/2.8.0"
if run_setup "$multiple" 2>"$multiple.err"; then
    fail "multiple BSP directories succeeded"
fi
grep -q "Multiple BSP versions" "$multiple.err" || fail "multiple layout error was unclear"
[[ -d "$multiple/packages/mcci/hardware/stm32/2.7.0" ]] || fail "multiple layout changed 2.7.0"
[[ -d "$multiple/packages/mcci/hardware/stm32/2.8.0" ]] || fail "multiple layout changed 2.8.0"

normal="$TEST_ROOT/normal"
mkdir -p "$normal/packages/mcci/hardware/stm32/2.7.0"
run_setup "$normal"
[[ -d "$normal/packages/mcci/hardware/stm32/2.7.0" ]] || fail "cleanup did not restore the BSP"
[[ ! -h "$normal/packages/mcci/hardware/stm32/2.8.0" ]] || fail "cleanup left the overlay link"
[[ ! -d "$normal/packages/mcci/.tools-build-with-cli.lock" ]] || fail "cleanup left its lock"

locked="$TEST_ROOT/locked"
mkdir -p "$locked/packages/mcci/hardware/stm32/2.7.0" "$locked/packages/mcci/.tools-build-with-cli.lock"
printf 'other\n' > "$locked/packages/mcci/.tools-build-with-cli.lock/pid"
if run_setup "$locked" 2>"$locked.err"; then
    fail "concurrent BSP setup succeeded"
fi
grep -q "Another tools-build-with-cli process" "$locked.err" || fail "lock error was unclear"
[[ -d "$locked/packages/mcci/hardware/stm32/2.7.0" ]] || fail "locked layout was changed"

echo "BSP layout tests passed"
