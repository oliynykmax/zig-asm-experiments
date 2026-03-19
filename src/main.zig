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

// ============================================================
// Cycle counter — impossible from pure zig, requires asm
// Reads the CPU timestamp counter directly.
// x86_64: rdtsc (returns cycles since reset in EDX:EAX)
// aarch64: mrs cntvct_el0 (virtual counter)
// ============================================================

pub fn readCycles() u64 {
    return switch (builtin.cpu.arch) {
        .x86_64 => asm volatile (
            \\lfence
            \\rdtsc
            \\shl $32, %%rdx
            \\or %%rdx, %%rax
            : [ret] "={rax}" (-> u64),
            :
            : .{ .rdx = true }),
        .aarch64 => asm volatile (
            \\mrs x0, cntvct_el0
            : [ret] "={x0}" (-> u64),
        ),
        else => @compileError("unsupported arch"),
    };
}

fn benchmarkCycleCounter() !void {
    const stdout = std.fs.File.stdout().deprecatedWriter();

    try stdout.print("\n--- Cycle counter (requires asm, impossible from pure zig) ---\n", .{});

    // Measure overhead of reading the counter itself
    const a = readCycles();
    const b = readCycles();
    const overhead = b -% a;
    try stdout.print("rdtsc overhead: ~{d} cycles\n", .{overhead});

    // Measure a known workload in cycles
    const start = readCycles();
    var x: u64 = 0;
    for (0..10_000) |i| {
        x +%= i;
    }
    const elapsed = readCycles() -% start;
    try stdout.print("10k iterations: {d} cycles (result={d})\n", .{ elapsed, x });
}

// ============================================================
// Bit scan — find first set bit in constant time
// zig: loop checking each bit (up to 64 iterations)
// asm: tzcnt instruction (single cycle on modern CPUs)
// ============================================================

pub fn bit_scan_zig(val: u64) u64 {
    if (val == 0) return std.math.maxInt(u64);
    var v = val;
    var pos: u64 = 0;
    while (v & 1 == 0) {
        v >>= 1;
        pos += 1;
    }
    return pos;
}

pub fn bit_scan_asm(val: u64) u64 {
    var result = val;
    asm volatile (switch (builtin.cpu.arch) {
            .x86_64 =>
            \\tzcnt %[v], %[v]
            ,
            .aarch64 =>
            \\rbit %[v], %[v]
            \\clz %[v], %[v]
            ,
            else => @compileError("unsupported arch"),
        }
        : [v] "+r" (result),
    );
    return result;
}

fn benchmarkBitScan() !void {
    const stdout = std.fs.File.stdout().deprecatedWriter();
    const iterations = 10_000_000;

    const test_vals = [_]u64{ 1, 2, 1 << 31, 1 << 63, 0x00FF00FF00FF00FF };

    try stdout.print("\n--- Bit scan (tzcnt vs loop) ---\n", .{});
    try stdout.print("iterations: {d} (5 values cycled)\n", .{iterations});

    // Correctness check
    for (test_vals) |v| {
        const z = bit_scan_zig(v);
        const a = bit_scan_asm(v);
        if (z != a) try stdout.print("  MISMATCH val=0x{x}: zig={d} asm={d}\n", .{ v, z, a });
    }

    var timer = try std.time.Timer.start();
    var dummy: u64 = 0;
    for (0..iterations) |i| {
        dummy +%= bit_scan_zig(test_vals[i % test_vals.len]);
    }
    const zig_ns = timer.read();
    timer.reset();

    for (0..iterations) |i| {
        dummy +%= bit_scan_asm(test_vals[i % test_vals.len]);
    }
    const asm_ns = timer.read();

    try stdout.print("zig loop: {d:.3} ms (acc={d})\n", .{ @as(f64, @floatFromInt(zig_ns)) / 1_000_000.0, dummy });
    try stdout.print("asm tzcnt: {d:.3} ms\n", .{@as(f64, @floatFromInt(asm_ns)) / 1_000_000.0});
}

pub fn main() !void {
    try benchmarkAdd();
    try benchmarkSimdAdd();
    try benchmarkCycleCounter();
    try benchmarkBitScan();
}
