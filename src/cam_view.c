// SPDX-License-Identifier: GPL-2.0
// cam_view - viewfinder for K50 main camera bringup.
// Reads a captured frame file written by the capture step:
//   magic "K50F", u32 width, u32 height (LE), then width*height RGB888 bytes.
// Scales (nearest neighbour) to the framebuffer and blits fullscreen.
// Usage: cam_view [framefile]   (default /tmp/frame.rgb)
// Keeps running and re-blits whenever the file changes (poll every 500ms).
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <linux/fb.h>

static int fb_fd;
static struct fb_var_screeninfo vinfo;
static struct fb_fix_screeninfo finfo;
static unsigned char *fb;
static long fbsize;

static int fb_init(void)
{
	fb_fd = open("/dev/fb0", O_RDWR);
	if (fb_fd < 0)
		return -1;
	if (ioctl(fb_fd, FBIOGET_VSCREENINFO, &vinfo))
		return -1;
	if (ioctl(fb_fd, FBIOGET_FSCREENINFO, &finfo))
		return -1;
	fbsize = (long)finfo.smem_len;
	fb = mmap(0, fbsize, PROT_READ | PROT_WRITE, MAP_SHARED, fb_fd, 0);
	if (fb == MAP_FAILED)
		return -1;
	fprintf(stderr, "fb: %dx%d %dbpp stride=%d\n", vinfo.xres, vinfo.yres,
		vinfo.bits_per_pixel, finfo.line_length);
	return 0;
}

static uint32_t pixel_argb(int r, int g, int b)
{
	if (vinfo.bits_per_pixel == 32) {
		uint32_t p = 0;
		p |= ((uint32_t)r >> (8 - vinfo.red.length)) << vinfo.red.offset;
		p |= ((uint32_t)g >> (8 - vinfo.green.length)) << vinfo.green.offset;
		p |= ((uint32_t)b >> (8 - vinfo.blue.length)) << vinfo.blue.offset;
		return p;
	}
	return 0;
}

static void blit(const unsigned char *src, int w, int h)
{
	int x, y;

	for (y = 0; y < (int)vinfo.yres; y++) {
		uint32_t *dst = (uint32_t *)(fb + (long)y * finfo.line_length);
		int sy = y * h / (int)vinfo.yres;
		const unsigned char *srow = src + (long)sy * w * 3;

		for (x = 0; x < (int)vinfo.xres; x++) {
			int sx = x * w / (int)vinfo.xres;
			const unsigned char *p = srow + (long)sx * 3;

			dst[x] = pixel_argb(p[0], p[1], p[2]);
		}
	}
}

int main(int argc, char **argv)
{
	const char *path = argc > 1 ? argv[1] : "/tmp/frame.rgb";
	unsigned char *buf = NULL;
	int bw = 0, bh = 0;

	if (fb_init()) {
		perror("fb0");
		return 1;
	}

	while (1) {
		int fd = open(path, O_RDONLY);
		struct stat st;
		uint32_t hdr[3];

		if (fd >= 0 && fstat(fd, &st) == 0 && st.st_size > 12 &&
		    read(fd, hdr, 12) == 12 && hdr[0] == 0x4630354b /* K50F */) {
			int w = (int)hdr[1], h = (int)hdr[2];
			long need = (long)w * h * 3;

			if (w > 0 && h > 0 && st.st_size >= need + 12 &&
			    (w != bw || h != bh || !buf)) {
				free(buf);
				buf = malloc(need);
				bw = w;
				bh = h;
			}
			if (buf && bw == w && bh == h &&
			    pread(fd, buf, need, 12) == need) {
				blit(buf, bw, bh);
				fprintf(stderr, "showed %dx%d\n", bw, bh);
			}
		}
		if (fd >= 0)
			close(fd);
		usleep(500000);
	}
	return 0;
}
