#define PROGRAM_NAME "picdims"
#define USAGE_OPTS "infile.png outfile.dim"

// Writes the one-byte sprite dimensions that base stats read
// (INCBIN "....dim" ; sprite dimensions): width in tiles in the high nybble,
// height in tiles in the low nybble - the same byte pkmncompress used to put
// first in a .pic. LZ-compressed pics carry no such header, so it comes from
// the PNG instead.

#include "common.h"

static uint32_t read_be32(const uint8_t *p) {
	return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3];
}

int main(int argc, char *argv[]) {
	if (argc != 3) {
		usage_exit(1);
	}
	long size;
	uint8_t *png = read_u8(argv[1], &size);
	if (size < 24 || memcmp(png, "\x89PNG\r\n\x1a\n", 8) || memcmp(png + 12, "IHDR", 4)) {
		error_exit("%s: not a PNG\n", argv[1]);
	}
	uint32_t width = read_be32(png + 16);
	uint32_t height = read_be32(png + 20);
	free(png);
	if (width % 8 || height % 8 || width < 8 || height < 8 || width > 7 * 8 || height > 7 * 8) {
		error_exit("%s: %ux%u is not a 1-7 x 1-7 tile sprite\n", argv[1], width, height);
	}
	uint8_t dimensions = (uint8_t)((width / 8) << 4 | (height / 8));
	write_u8(argv[2], &dimensions, 1);
	return 0;
}
