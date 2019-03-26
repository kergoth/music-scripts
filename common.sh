# Shell runs its signal handlers after the foreground process exits, delaying
# responsiveness. Run all processes as backgrounded jobs, then wait for them
# to exit, and kill both this process and its children in its handlers. Ex.:
#
#    tmpfile=$(mktemp -t "$scriptname.XXXX") || die
#    trap 'rm -f "$tmpfile"' EXIT
#    trap 'rm -f "$tmpfile"; trap - INT; kill -INT 0' INT
#    trap 'rm -f "$tmpfile"; trap - TERM; kill -TERM 0' TERM

scriptname=${0##*/}

_printf() {
    fmt=$1
    shift
    # shellcheck disable=SC2059
    printf "$scriptname: $fmt" "$@"
}

die() {
    ret=${1:-1}
    if [ $# -gt 1 ]; then
        fmt=$1
        shift
        _printf "Error: $fmt\\n" "$@" >&2
    fi
    exit "$ret"
}

warn() {
    fmt=$1
    shift
    _printf "Warning: $fmt\\n" "$@" >&2
}

info() {
    fmt=$1
    shift
    verbose=${verbose:-0}
    if [ "$verbose" -gt 0 ]; then
        _printf "$fmt\\n" "$@" >&2 || :
    fi
    return 0
}

_assert() {
    env "$@"
    assert_ret=$?
    if [ $assert_ret -ne 0 ]; then
        die 1 'Assertion failed: %s returned %d' "$*" "$assert_ret"
    fi
}

assert() {
    _assert test "$@"
}

run() {
    env "$@" &
    wait $!
}
