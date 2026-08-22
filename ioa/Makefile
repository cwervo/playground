# ioa -- Image Over Air

TCLSH ?= tclsh

.PHONY: help test demo products transports codecs fabric plan run deploy clean

help:
	@$(TCLSH) ioa.tcl help

test:
	@$(TCLSH) tests/all.tcl

demo:
	@$(TCLSH) ioa.tcl demo

products:
	@$(TCLSH) ioa.tcl products

transports:
	@$(TCLSH) ioa.tcl transports

codecs:
	@$(TCLSH) ioa.tcl codecs

# make plan FROM=eye-01 TO=desk WANT=webcam FABRIC=studio.ioa
FABRIC ?= studio.ioa
FROM   ?= eye-01
TO     ?= desk
WANT   ?= webcam

fabric:
	@$(TCLSH) ioa.tcl fabric --fabric $(FABRIC)

plan:
	@$(TCLSH) ioa.tcl plan --fabric $(FABRIC) --from $(FROM) --to $(TO) --want $(WANT)

run:
	@$(TCLSH) ioa.tcl run --fabric $(FABRIC) --from $(FROM) --to $(TO) --want $(WANT)

deploy:
	@$(TCLSH) ioa.tcl deploy --fabric $(FABRIC) --from $(FROM) --to $(TO) --want $(WANT)

clean:
	@rm -f *.ioaf
