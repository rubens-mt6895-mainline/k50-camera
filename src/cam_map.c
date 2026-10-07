// cam_map.c - map the whole 0x1a000000..0x1a1a0000 camera aperture and find
// exactly which 4K pages respond (read non-zero) and which accept writes.
#include <stdio.h>
#include <stdint.h>
#include <fcntl.h>
#include <string.h>
#include <errno.h>
#include <sys/mman.h>
#include <unistd.h>

#define BASE 0x1a000000UL
#define SIZE 0x1a0000UL          /* 1.625 MB -> covers 0x1a000000..0x1a19ffff */

int main(void)
{
	int fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (fd < 0) { perror("open /dev/mem"); return 1; }

	volatile uint32_t *m = mmap(NULL, SIZE, PROT_READ | PROT_WRITE,
				    MAP_SHARED, fd, BASE);
	if (m == MAP_FAILED) { perror("mmap"); return 1; }

	printf("PAGE SCAN 0x%08lx .. 0x%08lx (size 0x%lx)\n",
	       BASE, BASE + SIZE - 1, SIZE);

	unsigned long off;
	int alive = 0;
	for (off = 0; off < SIZE; off += 0x1000) {
		volatile uint32_t *p = (volatile uint32_t *)((char *)m + off);
		uint32_t w[16];
		int i, nz = 0;

		for (i = 0; i < 16; i++) {
			w[i] = p[i];
			if (w[i])
				nz = 1;
		}
		if (!nz)
			continue;

		alive++;
		printf("PAGE %08lx :", BASE + off);
		for (i = 0; i < 16; i++)
			printf(" %08x", w[i]);
		printf("\n");

		/* write test on a page that responds: offset 0x100 */
		uint32_t old = p[0x40];
		p[0x40] = 0xA5A5A5A5u;
		uint32_t rb = p[0x40];
		p[0x40] = old;
		printf("        wr[+0x100]=%08x -> %s (readback %08x)\n",
		       0xA5A5A5A5u, rb == 0xA5A5A5A5u ? "STUCK" : "DROPPED", rb);
	}

	printf("RESPONSIVE PAGES: %d / %lu\n", alive, SIZE / 0x1000);
	return 0;
}
