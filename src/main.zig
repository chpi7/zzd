const std = @import("std");
const lib = @import("zzd_lib");
const clap = @import("clap");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help    Display this help text.
        \\-i, --input <str>   Input file path.
        \\-c, --cols <u32>    Number of bytes per line.
        \\-g, --bytes <u32>   Number of bytes per group.
        \\-s, --skip <usize>  Start printing at that offset.
        \\-l, --limit <usize> Stop printing after that amount of bytes.
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = gpa.allocator(),
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    if (res.args.input) |input| {
        const dump_config = lib.DumpConfig{
            .octet_per_group = res.args.bytes orelse 2,
            .bytes_per_line = res.args.cols orelse 16,
            .limit = res.args.limit orelse null,
            .skip = res.args.skip orelse null,
        };

        if (std.mem.eql(u8, "-", input)) {
            lib.handle_stdin(dump_config, allocator);
        } else {
            lib.handle_file(input, dump_config, allocator);
        }
    }
}
