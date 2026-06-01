#!/bin/zsh

if [ -z "$1" ]; then
  echo "Usage: $0 <gif_path> [strip_length] [--local]"
  echo "  <gif_path>: Path to the input GIF file."
  echo "  [strip_length]: Optional. The desired length (number of frames) of the horizontal strip. Defaults to all frames."
  echo "  [--local]: Optional flag. If present, the output strip will be saved in the current working directory."
  echo "             Otherwise, it will be saved alongside the input GIF."
  exit 1
fi

gif_path="$1"
strip_length="${2:-all}"
local_output=false

# Check for the --local flag
if [ "$3" == "--local" ]; then
  local_output=true
fi

output_name_base="${gif_path%.gif}_strip.png"
output_path=""

if "$local_output"; then
  output_path="./${output_name_base}"
else
  output_path="${gif_path%/*}/${output_name_base}" # Save alongside input GIF
fi

frames_dir=$(mktemp -d) # Create a temporary directory to store frames

if [ ! -f "$gif_path" ]; then
  echo "Error: GIF file not found at '$gif_path'."
  rm -rf "$frames_dir"
  exit 1
fi

# Get GIF frame count using ImageMagick's identify (more robustly)
frame_count=$(identify -format "%n" "$gif_path" 2>/dev/null)
if [ -z "$frame_count" ] || [[ ! "$frame_count" =~ ^[0-9]+$ ]]; then
  echo "Error: Could not determine frame count of GIF."
  rm -rf "$frames_dir"
  exit 1
fi

echo "GIF Path: '$gif_path'"
echo "Strip Length: '$strip_length'"
echo "Output Path: '$output_path'"
echo "Frame Count: '$frame_count'"
echo "Temporary frames directory: '$frames_dir'"

success=false

if [[ "$strip_length" == "all" ]]; then
  echo "Creating a horizontal strip of all $frame_count frames."
  convert "$gif_path" "$frames_dir/frame-%03d.png" # Extract all frames
  if montage "$frames_dir/frame-*.png" -tile x1 -geometry +0+0 "$output_path"; then
    success=true
  fi
else
  if [[ ! "$strip_length" =~ ^[0-9]+$ ]]; then
    echo "Error: Strip length must be a positive integer or 'all'."
    rm -rf "$frames_dir"
    exit 1
  fi

  if (( strip_length > frame_count )); then
    echo "Warning: Requested strip length ($strip_length) is greater than the number of frames in the GIF ($frame_count). Using all frames."
    convert "$gif_path" "$frames_dir/frame-%03d.png" # Extract all frames
    if montage "$frames_dir/frame-*.png" -tile x1 -geometry +0+0 "$output_path"; then
      success=true
    fi
  else
    echo "Creating a horizontal strip of the first $strip_length frames."
    convert "$gif_path"[0-"$((strip_length - 1))"] "$frames_dir/frame-%03d.png" # Extract specified frames
    if montage "$frames_dir/frame-*.png" -tile x1 -geometry +0+0 "$output_path"; then
      success=true
    fi
  fi
fi

if "$success"; then
  echo "Successfully created '$output_path'."
else
  echo "Error: Failed to create the horizontal strip."
fi

rm -rf "$frames_dir" # Clean up the temporary directory

exit 0
