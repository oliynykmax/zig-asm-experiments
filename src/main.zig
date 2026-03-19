const std = @import("std");
const builtin = @import("builtin");

// ============================================================
// Scalar add — zig vs inline asm
// Demonstrates that asm has no benefit for trivial operations.
// The compiler optimizes simple addition just as well (or better).
// ============================================================

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

fn benchmarkAdd() !void {
    const stdout = std.fs.File.stdout().deprecatedWriter();
    const iterations: usize = 1_000_000;
    var sum: u64 = 0;

    try stdout.print("\n--- Scalar add (pointless in asm) ---\n", .{});

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

    try stdout.print("zig add: {d:.3} ms (sum={d})\n", .{ @as(f64, @floatFromInt(zig_ns)) / 1_000_000.0, sum });
    try stdout.print("asm add: {d:.3} ms (sum={d})\n", .{ @as(f64, @floatFromInt(asm_ns)) / 1_000_000.0, sum });
}

// ============================================================
// SIMD array add — where asm actually wins
// The compiler often fails to auto-vectorize loops like this,
// so hand-written SIMD (NEON/SSE) gives a real ~4x speedup
// by processing 4 i32s per instruction instead of 1.
//
// Implemented in a separate .s file, linked at build time.
// ============================================================

pub fn add_arrays_zig(a: [*]const i32, b: [*]const i32, c: [*]i32, len: usize) void {
    for (0..len) |i| {
        c[i] = a[i] + b[i];
    }
}

// Defined in src/simd_add.s (x86_64) or src/simd_add_arm.s (aarch64)
extern fn add_arrays_asm(a: [*]const i32, b: [*]const i32, c: [*]i32, len: usize) void;

fn benchmarkSimdAdd() !void {
    // Debug: asm SIMD wins ~400x (compiler doesn't vectorize)
    // Release: compiler auto-vectorizes and may beat hand-written asm
    // Always benchmark both modes — release builds are the real comparison.
    const stdout = std.fs.File.stdout().deprecatedWriter();
    const len = 1000; // must be multiple of 4
    const iterations = 1_000_000;

    var input_a: [len]i32 = undefined;
    var input_b: [len]i32 = undefined;
    var output: [len]i32 = undefined;

    for (0..len) |i| {
        input_a[i] = @intCast(i);
        input_b[i] = @intCast(i * 2);
    }

    try stdout.print("\n--- SIMD array add (real asm win) ---\n", .{});
    try stdout.print("array size: {d}, iterations: {d}\n", .{ len, iterations });

    var timer = try std.time.Timer.start();

    for (0..iterations) |_| {
        add_arrays_zig(&input_a, &input_b, &output, len);
    }
    const zig_ns = timer.read();
    timer.reset();

    for (0..iterations) |_| {
        add_arrays_asm(&input_a, &input_b, &output, len);
    }
    const asm_ns = timer.read();

    try stdout.print("zig scalar: {d:.3} ms (output[0]={d})\n", .{ @as(f64, @floatFromInt(zig_ns)) / 1_000_000.0, output[0] });
    try stdout.print("asm simd:   {d:.3} ms (output[0]={d})\n", .{ @as(f64, @floatFromInt(asm_ns)) / 1_000_000.0, output[0] });
}

pub fn main() !void {
    try benchmarkAdd();
    try benchmarkSimdAdd();
}
