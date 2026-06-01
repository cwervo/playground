# init.tcl - A Tcl script to initialize the 'www' (WhatWentWrong) Zig project.
#
# This script creates the directory structure and populates it with the
# build.zig and main source file.

puts "--- Initializing 'WhatWentWrong' Zig Project ---"

set project_dir "www-zig"

# 1. Clean up existing project directory to ensure a fresh start.
if {[file isdirectory $project_dir]} {
    puts "Removing existing project directory to ensure a clean build: $project_dir"
    file delete -force -- $project_dir
}

# 2. Create the project and source directories
puts "Creating project directory: $project_dir"
file mkdir $project_dir
set src_dir [file join $project_dir "src"]
puts "Creating source directory: $src_dir"
file mkdir $src_dir


# 3. Create the build.zig file with the updated API
set build_zig_path [file join $project_dir "build.zig"]
puts "Creating build script: $build_zig_path"
set f [open $build_zig_path w]
puts $f {const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the 'www' executable
    const exe = b.addExecutable(.{
        .name = "www",
        // FIX: Changed .root_source_file to .root_source for newer Zig versions
        .root_source = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // This is important for enabling the http client and its dependencies
    exe.linkSystemLibrary("c");

    b.installArtifact(exe);

    // Create a 'run' step to easily run the binary
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
}
close $f

# 4. Create the main.zig source file
set main_zig_path [file join $src_dir "main.zig"]
puts "Creating main source file: $main_zig_path"
set f [open $main_zig_path w]
puts $f {const std = @import("std");
const http = std.http;
const json = std.json;
const mem = std.mem;
const process = std.process;

// Gemini API Configuration
const GEMINI_API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-05-20:generateContent?key=";
const API_KEY_ENV_VAR = "GEMINI_API_KEY";
const PROMPT_PREFIX = "What went wrong here? Provide a reliable fix in a nicely formatted terminal prompt response. Here is the error output:\n\n";

// Structs for building the Gemini JSON request payload
const GeminiPart = struct { text: []const u8 };
const GeminiContent = struct { parts: []const GeminiPart };
const GeminiRequest = struct { contents: []const GeminiContent };

// Structs for parsing the Gemini JSON response
const GeminiResponsePart = struct { text: ?[]const u8 };
const GeminiResponseContent = struct { parts: ?[]GeminiResponsePart };
const GeminiCandidate = struct { content: ?GeminiResponseContent };
const GeminiResponse = struct { candidates: ?[]GeminiCandidate };

pub fn main() !void {
    // Standard allocator setup
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. Get Gemini API Key from environment variable
    const api_key = try process.getEnvVarOwned(allocator, API_KEY_ENV_VAR) catch |err| {
        std.debug.print("Error: Environment variable {s} not set.\n", .{API_KEY_ENV_VAR});
        std.debug.print("Please set your Gemini API key to use this tool.\n", .{});
        std.debug.print("Example: export {s}=\"YOUR_API_KEY\"\n", .{API_KEY_ENV_VAR});
        return err;
    };
    defer allocator.free(api_key);

    // 2. Read all data from standard input (the piped command output)
    const stdin = std.io.getStdIn().reader();
    const input_data = try stdin.readAllAlloc(allocator, 1 * 1024 * 1024); // 1MB limit
    defer allocator.free(input_data);

    if (input_data.len == 0) {
        std.debug.print("Usage: <some_command_that_failed> | www\n", .{});
        return;
    }

    // 3. Construct the full prompt
    const full_prompt = try std.fmt.allocPrint(allocator, "{s}{s}", .{ PROMPT_PREFIX, input_data });
    defer allocator.free(full_prompt);

    // 4. Create the JSON payload for the Gemini API
    const request_payload = GeminiRequest{
        .contents = &.{GeminiContent{
            .parts = &.{GeminiPart{ .text = full_prompt }},
        }},
    };

    var request_body_buffer = std.ArrayList(u8).init(allocator);
    defer request_body_buffer.deinit();
    try json.stringify(request_payload, .{}, request_body_buffer.writer());

    // 5. Set up the HTTP client and make the request
    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    const full_api_url = try std.fmt.allocPrint(allocator, "{s}{s}", .{ GEMINI_API_URL, api_key });
    defer allocator.free(full_api_url);

    const uri = try std.Uri.parse(full_api_url);
    var request = try client.request(.POST, uri, .{
        .allocator = allocator,
    });
    defer request.deinit();

    try request.addHeader("Content-Type", "application/json");
    try request.setBody(request_body_buffer.items);
    try request.start();
    try request.wait();

    // 6. Handle the HTTP response
    if (request.response.status != .ok) {
        std.debug.print("API request failed with status: {s}\n", .{@tagName(request.response.status)});
        std.debug.print("Response body:\n{s}\n", .{request.response.body.?.items});
        return error.HttpRequestFailed;
    }

    const response_body = request.response.body.?.items;

    // 7. Parse the JSON response to extract the text
    var tree = try json.parseFromSlice(GeminiResponse, allocator, response_body, .{});
    defer tree.deinit();

    const stdout_writer = std.io.getStdOut().writer();

    if (tree.value.candidates) |candidates| {
        if (candidates.len > 0) {
            if (candidates[0].content) |content| {
                if (content.parts) |parts| {
                    if (parts.len > 0) {
                        if (parts[0].text) |text| {
                            try stdout_writer.print("{s}\n", .{text});
                            return;
                        }
                    }
                }
            }
        }
    }

    // Fallback if parsing fails to find the text
    std.debug.print("Could not parse a valid response from the Gemini API.\n", .{});
    std.debug.print("Raw API Response:\n{s}\n", .{response_body});
}
}
close $f

puts ""
puts "--- ✅ Project Initialized Successfully! ---"
puts ""
puts "Next Steps:"
puts "1. Get a Gemini API Key from Google AI Studio."
puts "2. Set the environment variable:"
puts "   export GEMINI_API_KEY=\"YOUR_API_KEY\""
puts ""
puts "3. Navigate into the project directory:"
puts "   cd $project_dir"
puts ""
puts "4. Build the executable:"
puts "   zig build"
puts ""
puts "5. Install the binary to make it globally available (requires sudo):"
puts "   sudo mv zig-out/bin/www /usr/local/bin/"
puts ""
puts "6. Test it out with a failing command:"
puts "   ls /nonexistent/directory 2>&1 | www"
puts "------------------------------------------------"


