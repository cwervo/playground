#!/bin/zsh

if [ -z "$1" ]; then
  echo "Usage: $0 <gif_path> [strip_length]"
  echo "  <gif_path>: Path to the input GIF file."
  echo "  [strip_length]: Optional. The desired length (number of frames) of the horizontal strip. Defaults to all frames."
  exit 1
fi

gif_path="$1"
strip_length="${2:-all}"
output_name="${gif_path%.gif}_strip.png"

if [ ! -f "$gif_path" ]; then
  echo "Error: GIF file not found at '$gif_path'."
  exit 1
fi

# Get GIF frame count
frame_count=$(ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_frames -of default=nokey=1:noprint_wrappers=1 "$gif_path")

if [[ "$strip_length" == "all" ]]; then
  echo "Creating a horizontal strip of all $frame_count frames."
  ffmpeg -i "$gif_path" -vf "tile=w=$frame_count" "$output_name"
else
  if [[ ! "$strip_length" =~ ^[0-9]+$ ]]; then
    echo "Error: Strip length must be a positive integer or 'all'."
    exit 1
  fi

  if (( strip_length > frame_count )); then
    echo "Warning: Requested strip length ($strip_length) is greater than the number of frames in the GIF ($frame_count). Using all frames."
    ffmpeg -i "$gif_path" -vf "tile=w=$frame_count" "$output_name"
  else
    echo "Creating a horizontal strip of the first $strip_length frames."
    ffmpeg -i "$gif_path" -vf "select=lte(n-1,$(($strip_length - 1))),tile=w=$strip_length" -frames:v "$strip_length" "$output_name"
  fi
fi

echo "Successfully created '$output_name'."

exit 0
