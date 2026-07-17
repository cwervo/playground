#!/bin/sh -e
# Builds the host harness and runs engine conformance checks against
# the same C + Jim Tcl + folk-engine.tcl stack the iOS app embeds.
cd "$(dirname "$0")/.."

mkdir -p build
cc -O2 -w -o build/folkboy-host \
    HostTest/folk_host_test.c CSources/folk_jim.c \
    -ICSources/include -IVendor

run() { printf '%s' "$1" | ./build/folkboy-host Engine/folk-engine.tcl -; }

check() {
    desc="$1"; program="$2"; expect_py="$3"
    out=$(run "$program")
    if printf '%s' "$out" | python3 -c "
import json, sys
frame = json.load(sys.stdin)
display = frame['display']
assert $expect_py, f'FAILED: {frame}'
"; then
        echo "ok   - $desc"
    else
        echo "FAIL - $desc"
        printf '       program: %s\n       output: %s\n' "$program" "$out"
        exit 1
    fi
}

check "outline + label (the FolkBoy hello program)" \
    'Wish $this is outlined green; Wish $this is labelled "hello from iOS"' \
    "display == [
        {'op':'outline','color':'green','thickness':3},
        {'op':'label','text':'hello from iOS','color':'white'}]"

check "smart quotes are normalized" \
    'Wish $this is labelled “hello from iOS”' \
    "display == [{'op':'label','text':'hello from iOS','color':'white'}]"

check "When + claimize + variable capture" \
    'Claim $this is cool
     When /p/ is cool { Wish $p is outlined gold }' \
    "display == [{'op':'outline','color':'gold','thickness':3}]"

check "nested When captures outer bindings" \
    'Claim bob is cool
     Claim sue is hot
     When /p/ is cool { When /q/ is hot { Wish $this is labelled "$p loves $q" } }' \
    "display == [{'op':'label','text':'bob loves sue','color':'white'}]"

check "thick outline variant" \
    'Wish $this is outlined thick magenta' \
    "display == [{'op':'outline','color':'magenta','thickness':7}]"

check "rest-variable options (draws a circle)" \
    'Wish $this draws a circle with radius 80 color magenta filled true' \
    "display == [{'op':'circle','color':'magenta','radius':80,'x':0,'y':0,'filled':True}]"

check "labelled with color" \
    'Wish $this is labelled "hi" with color skyblue' \
    "display == [{'op':'label','text':'hi','color':'skyblue'}]"

check "titled / highlighted / filled" \
    'Wish $this is titled "T"; Wish $this is highlighted blue; Wish $this is filled with color black' \
    "sorted(d['op'] for d in display) == ['fill','highlight','title']"

check "duplicate wishes are deduplicated" \
    'Wish $this is outlined red; Wish $this is outlined red' \
    "display == [{'op':'outline','color':'red','thickness':3}]"

check "non-capturing wildcards do not bind" \
    'Claim x is cool
     When /anyone/ claims /p/ is cool { Wish $p is outlined cyan }' \
    "display == [{'op':'outline','color':'cyan','thickness':3}]"

check "errors surface as an error op and ok:false" \
    'this-command-does-not-exist 1 2 3' \
    "frame['ok'] == False and display[0]['op'] == 'error'"

check "error in a When body does not kill the frame" \
    'Wish $this is outlined green
     When /someone/ wishes /t/ is outlined /c/ { error boom }' \
    "any(d['op'] == 'outline' for d in display) and any(d['op'] == 'error' for d in display)"

check "unmatched wishes render nothing" \
    'Wish $this is totally bogus' \
    "display == []"

echo "all host tests passed"
