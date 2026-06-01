#!/usr/bin/env ruby

if ARGV.empty?
  puts "Usage: #{$PROGRAM_NAME} <gif_path> [strip_length]"
  puts "  <gif_path>: Path to the input GIF file."
  puts "  [strip_length]: Optional. The desired length (number of frames) of the horizontal strip. Defaults to all frames."
  exit 1
end

gif_path = ARGV[0]
strip_length_str = ARGV[1]
output_name = gif_path.gsub(/\.gif$/, '_strip.png')

unless File.exist?(gif_path)
  puts "Error: GIF file not found at '#{gif_path}'."
  exit 1
end

# Get GIF frame count
frame_count = `ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_frames -of default=nokey=1:noprint_wrappers=1 "#{gif_path}"`.strip.to_i

puts "GIF Path: #{gif_path}"
puts "Strip Length (string): #{strip_length_str}"
puts "Output Name: #{output_name}"
puts "Frame Count: #{frame_count}"

if strip_length_str.nil? || strip_length_str.downcase == 'all'
  puts "Creating a horizontal strip of all #{frame_count} frames."
  ffmpeg_command = "ffmpeg -i \"#{gif_path}\" -vf \"tile=w=#{frame_count}\" \"#{output_name}\""
  puts "Executing: #{ffmpeg_command}"
  system(ffmpeg_command)
else
  strip_length = strip_length_str.to_i
  unless strip_length > 0
    puts "Error: Strip length must be a positive integer or 'all'."
    exit 1
  end

  if strip_length > frame_count
    puts "Warning: Requested strip length (#{strip_length}) is greater than the number of frames in the GIF (#{frame_count}). Using all frames."
    ffmpeg_command = "ffmpeg -i \"#{gif_path}\" -vf \"tile=w=#{frame_count}\" \"#{output_name}\""
    puts "Executing (all frames due to length): #{ffmpeg_command}"
    system(ffmpeg_command)
  else
    puts "Creating a horizontal strip of the first #{strip_length} frames."
    calculated_end = strip_length - 1
    ffmpeg_command = "ffmpeg -i \"#{gif_path}\" -vf \"select=lte(n-1,#{calculated_end}),tile=w=#{strip_length}\" -frames:v #{strip_length} \"#{output_name}\""
    puts "Executing (first #{strip_length} frames): #{ffmpeg_command}"
    system(ffmpeg_command)
  end
end

puts "Successfully created '#{output_name}'."
