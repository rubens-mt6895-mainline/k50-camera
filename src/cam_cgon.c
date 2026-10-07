/* cam_cgon.c v2 - locate the CAM_MAIN clock-gate control register and try to
 * enable all gates so SENINF/CAMSV become accessible.
 *
 * MTK clk-gate layouts are one of:
 *   A) setclr : SET = +0x0, CLR = +0x4  (what clk-mt*-cam.c uses on many SoCs)
 *   B) sta/set/clr : STA = +0x0, SET = +0x4, CLR = +0x8
 * cam_st showed 0x1a000000 = 0, 0x1a000004 = 0, 0x1a000008 = 0,
 * 0x1a00000c = de8d3e67, 0x1a000010 = 0x5b, 0x1a000014 = 0x5b.
 * So probe every offset 0x0..0x3c individually: write 0xffffffff, look at the
 * read-back (RW vs RO) and at whether 0x1a010000 / 0x1a110000 come alive,
 * then restore the old value.  Finally apply every "live" offset for real.
 *
 * Build on device: gcc -O2 -o cam_cgon cam_cgon.c
 */
#include <stdio.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <sys/mman.h>

static int fd = -1;
#define MAXPG 64
static void *pgv[MAXPG]; static uint32_t pgt[MAXPG]; static int npg;

static void *mp(uint32_t a){
    uint32_t p = a & ~0xfffu;
    for(int i=0;i<npg;i++) if(pgt[i]==p) return pgv[i];
    if(npg>=MAXPG) return 0;
    void *m = mmap(0,0x1000,PROT_READ|PROT_WRITE,MAP_SHARED,fd,(off_t)p);
    if(m==MAP_FAILED){ printf("  !! mmap %08x failed\n",p); return 0; }
    pgv[npg]=m; pgt[npg]=p; npg++; return m;
}
static uint32_t RD(uint32_t a){ void*m=mp(a); if(!m) return 0xdeadbeef;
    return *(volatile uint32_t*)((char*)m+(a&0xfff)); }
static void WR(uint32_t a,uint32_t v){ void*m=mp(a); if(m){
    *(volatile uint32_t*)((char*)m+(a&0xfff))=v; } }

/* returns seninf TOP register */
static uint32_t seninf(void){ return RD(0x1a010000); }
static uint32_t camsv1(void){ return RD(0x1a110000); }
static uint32_t csi2en(void){ return RD(0x1a014a00); }

static void probe(const char *tag){
    printf("  [%-10s] seninf=%08x camsv1=%08x csi2_en=%08x s1_48=%08x pkt=%08x "
           "mux12=%08x pda=%08x cgsta0=%08x cgsta1=%08x\n",
        tag, seninf(), camsv1(), csi2en(), RD(0x1a010048), RD(0x1a014adc),
        RD(0x1a01cd00), RD(0x1a100000), RD(0x1a000000), RD(0x1a000010));
    fflush(stdout);
}

int main(void){
    fd = open("/dev/mem",O_RDWR|O_SYNC);
    if(fd<0){ perror("open /dev/mem"); return 1; }

    printf("== baseline 0x1a000000..0x3c ==\n");
    for(uint32_t o=0;o<0x40;o+=4) printf("  %08x: %08x\n",0x1a000000+o,RD(0x1a000000+o));
    probe("base");

    uint32_t live[16]; int nlive=0;
    for(uint32_t o=0;o<0x40;o+=4){
        uint32_t addr=0x1a000000+o;
        uint32_t old=RD(addr);
        if(old==0xdeadbeef) continue;
        uint32_t s0=seninf(), c0=camsv1();
        WR(addr,0xffffffffu);
        usleep(5000);
        uint32_t back=RD(addr), s1=seninf(), c1=camsv1();
        int rw = (back==0xffffffffu);
        int effect = (s1!=s0)||(c1!=c0);
        printf("%08x: old=%08x back=%08x %s %s | seninf %08x->%08x camsv %08x->%08x\n",
               addr, old, back, rw?"RW":"RO", effect?"EFFECT":"      ", s0,s1,c0,c1);
        if(effect){ live[nlive++]=(int)addr; }
        WR(addr,old);           /* restore */
        usleep(2000);
    }
    printf("-- restoring baseline --\n");
    for(uint32_t o=0;o<0x40;o+=4) WR(0x1a000000+o, RD(0x1a000000+o));
    probe("restored");

    if(nlive){
        printf("== effective offsets: ==\n");
        for(int i=0;i<nlive;i++) printf("   %08x\n", live[i]);
    } else {
        printf("== no single offset changed seninf/camsv; trying cumulative SET pass ==\n");
    }

    /* cumulative pass: set every offset that read back RW (plausible set/clr) */
    printf("== cumulative: write 0xffffffff to 0x4/0x14/0x24/0x34/0x44 (SET candidates) ==\n");
    { static const uint32_t s[]={0x1a000004,0x1a000014,0x1a000024,0x1a000034,0x1a000044};
      for(unsigned i=0;i<sizeof s/sizeof s[0];i++){ WR(s[i],0xffffffffu); usleep(3000);} }
    probe("setpass");
    printf("== cumulative: write 0xffffffff to 0x0/0x10/0x20/0x30/0x40 (unknown candidates) ==\n");
    { static const uint32_t s[]={0x1a000000,0x1a000010,0x1a000020,0x1a000030,0x1a000040};
      for(unsigned i=0;i<sizeof s/sizeof s[0];i++){ WR(s[i],0xffffffffu); usleep(3000);} }
    probe("allpass");

    printf("== final dump 0x1a000000..0x3c ==\n");
    for(uint32_t o=0;o<0x40;o+=4) printf("  %08x: %08x\n",0x1a000000+o,RD(0x1a000000+o));
    printf("== seninf region ==\n");
    { static const uint32_t a[]={0x1a010000,0x1a010048,0x1a010068,0x1a014200,0x1a014210,
        0x1a014a00,0x1a014ac8,0x1a014adc,0x1a014d00,0x1a01cd00,0x1a110000,0x1a180000};
      for(unsigned i=0;i<sizeof a/sizeof a[0];i++) printf("  %08x: %08x\n",a[i],RD(a[i]));
    }
    printf("== write test 0x1a010000 <= 12345678 ==\n");
    { uint32_t old=RD(0x1a010000); WR(0x1a010000,0x12345678u); usleep(2000);
      printf("  old=%08x back=%08x\n", old, RD(0x1a010000)); WR(0x1a010000,old); }
    return 0;
}
