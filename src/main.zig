const rl = @import("raylib");
const std = @import("std");
const math = std.math;
const ArrayList = std.ArrayList;

const SortContext = @import("kd_tree.zig").SortContext;
const KdTree = @import("kd_tree.zig").KdTree;

const TileType = enum { Water, Land };

const Tile = struct { index: usize, tile_type: TileType, color: rl.Color, center: rl.Vector2 };

pub fn main() anyerror!void {
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

    const numPoints = 10000;
    var tiles = ArrayList(Tile).init(allocator);
    defer tiles.deinit();

    var point_indices = try allocator.alloc(usize, numPoints);
    defer allocator.free(point_indices);

    for (0..numPoints) |i| {
        const position = rl.Vector2{
            .x = rand.float(f32) * screenWidth,
            .y = rand.float(f32) * screenHeight,
        };
        const color = rl.Color{
            .r = rand.int(u8),
            .g = rand.int(u8),
            .b = rand.int(u8),
            .a = 255,
        };
        try tiles.append(.{
            .color = color,
            .center = position,
            .tile_type = .Water,
            .index = i,
        });
        point_indices[i] = i;
    }

    var point_refs = try allocator.alloc(rl.Vector2, tiles.items.len);
    defer allocator.free(point_refs);
    for (tiles.items, 0..) |tile, i| {
        point_refs[i] = tile.center;
    }

    const kdtree = try KdTree.build(allocator, point_refs, point_indices, 0);
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

            rl.drawPixel(@intFromFloat(pixel.x), @intFromFloat(pixel.y), tiles.items[closestIndex].color);
        }
    }

    rl.endTextureMode();

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(.white);
        rl.drawTextureRec(voronoiTexture.texture, .{ .x = 0, .y = 0, .width = screenWidth, .height = -screenHeight }, .{ .x = 0, .y = 0 }, .white);
    }
}
