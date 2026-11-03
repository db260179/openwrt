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
ARGS="--init --rm --name ${DCKRNAME} -d --cap-add NET_ADMIN -v ${PWD}/openwrt:/home/buser/openwrt -v ${PWD}/../../dl:/home/buser/openwrt/dl"

# Check if Docker image exists, if not, build the image
if [ -n "$(docker images -q ${DCKRIMAGE})" ]; then
   echo "Docker image ${DCKRIMAGE} is ready!"
else
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
    echo "Building official OpenWrt firmware using ${DCKRIMAGE}..."
    docker run ${ARGS} ${DCKRIMAGE} build-official ${2} ${3}
    build_and_watch
    ;;
  build-custom)
    echo "Building custom OpenWrt firmware using ${DCKRIMAGE}..."
    docker run ${ARGS} ${DCKRIMAGE} build-custom ${opt}
    build_and_watch
    ;;
  rebuild)
    echo "Rebuilding the OpenWrt firmware..."
    docker run ${ARGS} ${DCKRIMAGE} build-rebuild
    ;;
  clean-min)
    echo "Performing a minimal cleanup..."
    docker run ${ARGS} ${DCKRIMAGE} clean-min
    ;;
  clean-full)
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
    echo "Entering the Docker container shell..."
    docker run --init --rm --name ${DCKRNAME} -it --entrypoint /bin/bash \
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
