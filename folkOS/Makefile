TCLSH ?= tclsh

.PHONY: all validate generate clean

all: validate generate

validate:
	$(TCLSH) folklang.bnf.tcl validate

generate: validate
	mkdir -p generated
	$(TCLSH) folklang.bnf.tcl emit ebnf   > generated/folklang.ebnf
	$(TCLSH) folklang.bnf.tcl emit json   > generated/folklang.json
	$(TCLSH) folklang.bnf.tcl emit matrix > generated/capability-matrix.md

clean:
	rm -rf generated
