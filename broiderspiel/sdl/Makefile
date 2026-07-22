# Broiderspiel — SDL2 + OpenGL port
#
#   make            build ./broiderspiel
#   make run        build and run
#   make figure     headless render -> broiderspiel.ppm (needs Xvfb if no display)
#
# Requires: SDL2, GLEW, an OpenGL 3.3 core driver.
#   Debian/Ubuntu:  sudo apt install libsdl2-dev libglew-dev libgl1-mesa-dev

CC      ?= cc
CFLAGS  ?= -O2 -Wall -Wextra
CFLAGS  += $(shell pkg-config --cflags sdl2 glew)
LIBS    := $(shell pkg-config --libs sdl2 glew) -lGL -lm

broiderspiel: broiderspiel.c
	$(CC) $(CFLAGS) -o $@ $< $(LIBS)

run: broiderspiel
	./broiderspiel

figure: broiderspiel
	./broiderspiel --frames 600 --debug --out broiderspiel.ppm

clean:
	rm -f broiderspiel broiderspiel*.ppm

.PHONY: run figure clean
