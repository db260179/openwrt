# Source https://www.cnblogs.com/p123/p/18046679
Recover from bootloader brick:

1.Power off router, then connect serial lead
2.Run the mtk_uartboot - sudo ./mtk_uartboot -s /dev/ttyUSB0 -p mt7981-ram-ddr3-bl2.bin -a -f mt7981_comfast_cf-e395ax-fip-fixed-parts.bin -l $((0x201000)) && screen /dev/ttyUSB0 115200
3.Power on router, it should show handshake then payload action
4.Once fip is loaded the program will exit and connect to serial via screen
5.Select Upgrade ATF BL2 or ATF FIP to tftpboot working preloader (mediatek-filogic-comfast_cf-e393ax-preloader.bin) and uboot image (mt7981_comfast_cf-e395ax-fip-fixed-parts.bin or openwrt bl31-uboot) to write back
