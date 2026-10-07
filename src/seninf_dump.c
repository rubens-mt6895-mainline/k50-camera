// seninf_dump.c - dump K50 SENINF/DPHY/CSI2 state (port 2 focus)
// Address map per SENINF_CONFIG.md:
//   SENINF TOP 0x1a010000 ; per-port page if_base+0x200+i*0x2000
//   port2 base = 0x1a014200 ; CSI2_EN port2 = 0x1a014a00 ; MUX_CTRL_0 = 0x1a014f00
//   CSI2_PACKET_CNT port2 = 0x1a014adc ; TOP mux j=12 -> 0x1a01cd00 ; PHY_CTRL_CSI2 = TOP+0x48
//   DPHY analog RX = 0x11c80000 (+0x20000), port2 = 0x11c88000 / 0x11c89000 / 0x11c8a000
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <stdint.h>

static int fd;
static uint32_t rd(unsigned long a){
    off_t off = a & ~0xfffUL;
    void *m = mmap(NULL, 0x1000, PROT_READ|PROT_WRITE, MAP_SHARED, fd, off);
    if (m == MAP_FAILED) return 0xdeadbeef;
    return *(uint32_t *)((char *)m + (a & 0xfff));
}
static void sh(const char *n, unsigned long a){
    uint32_t v = rd(a);
    printf("  %-34s %08lx = %08x%s\n", n, a, v, (v==0xdeadbeef)?"  <<MMAPFAIL":"");
}

int main(void){
    fd = open("/dev/mem", O_RDWR|O_SYNC);
    if (fd < 0){ perror("/dev/mem"); return 1; }

    printf("== SENINF TOP ==\n");
    sh("TOP+0x00",        0x1a010000);
    sh("TOP+0x48 PHY_CTRL_CSI2", 0x1a010048);
    sh("TOP mux[12] +0x0d00+12*0x1000", 0x1a01cd00);

    printf("== port2 page (0x1a014200) ==\n");
    sh("CTRL +0x000",       0x1a014200);
    sh("CSI2_CTRL +0x010",  0x1a014210);
    sh("CSI2_EN +0x800",    0x1a014a00);
    sh("CSI2_IRQ_STATUS +0x8C8", 0x1a014ac8);
    sh("CSI2_PKT_CNT +0x8dc",    0x1a014adc);
    sh("MUX_CTRL_0 +0xB00", 0x1a014f00);
    sh("MUX_CTRL_1 +0xB04", 0x1a014f04);
    sh("MUX_OPT +0xB08",    0x1a014f08);

    printf("== DPHY port2 (2_0-style base) ==\n");
    for (unsigned long a = 0x11c88000; a <= 0x11c8803c; a += 4) sh("A", a);
    for (unsigned long a = 0x11c89000; a <= 0x11c8903c; a += 4) sh("B", a);
    sh("dphy_top 0x11c8a000", 0x11c8a000);
    sh("dphy_top+0x04",       0x11c8a004);

    printf("== CAMSV0 (0x1a110000) ==\n");
    sh("CAMSV0+0x00", 0x1a110000);
    sh("CAMSV0+0x04", 0x1a110004);
    sh("CAMSV0+0x1c", 0x1a11001c);
    return 0;
}
