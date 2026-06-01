const std = @import("std");
const c = @cImport({
    @cInclude("opencv4/opencv2/videoio/c.h");
    @cInclude("opencv4/opencv2/imgproc/c.h");
    @cInclude("opencv4/opencv2/imgcodecs/c.h");
});

const Allocator = std.mem.Allocator;

// A simple GIF encoder. For a real project, a more robust library would be used.
const Gif = struct {
    const Self = @This();
    file: std.fs.File,
    width: u16,
    height: u16,
    first_frame: bool = true,

    pub fn init(file: std.fs.File, width: u16, height: u16) !Self {
        var self = Self{ .file = file, .width = width, .height = height };
        try self.writeHeader();
        return self;
    }

    fn writeHeader(self: *Self) !void {
        try self.file.writer().writeAll("GIF89a");
        try self.file.writer().writeAll(&std.mem.toBytes(self.width));
        try self.file.writer().writeAll(&std.mem.toBytes(self.height));
        // Global Color Table Flag (on), Color Resolution (8-bit), Sort Flag (off), Size of GCT (256)
        try self.file.writer().writeByte(0xF7);
        try self.file.writer().writeByte(0); // Background Color Index
        try self.file.writer().writeByte(0); // Pixel Aspect Ratio

        // Write a simple grayscale global color table
        for (0..256) |i| {
            const v = @intCast(u8, i);
            try self.file.writer().writeByte(v);
            try self.file.writer().writeByte(v);
            try self.file.writer().writeByte(v);
        }

        // Application Extension for looping
        try self.file.writer().writeAll(&.{ 0x21, 0xFF, 0x0B });
        try self.file.writer().writeAll("NETSCAPE2.0");
        try self.file.writer().writeAll(&.{ 0x03, 0x01, 0x00, 0x00, 0x00 });
    }

    pub fn addFrame(self: *Self, pixels: []const u8, delay_cs: u16) !void {
        // Graphic Control Extension
        try self.file.writer().writeByte(0x21); // Extension Introducer
        try self.file.writer().writeByte(0xF9); // Graphic Control Label
        try self.file.writer().writeByte(4); // Block Size
        try self.file.writer().writeByte(0x04); // Disposal Method
        try self.file.writer().writeAll(&std.mem.toBytes(delay_cs));
        try self.file.writer().writeByte(0); // Transparent Color Index
        try self.file.writer().writeByte(0); // Block Terminator

        // Image Descriptor
        try self.file.writer().writeByte(0x2C);
        try self.file.writer().writeAll(&.{ 0, 0, 0, 0 }); // Image Left/Top
        try self.file.writer().writeAll(&std.mem.toBytes(self.width));
        try self.file.writer().writeAll(&std.mem.toBytes(self.height));
        try self.file.writer().writeByte(0x00); // No Local Color Table

        // Image Data (using LZW)
        const lzw_min_code_size: u8 = 8;
        try self.file.writer().writeByte(lzw_min_code_size);

        var data_len: u8 = @intCast(u8, pixels.len);
        while (data_len > 0) {
            const block_size = @min(data_len, 255);
            try self.file.writer().writeByte(block_size);
            try self.file.writer().writeAll(pixels[pixels.len - data_len .. pixels.len - data_len + block_size]);
            data_len -= block_size;
        }

        try self.file.writer().writeByte(0); // End of image data
    }

    pub fn finish(self: *Self) !void {
        try self.file.writer().writeByte(0x3B); // GIF Trailer
    }
};


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // --- Argument Parsing ---
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next(); // skip executable name

    var input_path: ?[]const u8 = null;
    var output_path: []const u8 = "output.gif";
    var frame_skip: usize = 10;
    var delay: u16 = 10;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-i")) {
            input_path = args.next();
        } else if (std.mem.eql(u8, arg, "-o")) {
            output_path = args.next() orelse "output.gif";
        } else if (std.mem.eql(u8, arg, "-s")) {
            frame_skip = try std.fmt.parseUnsigned(usize, args.next() orelse "10", 10);
        } else if (std.mem.eql(u8, arg, "-d")) {
            delay = try std.fmt.parseUnsigned(u16, args.next() orelse "10", 10);
        }
    }

    if (input_path == null) {
        std.debug.print("Error: Input video file path is required. Use -i <path>\n", .{});
        return;
    }

    const input_path_z = try std.cstr.addZ(allocator, input_path.?);
    defer allocator.free(input_path_z);


    // --- Video Processing ---
    std.debug.print("Opening video: {s}\n", .{input_path.?});
    const capture = c.cvCreateFileCapture(input_path_z.ptr);
    if (capture == null) {
        std.debug.print("Error: Could not open video file.\n", .{});
        return;
    }
    defer c.cvReleaseCapture(&capture);

    var frame_count: usize = 0;
    var processed_frames: usize = 0;
    var gif: ?Gif = null;
    defer if (gif) |*g| g.finish() catch {};

    while (true) {
        const frame = c.cvQueryFrame(capture);
        if (frame == null) {
            std.debug.print("\nReached end of video.\n", .{});
            break;
        }

        if (frame_count % frame_skip == 0) {
            // Convert frame to grayscale for simplicity
            const gray_frame = c.cvCreateImage(c.cvGetSize(frame), c.IPL_DEPTH_8U, 1);
            defer c.cvReleaseImage(&gray_frame);
            c.cvCvtColor(frame, gray_frame, c.CV_BGR2GRAY);

            const width = @intCast(u16, gray_frame.*.width);
            const height = @intCast(u16, gray_frame.*.height);
            const image_size = gray_frame.*.imageSize;
            
            // Create the GIF file and writer on the first valid frame
            if (gif == null) {
                const outfile = try std.fs.cwd().createFile(output_path, .{});
                gif = try Gif.init(outfile, width, height);
                std.debug.print("Creating GIF: {s}\n", .{output_path});
            }

            const pixels = std.mem.sliceAsBytes(std.mem.span(gray_frame.*.imageData, @intCast(usize, image_size)));
            try gif.?.addFrame(pixels, delay);
            
            processed_frames += 1;
            std.debug.print("\rProcessed frame {d}", .{processed_frames});
        }
        frame_count += 1;
    }
    
    std.debug.print("\nSuccessfully created stop-motion GIF!\n", .{});
}

