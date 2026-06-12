#!/bin/bash

# --- CONFIGURATION (SECURE) ---
# Load secrets from a local file if it exists.
# This file should be added to your .gitignore.
# --- CONFIGURATION (Fill these in to enable notifications) ---
# Discord Webhook URL
#DISCORD_WEBHOOK=""
# Telegram Settings (Bot Token and Chat ID)
#TELEGRAM_TOKEN=""
#TELEGRAM_CHAT_ID=""
# -------------------------------------------------------------
if [ -f ".build_env" ]; then
    source .build_env
fi

# Fallback: If variables aren't in the file, the script will
# naturally use variables already exported in your shell (env).
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
    local msg="🚀 *OpenWrt Build Report*%0A*Target:* $build_type%0A*Status:* $status%0A*Duration:* $duration"

    # Discord Notification (Uses $DISCORD_WEBHOOK from local env)
    if [ -n "$DISCORD_WEBHOOK" ]; then
        local discord_msg="{\"content\": \"🚀 **OpenWrt Build Report**\n**Target:** $build_type\n**Status:** $status\n**Duration:** $duration\"}"
        curl -H "Content-Type: application/json" -X POST -d "$discord_msg" "$DISCORD_WEBHOOK" > /dev/null 2>&1
    fi

    # Telegram Notification (Uses $TELEGRAM_TOKEN and $TELEGRAM_CHAT_ID from local env)
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
    make tools/install -j${num_cores} || make tools/install -j1 V=s 2>&1 | tee build.log
    make toolchain/install -j${num_cores} || make toolchain/install -j1 V=s 2>&1 | tee build.log
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
        fi
    fi

    if [ -f "Custom.config" ]; then
        echo "Copying Custom Openwrt config..."
        cp Custom.config .config
    else
        echo "Custom.config does not exist! Please copy your custom config first!"
        exit 1
    fi

    echo "Set to use default config"
    make defconfig
    echo "Download packages before build"
    [[ ! " ${arguments[@]} " =~ "nodownload" ]] && make download
    build_toolchain_safe
    run_build_logic "Custom-Build"
}

case "$1" in
    official) build-official "$2" ;;
    custom) build-custom ;;
    rebuild) run_build_logic "Incremental-Rebuild" ;;
    clean-min) make clean ;;
    clean-toolchain) make dirclean ;;
    clean-full) make distclean ;;
    *)
        echo "Usage: $0 {official|custom|rebuild|clean-min|clean-toolchain|clean-full} <target> [-j cores] [nodownload] [routerconf]"
        echo "official: specify target name .i.e. ramips/mt7621, mediatek/filogic {Openwrt standard config}" >&2
        echo "custom: {Custom config}" >&2
        echo "-j <cores>: Optional. Specify the number of cores for building." >&2
        echo "Optional: nodownload - No downloads of packages" >&2
        echo "Optional: routerconf - Get /etc/build.config from router" >&2
        exit 1
        ;;
esac