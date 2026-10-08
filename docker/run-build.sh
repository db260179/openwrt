#!/bin/bash

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
  echo "Error: Docker is not installed or not found in PATH."
  echo "Please install Docker or ensure it is available in your PATH."
  exit 1
fi

# Enable debugging if DEBUG is set to true
if [ "${DEBUG}" == "true" ]; then
  set -x
else
  set -e
fi

opt=$2
export USERUID="$(id -u)"
export USERGID="$(id -g)"
GITBRANCH=$(git branch --show-current)
DCKRIMAGE="openwrt-imagebuild-${GITBRANCH}:latest"
DCKRNAME="openwrt-imagebuild-${GITBRANCH}"
BARGS="--build-arg USERUID=${USERUID} --build-arg USERGID=${USERGID}"
ARGS="--init --name ${DCKRNAME} -d --cap-add NET_ADMIN -v ${PWD}/openwrt:/home/buser/openwrt -v ${PWD}/../../dl:/home/buser/openwrt/dl"

# Function to check container state and handle prompt
check_existing_container() {
  local status
  status=$(docker inspect --format='{{.State.Status}}' "${DCKRNAME}" 2>/dev/null || true)

  if [ "${status}" == "running" ]; then
    echo "Warning: Container '${DCKRNAME}' is already running."
    read -p "Select action: [A]ttach to container / [S]top container / [C]ancel? (a/s/c): " -n 1 -r
    echo ""
    case "$REPLY" in
      [Aa]*)
        echo "Attaching to container '${DCKRNAME}'..."
        echo "(Use Ctrl+P followed by Ctrl+Q to detach without stopping the container)"
        docker attach "${DCKRNAME}"
        exit 0
        ;;
      [Ss]*)
        echo "Stopping existing container..."
        docker stop -t 60 "${DCKRNAME}"
        docker rm "${DCKRNAME}"
        ;;
      *)
        echo "Operation cancelled."
        exit 0
        ;;
    esac
  elif [ "${status}" == "exited" ]; then
      echo "Container '${DCKRNAME}' is currently exited. Starting and attaching..."
      docker start -ai "${DCKRNAME}"
      exit 0
  elif [ -n "${status}" ]; then
    echo "Removing stopped container '${DCKRNAME}'..."
    docker rm "${DCKRNAME}" > /dev/null
  fi
}

# Check if Docker image exists, if not, build the image
if [ -z "$(docker images -q ${DCKRIMAGE})" ]; then
   echo "Docker image ${DCKRIMAGE} does not exist. Running './$0 build-image' to create it."
   docker build ${BARGS} -t ${DCKRIMAGE} -f Dockerfile.build .
fi

# Function to handle building and logging
build_and_watch() {
  echo "Build started - now watching ${DCKRNAME}"
  echo "Press CTRL+C to stop watching!"
  echo "To stop the build completely - './$0 stop'"
  docker logs -f ${DCKRNAME}
}

# Main command handler
case "$1" in
  build-image)
    echo "Building Docker image ${DCKRIMAGE}..."
    docker build ${BARGS} -t ${DCKRIMAGE} -f Dockerfile.build .
    ;;
  build-official)
    check_existing_container
    echo "Building official OpenWrt firmware using ${DCKRIMAGE}..."
    docker run ${ARGS} ${DCKRIMAGE} build-official ${2} ${3}
    build_and_watch
    ;;
  build-custom)
    check_existing_container
    echo "Building custom OpenWrt firmware using ${DCKRIMAGE}..."
    docker run ${ARGS} ${DCKRIMAGE} build-custom ${opt}
    build_and_watch
    ;;
  rebuild)
    check_existing_container
    echo "Rebuilding the OpenWrt firmware..."
    docker run ${ARGS} ${DCKRIMAGE} build-rebuild
    ;;
  clean-min)
    check_existing_container
    echo "Performing a minimal cleanup..."
    docker run ${ARGS} ${DCKRIMAGE} clean-min
    ;;
  clean-full)
    check_existing_container
    echo "Performing a full cleanup..."
    docker run ${ARGS} ${DCKRIMAGE} clean-full
    ;;
  watch-build)
    echo "Watching the OpenWrt build logs..."
    docker logs -f ${DCKRNAME}
    ;;
  stop)
    echo "Stopping the Docker container ${DCKRNAME}..."
    docker stop -t 60 ${DCKRNAME}
    ;;
  shell)
    check_existing_container
    echo "Entering the Docker container shell..."
    docker run --init --name ${DCKRNAME} -it --entrypoint /bin/bash \
      --privileged -v ${PWD}/openwrt:/home/buser/openwrt -v ${PWD}/../../dl:/home/buser/openwrt/dl ${DCKRIMAGE}
    ;;
  *)
    echo "Usage: $0 {build-image|build-official|build-custom|rebuild|clean-min|clean-full|stop|shell|watch-build}" >&2
    echo "build-image: Build the Docker image ${DCKRIMAGE} for OpenWrt firmware builds." >&2
    echo "build-official: Build OpenWrt with official config. Specify the target (e.g., ramips/mt7621)." >&2
    echo "build-custom: Build OpenWrt with custom config (Custom.config)." >&2
    echo "rebuild: Restart the build process." >&2
    echo "clean-min: Perform a minimal cleanup (keep config)." >&2
    echo "clean-full: Perform a full cleanup (clean slate)." >&2
    echo "watch-build: Watch the OpenWrt build in the container." >&2
    echo "shell: Enter a bash shell in the Docker container." >&2
    exit 1
    ;;
esac