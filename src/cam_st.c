/* cam_st.c - single-shot camera power / clock / reachability probe (read-mostly)
 * Build on device:  gcc -O2 -o cam_st cam_st.c
 * Safe set: never touches 0x1000xxxx (SPM-reserved -> hard bus error).
 */
#include <stdio.h>
#include <stdlib.h>
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
static void WR(uint32_t a,uint32_t v){ void*m=mp(a); if(m)
    *(volatile uint32_t*)((char*)m+(a&0xfff))=v; }

static void sh(const char *cmd){
    FILE *f = popen(cmd,"r");
    if(!f){ printf("  <popen fail>\n"); return; }
    char b[512]; int n=0;
    while(fgets(b,sizeof b,f)){ b[strcspn(b,"\n")]=0; printf("  %s\n",b); n=1; }
    if(!n) printf("  <empty/none>\n");
    pclose(f);
}

int main(void){
    fd = open("/dev/mem",O_RDWR|O_SYNC);
    if(fd<0){ perror("open /dev/mem"); return 1; }

    printf("== genpd current_state ==\n");
    sh("for d in mm_infra isp_vcore isp_main isp_dip1 isp_ipe cam_vcore cam_main cam_suba cam_subb cam_subc cam_mraw; do "
       "p=/sys/kernel/debug/pm_genpd/$d/current_state; "
       "if [ -f $p ]; then echo \"$d = $(cat $p)\"; else echo \"$d = MISSING\"; fi; done");

    printf("== SPM 0x1c001000 + 0xDF0..0xEFC ==\n");
    for(uint32_t o=0xDF0;o<0xF00;o+=4) printf("  %03x: %08x\n",o,RD(0x1c001000+o));

    printf("== cam mmio reachability ==\n");
    {
      static const uint32_t a[]={
        0x1a000000,0x1a000004,0x1a000008,0x1a00000c,0x1a000010,0x1a000014,
        0x1a000020,0x1a000030,0x1a000040,0x1a000080,0x1a000100,0x1a000200,
        0x1a010000,0x1a010048,0x1a010068,0x1a014200,0x1a014210,0x1a014a00,
        0x1a014ac8,0x1a014adc,0x1a014d00,0x1a01cd00,0x1a100000,0x1a110000,
        0x1a170000,0x1a180000,0x11c80000,0x11c86000,0x11c86030,0x11c88000,0x11c8a000};
      for(unsigned i=0;i<sizeof a/sizeof a[0];i++)
        printf("  %08x: %08x\n",a[i],RD(a[i]));
    }

    printf("== write test (value restored) ==\n");
    {
      static const uint32_t t[]={0x1a110000,0x1a010000,0x1a014a00};
      for(unsigned i=0;i<sizeof t/sizeof t[0];i++){
        uint32_t s=RD(t[i]);
        WR(t[i],0x12345678); uint32_t r=RD(t[i]); WR(t[i],s);
        printf("  %08x: wrote 12345678 -> read %08x (%s)\n",t[i],r,
               r==0x12345678?"STICKS":"DROPPED");
      }
    }

    printf("== clock gates ==\n");
    sh("for c in cam_m_seninf_con cam_m_camtg_con cam_m_camsv_con cam_m_cam_con cam_m_cam2sys_gcon "
       "cam_m_cam2mm0_gcon cam_m_cam2mm1_gcon cam_m_gcamsva_con seninf_ck seninf1_ck seninf2_ck "
       "seninf3_ck seninf4_ck camtg_ck camtg3_ck camtm_ck camsys_cam_main_r1a; do "
       "p=/sys/kernel/debug/clk/$c; "
       "if [ -d $p ]; then echo \"$c en=$(cat $p/clk_enable_count 2>/dev/null) "
       "prep=$(cat $p/clk_prepare_count 2>/dev/null) rate=$(cat $p/clk_rate 2>/dev/null) "
       "parent=$(cat $p/clk_parent 2>/dev/null)\"; fi; done");

    printf("== iomem 1a0 ==\n");
    sh("grep -i 1a0 /proc/iomem | head -20");
    printf("== modules ==\n");
    sh("lsmod | grep -E 'cam|ovl'");
    return 0;
}
