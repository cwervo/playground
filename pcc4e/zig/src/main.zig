// pcc4e-node: reference prototype of the PCC4E discovery protocol
// (see pcc4e/proto/DISCOVERY.md), Zig port of the Go implementation.
//
// Wire format is identical to go/cmd/pcc4e-node so a Zig node and a Go node
// discover each other on the same multicast group. JSON parsing here is a
// small hand-rolled scanner (not std.json) because we only ever need to pull
// a fixed set of keys out of announces we control the shape of.
const std = @import("std");
const posix = std.posix;

const MULTICAST_ADDR = "239.255.77.77";
const MULTICAST_PORT: u16 = 7777;
const ANNOUNCE_EVERY_NS: i128 = 2 * std.time.ns_per_s;
const PEER_TIMEOUT_NS: i128 = 6 * std.time.ns_per_s;

const Announce = struct {
    node_id: []const u8,
    name: []const u8,
    caps: []const u8, // raw JSON array text, e.g. ["compute","relay"]
    pubkey: []const u8,
    port: i64,
    ts: i64,
};

const Peer = struct {
    name: [64]u8,
    name_len: usize,
    caps: [128]u8,
    caps_len: usize,
    port: i64,
    last_seen_ns: i128,
};

fn randHex(buf: []u8, n: usize) void {
    var raw: [32]u8 = undefined;
    std.crypto.random.bytes(raw[0..n]);
    const hex_chars = "0123456789abcdef";
    var i: usize = 0;
    while (i < n) : (i += 1) {
        buf[i * 2] = hex_chars[raw[i] >> 4];
        buf[i * 2 + 1] = hex_chars[raw[i] & 0x0f];
    }
}

fn extractString(json: []const u8, key: []const u8, out: []u8) ?usize {
    var key_pat_buf: [64]u8 = undefined;
    const key_pat = std.fmt.bufPrint(&key_pat_buf, "\"{s}\":\"", .{key}) catch return null;
    const idx = std.mem.indexOf(u8, json, key_pat) orelse return null;
    const start = idx + key_pat.len;
    const end = std.mem.indexOfScalarPos(u8, json, start, '"') orelse return null;
    const len = end - start;
    if (len > out.len) return null;
    @memcpy(out[0..len], json[start..end]);
    return len;
}

fn extractArrayRaw(json: []const u8, key: []const u8, out: []u8) ?usize {
    var key_pat_buf: [64]u8 = undefined;
    const key_pat = std.fmt.bufPrint(&key_pat_buf, "\"{s}\":[", .{key}) catch return null;
    const idx = std.mem.indexOf(u8, json, key_pat) orelse return null;
    const start = idx + key_pat.len - 1; // include the '['
    const end = std.mem.indexOfScalarPos(u8, json, start, ']') orelse return null;
    const len = end - start + 1;
    if (len > out.len) return null;
    @memcpy(out[0..len], json[start .. end + 1]);
    return len;
}

fn extractInt(json: []const u8, key: []const u8) ?i64 {
    var key_pat_buf: [64]u8 = undefined;
    const key_pat = std.fmt.bufPrint(&key_pat_buf, "\"{s}\":", .{key}) catch return null;
    const idx = std.mem.indexOf(u8, json, key_pat) orelse return null;
    const start = idx + key_pat.len;
    var end = start;
    while (end < json.len and (std.ascii.isDigit(json[end]) or json[end] == '-')) : (end += 1) {}
    if (end == start) return null;
    return std.fmt.parseInt(i64, json[start..end], 10) catch null;
}

fn getenvSlice(key: [:0]const u8) ?[]const u8 {
    const c = std.c.getenv(key) orelse return null;
    return std.mem.sliceTo(c, 0);
}

pub fn main() !void {
    var gpa_state = std.heap.DebugAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    // Configuration is via environment variables (PCC4E_NAME / PCC4E_PORT /
    // PCC4E_RUN_FOR_SECONDS) rather than CLI flags — std.process's argv
    // iterator API is in flux across Zig versions, env vars are stable.
    var name_buf: [64]u8 = undefined;
    var name: []const u8 = "zig-node";
    var data_port: i64 = 9444;
    var run_for_s: i64 = 0;

    if (getenvSlice("PCC4E_NAME")) |v| {
        const l = @min(v.len, name_buf.len);
        @memcpy(name_buf[0..l], v[0..l]);
        name = name_buf[0..l];
    }
    if (getenvSlice("PCC4E_PORT")) |v| {
        data_port = std.fmt.parseInt(i64, v, 10) catch data_port;
    }
    if (getenvSlice("PCC4E_RUN_FOR_SECONDS")) |v| {
        run_for_s = std.fmt.parseInt(i64, v, 10) catch 0;
    }

    var node_id_buf: [16]u8 = undefined;
    randHex(&node_id_buf, 8);
    const node_id = node_id_buf[0..16];

    var pubkey_buf: [32]u8 = undefined;
    randHex(&pubkey_buf, 16);
    const pubkey = pubkey_buf[0..32];

    const mcast_ip = try std.net.Ip4Address.parse(MULTICAST_ADDR, MULTICAST_PORT);
    const mcast_addr = std.net.Address{ .in = mcast_ip };

    // Receive socket: bound to 0.0.0.0:MULTICAST_PORT, joined to the group.
    const recv_sock = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
    defer posix.close(recv_sock);

    try posix.setsockopt(recv_sock, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));

    const bind_addr = try std.net.Address.parseIp4("0.0.0.0", MULTICAST_PORT);
    try posix.bind(recv_sock, &bind_addr.any, bind_addr.getOsSockLen());

    const ip_mreq = extern struct {
        imr_multiaddr: u32,
        imr_interface: u32,
    };
    const mreq = ip_mreq{
        .imr_multiaddr = mcast_ip.sa.addr,
        .imr_interface = 0, // INADDR_ANY
    };
    const IP_ADD_MEMBERSHIP: u32 = 35; // Linux value
    try posix.setsockopt(recv_sock, posix.IPPROTO.IP, IP_ADD_MEMBERSHIP, std.mem.asBytes(&mreq));

    // Send socket: ephemeral local port, sends to the multicast group.
    const send_sock = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
    defer posix.close(send_sock);

    const stdout = std.io.getStdOut().writer();
    try stdout.print("pcc4e-node {s} ({s}) up — data-plane port {d}, group {s}:{d}\n", .{ name, node_id, data_port, MULTICAST_ADDR, MULTICAST_PORT });

    var peers = std.StringHashMap(Peer).init(gpa);
    defer {
        var it = peers.keyIterator();
        while (it.next()) |k| gpa.free(k.*);
        peers.deinit();
    }

    var send_buf: [512]u8 = undefined;
    var recv_buf: [2048]u8 = undefined;

    const start = std.time.nanoTimestamp();
    var last_announce: i128 = 0;

    while (true) {
        const now = std.time.nanoTimestamp();

        if (now - last_announce >= ANNOUNCE_EVERY_NS) {
            const ts = std.time.timestamp();
            const msg = try std.fmt.bufPrint(&send_buf, "{{\"v\":1,\"type\":\"announce\",\"node_id\":\"{s}\",\"name\":\"{s}\",\"caps\":[\"compute\",\"relay\"],\"pubkey\":\"{s}\",\"port\":{d},\"ts\":{d}}}\n", .{ node_id, name, pubkey, data_port, ts });
            _ = posix.sendto(send_sock, msg, 0, &mcast_addr.any, mcast_addr.getOsSockLen()) catch |err| {
                try stdout.print("send error: {}\n", .{err});
            };
            last_announce = now;
        }

        // Non-blocking-ish poll: short timeout via SO_RCVTIMEO so the loop
        // still ticks announces/reap on time.
        const tv = posix.timeval{ .sec = 0, .usec = 200_000 };
        try posix.setsockopt(recv_sock, posix.SOL.SOCKET, posix.SO.RCVTIMEO, std.mem.asBytes(&tv));

        var src_addr: posix.sockaddr = undefined;
        var src_len: posix.socklen_t = @sizeOf(posix.sockaddr);
        const n = posix.recvfrom(recv_sock, &recv_buf, 0, &src_addr, &src_len) catch |err| switch (err) {
            error.WouldBlock => 0,
            else => blk: {
                try stdout.print("recv error: {}\n", .{err});
                break :blk 0;
            },
        };

        if (n > 0) {
            const json = recv_buf[0..n];
            var id_buf: [64]u8 = undefined;
            if (extractString(json, "node_id", &id_buf)) |id_len| {
                const id = id_buf[0..id_len];
                if (!std.mem.eql(u8, id, node_id)) {
                    var peer_name_buf: [64]u8 = undefined;
                    var caps_buf: [128]u8 = undefined;
                    const pname_len = extractString(json, "name", &peer_name_buf) orelse 0;
                    const caps_len = extractArrayRaw(json, "caps", &caps_buf) orelse 0;
                    const port = extractInt(json, "port") orelse 0;

                    const existing = peers.getPtr(id);
                    if (existing) |p| {
                        p.last_seen_ns = now;
                    } else {
                        const owned_id = try gpa.dupe(u8, id);
                        const gop = try peers.getOrPut(owned_id);
                        var p: Peer = undefined;
                        p.name_len = pname_len;
                        @memcpy(p.name[0..pname_len], peer_name_buf[0..pname_len]);
                        p.caps_len = caps_len;
                        @memcpy(p.caps[0..caps_len], caps_buf[0..caps_len]);
                        p.port = port;
                        p.last_seen_ns = now;
                        gop.value_ptr.* = p;
                        try stdout.print("discovered peer {s:<12} id={s} caps={s} port={d}\n", .{ peer_name_buf[0..pname_len], id, caps_buf[0..caps_len], port });
                    }
                }
            }
        }

        if (run_for_s > 0 and now - start >= @as(i128, run_for_s) * std.time.ns_per_s) {
            try stdout.print("\n=== {s} ({s}) final peer table ===\n", .{ name, node_id });
            var it = peers.iterator();
            while (it.next()) |entry| {
                const p = entry.value_ptr.*;
                try stdout.print("  {s:<12} id={s} caps={s} port={d}\n", .{ p.name[0..p.name_len], entry.key_ptr.*, p.caps[0..p.caps_len], p.port });
            }
            return;
        }
    }
}
