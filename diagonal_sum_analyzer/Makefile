CC ?= cc
CFLAGS ?= -std=c11 -O2 -Wall -Wextra -pedantic
LDLIBS ?= -pthread

.PHONY: all compile run test clean

all: proj4.out
compile: proj4.out

proj4.out: main.c proj4.c proj4.h
	$(CC) $(CFLAGS) -pthread main.c proj4.c -o $@ $(LDLIBS)

run: proj4.out
	./proj4.out examples/in1.txt out1.txt 10 2

test: proj4.out
	sh tests/smoke.sh

clean:
	rm -f proj4.out out1.txt
