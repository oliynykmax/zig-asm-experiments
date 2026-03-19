const std = @import("std");
const builtin = @import("builtin");

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

pub fn add_asm(a: i32, b: i32) i32 {
    return asm volatile (switch (builtin.cpu.arch) {
            .aarch64 => "add %[ret], %[a], %[b]",
            .x86_64 =>
            \\mov %[a], %[ret]
            \\add %[b], %[ret]
            ,
            else => @compileError("unsupported arch"),
        }
        : [ret] "=r" (-> i32),
        : [a] "r" (a),
          [b] "r" (b),
    );
}

pub fn main() !void {
    const iterations: usize = 1_000_000;
    var sum: u64 = 0;

    var timer = try std.time.Timer.start();

    sum = 0;
    for (0..iterations) |i| {
        sum += @intCast(add(@intCast(i), @intCast(i)));
    }
    const zig_ns = timer.read();
    timer.reset();

    sum = 0;
    for (0..iterations) |i| {
        sum += @intCast(add_asm(@intCast(i), @intCast(i)));
    }
    const asm_ns = timer.read();

    const stdout = std.fs.File.stdout().deprecatedWriter();
    try stdout.print("iterations: {d}\n", .{iterations});
    try stdout.print("zig add:    {d:.3} ms (sum={d})\n", .{ @as(f64, @floatFromInt(zig_ns)) / 1_000_000.0, sum });
    try stdout.print("asm add:    {d:.3} ms (sum={d})\n", .{ @as(f64, @floatFromInt(asm_ns)) / 1_000_000.0, sum });
}
