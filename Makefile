# Huffman vs Shannon-Fano & Code Analyzer
CC     ?= cc
CFLAGS ?= -Wall -Wextra -O2

all: main gui

main: main.c compression.c compression.h
	$(CC) $(CFLAGS) -o main main.c compression.c -lm

gui: gui.m compression.c compression.h
	$(CC) $(CFLAGS) -o gui gui.m compression.c -framework Cocoa -lm

clean:
	rm -f main gui

.PHONY: all clean
