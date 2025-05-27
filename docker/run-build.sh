#!/bin/bash
#set -x
opt=$2
export USERUID="$(id -u)"
export USERGID="$(id -g)"
DCKRIMAGE="openwrt-imagebuild:latest"
DCKRNAME="openwrt-imagebuild"
BARGS="--build-arg USERUID=$USERUID --build-arg USERGID=$USERGID"
ARGS="--rm --name $DCKRNAME -d --cap-add NET_ADMIN -v $PWD/openwrt:/home/buser/openwrt -v $PWD/../../dl:/home/buser/openwrt/dl"

# Check if docker image exist, if not build image
if test ! -z "$(docker images -q $DCKRIMAGE)"; then
   echo "Ready to Start!"
else
   echo "$DCKRIMAGE doesnt exist!, running './$0 build-image' first!"
   docker build $BARGS -t $DCKRIMAGE -f Dockerfile.build .
fi

case "$1" in
  build-image)
    docker build $BARGS -t $DCKRIMAGE -f Dockerfile.build .
    ;;
  build-official)
    docker run $ARGS $DCKRIMAGE build-official $2 $3
    echo "Build started - now watching $DCKRNAME"
    echo "Press CTRL+C to stop watching!"
    echo "To stop build completely - '$0 stop'"
    docker logs -f $DCKRNAME
    ;;
  build-custom)
    docker run $ARGS $DCKRIMAGE build-custom $opt
    echo "Build started - now watching $DCKRNAME"
    echo "Press CTRL+C to stop watching!"
    echo "To stop build completely - '$0 stop'"
    docker logs -f $DCKRNAME
    ;;
  rebuild)
    docker run $ARGS $DCKRIMAGE build-rebuild
    ;;
  clean-min)
    docker run $ARGS $DCKRIMAGE clean-min
    ;;
  clean-full)
    docker run $ARGS $DCKRIMAGE clean-full
    ;;
  watch-build)
    echo "Press CTRL+C to stop watching!"
    echo "To stop build completely - '$0 stop'"
    sleep 5
    docker logs -f $DCKRNAME
    ;;
  stop)
    docker stop -t 60 $DCKRNAME
    ;;
  shell)
    docker run --rm --name $DCKRNAME -it --entrypoint /bin/bash \
    --cap-add NET_ADMIN -v $PWD/openwrt:/home/buser/openwrt -v $PWD/../../dl:/home/buser/openwrt/dl $DCKRIMAGE
    ;;
  *)
    echo "Usage: $0 {build-image|build-official|build-custom|rebuild|clean-min|clean-full|stop}" >&2
    echo "build-image: Build $DCKRIMAGE to build openwrt firmware images" >&2
    echo "build-official: Build Openwrt with official config using $DCKRIMAGE [specify target name .i.e. ramips/mt7621]" >&2
    echo "build-custom: Build Openwrt with custom config (Custom.config) using $DCKRIMAGE" >&2
    echo "rebuild: Restart build process" >&2
    echo "clean-min: Cleanup minimum build - keep config" >&2
    echo "clean-full: Cleanup full build - clean slate" >&2
    echo "watch-build: Watch the Openwrt build on container" >&2
    echo "shell: Enter bash shell in docker container" >&2
    exit 1
    ;;
esac
