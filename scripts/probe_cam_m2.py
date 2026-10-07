import mmap,os,struct
f=os.open('/dev/mem',os.O_RDWR|os.O_SYNC)
def rd(a):
    m=mmap.mmap(f,0x1000,mmap.MAP_SHARED,offset=a&~0xfff)
    v=struct.unpack_from('<I',m,a&0xfff)[0]; m.close(); return v
def wr(a,v):
    m=mmap.mmap(f,0x1000,mmap.MAP_SHARED,offset=a&~0xfff)
    struct.pack_into('<I',m,a&0xfff,v); m.close()
wr(0x1a000004, 0xFFFFFFFF)
print('sta after set-all:', hex(rd(0x1a000000)))
print('set readback:', hex(rd(0x1a000004)))
print('larb13:', hex(rd(0x1a001000)), hex(rd(0x1a001004)))
print('seninf_top 0x68:', hex(rd(0x1a010068)))
print('camsv1 0x1a110000:', hex(rd(0x1a110000)))
