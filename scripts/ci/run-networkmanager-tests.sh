#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly project_root="$(cd "${script_dir}/../.." && pwd)"
readonly networkmanager_log="${TMPDIR:-/tmp}/nmrs-networkmanager.log"
networkmanager_pid=""

cleanup() {
    if [[ -n "${networkmanager_pid}" ]] && kill -0 "${networkmanager_pid}" 2>/dev/null; then
        kill "${networkmanager_pid}" || true
        wait "${networkmanager_pid}" || true
    fi
}

print_networkmanager_log() {
    echo "NetworkManager did not become ready. Its log follows:" >&2
    cat "${networkmanager_log}" >&2 || true
}

trap cleanup EXIT

mkdir -p /run/dbus
dbus-daemon \
    --config-file="${project_root}/scripts/ci/dbus-system.conf" \
    --fork \
    --nopidfile

NetworkManager --no-daemon --log-level=INFO >"${networkmanager_log}" 2>&1 &
networkmanager_pid=$!

for _ in $(seq 1 30); do
    if nmcli --terse --fields RUNNING general 2>/dev/null | grep --quiet '^running$'; then
        break
    fi

    if ! kill -0 "${networkmanager_pid}" 2>/dev/null; then
        print_networkmanager_log
        exit 1
    fi

    sleep 1
done

if ! nmcli --terse --fields RUNNING general 2>/dev/null | grep --quiet '^running$'; then
    print_networkmanager_log
    exit 1
fi

nmcli general status

export NMRS_REQUIRE_NETWORKMANAGER=1

case "${1:-all}" in
    all)
        cargo test --locked --all-features --workspace
        ;;
    integration)
        cargo test --locked --test integration_test --all-features
        ;;
    shell)
        bash
        ;;
    *)
        echo "Usage: $0 [all|integration|shell]" >&2
        exit 2
        ;;
esac
