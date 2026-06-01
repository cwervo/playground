const std = @import("std");
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

