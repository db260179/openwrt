## Scripts and Docker container (docker/run-build.sh, docker/tftpserver.sh)

### Docker

For convenience have added a docker container to run a dhcp, tftp server to push out images via the u-boot menu

Make sure to have a host that has docker engine installed and running (https://docs.docker.com/engine/install)

NOTE: Build on docker engine is only guarenteed to work on a Linux platform, using Macosx or Windows is not fully supported!

**And have a USB ttl serial lead to connect to the uart ports!
This is really important, as only recover is to hold reset and install factory image again (test.bin)**

### Build the openwrt image - image to flash to router

You need to build the docker image first:

    ./run-build.sh build-image

Then start the openwrt build code process (Openwrt official release config):

    ./run-build.sh build-official

This will take a long time depending on your host compiling the code!

Once finished, the image will be available in top level of the openwrt folder in - bin/targets/ramips/mt7621/

### DHCP server and TFTP server - upload to router via u-boot

You need to build the docker image first:

    ./tftpserver.sh build

you can configure the 'dnsmasq.conf' to suit your needs - defaults should be fine and will detect all cards (tested in linux only)

Before starting the dnsmasq container, make sure the host running docker-engine has the IP - 192.168.31.1

The default oem firmware is looking for that IP address to pull down the recovery firmware file (test.bin)!

To run it:

    ./tftpserver.sh start

To stop the dhcp container:

    ./tftpserver.sh stop

To restart the dhcp container:

    ./tftpserver.sh restart

Put your new openwrt images into the '**docker/tftpboot**' folder
Then specify the images when interacting with the u-boot menu.

If you haven't gained access to the u-boot menu, then do the exploit method - go to https://github.com/acecilia/OpenWRTInvasion
and follow the exploit guide.

Before flashing your new image during the exploit, run the following commands first:

    nvram set uart_en=1
    nvram set boot_wait=on
    nvram set boot_delay=5
    nvram commit

This allows you to recover from bad flashes without going back to the OEM firmware.

Then continue the exploit guide.

If unsure of compatibilty, write the **openwrt-initramfs image** instead of the sysupgrade image. As this does not write anything to the SPI NOR chip.

Any issues, leave an issue on this git repo!
