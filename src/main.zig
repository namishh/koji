const rl = @import("raylib");
const std = @import("std");
const math = std.math;
const ArrayList = std.ArrayList;

const SortContext = @import("kd_tree.zig").SortContext;
const KdTree = @import("kd_tree.zig").KdTree;

pub fn main() anyerror!void {
    var timer = std.time.nanoTimestamp();
    const screenWidth = 1280;
    const screenHeight = 720;
    rl.initWindow(screenWidth, screenHeight, "koji");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        std.posix.getrandom(std.mem.asBytes(&seed)) catch unreachable;
        break :blk seed;
    });
    const rand = prng.random();

    const numPoints = 100_000;
    var points = ArrayList(rl.Vector2).init(allocator);
    defer points.deinit();
    var colors = ArrayList(rl.Color).init(allocator);
    defer colors.deinit();

    var point_indices = try allocator.alloc(usize, numPoints);
    defer allocator.free(point_indices);

    for (0..numPoints) |i| {
        try points.append(.{
            .x = rand.float(f32) * screenWidth,
            .y = rand.float(f32) * screenHeight,
        });
        try colors.append(.{
            .r = rand.int(u8),
            .g = rand.int(u8),
            .b = rand.int(u8),
            .a = 255,
        });
        point_indices[i] = i;
    }

    const kdtree = try KdTree.build(allocator, points.items, point_indices, 0);
    defer kdtree.?.deinitKdTree(allocator);

    const voronoiTexture = try rl.loadRenderTexture(screenWidth, screenHeight);
    defer rl.unloadRenderTexture(voronoiTexture);

    rl.beginTextureMode(voronoiTexture);
    rl.clearBackground(.white);

    for (0..screenHeight) |y| {
        for (0..screenWidth) |x| {
            const pixel = rl.Vector2{ .x = @floatFromInt(x), .y = @floatFromInt(y) };
            var closestDist: f32 = math.inf(f32);
            var closestIndex: usize = 0;

            if (kdtree) |tree| {
                tree.findNearest(pixel, &closestDist, &closestIndex);
            }

            rl.drawPixel(@intFromFloat(pixel.x), @intFromFloat(pixel.y), colors.items[closestIndex]);
        }
    }

    rl.endTextureMode();

    timer = std.time.nanoTimestamp() - timer;
    const f_time = @as(f64, @floatFromInt(timer)) / 1000000000.0;
    std.debug.print("Time taken: {d:.3} seconds\n", .{f_time});

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(.white);
        rl.drawTextureRec(voronoiTexture.texture, .{ .x = 0, .y = 0, .width = screenWidth, .height = -screenHeight }, .{ .x = 0, .y = 0 }, .white);
    }
}
