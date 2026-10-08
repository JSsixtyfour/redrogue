.PHONY: all clean

CC := gcc
CFLAGS := -O3 -std=c11 -Wall -Wextra -pedantic

tools := \
	gfx \
	lzcompress \
	make_patch \
	picdims \
	pkmncompress \
	trim_sgb_tilemap \
	scan_includes

all: $(tools)
	@:

clean:
	$(RM) $(tools)

%: %.c common.h
	$(CC) $(CFLAGS) -o $@ $<
