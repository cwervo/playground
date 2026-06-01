#!/bin/bash

# This script generates PostScript files of varying sizes.
# Usage: ./generate_ps.sh [small|medium|large|all]

# --- Configuration ---
TUTORIAL_DIR="./postscriptTutorial"
SMALL_FILE="$TUTORIAL_DIR/small.ps"
MEDIUM_FILE="$TUTORIAL_DIR/medium.ps"
LARGE_FILE="$TUTORIAL_DIR/large.ps"

# --- Generation Functions ---

# Generates the smallest possible document.
generate_small() {
    echo "Generating small document..."
    cat > "$SMALL_FILE" <<EOF
%!PS-Adobe-3.0
%%BoundingBox: 0 0 595 842
% This is a minimal PostScript file.

/Helvetica-Bold findfont 48 scalefont setfont
72 750 moveto
(Small Document) show

/Helvetica findfont 24 scalefont setfont
72 700 moveto
(Approx. 1 KB) show

showpage
EOF
}

# Generates a medium-sized document using comments for bloat.
generate_medium() {
    echo "Generating medium document (this may take a moment)..."
    # Start with the same visual content
    cat > "$MEDIUM_FILE" <<EOF
%!PS-Adobe-3.0
%%BoundingBox: 0 0 595 842
% This file is intentionally bloated with comments to increase its size.

/Helvetica-Bold findfont 48 scalefont setfont
72 750 moveto
(Medium Document) show

/Helvetica findfont 24 scalefont setfont
72 700 moveto
(Approx. 500 KB) show

% --- Start of Bloat Data (Comments) ---
EOF
    # Append 5,000 lines of comments to bloat the file
    for i in {1..5000}; do
        echo "% This is a long line of commented text to increase the file size. Line $i" >> "$MEDIUM_FILE"
    done
    # Add the final part of the PostScript file
    cat >> "$MEDIUM_FILE" <<EOF
% --- End of Bloat Data ---

showpage
EOF
}

# Generates a large document using an unused string definition for bloat.
generate_large() {
    echo "Generating large document (this will take a bit longer)..."
    # Start with the same visual content
    cat > "$LARGE_FILE" <<EOF
%!PS-Adobe-3.0
%%BoundingBox: 0 0 595 842
% This file is bloated with a large, unused string definition.

/Helvetica-Bold findfont 48 scalefont setfont
72 750 moveto
(Large Document) show

/Helvetica findfont 24 scalefont setfont
72 700 moveto
(Approx. 5 MB) show

% --- Start of Bloat Data (Unused Procedure) ---
% The following procedure defines a massive string but is never called.
/addUnusedData {
(
EOF
    # Append 50,000 lines of text inside the string definition
    for i in {1..50000}; do
        echo "This is filler text inside a PostScript string to increase the file size. Line $i." >> "$LARGE_FILE"
    done
    # Close the string and procedure definition, then show the page
    cat >> "$LARGE_FILE" <<EOF
)
} def
% --- End of Bloat Data ---

showpage
EOF
}

# --- Main Logic ---

# Check for argument, if none, print usage info.
if [ -z "$1" ]; then
    echo "Usage: $0 [small|medium|large|all]"
    exit 1
fi

# Create the output directory if it doesn't exist.
mkdir -p "$TUTORIAL_DIR"

# Process the command-line argument.
case "$1" in
    small)
        generate_small
        ;;
    medium)
        generate_medium
        ;;
    large)
        generate_large
        ;;
    all)
        generate_small
        generate_medium
        generate_large
        ;;
    *)
        echo "Invalid argument. Usage: $0 [small|medium|large|all]"
        exit 1
        ;;
esac

# --- Final Message ---
echo ""
echo "Successfully generated requested file(s) in '$TUTORIAL_DIR':"
ls -lh "$TUTORIAL_DIR"
echo ""
echo "You can now open these .ps files with a PostScript viewer or convert them to PDF."
echo "They will look the same, but their file sizes are very different."


