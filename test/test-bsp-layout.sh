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
        PNAME=test-bsp-layout
        OPTVERBOSE="${OPTVERBOSE:-0}"
        BSP_MCCI="$data/packages/mcci"
        BSP_CORE="$BSP_MCCI/hardware/stm32/"
        LOCAL_BSP_CORE="$data/local-core"
        PRIVATE_KEY_UNLOCKED=""
        ACTIVE_BSP_LINK=""
        SAVE_BSP_CORE=""
        BSP_LOCK_DIR=""
        trap '_cleanup_trap' EXIT
        _setupBsp
        ls -A "$BSP_CORE" > "$data/during-setup"
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
run_setup "$normal" 2>"$normal.err" || fail "normal setup failed: $(cat "$normal.err")"
[[ -d "$normal/packages/mcci/hardware/stm32/2.7.0" ]] || fail "cleanup did not restore the BSP"
[[ ! -h "$normal/packages/mcci/hardware/stm32/2.8.0" ]] || fail "cleanup left the overlay link"
[[ ! -d "$normal/packages/mcci/.tools-build-with-cli.lock" ]] || fail "cleanup left its lock"

[[ "$(cat "$normal/during-setup")" == "2.8.0" ]] || fail "link without a platform.txt version was not named 2.8.0"

# the link takes its name from the local BSP's platform.txt version
named="$TEST_ROOT/named"
mkdir -p "$named/packages/mcci/hardware/stm32/3.0.5" "$named/local-core"
printf 'name=MCCI Catena STM32 Boards\r\nversion=3.3.1-pre2\r\n' > "$named/local-core/platform.txt"
run_setup "$named" 2>"$named.err" || fail "named link setup failed: $(cat "$named.err")"
[[ "$(cat "$named/during-setup")" == "3.3.1-pre2" ]] || fail "link was not named for the platform.txt version: $(cat "$named/during-setup")"
[[ -d "$named/packages/mcci/hardware/stm32/3.0.5" ]] || fail "named-link build did not restore the BSP"
[[ ! -e "$named/packages/mcci/hardware/stm32/3.3.1-pre2" ]] || fail "named-link build left its link"

# an unusable version falls back to 2.8.0, with a warning
badver="$TEST_ROOT/badver"
mkdir -p "$badver/packages/mcci/hardware/stm32/3.0.5" "$badver/local-core"
printf 'version=latest\n' > "$badver/local-core/platform.txt"
run_setup "$badver" 2>"$badver.err" || fail "bad-version setup failed: $(cat "$badver.err")"
[[ "$(cat "$badver/during-setup")" == "2.8.0" ]] || fail "unusable version did not fall back to 2.8.0"
grep -q "naming the BSP link 2.8.0" "$badver.err" || fail "fallback to 2.8.0 was not reported"

# a lock held by a running process stops the build and names the PID
sleep 60 &
live_pid=$!
locked="$TEST_ROOT/locked"
lock="$locked/packages/mcci/.tools-build-with-cli.lock"
mkdir -p "$locked/packages/mcci/hardware/stm32/2.7.0" "$lock"
printf '%s\n' "$live_pid" > "$lock/pid"
if run_setup "$locked" 2>"$locked.err"; then
    kill "$live_pid" 2>/dev/null || true
    fail "concurrent BSP setup succeeded"
fi
kill "$live_pid" 2>/dev/null || true
wait "$live_pid" 2>/dev/null || true
grep -q "Another tools-build-with-cli process" "$locked.err" || fail "lock error was unclear"
grep -q "PID $live_pid" "$locked.err" || fail "lock error did not name the holder's PID"
[[ -d "$locked/packages/mcci/hardware/stm32/2.7.0" ]] || fail "locked layout was changed"
[[ "$(cat "$lock/pid")" == "$live_pid" ]] || fail "refused build released the other build's lock"

# a lock left by a process that is no longer running is taken over
sleep 0 &
dead_pid=$!
wait "$dead_pid"
stale="$TEST_ROOT/stale"
lock="$stale/packages/mcci/.tools-build-with-cli.lock"
mkdir -p "$stale/packages/mcci/hardware/stm32/2.7.0" "$lock"
printf '%s\n' "$dead_pid" > "$lock/pid"
OPTVERBOSE=1 run_setup "$stale" 2>"$stale.err" || fail "stale lock was not taken over: $(cat "$stale.err")"
grep -q "stale (PID $dead_pid is not running)" "$stale.err" || fail "stale lock takeover was not reported"
[[ -d "$stale/packages/mcci/hardware/stm32/2.7.0" ]] || fail "stale-lock build did not restore the BSP"
[[ ! -d "$lock" ]] || fail "stale-lock build left its lock"
compgen -G "$lock.stale.*" > /dev/null && fail "stale-lock build left the old lock behind"

# a lock without a usable PID stops the build and names the lock directory
invalid="$TEST_ROOT/invalid"
lock="$invalid/packages/mcci/.tools-build-with-cli.lock"
mkdir -p "$invalid/packages/mcci/hardware/stm32/2.7.0" "$lock"
printf 'garbage\n' > "$lock/pid"
if run_setup "$invalid" 2>"$invalid.err"; then
    fail "lock without a valid PID was ignored"
fi
grep -qF "$lock" "$invalid.err" || fail "invalid-lock error did not name the lock directory"
[[ -d "$invalid/packages/mcci/hardware/stm32/2.7.0" ]] || fail "invalid-lock layout was changed"

# a link and a saved BSP left by a build that died: the saved BSP is taken
# over and restored, and the link is replaced, not followed
dead="$TEST_ROOT/dead"
mkdir -p "$dead/packages/mcci/hardware/stm32-2.7.0" "$dead/packages/mcci/hardware/stm32" "$dead/other-core"
ln -s "$dead/other-core" "$dead/packages/mcci/hardware/stm32/2.8.0"
run_setup "$dead" 2>"$dead.err" || fail "stale link with a saved BSP failed: $(cat "$dead.err")"
grep -q "stm32-2.7.0 will be restored" "$dead.err" || fail "takeover of the saved BSP was not reported"
[[ -d "$dead/packages/mcci/hardware/stm32/2.7.0" ]] || fail "saved BSP was not restored"
[[ ! -e "$dead/packages/mcci/hardware/stm32-2.7.0" ]] || fail "saved BSP was left beside stm32"
[[ ! -h "$dead/packages/mcci/hardware/stm32/2.8.0" ]] || fail "stale link was left"
[[ -z "$(ls -A "$dead/other-core")" ]] || fail "ln followed the stale link into its target"
[[ -z "$(ls -A "$dead/local-core")" ]] || fail "ln created a link inside the local core"
[[ ! -d "$dead/packages/mcci/.tools-build-with-cli.lock" ]] || fail "stale-link build left its lock"

# a stale link under an old name is replaced by one named for the version
renamed="$TEST_ROOT/renamed"
mkdir -p "$renamed/packages/mcci/hardware/stm32-3.0.5" "$renamed/packages/mcci/hardware/stm32" "$renamed/other-core" "$renamed/local-core"
printf 'version=3.3.1-pre2\n' > "$renamed/local-core/platform.txt"
ln -s "$renamed/other-core" "$renamed/packages/mcci/hardware/stm32/2.8.0"
run_setup "$renamed" 2>"$renamed.err" || fail "stale link rename failed: $(cat "$renamed.err")"
[[ "$(cat "$renamed/during-setup")" == "3.3.1-pre2" ]] || fail "stale link was not replaced by a named link: $(cat "$renamed/during-setup")"
[[ "$(ls -A "$renamed/packages/mcci/hardware/stm32")" == "3.0.5" ]] || fail "stale-link rename did not leave the saved BSP alone in stm32"

# a link with several saved BSPs stops the build and names them
several="$TEST_ROOT/several"
mkdir -p "$several/packages/mcci/hardware/stm32-2.6.0" "$several/packages/mcci/hardware/stm32-2.7.0" "$several/packages/mcci/hardware/stm32" "$several/other-core"
ln -s "$several/other-core" "$several/packages/mcci/hardware/stm32/2.8.0"
if run_setup "$several" 2>"$several.err"; then
    fail "stale link with several saved BSPs succeeded"
fi
grep -q "stm32-2.6.0" "$several.err" && grep -q "stm32-2.7.0" "$several.err" || fail "several-saved error did not name the saved BSPs"
[[ -h "$several/packages/mcci/hardware/stm32/2.8.0" ]] || fail "several-saved layout was changed"
[[ -d "$several/packages/mcci/hardware/stm32-2.6.0" ]] && [[ -d "$several/packages/mcci/hardware/stm32-2.7.0" ]] || fail "several-saved layout lost a saved BSP"

echo "BSP layout tests passed"
