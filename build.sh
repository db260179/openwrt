#!/bin/bash

# --- CONFIGURATION (SECURE) ---
# Load secrets from a local file if it exists.
# This file should be added to your .gitignore.
if [ -f ".build_env" ]; then
    source .build_env
fi

# --- CONFIGURATION (Fill these in to enable notifications) ---
# Discord Webhook URL
#DISCORD_WEBHOOK=""
# Telegram Settings (Bot Token and Chat ID)
#TELEGRAM_TOKEN=""
#TELEGRAM_CHAT_ID=""
# ------------------------------

if [ "${DEBUG}" == "true" ]; then set -x; fi

num_cores=$(($(nproc) + 1))

while getopts ":j:" opt; do
  case $opt in
    j) num_cores="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
  esac
done
shift $((OPTIND -1))
arguments=("$@")

# --- HELPER FUNCTIONS ---

notify() {
    local status=$1
    local duration=$2
    local build_type=$3
    local build_host=$(hostname)
    local finish_time=$(date "+%Y-%m-%d %H:%M:%S") # Captures current local time

    # Telegram message (URL-encoded %0A for newlines)
    local msg="🚀 *OpenWrt Build Report*%0A*Host:* $build_host%0A*Target:* $build_type%0A*Status:* $status%0A*Duration:* $duration%0A*Finished:* $finish_time"

    # Discord Notification
    if [ -n "$DISCORD_WEBHOOK" ]; then
        local discord_msg="{\"content\": \"🚀 **OpenWrt Build Report**\n**Host:** $build_host\n**Target:** $build_type\n**Status:** $status\n**Duration:** $duration\n**Finished:** $finish_time\"}"
        curl -H "Content-Type: application/json" -X POST -d "$discord_msg" "$DISCORD_WEBHOOK" > /dev/null 2>&1
    fi

    # Telegram Notification
    if [ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
            -d "chat_id=$TELEGRAM_CHAT_ID" \
            -d "text=$msg" -d "parse_mode=Markdown" > /dev/null 2>&1
    fi
}

run_build_logic() {
    local type_label=$1
    local start_time=$(date +%s)

    echo "Starting build: $type_label with $num_cores cores..."

    make -j${num_cores} V=s CONFIG_DEBUG_SECTION_MISMATCH=y world 2>&1 | tee build.log

    local exit_code=${PIPESTATUS[0]}
    local end_time=$(date +%s)
    local duration=$(( (end_time - start_time) / 60 ))

    if [ $exit_code -eq 0 ]; then
        notify "✅ SUCCESS" "${duration} min" "$type_label"
        echo "-------------------------------------------------------"
        echo "BUILD SUCCESSFUL (${duration} min)"
        echo "-------------------------------------------------------"
    else
        notify "❌ FAILED" "${duration} min" "$type_label"
        echo "-------------------------------------------------------"
        echo "BUILD FAILED (${duration} min). Check build.log for errors."
        echo "-------------------------------------------------------"
        exit 1
    fi
}

prepare_feeds() {
    echo "Updating and installing feeds..."
    ./scripts/feeds update -a && ./scripts/feeds install -a
}

build_toolchain_safe() {
    echo "Pre-building Toolchain (Safety Step)..."
    make tools/install -j${num_cores} || make tools/install -j1 V=s 2>&1 | tee -a build.log
    make toolchain/install -j${num_cores} || make toolchain/install -j1 V=s 2>&1 | tee -a build.log
}

build-official () {
    target=$1
    if [ -z "$target" ]; then
        echo "Usage: $0 official <target> (e.g. ramips/mt7621)"
        exit 1
    fi
    prepare_feeds
    echo "Copy Openwrt official config..."
    release=$(grep -m1 '$(VERSION_REPO),' include/version.mk | awk -F, '{print $3}' | tr -d ')')
    wget "$release/targets/$target/config.buildinfo" -O .config
    echo "Set to use default config"
    make defconfig
    echo "Download packages before build"
    [[ ! " ${arguments[@]} " =~ "nodownload" ]] && make download
    build_toolchain_safe
    run_build_logic "Official-$target"
}

build-custom () {
    prepare_feeds
    if [[ " ${arguments[@]} " =~ "routerconf" ]]; then
        echo "Grabbing /etc/build.config from your router!"
        echo "Enter your router hostname or IP address:"
        read -r routerip
        echo "Router hostname or IP address: $routerip"
        echo "Enter username:"
        read -r user
        echo "Username: $user"
        echo "Attempting to grab /etc/build.config from $routerip"
        scp -3 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "$user@$routerip:/etc/build.config" Custom.config

        if [ $? -eq 0 ]; then
            echo "SCP of /etc/build.config to Custom.config was successful!"
        else
            echo "Something went wrong? Check username or hostname."
            echo "Check your build config has the /etc/build.config stored on the router."
            exit 1
        fi
    fi

    if [ -f "Custom.config" ]; then
        cp Custom.config .config
    else
        echo "Custom.config does not exist!"
        exit 1
    fi

    echo "Set to use default config"
    make defconfig
    echo "Download packages before build"
    [[ ! " ${arguments[@]} " =~ "nodownload" ]] && make download
    build_toolchain_safe
    run_build_logic "Custom-Build"
}

build-rebuild () {
    make defconfig
    echo "Start build and log to build.log"
    make -j${num_cores} V=s CONFIG_DEBUG_SECTION_MISMATCH=y 2>&1 | tee build.log | grep -i -E "^make.*(error|[12345]...Entering dir)"
}

build-rebuild-ignore () {
    make defconfig
    echo "Start build and log to build.log - Ignoring build errors..."
    make -i -j${num_cores} V=s CONFIG_DEBUG_SECTION_MISMATCH=y 2>&1 | tee build.log | grep -i -E "^make.*(error|[12345]...Entering dir)"
}

clean-min () {
    echo "Cleaning: dirclean..."
    make dirclean
}

clean-full () {
    echo "Cleaning: distclean (Full)..."
    make distclean
}

case "$1" in
    official)         build-official "$2" ;;
    custom)           build-custom ;;
    rebuild)          build-rebuild ;;
    rebuild-ignore)   build-rebuild-ignore ;;
    clean-min)        clean-min ;;
    clean-toolchain)  make dirclean ;; # Kept for backward compatibility
    clean-full)       clean-full ;;
    *)
        echo "Usage: $0 {official|custom|rebuild|rebuild-ignore|clean-min|clean-full} <target> [-j cores] [nodownload] [routerconf]"
        echo "------------------------------------------------------------------------------------------------"
        echo "official:       Specify target (e.g., ramips/mt7621) using standard OpenWrt config."
        echo "custom:         Uses Custom.config."
        echo "rebuild:        Run make defconfig and incremental build with error filtering."
        echo "rebuild-ignore: Same as rebuild but continues past errors (-i)."
        echo "clean-min:      Runs 'make dirclean'."
        echo "clean-full:     Runs 'make distclean' (Caution: wipes everything!)."
        echo "-j <cores>:     Specify number of CPU cores."
        echo "nodownload:     Skip downloading package sources."
        echo "routerconf:     Fetch config from a live router."
        exit 1
        ;;
esac