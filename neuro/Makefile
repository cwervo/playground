# neuro — one numeric pass in C++, one bytecode, four renderers.
#
#   make            build everything into build/
#   make analyze    just the engine
#   make dash       the self-contained browser dashboard
#   make physical   SVG for print and plotter, STL and SCAD, pocket card
#   make figures    TIFFs of every figure in the source scans, plus a zip
#   make conference the simulated proceedings PDF, with Xanadu-style ley lines
#   make video      the 9:16 reel of the photic block, with its sonification
#   make book       the large-format book, 300 x 380 mm, QR codes in the citations
#   make explore    launch the Tk explorer (needs a display)
#   make disasm     read the drawing program as assembly
#   make check      round-trip the display file through every host
#   make whatif M=beh.rt V=430   re-derive with one value overridden
#   make clean

CXX      ?= g++
CXXFLAGS ?= -std=c++17 -O2 -Wall -Wextra
TCLSH    ?= tclsh
WISH     ?= wish8.6

SESSION  ?= data/session-2026-08-18.json
PRIOR    ?= data/prior-graph.json
PERM     ?= 200000
SEED     ?= 20260818

B        := build
ENGINE   := $(B)/analyze
NVM      := $(B)/dashboard.nvm
HDRS     := src/nvm.hpp src/stats.hpp src/json.hpp

.PHONY: all analyze dash physical figures conference video book explore disasm check whatif clean help

all: dash physical figures conference
	@echo
	@echo "  built:"
	@ls -1sh $(B) | sed 's/^/    /'

# ---------------------------------------------------------------------------
$(ENGINE): src/analyze.cpp $(HDRS) | $(B)
	$(CXX) $(CXXFLAGS) -o $@ src/analyze.cpp

$(B):
	@mkdir -p $(B)

analyze: $(ENGINE)

# The display file is the only thing downstream targets depend on. Nothing else
# in this project re-reads the session JSON, which is the guarantee that the
# card, the plotter output and the browser cannot disagree with each other.
$(NVM): $(ENGINE) $(SESSION) $(PRIOR)
	./$(ENGINE) --session $(SESSION) --prior $(PRIOR) \
	            --out $(NVM) --json $(B)/derived.json \
	            --perm $(PERM) --seed $(SEED)

nvm: $(NVM)

# ---------------------------------------------------------------------------
dash: $(B)/dashboard.html

$(B)/dashboard.html: $(NVM) web/host.html web/bundle.tcl
	$(TCLSH) web/bundle.tcl web/host.html $(NVM) $@

# ---------------------------------------------------------------------------
physical: $(B)/dashboard.svg $(B)/plot.svg $(B)/card.svg $(B)/comb.stl

$(B)/dashboard.svg: $(NVM) physical/plot.tcl tcl/nvm.tcl
	$(TCLSH) physical/plot.tcl $(NVM) $@ --mode print

$(B)/plot.svg: $(NVM) physical/plot.tcl tcl/nvm.tcl
	$(TCLSH) physical/plot.tcl $(NVM) $@ --mode pen

$(B)/card.svg: $(NVM) physical/card.tcl tcl/nvm.tcl
	$(TCLSH) physical/card.tcl $(NVM) $@

$(B)/comb.stl: $(NVM) physical/solid.tcl tcl/nvm.tcl
	$(TCLSH) physical/solid.tcl $(NVM) $(B)/comb

# ---------------------------------------------------------------------------
# Figures cut out of the original scans. This target does not depend on the
# display file: it reads the source PDFs directly, because it is extracting what
# the instruments drew rather than anything this project derived.
figures: $(B)/figures.zip

$(B)/figures.zip: figures/extract-figures.py | $(B)
	python3 figures/extract-figures.py --out $(B)/figures --zip $@ \
	        --also-png $(B)/conference/img

# ---------------------------------------------------------------------------
# The simulated conference. Tcl builds the document, the browser lays it out and
# draws the ley lines, and only then is it printed -- printing before the page
# reports ready gives a PDF with the right words and no lines on it.
NODE     ?= node
CHROMIUM ?= /opt/pw-browsers/chromium-1194/chrome-linux/chrome

conference: $(B)/conference/proceedings.pdf

$(B)/conference/proceedings.html: conference/build.tcl conference/proceedings.tcl \
                                  conference/sources.tcl $(B)/figures.zip
	$(TCLSH) conference/build.tcl --img $(B)/conference/img --out $@

$(B)/conference/proceedings.pdf: $(B)/conference/proceedings.html conference/topdf.mjs
	CHROMIUM_PATH=$(CHROMIUM) $(NODE) conference/topdf.mjs $< $@

# ---------------------------------------------------------------------------
# The reel. Four stages, each one writing a file the next one reads, so the
# picture and the sound are driven from the same event list and cannot drift:
#
#   trace    ink on the scanned figures  ->  time series
#   analyse  time series                 ->  peaks, polarity reversals, order
#   sonify   those events                ->  score + stereo master
#   render   all of it                   ->  frames, muxed with the master
#
# SCALE=1 gives 1080x1920 in about a minute, for looking at; SCALE=2 gives
# 2160x3840, which is what actually ships.
SCALE  ?= 2
VIDEO  := $(B)/video

video: $(VIDEO)/photic.mp4

$(VIDEO)/series.json: video/trace.py $(B)/figures.zip
	python3 video/trace.py --img $(B)/conference/img --out $@

$(VIDEO)/features.json: video/analyse.py $(VIDEO)/series.json
	python3 video/analyse.py --series $(VIDEO)/series.json --out $@

$(VIDEO)/track.wav $(VIDEO)/score.json: video/sonify.py video/common.py $(VIDEO)/features.json
	python3 video/sonify.py --features $(VIDEO)/features.json \
	        --series $(VIDEO)/series.json \
	        --out $(VIDEO)/track.wav --score $(VIDEO)/score.json

$(VIDEO)/photic.mp4: video/render.py video/common.py $(VIDEO)/track.wav \
                     $(VIDEO)/score.json $(VIDEO)/features.json
	python3 video/render.py --scale $(SCALE) --series $(VIDEO)/series.json \
	        --features $(VIDEO)/features.json --score $(VIDEO)/score.json \
	        --audio $(VIDEO)/track.wav --out $@

# ---------------------------------------------------------------------------
# The book. 300 x 380 mm, composed page by page in Tcl and printed from the
# same headless Chromium the proceedings use.
#
# It reads the display file for every number it prints, the figure manifest for
# the plate data, conference/sources.tcl for the bibliography, and three frames
# lifted out of the reel -- which is why it depends on the video pipeline's
# feature and score files even though it renders no video itself.
#
# book/qr.tcl encodes the citation codes. book/qr-verify.py checks that encoder
# against an independent implementation; it is not wired into this target
# because it needs a package the build deliberately does not.
BOOK := $(B)/book

book: $(BOOK)/one-afternoon.pdf

$(BOOK)/frame-10.6s.png: video/render.py video/common.py $(VIDEO)/score.json \
                         $(VIDEO)/features.json
	python3 video/render.py --scale 1 --stills-only --stills 7.9,10.6,24.5 \
	        --series $(VIDEO)/series.json --features $(VIDEO)/features.json \
	        --score $(VIDEO)/score.json --out $(BOOK)/frame.png

$(BOOK)/one-afternoon.html: book/build.tcl book/qr.tcl conference/sources.tcl \
                            $(NVM) $(B)/figures.zip $(BOOK)/frame-10.6s.png
	$(TCLSH) book/build.tcl --img $(B)/conference/img --frames $(BOOK) \
	         --nvm $(NVM) --out $@

$(BOOK)/one-afternoon.pdf: $(BOOK)/one-afternoon.html book/topdf.mjs
	CHROMIUM_PATH=$(CHROMIUM) $(NODE) book/topdf.mjs $< $@

# ---------------------------------------------------------------------------
explore: $(NVM)
	$(WISH) tcl/explore.tcl $(NVM)

disasm: $(NVM)
	@$(TCLSH) tcl/nvmdump.tcl $(NVM) --disasm

dump: $(NVM)
	@$(TCLSH) tcl/nvmdump.tcl $(NVM)

# Every host reads the same bytes. If one of them stops agreeing with the
# others, that is a bug in the host and not in the analysis, and this target is
# how you find out which.
check: $(NVM)
	@echo "== container and symbol table =="
	@$(TCLSH) tcl/nvmdump.tcl $(NVM) | head -12
	@echo
	@echo "== every host executes it =="
	@$(TCLSH) physical/plot.tcl $(NVM) $(B)/check-print.svg --mode print
	@$(TCLSH) physical/plot.tcl $(NVM) $(B)/check-pen.svg   --mode pen
	@$(TCLSH) physical/card.tcl $(NVM) $(B)/check-card.svg
	@$(TCLSH) physical/solid.tcl $(NVM) $(B)/check-comb
	@$(TCLSH) web/bundle.tcl web/host.html $(NVM) $(B)/check-dash.html
	@echo
	@echo "== the analysis is reproducible from the seed =="
	@./$(ENGINE) --session $(SESSION) --prior $(PRIOR) --perm $(PERM) --seed $(SEED) \
	             --out $(B)/check.nvm --json $(B)/check.json 2>/dev/null
	@cmp -s $(NVM) $(B)/check.nvm && echo "   byte-identical rebuild: ok" \
	                              || echo "   REBUILD DIFFERS -- the pipeline is not deterministic"
	@rm -f $(B)/check-*.svg $(B)/check-*.html $(B)/check-comb.* $(B)/check.nvm $(B)/check.json

# Sketchpad's constraint drag from the command line.
#   make whatif M=beh.rt V=430
M ?= beh.rt
V ?= 430
whatif: $(ENGINE)
	@./$(ENGINE) --session $(SESSION) --prior $(PRIOR) --perm 40000 \
	             --override $(M)=$(V) --out $(B)/whatif.nvm --json $(B)/whatif.json

clean:
	rm -rf $(B)

help:
	@sed -n '2,16p' Makefile | sed 's/^# \?//'
