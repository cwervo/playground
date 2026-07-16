# folklang.bnf.tcl — the folkOS source of truth for the Folk language.
#
# This file is a *machine-readable description* of folklang: the
# reactive, natural-language-Datalog DSL implemented by the Folk
# system (https://github.com/folkcomputer/folk). It is written in Tcl
# on purpose — Tcl is folklang's host language, so the descriptor can
# be sourced by Folk itself, by test harnesses, and by code
# generators, and its pattern literals (`/someone/ wishes ...`) are
# written in the exact same notation the live system uses.
#
# It describes four layers:
#
#   Layer 0  host      Tcl word/command structure (folk programs ARE
#                      Tcl scripts; this layer is what any simulator's
#                      reader must implement first)
#   Layer 1  forms     the folk reactive forms (Claim / Wish / When /
#                      Say / Hold! / On unmatch / Query! / ...)
#   Layer 2  patterns  the statement-pattern sublanguage (/var/,
#                      /...rest/, wildcards, negation, & joins)
#   Layer 3  clauses   the natural-language statement *conventions*
#                      (has/is/with shapes — not enforced by the
#                      engine, but what the stdlib vocabulary follows)
#
# plus two registries that are NOT grammar but are part of the
# language standard in practice:
#
#   vocab     the standard-library statement vocabulary (labels,
#             outlines, image/gif display, canvases, draw commands,
#             camera slices, ...) extracted from folk's
#             builtin-programs/ (formerly virtual-programs/)
#   features / renderers
#             a capability matrix skeleton: which planned folkOS
#             simulator/renderer backend supports which slice of the
#             syntax and stdlib
#
# Everything downstream (JS/WASM/C++ simulators, renderers) should be
# generated from or validated against THIS file, typically via:
#
#   tclsh folklang.bnf.tcl validate         # self-check the grammar
#   tclsh folklang.bnf.tcl emit ebnf        # human-readable EBNF
#   tclsh folklang.bnf.tcl emit json        # for JS/C++/WASM tooling
#   tclsh folklang.bnf.tcl emit matrix      # renderer capability matrix (markdown)
#
# Grammar notation used in `rule` bodies (a small EBNF dialect):
#   name         a nonterminal (must be defined by another `rule`)
#   NAME         a lexical terminal (must be defined by `terminal`)
#   'text'       a literal token
#   x? x* x+     optional / zero-or-more / one-or-more
#   ( ... )      grouping
#   x | y        alternation
#
# One honest caveat, encoded here rather than hidden: folklang's top
# layer is NOT context-free. It is Tcl — command dispatch, brace
# balancing, and runtime substitution decide meaning. So Layer 0 is a
# faithful-but-abbreviated word grammar, Layers 1–2 are genuinely
# BNF-able (they're what a simulator must implement to be "folklang"),
# and Layer 3 is convention. The registries carry the rest.

namespace eval ::folklang {
    variable meta      [dict create]
    variable terminals [dict create]   ;# name -> {description regex}
    variable ruleOrder {}
    variable rules     [dict create]   ;# name -> {layer description alternatives}
    variable vocab     [dict create]   ;# id   -> {kind pattern feature provider description}
    variable vocabOrder {}
    variable features  [dict create]   ;# id   -> {title description}
    variable featureOrder {}
    variable renderers [dict create]   ;# id   -> {title tech status syntax caps notes}
    variable rendererOrder {}

    proc meta {key value} {
        variable meta
        dict set meta $key $value
    }

    proc terminal {name description regex} {
        variable terminals
        if {[dict exists $terminals $name]} { error "duplicate terminal $name" }
        dict set terminals $name [dict create description $description regex $regex]
    }

    # rule name ?-layer N? description {alternative ...}
    proc rule {name args} {
        variable rules
        variable ruleOrder
        set layer 1
        while {[string index [lindex $args 0] 0] eq "-"} {
            set flag [lindex $args 0]
            set args [lrange $args 1 end]
            switch -- $flag {
                -layer { set layer [lindex $args 0]; set args [lrange $args 1 end] }
                default { error "rule $name: unknown flag $flag" }
            }
        }
        lassign $args description alternatives
        if {[dict exists $rules $name]} { error "duplicate rule $name" }
        dict set rules $name [dict create \
            layer $layer description $description alternatives $alternatives]
        lappend ruleOrder $name
    }

    # vocab id kind feature provider pattern description
    #   kind: wish-handler | claim-source | when-source | statement
    proc vocab {id kind feature provider pattern description} {
        variable vocab
        variable vocabOrder
        if {[dict exists $vocab $id]} { error "duplicate vocab $id" }
        dict set vocab $id [dict create \
            kind $kind feature $feature provider $provider \
            pattern $pattern description $description]
        lappend vocabOrder $id
    }

    proc feature {id title description} {
        variable features
        variable featureOrder
        if {[dict exists $features $id]} { error "duplicate feature $id" }
        dict set features $id [dict create title $title description $description]
        lappend featureOrder $id
    }

    # renderer id title tech status syntaxLevel capsDict notes
    #   status: reference | planned
    #   syntaxLevel: full | headless | subset-planned
    #   capsDict: feature-id -> yes | partial | no | planned | unknown
    proc renderer {id title tech status syntax caps notes} {
        variable renderers
        variable rendererOrder
        if {[dict exists $renderers $id]} { error "duplicate renderer $id" }
        dict set renderers $id [dict create \
            title $title tech $tech status $status syntax $syntax \
            caps $caps notes $notes]
        lappend rendererOrder $id
    }
}

# ======================================================================
# Metadata / provenance
# ======================================================================

::folklang::meta name        "folklang"
::folklang::meta version     "0.1.0"
::folklang::meta description "Folk reactive natural-language-Datalog DSL (Tcl host)"
::folklang::meta upstream    "https://github.com/folkcomputer/folk"
::folklang::meta upstream-commit "33e89446f6838288905a127862ccd2c130891be2"
::folklang::meta upstream-date   "2026-07-10"
::folklang::meta upstream-sources {prelude.tcl folk.c trie.c db.c builtin-programs/}
::folklang::meta note {
    builtin-programs/ was called virtual-programs/ in earlier folk
    revisions; the stdlib vocabulary below is the same lineage.
}

# ======================================================================
# Lexical terminals
# ======================================================================

::folklang::terminal IDENT   "identifier (variable / fn name)"      {[A-Za-z_][A-Za-z0-9_-]*}
::folklang::terminal INTEGER "integer literal"                      {-?[0-9]+}
::folklang::terminal NUMBER  "integer or float literal"             {-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?}
::folklang::terminal BARE-CHAR "any char legal in a bare Tcl word"  {[^\s;"\{\}\[\]\$\\]}
::folklang::terminal QUOTE-CHAR "any char inside double quotes except \" \\ \$ \[" {[^"\\\$\[]}
::folklang::terminal BRACE-TEXT "brace-balanced text (raw; no substitution)" {(?:[^{}]|\{(?R)\})*}
::folklang::terminal LINE-TEXT "rest of line"                       {[^\n]*}
::folklang::terminal WS      "intra-command whitespace"             {[ \t]+(?:\\\n[ \t]*)?}
::folklang::terminal COMMAND-END "command separator"                {[\n;]}
::folklang::terminal COLOR   "color name or #rrggbb (Tk-style color words)" {[a-zA-Z]+|#[0-9a-fA-F]{6}}

# ======================================================================
# Layer 0 — host script structure (Tcl, abbreviated dodecalogue)
#
# A .folk file is a Tcl script evaluated in a Folk interpreter. A
# simulator does not need a full Tcl; it needs at least this word
# reader plus the Layer-1 form dispatch. `body` blocks recurse into
# folk-script, which is how When bodies nest arbitrarily deep.
# ======================================================================

::folklang::rule folk-script -layer 0 \
    "A folk program: a sequence of commands (this is a Tcl script)" {
    { (command | comment)* }
}
::folklang::rule command -layer 0 \
    "One command: words separated by whitespace, ended by newline or ;" {
    { word (WS word)* COMMAND-END }
}
::folklang::rule comment -layer 0 \
    "Comment: # at command position through end of line" {
    { '#' LINE-TEXT COMMAND-END }
}
::folklang::rule word -layer 0 \
    "A Tcl word; braces are raw, quotes and bare words substitute" {
    { braced-word }
    { quoted-word }
    { bare-word }
}
::folklang::rule braced-word -layer 0 \
    "Brace-quoted word: no substitution, braces must balance" {
    { '{' BRACE-TEXT '}' }
}
::folklang::rule quoted-word -layer 0 \
    "Double-quoted word: \$var, \[cmd\], and backslash substitution apply" {
    { '"' (QUOTE-CHAR | substitution)* '"' }
}
::folklang::rule bare-word -layer 0 \
    "Unquoted word: ends at whitespace; substitutions apply" {
    { (BARE-CHAR | substitution)+ }
}
::folklang::rule substitution -layer 0 \
    "Runtime substitution inside quoted/bare words" {
    { variable-sub }
    { command-sub }
    { backslash-sub }
}
::folklang::rule variable-sub -layer 0 \
    "Variable substitution" {
    { '$' IDENT }
    { '$' '{' BRACE-TEXT '}' }
}
::folklang::rule command-sub -layer 0 \
    "Command substitution: evaluates a nested script" {
    { '[' folk-script ']' }
}
::folklang::rule backslash-sub -layer 0 \
    "Backslash escape (\\n, \\t, \\\\, \\<newline> line-continuation, ...)" {
    { '\\' LINE-TEXT }
}
::folklang::rule body -layer 0 \
    "A code block argument: a braced word whose content is a folk-script.
     Lexical environment is captured around it (captureEnvStack) unless
     -noncapturing is given on the enclosing form" {
    { braced-word }
}

# ======================================================================
# Layer 1 — folk reactive forms
#
# These are the commands that make a Tcl script a *folk* program.
# Semantics (normative, from prelude.tcl):
#   - Claim X   => Say $this claims X
#   - Wish  X   => Say $this wishes X
#   - When P {B} reruns B whenever a statement matching P exists; the
#     body's statements are retracted when the match is removed.
#   - When also auto-matches the claimized form (/someone/ claims P).
#   - Hold! keeps a statement across re-evaluations under a key.
#   - On unmatch {B} registers a destructor for the current match.
# ======================================================================

::folklang::rule folk-form -layer 1 \
    "Any folk reactive form (all are ordinary commands to the host)" {
    { claim-form } { wish-form } { when-form } { say-form }
    { hold-form } { on-unmatch-form } { subscribe-form } { notify-form }
    { query-form } { query-one-form } { expect-form } { foreach-form }
    { fn-form } { assert-form }
}
::folklang::rule claim-form -layer 1 \
    "Assert a fact on behalf of \$this: (this claims <clause>)" {
    { 'Claim' statement-modifier* clause }
}
::folklang::rule wish-form -layer 1 \
    "Declare a desire on behalf of \$this: (this wishes <clause>)" {
    { 'Wish' statement-modifier* clause }
}
::folklang::rule say-form -layer 1 \
    "Assert a raw statement (subject and verb explicit)" {
    { 'Say' statement-modifier* clause }
}
::folklang::rule statement-modifier -layer 1 \
    "Modifiers accepted by Say / Claim / Wish" {
    { '-keep' duration }
    { '-nonatomically' }
    { '-destructor' body }
}
::folklang::rule when-form -layer 1 \
    "React to matching statements; body reruns per match" {
    { 'When' when-modifier* join-pattern body }
}
::folklang::rule when-modifier -layer 1 \
    "Modifiers accepted by When" {
    { '-noncapturing' }
    { '-serially' }
    { '-atomically' }
    { '-atomicallyInherit' }
    { '-atomicallyWithKey' word }
    { '-nonatomically' }
}
::folklang::rule hold-form -layer 1 \
    "Hold a statement (or a when-body) stably across program re-runs.
     Clause may use Claim/Wish sugar; a lone body holds a when-block" {
    { 'Hold!' hold-modifier* '--' clause }
    { 'Hold!' hold-modifier* body }
    { 'Hold!' hold-modifier* ('Claim' | 'Wish')? clause? }
}
::folklang::rule hold-modifier -layer 1 \
    "Modifiers accepted by Hold!" {
    { '-on' word }
    { '-key' word }
    { '-keep' duration }
    { '-source' word }
    { '-destructor' body }
    { '-version' word }
    { '-noncapturing' }
    { '-save' }
}
::folklang::rule on-unmatch-form -layer 1 \
    "Destructor: runs when the enclosing When's match is retracted" {
    { 'On' 'unmatch' body }
}
::folklang::rule subscribe-form -layer 1 \
    "Subscribe to matches outside the reactive graph (advanced)" {
    { 'Subscribe:' pattern body }
}
::folklang::rule notify-form -layer 1 \
    "Fire-and-forget notification statement (e.g. save requests)" {
    { 'Notify:' clause }
}
::folklang::rule query-form -layer 1 \
    "Synchronous sampling query; returns list of binding dicts" {
    { 'Query!' '-atomically'? join-pattern }
}
::folklang::rule query-one-form -layer 1 \
    "Query expecting exactly one result (error otherwise)" {
    { 'QueryOne!' ('-default' word)? pattern }
}
::folklang::rule expect-form -layer 1 \
    "QueryOne! that binds results directly into caller scope" {
    { 'Expect!' pattern }
}
::folklang::rule foreach-form -layer 1 \
    "Iterate a query's results, binding each result dict in body" {
    { 'ForEach!' join-pattern body }
}
::folklang::rule fn-form -layer 1 \
    "Define/capture a lexically-scoped function shareable through statements" {
    { 'fn' IDENT arg-list body }
    { 'fn' IDENT }
}
::folklang::rule arg-list -layer 1 \
    "Function argument names, as a Tcl list word" {
    { word }
}
::folklang::rule assert-form -layer 1 \
    "Runtime assertion of a Tcl expr condition" {
    { 'assert' word }
}
::folklang::rule duration -layer 1 \
    "Duration literal, e.g. 50ms (microseconds appear as N us in options)" {
    { INTEGER 'ms' }
}

# ======================================================================
# Layer 2 — statement patterns
#
# Patterns are ordinary Tcl words to the reader; the trie matcher
# (trie.c) gives them meaning word-by-word:
#   /name/       capture variable, binds $name in the body
#   /...name/    rest variable: captures all remaining terms
#   /any/ /anyone/ /someone/ /something/ /anything/
#                non-capturing wildcards (trieVariableNameIsNonCapturing)
#   /nobody/ /nothing/
#                negation: body runs when NO statement matches
#   $name        in a joined (&) pattern: substitute a binding from an
#                earlier pattern in the same When (bound reference)
#   &            join: all patterns must match simultaneously
# Variable names may not contain spaces.
# ======================================================================

::folklang::rule join-pattern -layer 2 \
    "One or more patterns joined with &; later ones see earlier bindings" {
    { pattern ('&' pattern)* }
}
::folklang::rule pattern -layer 2 \
    "A statement pattern: a sequence of terms matched word-by-word" {
    { pattern-term+ }
}
::folklang::rule pattern-term -layer 2 \
    "One term of a pattern" {
    { match-variable }
    { bound-reference }
    { word }
}
::folklang::rule match-variable -layer 2 \
    "Slash-delimited variable/wildcard/negation term" {
    { '/' variable-name '/' }
}
::folklang::rule variable-name -layer 2 \
    "Capture name, rest-capture, wildcard, or negation word" {
    { '...' IDENT }
    { wildcard-name }
    { negation-name }
    { IDENT }
}
::folklang::rule wildcard-name -layer 2 \
    "Matches any single term without binding it" {
    { 'any' } { 'anyone' } { 'someone' } { 'something' } { 'anything' }
}
::folklang::rule negation-name -layer 2 \
    "Negates the whole pattern: match when nothing matches" {
    { 'nobody' } { 'nothing' }
}
::folklang::rule bound-reference -layer 2 \
    "Reference to a binding from an earlier joined pattern (or scope)" {
    { '$' IDENT }
}

# ======================================================================
# Layer 3 — clause conventions (natural-language Datalog)
#
# The engine matches arbitrary word sequences; these shapes are the
# CONVENTIONS the standard library follows, and what folkOS tooling
# should lint toward. Normalized statements in the database are
# (subject claims|wishes ...) — Claim/Wish add subject+verb, and When
# auto-wraps patterns lacking claims/wishes in (/someone/ claims _).
# ======================================================================

::folklang::rule statement -layer 3 \
    "A normalized database statement" {
    { subject 'claims' clause }
    { subject 'wishes' clause }
    { clause }
}
::folklang::rule subject -layer 3 \
    "Who is speaking: a program/page id (usually \$this) or node" {
    { word }
}
::folklang::rule clause -layer 3 \
    "The content of a claim/wish; conventional shapes below" {
    { has-clause }
    { is-clause }
    { does-clause }
    { pattern-term+ }
}
::folklang::rule has-clause -layer 3 \
    "Attribute shape: <entity> has <attribute...> <value> ?with-options?" {
    { entity 'has' pattern-term+ with-options? }
}
::folklang::rule is-clause -layer 3 \
    "Classification/decoration shape: <entity> is <description...>" {
    { entity 'is' pattern-term+ with-options? }
}
::folklang::rule does-clause -layer 3 \
    "Action shape: <entity> <verb> <complement...> (draws, displays, points, runs...)" {
    { entity pattern-term+ with-options? }
}
::folklang::rule entity -layer 3 \
    "The thing spoken about: page id, tag id, camera path, node, ..." {
    { pattern-term }
}
::folklang::rule with-options -layer 3 \
    "Keyword-options tail: with key value key value ... ; a rest
     variable /...options/ conventionally captures it as a dict" {
    { 'with' (option-key option-value)+ }
}
::folklang::rule option-key -layer 3 \
    "Option name (color, scale, width, height, layer, font, filled, ...)" {
    { IDENT }
}
::folklang::rule option-value -layer 3 \
    "Option value: any single word" {
    { word }
}

# ======================================================================
# Standard-library statement vocabulary
#
# Extracted from folk builtin-programs/ (née virtual-programs/) at the
# pinned upstream commit. `wish-handler` means the stdlib installs a
# When over (wishes <pattern>) — this is the *effectful surface* a
# renderer must implement. `claim-source` means the stdlib produces
# these claims — a simulator must synthesize them (e.g. fake camera
# frames, clock). Patterns are templates: /x/ marks a variable slot.
# ======================================================================

# --- decorations ------------------------------------------------------
::folklang::vocab outline wish-handler decorations builtin-programs/decorations/outline.folk \
    {/thing/ is outlined /color/} \
    "Draw an outline around a page/region; 'thick' prefix variant exists"
::folklang::vocab label wish-handler decorations builtin-programs/decorations/label.folk \
    {/thing/ is labelled /text/ with-options?} \
    "Render text label on a page (options: font, size, color, position)"
::folklang::vocab title wish-handler decorations builtin-programs/title.folk \
    {/thing/ is titled /text/} \
    "Title above a page"
::folklang::vocab highlight wish-handler decorations builtin-programs/_archive/highlight.folk \
    {/thing/ is highlighted /color/} \
    "Fill a page's region with translucent color"
::folklang::vocab fill wish-handler decorations builtin-programs/draw/fill.folk \
    {/thing/ is filled with color /color/} \
    "Solid fill of a page's quad"

# --- canvas & 2D drawing ---------------------------------------------
::folklang::vocab canvas wish-handler canvas builtin-programs/gpu/canvases.folk \
    {/p/ has a canvas with-options?} \
    "Allocate a GPU canvas for a page (options: width, height, layer, settle)"
::folklang::vocab canvas-claim claim-source canvas builtin-programs/gpu/canvases.folk \
    {/p/ has canvas /id/ with /...options/} \
    "Canvas allocation result; canvas projection claimed alongside"
::folklang::vocab draw-shape wish-handler draw2d builtin-programs/draw/shapes.folk \
    {/p/ draws a /shape/ with-options?} \
    "Draw a named shape (circle, arc, ...; options: color, filled, radius...)"
::folklang::vocab draw-polygon wish-handler draw2d builtin-programs/draw/shapes.folk \
    {/p/ draws a polygon /points/ with-options?} \
    "Filled/stroked polygon in page coordinates"
::folklang::vocab draw-polyline wish-handler draw2d builtin-programs/draw/curve.folk \
    {/p/ draws a polyline /points/ with-options?} \
    "Open polyline / curve"
::folklang::vocab draw-line wish-handler draw2d builtin-programs/draw/line.folk \
    {/p/ draws a line from /a/ to /b/ with-options?} \
    "Line segment (dashed variant in draw/dashed-line.folk)"
::folklang::vocab draw-points wish-handler draw2d builtin-programs/draw/shapes.folk \
    {/p/ draws points /points/ with-options?} \
    "Point cloud"
::folklang::vocab draw-text wish-handler draw2d builtin-programs/draw/text.folk \
    {/p/ draws text /text/ with-options?} \
    "Raw text drawing (label is the higher-level form)"
::folklang::vocab toy-shader wish-handler gpu-shader builtin-programs/gpu/toy-shader.folk \
    {/p/ draws toy shader /shaderCode/} \
    "Shadertoy-style fragment shader on a page quad"
::folklang::vocab gpu-pipeline wish-handler gpu-shader builtin-programs/gpu/pipelines.folk \
    {the GPU compiles pipeline /name/ /source/} \
    "Compile a custom GPU pipeline (also: compiles function; creates canvas; loads image as texture)"

# --- images / media ---------------------------------------------------
::folklang::vocab display-image wish-handler image builtin-programs/draw/image.folk \
    {/p/ displays image /im/ with-options?} \
    "Blit an image value onto a page (options: scale, width, x, y)"
::folklang::vocab image-loader-jpeg claim-source image-jpeg builtin-programs/image/jpeg-lib.folk \
    {/loaderFn/ is an image loader} \
    "JPEG codec registered as an image loader fn"
::folklang::vocab image-loader-png claim-source image-png builtin-programs/image/png-lib.folk \
    {/loaderFn/ is an image loader} \
    "PNG codec registered as an image loader fn"
::folklang::vocab display-gif wish-handler image-gif builtin-programs/draw/gif.folk \
    {/p/ displays gif /gif/ with-options?} \
    "Animated GIF playback on a page (gif-lib.folk decodes frames)"
::folklang::vocab sprite wish-handler sprite builtin-programs/sprites.folk \
    {/p/ draws sprite /path/ with /n/ frames and /m/ columns} \
    "Sprite-sheet animation"
::folklang::vocab camera-slice wish-handler camera-slice builtin-programs/camera/slice.folk \
    {/p/ has camera slice} \
    "Crop of the camera image under a page's quad, claimed back as (has camera slice /slice/)"
::folklang::vocab display-camera-slice wish-handler camera-slice builtin-programs/camera/slice.folk \
    {/p/ displays camera slice /slice/} \
    "Show a captured slice on a page"

# --- vision / physical substrate -------------------------------------
::folklang::vocab camera-frame claim-source camera builtin-programs/camera/usb.folk \
    {camera /camera/ has frame /frame/ at timestamp /ts/} \
    "Camera frames (also: gray frame, jpeg frame, width/height claims)"
::folklang::vocab use-camera wish-handler camera builtin-programs/camera/enumerate.folk \
    {$::thisNode uses camera /camera/ with /...options/} \
    "Enable a camera on this node"
::folklang::vocab display-info claim-source canvas builtin-programs/gpu/enumerate.folk \
    {$::thisNode has display /display/ with info /info/} \
    "Display enumeration; display /d/ has width/height claims follow"
::folklang::vocab tag-detection claim-source apriltags builtin-programs/apriltags.folk \
    {tag /id/ has detection /det/ on camera /camera/} \
    "AprilTag detections (tag ... is a tag, tag ... has a program follow)"
::folklang::vocab page-quad claim-source geometry builtin-programs/tags-to-quads.folk \
    {/thing/ has quad /q/} \
    "Physical pose of a page as a quad; also (has region /r/), (has resolved geometry /g/)"
::folklang::vocab points-at claim-source geometry builtin-programs/points-at.folk \
    {/rect/ points /direction/ at /target/} \
    "Spatial pointing relation between pages (variant: with length /l/)"
::folklang::vocab wish-points wish-handler geometry builtin-programs/points-at.folk \
    {/rect/ points /direction/ with length /l/} \
    "Ask for a pointing whisker of a given length"
::folklang::vocab neighbors wish-handler geometry builtin-programs/intersect.folk \
    {/p/ has neighbors} \
    "Compute adjacent pages; claims (has neighbor /p2/)"
::folklang::vocab calibration claim-source calibration builtin-programs/calibrate/load-calibration.folk \
    {a calibration from camera /camera/ to display /display/ is /calibration/} \
    "Camera->display homography; intrinsics/extrinsics claims alongside"
::folklang::vocab connections wish-handler connections builtin-programs/connections.folk \
    {/source/ is connected to /sink/ /...options/} \
    "Draw a connecting line between two pages (dynamic variant exists)"
::folklang::vocab contours wish-handler recognition builtin-programs/recognition/contours.folk \
    {/p/ has contours} \
    "Image contours of a page's slice; SAM2/CRAFT/TrOCR loaders adjacent"

# --- interaction / system --------------------------------------------
::folklang::vocab keyboard claim-source keyboard builtin-programs/keyboard.folk \
    {/k/ is a keyboard with path /path/ locale /locale/} \
    "Keyboard devices; (/k/ is typing into /program/), (has keyboard input)"
::folklang::vocab clock claim-source clock builtin-programs/gpu/gpu.folk \
    {the clock time is /t/} \
    "Per-frame clock claim driving animation (auto-atomically in When)"
::folklang::vocab collect wish-handler collect builtin-programs/collect.folk \
    {to collect results for /pattern/ with settle /settle/} \
    "Aggregate: claims (the collected results for /pattern/ are /results/)"
::folklang::vocab unix-command wish-handler unix builtin-programs/unix-commands.folk \
    {/p/ runs Unix command /command/ with-options?} \
    "Spawn a process; claims (has Unix output lines /lines/), (has Unix error output /e/)"
::folklang::vocab error-claim claim-source errors prelude.tcl \
    {/p/ has error /err/ with info /info/} \
    "Runtime errors surface as statements; errors.folk renders them"
::folklang::vocab program-code claim-source programs builtin-programs/programs.folk \
    {/p/ has program code /code/} \
    "Program source as data; editor/print pipeline consumes it"
::folklang::vocab editor when-source editor builtin-programs/editor/editor.folk \
    {/editor/ is an editor with /...options/} \
    "On-table editor pages"
::folklang::vocab print wish-handler print builtin-programs/print/print.folk \
    {printer /name/ is a cups printer with /...options/} \
    "Printing programs onto paper (esc-pos.folk for receipt printers)"
::folklang::vocab terminal wish-handler terminal builtin-programs/terminal.folk \
    {/thing/ is a terminal spawning /cmd/} \
    "Interactive terminal on a page"
::folklang::vocab audio when-source audio builtin-programs/audio.folk \
    {/p/ plays audio /...options/} \
    "Audio playback / music.folk sequencing"
::folklang::vocab web when-source web builtin-programs/web/web.folk \
    {/page/ has editor code /code/} \
    "Web dashboard: browser-based editing, db inspection, camera views"

# ======================================================================
# Feature registry — the axes of the capability matrix
# ======================================================================

::folklang::feature core-syntax   "Core syntax"        "Layers 0-2: reader, Claim/Wish/When/Hold!/On unmatch, patterns, joins, negation, rest-vars"
::folklang::feature reactive-db   "Reactive DB"        "Statement trie, incremental match/unmatch, destructors, -keep expiry, atomically"
::folklang::feature decorations   "Decorations"        "outlined / labelled / titled / highlighted / filled"
::folklang::feature canvas        "Canvas"             "Per-page canvas allocation, layers, projections"
::folklang::feature draw2d        "2D drawing"         "shapes, polygons, polylines, lines, points, text"
::folklang::feature image         "Image display"      "displays image, scaling, placement"
::folklang::feature image-jpeg    "JPEG codec"         "decode/encode (camera frames, saved slices)"
::folklang::feature image-png     "PNG codec"          "decode (assets, editor previews)"
::folklang::feature image-gif     "GIF playback"       "decode + animate"
::folklang::feature sprite        "Sprite sheets"      "frame/column sprite animation"
::folklang::feature video         "Video"              "video file / stream playback (no builtin upstream; folkOS extension)"
::folklang::feature camera        "Camera input"       "frames, formats, enumeration (simulators: synthetic frames)"
::folklang::feature camera-slice  "Camera slices"      "per-page crops of camera image"
::folklang::feature apriltags     "AprilTags"          "tag detection claims (simulators: virtual tag poses)"
::folklang::feature geometry      "Page geometry"      "quads, regions, resolved geometry, points-at, neighbors"
::folklang::feature calibration   "Calibration"        "camera<->display mapping (simulators: identity)"
::folklang::feature connections   "Connections"        "lines between pages"
::folklang::feature recognition   "Recognition"        "contours, SAM2, CRAFT, TrOCR"
::folklang::feature keyboard      "Keyboard"           "device claims, typing-into, shortcuts"
::folklang::feature clock         "Clock/animation"    "the clock time is /t/ frame driver"
::folklang::feature collect       "Collect"            "collected-results aggregation"
::folklang::feature unix          "Unix processes"     "runs Unix command, output claims"
::folklang::feature errors        "Error surfacing"    "error statements + display"
::folklang::feature programs      "Program mgmt"       "program code claims, saving, groups, demos"
::folklang::feature editor        "Editor"             "on-table editing"
::folklang::feature print         "Printing"           "CUPS / ESC-POS output"
::folklang::feature gpu-shader    "Custom shaders"     "toy shaders, GPU pipelines/functions"
::folklang::feature terminal      "Terminal pages"     "PTY on a page"
::folklang::feature audio         "Audio"              "playback / music"
::folklang::feature web           "Web dashboard"      "browser inspection/editing"

# ======================================================================
# Renderer / simulator target registry
#
# status:  reference (exists upstream) | planned (folkOS target)
# syntax:  expected Layer 0-2 support (full = complete reader+engine)
# caps:    feature-id -> yes | partial | no | planned | unknown
#          (reference entries describe upstream folk today; planned
#          entries are the goal state for a first milestone)
# ======================================================================

set ::folklang::_allYes {}
foreach f $::folklang::featureOrder { dict set ::folklang::_allYes $f yes }

::folklang::renderer folk-vulkan "Folk native (Vulkan)" "C + Jim Tcl + Vulkan" reference full \
    [dict replace $::folklang::_allYes video no] \
    "Upstream reference implementation; baseline for conformance. Video not built in."

::folklang::renderer folkos-vulkan "folkOS Vulkan clone" "C++ + Vulkan" planned full \
    {core-syntax planned reactive-db planned decorations planned canvas planned
     draw2d planned image planned image-jpeg planned image-png planned
     image-gif planned sprite planned video planned camera planned
     camera-slice planned apriltags planned geometry planned calibration planned
     connections planned recognition unknown keyboard planned clock planned
     collect planned unix planned errors planned programs planned editor planned
     print unknown gpu-shader planned terminal unknown audio unknown web planned} \
    "Clone + refine of upstream pipeline; parity target."

::folklang::renderer sim-js-cli "JS simulator (headless CLI)" "Node.js" planned full \
    {core-syntax planned reactive-db planned decorations planned canvas no
     draw2d no image no image-jpeg planned image-png planned image-gif planned
     sprite no video no camera planned camera-slice planned apriltags planned
     geometry planned calibration planned connections no recognition no
     keyboard planned clock planned collect planned unix planned errors planned
     programs planned editor no print no gpu-shader no terminal no audio no web planned} \
    "Engine-first target: reader + reactive db + synthetic claims; renders nothing, asserts everything."

::folklang::renderer sim-wasm "WASM simulator" "engine compiled to WASM" planned full \
    {core-syntax planned reactive-db planned decorations planned canvas planned
     draw2d planned image planned image-jpeg planned image-png planned
     image-gif planned sprite planned video no camera planned
     camera-slice planned apriltags planned geometry planned calibration planned
     connections planned recognition no keyboard planned clock planned
     collect planned unix no errors planned programs planned editor unknown
     print no gpu-shader unknown terminal no audio unknown web planned} \
    "Shared core for browser targets; no subprocess spawning in-sandbox."

::folklang::renderer sim-cpp-cli "C++ simulator (CLI)" "C++20" planned full \
    {core-syntax planned reactive-db planned decorations planned canvas planned
     draw2d planned image planned image-jpeg planned image-png planned
     image-gif planned sprite planned video planned camera planned
     camera-slice planned apriltags planned geometry planned calibration planned
     connections planned recognition unknown keyboard planned clock planned
     collect planned unix planned errors planned programs planned editor unknown
     print unknown gpu-shader unknown terminal planned audio unknown web unknown} \
    "Native engine; substrate for SDL/Metal/Vulkan frontends."

::folklang::renderer render-ascii "CLI ASCII emulation" "terminal cells" planned full \
    {core-syntax planned reactive-db planned decorations partial canvas partial
     draw2d partial image partial image-jpeg partial image-png partial
     image-gif partial sprite partial video no camera planned
     camera-slice partial apriltags planned geometry planned calibration planned
     connections partial recognition no keyboard planned clock planned
     collect planned unix planned errors planned programs planned editor partial
     print no gpu-shader no terminal planned audio no web no} \
    "Everything visual degrades to cells: outlines are box-drawing, images are half-block mosaics."

::folklang::renderer render-sdl "Linux SDL renderer" "C++ + SDL2/SDL3" planned full \
    {core-syntax planned reactive-db planned decorations planned canvas planned
     draw2d planned image planned image-jpeg planned image-png planned
     image-gif planned sprite planned video planned camera planned
     camera-slice planned apriltags planned geometry planned calibration planned
     connections planned recognition unknown keyboard planned clock planned
     collect planned unix planned errors planned programs planned editor planned
     print unknown gpu-shader partial terminal planned audio planned web unknown} \
    "Software/GL 2D path; gpu-shader partial (translate toy shaders to GLSL)."

::folklang::renderer render-js-canvas "JS <canvas> 2D" "TS + Canvas2D" planned full \
    {core-syntax planned reactive-db planned decorations planned canvas planned
     draw2d planned image planned image-jpeg yes image-png yes image-gif planned
     sprite planned video planned camera planned camera-slice planned
     apriltags planned geometry planned calibration planned connections planned
     recognition no keyboard planned clock planned collect planned unix no
     errors planned programs planned editor planned print no gpu-shader no
     terminal no audio planned web planned} \
    "Browser codecs are free (jpeg/png via Image, video via <video>); shaders unsupported."

::folklang::renderer render-js-wasm-canvas "JS+WASM <canvas>" "WASM engine + Canvas2D" planned full \
    {core-syntax planned reactive-db planned decorations planned canvas planned
     draw2d planned image planned image-jpeg yes image-png yes image-gif planned
     sprite planned video planned camera planned camera-slice planned
     apriltags planned geometry planned calibration planned connections planned
     recognition unknown keyboard planned clock planned collect planned unix no
     errors planned programs planned editor planned print no gpu-shader no
     terminal no audio planned web planned} \
    "Same surface as render-js-canvas with the WASM engine core."

::folklang::renderer render-webgpu "JS WebGPU <canvas>" "WASM/TS + WebGPU" planned full \
    {core-syntax planned reactive-db planned decorations planned canvas planned
     draw2d planned image planned image-jpeg yes image-png yes image-gif planned
     sprite planned video planned camera planned camera-slice planned
     apriltags planned geometry planned calibration planned connections planned
     recognition unknown keyboard planned clock planned collect planned unix no
     errors planned programs planned editor planned print no gpu-shader planned
     terminal no audio planned web planned} \
    "Closest browser analog to upstream's Vulkan path; toy shaders retargeted to WGSL."

::folklang::renderer render-metal-macos "Metal renderer (macOS)" "Swift/ObjC++ + Metal" planned full \
    {core-syntax planned reactive-db planned decorations planned canvas planned
     draw2d planned image planned image-jpeg yes image-png yes image-gif planned
     sprite planned video planned camera planned camera-slice planned
     apriltags planned geometry planned calibration planned connections planned
     recognition unknown keyboard planned clock planned collect planned unix planned
     errors planned programs planned editor planned print unknown
     gpu-shader planned terminal unknown audio planned web unknown} \
    "MSL retarget of shader surface; AVFoundation for camera/video."

::folklang::renderer render-metal-ios "Metal renderer (iOS)" "Swift + Metal" planned full \
    {core-syntax planned reactive-db planned decorations planned canvas planned
     draw2d planned image planned image-jpeg yes image-png yes image-gif planned
     sprite planned video planned camera planned camera-slice planned
     apriltags planned geometry planned calibration planned connections planned
     recognition unknown keyboard partial clock planned collect planned unix no
     errors planned programs planned editor partial print no gpu-shader planned
     terminal no audio planned web unknown} \
    "Touch-first; no subprocesses; camera is the device camera."

unset ::folklang::_allYes

# ======================================================================
# Toolchain: validate + emitters
# ======================================================================

namespace eval ::folklang {

    # --- EBNF alternative tokenizer (shared by validate and emitters) --
    proc tokenizeAlt {alt} {
        set tokens {}
        set i 0
        set n [string length $alt]
        while {$i < $n} {
            set c [string index $alt $i]
            if {[string is space $c]} { incr i; continue }
            if {$c eq "'"} {
                set j [string first "'" $alt [expr {$i+1}]]
                if {$j < 0} { error "unterminated literal in: $alt" }
                lappend tokens [list lit [string range $alt [expr {$i+1}] [expr {$j-1}]]]
                set i [expr {$j+1}]
            } elseif {$c in {( ) | ? * +}} {
                lappend tokens [list op $c]
                incr i
            } else {
                set j $i
                while {$j < $n} {
                    set d [string index $alt $j]
                    if {[string is space $d] || $d in {( ) | ? * + '}} break
                    incr j
                }
                lappend tokens [list sym [string range $alt $i [expr {$j-1}]]]
                set i $j
            }
        }
        return $tokens
    }

    proc validate {} {
        variable rules; variable ruleOrder; variable terminals
        variable vocab; variable vocabOrder
        variable features; variable featureOrder
        variable renderers; variable rendererOrder
        set errors {}

        # Every symbol referenced in a rule must be a rule or terminal.
        foreach name $ruleOrder {
            foreach alt [dict get $rules $name alternatives] {
                set depth 0
                foreach tok [tokenizeAlt $alt] {
                    lassign $tok kind val
                    if {$kind eq "op"} {
                        if {$val eq "("} { incr depth }
                        if {$val eq ")"} { incr depth -1 }
                        continue
                    }
                    if {$kind eq "sym"} {
                        if {![dict exists $rules $val] && ![dict exists $terminals $val]} {
                            lappend errors "rule $name: undefined symbol '$val'"
                        }
                    }
                }
                if {$depth != 0} { lappend errors "rule $name: unbalanced parens in: $alt" }
            }
        }

        # Every rule except the roots should be reachable from folk-script or statement.
        set reachable {}
        set queue {folk-script folk-form statement}
        while {[llength $queue]} {
            set queue [lassign $queue cur]
            if {$cur in $reachable || ![dict exists $rules $cur]} continue
            lappend reachable $cur
            foreach alt [dict get $rules $cur alternatives] {
                foreach tok [tokenizeAlt $alt] {
                    lassign $tok kind val
                    if {$kind eq "sym" && [dict exists $rules $val]} { lappend queue $val }
                }
            }
        }
        foreach name $ruleOrder {
            if {$name ni $reachable} { lappend errors "rule $name: unreachable from roots" }
        }

        # Vocab entries must reference defined features.
        foreach id $vocabOrder {
            set f [dict get $vocab $id feature]
            if {![dict exists $features $f]} {
                lappend errors "vocab $id: undefined feature '$f'"
            }
        }

        # Renderer caps must cover every feature with a legal status.
        foreach id $rendererOrder {
            set caps [dict get $renderers $id caps]
            foreach f $featureOrder {
                if {![dict exists $caps $f]} {
                    lappend errors "renderer $id: missing capability entry for '$f'"
                } elseif {[dict get $caps $f] ni {yes partial no planned unknown}} {
                    lappend errors "renderer $id: bad status '[dict get $caps $f]' for '$f'"
                }
            }
            foreach f [dict keys $caps] {
                if {![dict exists $features $f]} {
                    lappend errors "renderer $id: unknown feature '$f' in caps"
                }
            }
        }

        return $errors
    }

    proc emitEbnf {} {
        variable rules; variable ruleOrder; variable terminals; variable meta
        set out {}
        lappend out "(* folklang EBNF — generated from folklang.bnf.tcl; do not edit *)"
        lappend out "(* upstream: [dict get $meta upstream] @ [string range [dict get $meta upstream-commit] 0 11] *)"
        set lastLayer -1
        foreach name $ruleOrder {
            set r [dict get $rules $name]
            if {[dict get $r layer] != $lastLayer} {
                set lastLayer [dict get $r layer]
                lappend out ""
                lappend out "(* ===== Layer $lastLayer ===== *)"
            }
            lappend out ""
            lappend out "(* [string trim [regsub -all {\s+} [dict get $r description] { }]] *)"
            set alts {}
            foreach alt [dict get $r alternatives] {
                lappend alts [string trim [regsub -all {\s+} $alt { }]]
            }
            lappend out "$name = [join $alts "\n    | "] ;"
        }
        lappend out ""
        lappend out "(* ===== Lexical terminals (regex) ===== *)"
        dict for {name t} $terminals {
            lappend out "(* [dict get $t description] *)"
            lappend out "$name = /[dict get $t regex]/ ;"
        }
        return [join $out \n]
    }

    proc jsonEscape {s} {
        set map {\\ \\\\ \" \\\" \n \\n \t \\t \r \\r}
        return "\"[string map $map $s]\""
    }
    proc jsonList {items} { return "\[[join $items ,]\]" }
    proc jsonObj {pairs} {
        set out {}
        foreach {k v} $pairs { lappend out "[jsonEscape $k]:$v" }
        return "{[join $out ,]}"
    }

    proc emitJson {} {
        variable meta; variable terminals; variable rules; variable ruleOrder
        variable vocab; variable vocabOrder
        variable features; variable featureOrder
        variable renderers; variable rendererOrder

        set metaPairs {}
        dict for {k v} $meta {
            lappend metaPairs $k [jsonEscape [string trim [regsub -all {\s+} $v { }]]]
        }

        set termPairs {}
        dict for {name t} $terminals {
            lappend termPairs $name [jsonObj [list \
                description [jsonEscape [dict get $t description]] \
                regex [jsonEscape [dict get $t regex]]]]
        }

        set ruleItems {}
        foreach name $ruleOrder {
            set r [dict get $rules $name]
            set alts {}
            foreach alt [dict get $r alternatives] {
                lappend alts [jsonEscape [string trim [regsub -all {\s+} $alt { }]]]
            }
            lappend ruleItems [jsonObj [list \
                name [jsonEscape $name] \
                layer [dict get $r layer] \
                description [jsonEscape [string trim [regsub -all {\s+} [dict get $r description] { }]]] \
                alternatives [jsonList $alts]]]
        }

        set vocabItems {}
        foreach id $vocabOrder {
            set v [dict get $vocab $id]
            lappend vocabItems [jsonObj [list \
                id [jsonEscape $id] \
                kind [jsonEscape [dict get $v kind]] \
                feature [jsonEscape [dict get $v feature]] \
                provider [jsonEscape [dict get $v provider]] \
                pattern [jsonEscape [dict get $v pattern]] \
                description [jsonEscape [dict get $v description]]]]
        }

        set featureItems {}
        foreach id $featureOrder {
            set f [dict get $features $id]
            lappend featureItems [jsonObj [list \
                id [jsonEscape $id] \
                title [jsonEscape [dict get $f title]] \
                description [jsonEscape [dict get $f description]]]]
        }

        set rendererItems {}
        foreach id $rendererOrder {
            set r [dict get $renderers $id]
            set capPairs {}
            foreach f $featureOrder {
                lappend capPairs $f [jsonEscape [dict get $r caps $f]]
            }
            lappend rendererItems [jsonObj [list \
                id [jsonEscape $id] \
                title [jsonEscape [dict get $r title]] \
                tech [jsonEscape [dict get $r tech]] \
                status [jsonEscape [dict get $r status]] \
                syntax [jsonEscape [dict get $r syntax]] \
                capabilities [jsonObj $capPairs] \
                notes [jsonEscape [dict get $r notes]]]]
        }

        return [jsonObj [list \
            meta [jsonObj $metaPairs] \
            terminals [jsonObj $termPairs] \
            rules [jsonList $ruleItems] \
            vocabulary [jsonList $vocabItems] \
            features [jsonList $featureItems] \
            renderers [jsonList $rendererItems]]]
    }

    proc emitMatrix {} {
        variable features; variable featureOrder
        variable renderers; variable rendererOrder
        variable meta
        set sym {yes "✅" partial "🟡" planned "🔜" no "❌" unknown "❔"}
        set out {}
        lappend out "# folklang renderer capability matrix"
        lappend out ""
        lappend out "Generated from \`folklang.bnf.tcl\` (source of truth) —"
        lappend out "upstream [dict get $meta upstream] @ \`[string range [dict get $meta upstream-commit] 0 11]\`."
        lappend out ""
        lappend out "Legend: ✅ yes · 🟡 partial · 🔜 planned · ❌ not supported · ❔ undecided"
        lappend out ""
        set hdr "| Feature |"
        set sep "|---|"
        foreach id $rendererOrder {
            append hdr " [dict get $renderers $id title] |"
            append sep "---|"
        }
        lappend out $hdr
        lappend out $sep
        foreach f $featureOrder {
            set row "| [dict get $features $f title] (\`$f\`) |"
            foreach id $rendererOrder {
                append row " [dict get $sym [dict get $renderers $id caps $f]] |"
            }
            lappend out $row
        }
        lappend out ""
        lappend out "## Renderers"
        lappend out ""
        foreach id $rendererOrder {
            set r [dict get $renderers $id]
            lappend out "- **[dict get $r title]** (\`$id\`, [dict get $r tech], [dict get $r status]): [dict get $r notes]"
        }
        lappend out ""
        return [join $out \n]
    }
}

# ======================================================================
# CLI
# ======================================================================

if {[info exists ::argv0] && [file tail [info script]] eq [file tail $::argv0]} {
    set cmd [lindex $::argv 0]
    switch -- $cmd {
        validate {
            set errors [::folklang::validate]
            if {[llength $errors]} {
                puts stderr "folklang.bnf.tcl: [llength $errors] problem(s):"
                foreach e $errors { puts stderr "  - $e" }
                exit 1
            }
            puts "folklang.bnf.tcl: OK ([llength $::folklang::ruleOrder] rules,\
[dict size $::folklang::terminals] terminals,\
[llength $::folklang::vocabOrder] vocab entries,\
[llength $::folklang::featureOrder] features,\
[llength $::folklang::rendererOrder] renderers)"
        }
        emit {
            switch -- [lindex $::argv 1] {
                ebnf    { puts [::folklang::emitEbnf] }
                json    { puts [::folklang::emitJson] }
                matrix  { puts [::folklang::emitMatrix] }
                default { puts stderr "usage: tclsh folklang.bnf.tcl emit ebnf|json|matrix"; exit 1 }
            }
        }
        default {
            puts stderr "usage: tclsh folklang.bnf.tcl validate | emit ebnf|json|matrix"
            exit 1
        }
    }
}
