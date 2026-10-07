// camgpio_rs.c - correct MTK MT6895 gpio register map
// Source of truth: ${K50_REPO}\pinctrl-mt6895.c:70-101 (mt6895_pin_field_calc tables)
//   DIR : GPIO_BASE + 0x000 + bank*0x10   (bank = pin/32)
//   DOUT: GPIO_BASE + 0x100 + bank*0x10
//   DIN : GPIO_BASE + 0x200 + bank*0x10
//   MODE: GPIO_BASE + 0x300 + (pin/8)*0x10, 4 bits at (pin%8)*4
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <stdint.h>

#define GPIO_BASE 0x10005000UL

static int fd;
static uint32_t *pg(unsigned long a) {
    off_t off = a & ~0xfffUL;
    void *m = mmap(NULL, 0x1000, PROT_READ|PROT_WRITE, MAP_SHARED, fd, off);
    if (m == MAP_FAILED) { perror("mmap"); exit(1); }
    return (uint32_t *)((char *)m + (a & 0xfff));
}
static uint32_t rd(unsigned long a){ return *pg(a); }
static void wr(unsigned long a, uint32_t v){ *pg(a) = v; }

static unsigned long g_dir(int p){ return GPIO_BASE + 0x000 + (p/32)*0x10; }
static unsigned long g_do (int p){ return GPIO_BASE + 0x100 + (p/32)*0x10; }
static unsigned long g_di (int p){ return GPIO_BASE + 0x200 + (p/32)*0x10; }
static unsigned long g_mode(int p){ return GPIO_BASE + 0x300 + (p/8)*0x10; }
static int g_shift(int p){ return (p%8)*4; }

static int get_mode(int p){ return (rd(g_mode(p)) >> g_shift(p)) & 0xf; }
static int get_dir (int p){ return (rd(g_dir(p))  >> (p%32)) & 1; }
static int get_do  (int p){ return (rd(g_do(p))   >> (p%32)) & 1; }
static int get_di  (int p){ return (rd(g_di(p))   >> (p%32)) & 1; }

static void set_mode(int p, int v){
    unsigned long a = g_mode(p); uint32_t x = rd(a); int s = g_shift(p);
    x = (x & ~(0xfU << s)) | ((uint32_t)(v & 0xf) << s);
    wr(a, x);
}
static void set_dir(int p, int v){
    unsigned long a = g_dir(p); uint32_t x = rd(a);
    if (v) x |=  (1U << (p%32)); else x &= ~(1U << (p%32));
    wr(a, x);
}
static void set_do(int p, int v){
    unsigned long a = g_do(p); uint32_t x = rd(a);
    if (v) x |=  (1U << (p%32)); else x &= ~(1U << (p%32));
    wr(a, x);
}

static void dump(const char *tag, int *pins, int n){
    printf("-- %s --\n", tag);
    for (int i=0;i<n;i++){
        int p = pins[i];
        printf("  GPIO%-3d mode=%X dir=%d do=%d di=%d\n",
            p, get_mode(p), get_dir(p), get_do(p), get_di(p));
    }
}

int main(int argc, char **argv){
    int pins[] = {20, 149, 152, 155, 158, 159, 164};
    int n = sizeof(pins)/sizeof(pins[0]);
    int force = (argc > 1 && !strcmp(argv[1], "force"));

    fd = open("/dev/mem", O_RDWR|O_SYNC);
    if (fd < 0){ perror("/dev/mem"); return 1; }

    printf("== register bases ==\n");
    unsigned long words[] = {0x10005000,0x10005040,0x10005050,0x10005100,0x10005140,0x10005150,
                             0x10005200,0x10005240,0x10005250,0x10005420,0x10005430,0x10005440};
    for (unsigned i=0;i<sizeof(words)/sizeof(words[0]);i++)
        printf("  %08lx = %08x\n", words[i], rd(words[i]));

    dump("BEFORE", pins, n);

    if (!force){ printf("(dry run; pass 'force' to drive)\n"); return 0; }

    printf("== FORCE: mode=0, dir=out, do=1 (skip 152=MCLK func1) ==\n");
    for (int i=0;i<n;i++){
        if (pins[i] == 152) continue;
        set_mode(pins[i], 0);
        set_dir(pins[i], 1);
        set_do(pins[i], 1);
    }
    usleep(100000);
    dump("AFTER", pins, n);
    return 0;
}
