#!/bin/bash
set -o pipefail

# Ensure script runs from the OpenWrt repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

# --- CONFIGURATION (SECURE) ---
# Load secrets from a local file if it exists.
# This file should be added to your .gitignore.
if [ -f ".build_env" ]; then
    # shellcheck source=/dev/null
    source .build_env
fi

# --- CONFIGURATION (Fill these in or set in .build_env to enable notifications) ---
# DISCORD_WEBHOOK=""
# TELEGRAM_TOKEN=""
# TELEGRAM_CHAT_ID=""
# ------------------------------

if [ "${DEBUG}" = "true" ]; then set -x; fi

# Default core heuristic with fallbacks for minimal environments
num_cores=$(($(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1) + 1))

command_action=""
build_target=""
download_pkgs=true
fetch_router_conf=false

show_usage() {
    echo "Usage: $0 {official|custom|rebuild|rebuild-ignore|clean-min|clean-toolchain|clean-full} [target] [-j cores] [nodownload] [routerconf]"
    echo "------------------------------------------------------------------------------------------------"
    echo "official:        Specify target (e.g., ramips/mt7621) using standard OpenWrt config."
    echo "custom:          Uses Custom.config."
    echo "rebuild:         Run make defconfig and incremental build with error filtering."
    echo "rebuild-ignore:  Same as rebuild but continues past errors (-i)."
    echo "clean-min:       Runs 'make dirclean'."
    echo "clean-toolchain: Runs 'make dirclean' (backward compatibility)."
    echo "clean-full:      Runs 'make distclean' (Caution: wipes everything!)."
    echo "-j <cores>:      Specify number of CPU cores."
    echo "nodownload:      Skip downloading package sources."
    echo "routerconf:      Fetch config from a live router."
}

# --- UNIFIED ARGUMENT PARSER (Supports flags in any position) ---
while [ $# -gt 0 ]; do
    case "$1" in
        -j)
            if [ -n "$2" ] && [ "$2" -eq "$2" ] 2>/dev/null; then
                num_cores="$2"
                shift 2
            else
                echo "Error: -j requires a numeric argument." >&2
                exit 1
            fi
            ;;
        -j*)
            num_cores="${1#-j}"
            if ! [ "$num_cores" -eq "$num_cores" ] 2>/dev/null; then
                echo "Error: -j requires a numeric argument." >&2
                exit 1
            fi
            shift
            ;;
        nodownload|--nodownload|--no-download)
            download_pkgs=false
            shift
            ;;
        routerconf|--routerconf|--router-conf)
            fetch_router_conf=true
            shift
            ;;
        -d|--debug|debug)
            set -x
            shift
            ;;
        -h|--help|help)
            show_usage
            exit 0
            ;;
        official|custom|rebuild|rebuild-ignore|clean-min|clean-toolchain|clean-full)
            if [ -z "$command_action" ]; then
                command_action="$1"
                shift
                # If command is 'official', capture the target if provided next
                if [ "$command_action" = "official" ] && [ $# -gt 0 ] && [[ ! "$1" =~ ^- ]] && [ "$1" != "nodownload" ] && [ "$1" != "routerconf" ]; then
                    build_target="$1"
                    shift
                fi
            else
                echo "Error: Multiple commands specified ('$command_action' and '$1')." >&2
                exit 1
            fi
            ;;
        *)
            if [ "$command_action" = "official" ] && [ -z "$build_target" ]; then
                build_target="$1"
                shift
            else
                echo "Unknown argument: $1" >&2
                show_usage
                exit 1
            fi
            ;;
    esac
done

if [ -z "$command_action" ]; then
    show_usage
    exit 1
fi

# --- HELPER FUNCTIONS ---

format_duration() {
    local total_seconds=$1
    local minutes=$(( total_seconds / 60 ))
    local seconds=$(( total_seconds % 60 ))
    if [ "$minutes" -gt 0 ]; then
        echo "${minutes}m ${seconds}s"
    else
        echo "${seconds}s"
    fi
}

get_build_version() {
    local num=""
    local rev=""

    if [ -f ".config" ]; then
        num=$(grep '^CONFIG_VERSION_NUMBER=' .config 2>/dev/null | cut -d= -f2 | tr -d '"')
    fi

    # Fallback to version.mk if not explicitly set in .config
    if [ -z "$num" ] && [ -f "include/version.mk" ]; then
        # Default is the last argument of: VERSION_NUMBER:=$(if $(VERSION_NUMBER),$(VERSION_NUMBER),<default>)
        num=$(grep -m1 '^VERSION_NUMBER:=$(if ' include/version.mk 2>/dev/null | sed -n 's/.*,\([^,()]*\))[[:space:]]*$/\1/p')
    fi
    [ -z "$num" ] && num="unknown"

    if [ -x "./scripts/getver.sh" ]; then
        rev=$(./scripts/getver.sh 2>/dev/null)
    fi

    if [ -n "$rev" ]; then
        echo "${num}-${rev}"
    else
        echo "$num"
    fi
}

notify() {
    local status=$1
    local duration=$2
    local build_type=$3
    local build_version=$4
    local build_host
    build_host=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "unknown")
    local finish_time
    finish_time=$(date "+%Y-%m-%d %H:%M:%S")

    # Discord Notification (Safe JSON escaping)
    if [ -n "$DISCORD_WEBHOOK" ]; then
        local raw_content="🚀 **OpenWrt Build Report**
**Host:** $build_host
**Target:** $build_type
**Version:** $build_version
**Status:** $status
**Duration:** $duration
**Finished:** $finish_time"

        local discord_json
        if command -v jq >/dev/null 2>&1; then
            discord_json=$(jq -n --arg content "$raw_content" '{"content": $content}')
        else
            local escaped_content
            escaped_content=$(printf '%s' "$raw_content" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n')
            discord_json="{\"content\": \"$escaped_content\"}"
        fi

        curl -s -S --connect-timeout 10 --max-time 30 \
            -H "Content-Type: application/json" \
            -X POST -d "$discord_json" "$DISCORD_WEBHOOK" > /dev/null 2>&1 || true
    fi

    # Telegram Notification (HTML parse mode prevents parse errors caused by underscores/symbols)
    if [ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        local tg_html="🚀 <b>OpenWrt Build Report</b>
<b>Host:</b> ${build_host}
<b>Target:</b> ${build_type}
<b>Version:</b> ${build_version}
<b>Status:</b> ${status}
<b>Duration:</b> ${duration}
<b>Finished:</b> ${finish_time}"

        curl -s -S --connect-timeout 10 --max-time 30 \
            -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
            -d "chat_id=${TELEGRAM_CHAT_ID}" \
            -d "parse_mode=HTML" \
            --data-urlencode "text=${tg_html}" > /dev/null 2>&1 || true
    fi
}

run_build_logic() {
    local type_label=$1
    local start_time
    start_time=$(date +%s)

    echo "Starting build: $type_label with $num_cores cores..."

    make -j"${num_cores}" V=s CONFIG_DEBUG_SECTION_MISMATCH=y world 2>&1 | tee build.log
    local exit_code=${PIPESTATUS[0]}

    local end_time
    end_time=$(date +%s)
    local duration
    duration=$(format_duration $(( end_time - start_time )))
    local build_version
    build_version=$(get_build_version)

    if [ "$exit_code" -eq 0 ]; then
        notify "✅ SUCCESS" "$duration" "$type_label" "$build_version"
        echo "-------------------------------------------------------"
        echo "BUILD SUCCESSFUL ($duration) [$build_version]"
        echo "-------------------------------------------------------"
    else
        notify "❌ FAILED" "$duration" "$type_label" "$build_version"
        echo "-------------------------------------------------------"
        echo "BUILD FAILED ($duration) [$build_version]. Check build.log for errors."
        echo "-------------------------------------------------------"
        exit 1
    fi
}

prepare_feeds() {
    echo "Updating and installing feeds..."
    if ! ./scripts/feeds update -a; then
        echo "Error: Feeds update failed." >&2
        return 1
    fi
    if ! ./scripts/feeds install -a; then
        echo "Error: Feeds install failed." >&2
        return 1
    fi
}

build_step_safe() {
    local target_step=$1
    echo "Pre-building $target_step (Safety Step: -j${num_cores})..."
    if ! make "$target_step" -j"${num_cores}" 2>&1 | tee -a build.log; then
        echo "Parallel build for $target_step failed. Retrying with single core (-j1 V=s) for debug..."
        if ! make "$target_step" -j1 V=s 2>&1 | tee -a build.log; then
            echo "Error: Build failed at step '$target_step'." >&2
            return 1
        fi
    fi
}

build_toolchain_safe() {
    build_step_safe "tools/install" || return 1
    build_step_safe "toolchain/install" || return 1
}

# --- COMMAND IMPLEMENTATIONS ---

build_official() {
    local target=$1
    if [ -z "$target" ]; then
        echo "Usage: $0 official <target> (e.g. ramips/mt7621)" >&2
        exit 1
    fi

    prepare_feeds || exit 1

    echo "Copying OpenWrt official config..."
    local release
    release=$(grep -m1 '$(VERSION_REPO),' include/version.mk 2>/dev/null | awk -F, '{print $3}' | tr -d ')' | tr -d ' ')
    if [ -z "$release" ]; then
        release="https://downloads.openwrt.org/snapshots"
        echo "Warning: Could not detect VERSION_REPO from include/version.mk; falling back to $release"
    fi

    local config_url="$release/targets/$target/config.buildinfo"
    echo "Downloading config from: $config_url"
    if ! wget --timeout=30 -q --show-progress "$config_url" -O .config; then
        echo "Error: Failed to download config from $config_url" >&2
        echo "Please verify target name '$target' and release URL." >&2
        rm -f .config
        exit 1
    fi

    echo "Setting default configuration..."
    make defconfig

    if [ "$download_pkgs" = true ]; then
        echo "Downloading packages before build..."
        make download -j"${num_cores}" || make download
    fi

    build_toolchain_safe || exit 1
    run_build_logic "Official-$target"
}

build_custom() {
    prepare_feeds || exit 1

    if [ "$fetch_router_conf" = true ]; then
        echo "Grabbing /etc/build.config from your router..."
        local routerip="${ROUTER_IP:-}"
        local user="${ROUTER_USER:-}"

        if [ -z "$routerip" ]; then
            read -r -p "Enter your router hostname or IP address: " routerip
        fi
        if [ -z "$routerip" ]; then
            echo "Error: Router IP/hostname cannot be empty." >&2
            exit 1
        fi

        if [ -z "$user" ]; then
            read -r -p "Enter username [root]: " user
            user="${user:-root}"
        fi

        echo "Attempting to grab /etc/build.config from $user@$routerip..."
        if scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$user@$routerip:/etc/build.config" Custom.config; then
            echo "SCP of /etc/build.config to Custom.config was successful!"
        else
            echo "Error: SCP failed. Please check network, username, hostname, and ensure /etc/build.config exists on the router." >&2
            exit 1
        fi
    fi

    if [ -f "Custom.config" ]; then
        cp Custom.config .config
    else
        echo "Error: Custom.config does not exist!" >&2
        exit 1
    fi

    echo "Setting default configuration..."
    make defconfig

    if [ "$download_pkgs" = true ]; then
        echo "Downloading packages before build..."
        make download -j"${num_cores}" || make download
    fi

    build_toolchain_safe || exit 1
    run_build_logic "Custom-Build"
}

build_rebuild() {
    make defconfig
    echo "Start build and log to build.log (real-time error filter)..."
    make -j"${num_cores}" V=s CONFIG_DEBUG_SECTION_MISMATCH=y 2>&1 | tee build.log | grep --line-buffered -i -E "^make.*(error|[12345]...Entering dir)"
    local exit_code=${PIPESTATUS[0]}
    if [ "$exit_code" -ne 0 ]; then
        echo "Rebuild finished with errors (code $exit_code). Check build.log for details." >&2
        return "$exit_code"
    fi
}

build_rebuild_ignore() {
    make defconfig
    echo "Start build and log to build.log - Ignoring build errors..."
    make -i -j"${num_cores}" V=s CONFIG_DEBUG_SECTION_MISMATCH=y 2>&1 | tee build.log | grep --line-buffered -i -E "^make.*(error|[12345]...Entering dir)"
    return "${PIPESTATUS[0]}"
}

clean_min() {
    echo "Cleaning: dirclean..."
    make dirclean
}

clean_full() {
    echo "Cleaning: distclean (Full)..."
    make distclean
}

# --- DISPATCH ---
case "$command_action" in
    official)         build_official "$build_target" ;;
    custom)           build_custom ;;
    rebuild)          build_rebuild ;;
    rebuild-ignore)   build_rebuild_ignore ;;
    clean-min)        clean_min ;;
    clean-toolchain)  clean_min ;; # Kept for backward compatibility
    clean-full)       clean_full ;;
    *)                show_usage; exit 1 ;;
esac
