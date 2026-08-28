#define PROGRAM_NAME "trim_sgb_tilemap"
#define USAGE_OPTS "[-h|--help] [-r|--reverse|--revert] infile.tilemap outfile.tilemap"

#include "common.h"

enum {
	FULL_TILEMAP_SIZE = 0x700,
	TRIMMED_TILEMAP_SIZE = 0x430,
	TILEMAP_ROW_BYTES = 32 * 2,
	SCREEN_ROW_BYTES = 20 * 2,
	SCREEN_ROWS = 18,
	FRAME_START = (5 * 32 + 6) * 2,
	FRAME_END = (22 * 32 + 26) * 2,
};

static uint8_t output[FULL_TILEMAP_SIZE];

static void parse_args(int argc, char *argv[], bool *reverse) {
	struct option long_options[] = {
		{"reverse", no_argument, 0, 'r'},
		{"revert", no_argument, 0, 'r'},
		{"help", no_argument, 0, 'h'},
		{0}
	};

	for (int opt; (opt = getopt_long(argc, argv, "rh", long_options)) != -1;) {
		switch (opt) {
		case 'r':
			*reverse = true;
			break;
		case 'h':
			usage_exit(0);
			break;
		default:
			usage_exit(1);
		}
	}
}

static void validate_cropped_bytes(const uint8_t *data) {
	for (size_t row = 0; row < SCREEN_ROWS; row++) {
		size_t row_start = FRAME_START + row * TILEMAP_ROW_BYTES;
		for (size_t i = 0; i < SCREEN_ROW_BYTES; i++) {
			if (data[row_start + i] != 0) {
				error_exit("Input SGB tilemap has non-zero bytes in the cropped screen area.\n");
			}
		}
	}
}

static void trim_tilemap(const uint8_t *data) {
	size_t pos = 0;

	for (size_t i = 0; i < FRAME_START; i++) {
		output[pos++] = data[i];
	}

	for (size_t row = 0; row < SCREEN_ROWS - 1; row++) {
		size_t row_start = FRAME_START + SCREEN_ROW_BYTES + row * TILEMAP_ROW_BYTES;
		for (size_t i = 0; i < 12 * 2; i++) {
			output[pos++] = data[row_start + i];
		}
	}

	for (size_t i = FRAME_END; i < FULL_TILEMAP_SIZE; i++) {
		output[pos++] = data[i];
	}

	if (pos != TRIMMED_TILEMAP_SIZE) {
		error_exit("Internal SGB tilemap trim size mismatch.\n");
	}
}

static void expand_tilemap(const uint8_t *data) {
	size_t pos = 0;
	size_t frame_end = FRAME_START + SCREEN_ROWS * 12 * 2;

	for (size_t i = 0; i < FRAME_START; i++) {
		output[pos++] = data[i];
	}

	for (size_t row = 0; row < SCREEN_ROWS; row++) {
		for (size_t i = 0; i < SCREEN_ROW_BYTES; i++) {
			output[pos++] = 0;
		}
		for (size_t i = 0; i < 12 * 2; i++) {
			output[pos++] = data[FRAME_START + row * 12 * 2 + i];
		}
	}

	for (size_t i = frame_end; i < TRIMMED_TILEMAP_SIZE; i++) {
		output[pos++] = data[i];
	}

	if (pos != FULL_TILEMAP_SIZE) {
		error_exit("Internal SGB tilemap expansion size mismatch.\n");
	}
}

int main(int argc, char *argv[]) {
	bool reverse = false;
	parse_args(argc, argv, &reverse);

	argc -= optind;
	argv += optind;
	if (argc != 2) {
		usage_exit(1);
	}

	long filesize;
	uint8_t *data = read_u8(argv[0], &filesize);
	size_t expected_size = reverse ? TRIMMED_TILEMAP_SIZE : FULL_TILEMAP_SIZE;
	if (filesize != (long)expected_size) {
		free(data);
		error_exit("Input SGB tilemap has wrong size (expected 0x%zx bytes).\n", expected_size);
	}

	if (reverse) {
		expand_tilemap(data);
		write_u8(argv[1], output, FULL_TILEMAP_SIZE);
	} else {
		validate_cropped_bytes(data);
		trim_tilemap(data);
		write_u8(argv[1], output, TRIMMED_TILEMAP_SIZE);
	}

	free(data);
	return 0;
}
