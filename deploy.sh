#!/usr/bin/env bash

# Entry point for a fresh machine. Fail-soft by design: a flaky network on one
# step must not abort the install, because the init script chezmoi runs later
# re-attempts the same critical steps (Xcode CLI, Homebrew) with retries.
set -uo pipefail

readonly xcode_cli_tools_marker="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
sudo_keepalive_pid=""

cleanup_xcode_setup() {
    if [[ -n "$sudo_keepalive_pid" ]]; then
        kill "$sudo_keepalive_pid" 2>/dev/null || true
    fi
    rm -f "$xcode_cli_tools_marker"
}

run_sudo() {
    if [[ "${EUID}" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

request_sudo_for_xcode_setup() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo "Requesting sudo access for Xcode setup..."
        sudo -v
        while true; do
            sudo -n true
            sleep 60
            kill -0 "$$" || exit
        done 2>/dev/null &
        sudo_keepalive_pid=$!
    fi
}

# retry <description> <attempts> <command...>: used for steps where a stalled
# download or transient error should not end the run
retry() {
    local desc="$1" max="$2" n=1
    shift 2
    while ! "$@"; do
        if [[ "$n" -ge "$max" ]]; then
            echo "WARN: ${desc} failed after ${max} attempts, continuing..."
            return 1
        fi
        echo "Retrying ${desc} (attempt ${n}/${max}) in 5s..."
        sleep 5
        n=$((n + 1))
    done
}

install_xcode_cli_tools() {
    echo "Installing Xcode Command Line Tools..."
    touch "$xcode_cli_tools_marker"

    local xcode_command_line_tools
    xcode_command_line_tools=$(/usr/sbin/softwareupdate --list 2>&1 | \
        /usr/bin/awk -F: '/Label: Command Line Tools for Xcode/ {print $NF}' | \
        /usr/bin/sed 's/^ *//' | \
        /usr/bin/tail -1)

    if [[ -z "$xcode_command_line_tools" ]]; then
        echo "Unable to find Xcode Command Line Tools in softwareupdate."
        return 1
    fi

    run_sudo /usr/sbin/softwareupdate --install "$xcode_command_line_tools" --agree-to-license
}

accept_xcode_license() {
    if ! command -v xcodebuild >/dev/null 2>&1; then
        echo "xcodebuild not found; skipping Xcode license acceptance."
        return
    fi

    local developer_dir
    developer_dir=$(/usr/bin/xcode-select -p 2>/dev/null || true)

    local xcode_license_output
    if xcode_license_output=$(xcodebuild -license check 2>&1); then
        echo "Xcode license already accepted."
    elif grep -qi "requires Xcode" <<<"$xcode_license_output"; then
        echo "Full Xcode is not selected; Command Line Tools license was accepted during install."
        return
    else
        echo "Accepting Xcode license..."
        run_sudo /usr/bin/xcodebuild -license accept
    fi

    if [[ "$developer_dir" == /Applications/*.app/Contents/Developer ]] && \
        ! /usr/bin/xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
        echo "Running Xcode first-launch tasks..."
        run_sudo /usr/bin/xcodebuild -runFirstLaunch
    fi
}

install_chezmoi() {
    echo "Installing chezmoi..."
    # get.chezmoi.io replaces the retired git.io shortener
    curl -fsSL --retry 3 https://get.chezmoi.io | run_sudo sh -s -- -b /usr/local/bin
}

trap cleanup_xcode_setup EXIT
request_sudo_for_xcode_setup
if pkgutil --pkg-info com.apple.pkg.CLTools_Executables >/dev/null 2>&1; then
    echo "Xcode Command Line Tools already installed."
else
    retry "Xcode Command Line Tools install" 2 install_xcode_cli_tools
fi
accept_xcode_license || echo "WARN: Xcode license steps failed, continuing..."

# Check if chezmoi is installed
if command -v chezmoi >/dev/null 2>&1; then
    echo "Upgrading chezmoi..."
    retry "chezmoi upgrade" 2 chezmoi upgrade || echo "Continuing with the installed chezmoi version..."
else
    retry "chezmoi install" 3 install_chezmoi
fi

# Hard stop: nothing works without chezmoi itself
if ! command -v chezmoi >/dev/null 2>&1; then
    echo "ERROR: chezmoi could not be installed, cannot continue. Re-run deploy.sh once the network recovers."
    exit 1
fi

# Initialize chezmoi; an existing source dir is fine (re-run of deploy.sh) and
# leaves the already-cloned repo in place for apply
if ! retry "chezmoi init" 2 chezmoi init RyoKamui; then
    if [[ -d "$HOME/.local/share/chezmoi/.git" ]]; then
        echo "Using the existing chezmoi source checkout..."
    else
        echo "ERROR: chezmoi repo could not be cloned, cannot continue."
        exit 1
    fi
fi

# Apply configurations using chezmoi. A non-zero exit usually means the
# deployment summary (run_once_after_99_summary) left failed stages re-armed on
# purpose; its printed box explains what to expect, so report instead of
# crashing the tail of the deploy. --keep-going: one failing script must not
# starve the scripts after it (fail-soft end-to-end)
if chezmoi -v apply --keep-going; then
    echo "✓ Deploy complete."
else
    echo -e "\033[1;33m⚠ Deploy finished with incomplete stages — run 'chezmoi apply' again to retry them automatically.\033[0m"
fi

# Post-deploy health check: surfaces permission problems (Full Disk Access,
# Accessibility) and config anomalies that would otherwise only surface at runtime
chezmoi doctor || echo "WARN: 'chezmoi doctor' could not run — run it manually."
