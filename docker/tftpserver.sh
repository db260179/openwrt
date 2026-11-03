#!/bin/bash
#set -x

ARGS="--rm --name openwrt-recovery -d --cap-add NET_ADMIN --network host -v $PWD/dnsmasq.conf:/etc/dnsmasq.conf -v $PWD/tftpboot:/tftpboot"

case "$1" in
  build)
    docker build -t openwrt-dnsmasq:latest -f Dockerfile.dnsmasq .
    ;;
  start)
    docker run $ARGS openwrt-dnsmasq:latest
    ;;
  stop)
    docker stop openwrt-recovery
    ;;
  restart)
    docker restart openwrt-recovery
    ;;
  *)
    echo "Usage: $0 {build|start|stop|restart}" >&2
    exit 1
    ;;
esac
