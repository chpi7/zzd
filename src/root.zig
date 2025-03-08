//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const testing = std.testing;

pub const DumpConfig = struct {
    bytes_per_line: u32,
    octet_per_group: u32,
    skip: ?usize,
    limit: ?usize,
};

pub fn handle_stdin(dump_config: DumpConfig, allocator: std.mem.Allocator) void {
    const input_reader = std.io.getStdIn().reader();
    var input_buffered = std.io.bufferedReader(input_reader);
    var output_buffered = std.io.bufferedWriter(std.io.getStdOut().writer());

    write_hexdump(dump_config, input_buffered.reader(), output_buffered.writer(), allocator);

    output_buffered.flush() catch |err| {
        std.debug.print("Error during flush! {}\n", .{err});
    };
}

fn get_absolute_path(filename: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);

    return try std.fs.path.resolve(allocator, &.{ cwd, filename });
}

pub fn handle_file(filename: []const u8, dump_config: DumpConfig, allocator: std.mem.Allocator) void {
    const abs_input = get_absolute_path(filename, allocator) catch |err| {
        std.debug.print("Error getting absolute path. ({})", .{err});
        return;
    };
    defer allocator.free(abs_input);

    const file = std.fs.openFileAbsolute(abs_input, .{}) catch |err| {
        std.debug.print("Error opening input file: {}", .{err});
        return;
    };
    defer file.close();

    var input_buffered = std.io.bufferedReader(file.reader());
    var output_buffered = std.io.bufferedWriter(std.io.getStdOut().writer());
    write_hexdump(dump_config, input_buffered.reader(), output_buffered.writer(), allocator);

    output_buffered.flush() catch |err| {
        std.debug.print("Error during flush! {}\n", .{err});
    };
}

fn write_hexdump(dump_config: DumpConfig, reader: anytype, writer: anytype, allocator: std.mem.Allocator) void {
    var input_buffer = std.ArrayList(u8).init(allocator);
    defer input_buffer.deinit();
    input_buffer.resize(dump_config.bytes_per_line) catch |err| {
        std.debug.print("Failed to allocator input buffer memory ({})\n", .{err});
    };

    var current_offset: usize = 0;
    var num_written: usize = 0;

    if (dump_config.skip) |skip| {
        reader.skipBytes(skip, .{}) catch |err| {
            std.debug.print("Error during write: {}\n", .{err});
        };
        current_offset += skip;
    }

    while (reader.read(input_buffer.items)) |iter_read_count| {
        if (iter_read_count == 0) break;

        var write_count = iter_read_count;
        var stop_early = false;
        if (dump_config.limit) |limit| {
            stop_early = num_written + iter_read_count >= limit;
            if (stop_early) {
                write_count = limit - num_written;
            }
        }

        const start_newline = num_written != 0;
        write_hexdump_line(input_buffer.items, write_count, current_offset, start_newline, dump_config, writer) catch |err| {
            std.debug.print("Error during write: {}\n", .{err});
        };

        current_offset += write_count;
        num_written += write_count;

        if (stop_early) break;
    } else |err| {
        std.debug.print("Error during read: {}\n", .{err});
    }

    writer.print("\n", .{}) catch |err| {
        std.debug.print("Error during write: {}\n", .{err});
    };
}

fn replace_non_word(buffer: []u8, len: usize) void {
    for (0..len) |i| {
        switch (buffer[i]) {
            0...'\n' - 1, '\n' + 1...0x20 => buffer[i] = ' ',
            '\n' => buffer[i] = '.',
            else => {},
        }
    }
}

fn write_hexdump_line(buffer: []u8, num_bytes: usize, current_offset: usize, begin_newline: bool, dump_config: DumpConfig, writer: anytype) !void {
    if (begin_newline) try writer.print("\n", .{});
    try writer.print("{x:08}: ", .{current_offset});

    var written_length: usize = 0;

    for (0..num_bytes) |i| {
        const append_space = i % dump_config.octet_per_group == 0 and i > 0;
        try writer.print("{s}{x:02}", .{ if (append_space) " " else "", buffer[i] });

        if (append_space) written_length += 1;
    }
    written_length += 2 * num_bytes;

    const num_groups = dump_config.bytes_per_line / dump_config.octet_per_group;
    const data_full_length = num_groups * (dump_config.octet_per_group * 2 + 1) - 1;
    const missing = data_full_length - written_length;

    for (0..missing) |_| try writer.print(" ", .{});

    replace_non_word(buffer, num_bytes);
    try writer.print("  {s}", .{buffer[0..num_bytes]});
}
