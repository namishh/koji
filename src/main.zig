const rl = @import("raylib");
const std = @import("std");
const math = std.math;
const ArrayList = std.ArrayList;

const SortContext = @import("kd_tree.zig").SortContext;
const KdTree = @import("kd_tree.zig").KdTree;

const TileType = enum { Water, Land };

const VoronoiEdge = struct {
    start: rl.Vector2,
    end: rl.Vector2,
    neighbor_index: usize,
};

const Tile = struct {
    index: usize,
    tile_type: TileType,
    color: rl.Color,
    center: rl.Vector2,
    edges: ArrayList(VoronoiEdge),
    neighbors: ArrayList(usize),

    pub fn deinit(self: *Tile) void {
        self.edges.deinit();
        self.neighbors.deinit();
    }
};

const NodeCandidate = struct { dist_sq: f32, index: usize };

const KdTreeExt = struct {
    pub fn findKNearest(tree: *const KdTree, target: rl.Vector2, k: usize, allocator: std.mem.Allocator) ![]usize {
        var candidates = ArrayList(NodeCandidate).init(allocator);
        defer candidates.deinit();

        try collectAllNodes(tree, target, &candidates);

        std.sort.heap(NodeCandidate, candidates.items, {}, struct {
            fn lessThan(_: void, a: NodeCandidate, b: NodeCandidate) bool {
                return a.dist_sq < b.dist_sq;
            }
        }.lessThan);

        const result = try allocator.alloc(usize, @min(k, candidates.items.len));
        for (result, 0..) |*r, i| {
            r.* = candidates.items[i].index;
        }

        return result;
    }

    fn collectAllNodes(node: *const KdTree, target: rl.Vector2, candidates: *ArrayList(NodeCandidate)) !void {
        const dx = target.x - node.point.x;
        const dy = target.y - node.point.y;
        const dist_sq = dx * dx + dy * dy;

        try candidates.append(.{ .dist_sq = dist_sq, .index = node.color_index });

        if (node.left) |left| {
            try collectAllNodes(left, target, candidates);
        }
        if (node.right) |right| {
            try collectAllNodes(right, target, candidates);
        }
    }
};

fn findVoronoiEdges(tiles: []Tile, kdtree: *const KdTree, screen_width: i32, screen_height: i32, allocator: std.mem.Allocator) !void {
    _ = allocator;
    const sample_density = 2;

    for (0..@intCast(screen_height)) |y| {
        if (y % sample_density != 0) continue;

        for (0..@intCast(screen_width)) |x| {
            if (x % sample_density != 0) continue;

            const pixel = rl.Vector2{ .x = @floatFromInt(x), .y = @floatFromInt(y) };

            var closest_dist: f32 = math.inf(f32);
            var closest_index: usize = 0;
            kdtree.findNearest(pixel, &closest_dist, &closest_index);

            const directions = [_][2]i32{ .{ 1, 0 }, .{ 0, 1 }, .{ -1, 0 }, .{ 0, -1 } };

            for (directions) |dir| {
                const nx = @as(i32, @intCast(x)) + dir[0];
                const ny = @as(i32, @intCast(y)) + dir[1];

                if (nx >= 0 and nx < screen_width and ny >= 0 and ny < screen_height) {
                    const neighbor_pixel = rl.Vector2{ .x = @floatFromInt(nx), .y = @floatFromInt(ny) };

                    var neighbor_dist: f32 = math.inf(f32);
                    var neighbor_index: usize = 0;
                    kdtree.findNearest(neighbor_pixel, &neighbor_dist, &neighbor_index);

                    if (closest_index != neighbor_index) {
                        const edge_point = rl.Vector2{
                            .x = (pixel.x + neighbor_pixel.x) / 2,
                            .y = (pixel.y + neighbor_pixel.y) / 2,
                        };

                        const edge1 = VoronoiEdge{
                            .start = edge_point,
                            .end = edge_point,
                            .neighbor_index = neighbor_index,
                        };

                        try tiles[closest_index].edges.append(edge1);

                        var found = false;
                        for (tiles[closest_index].neighbors.items) |n| {
                            if (n == neighbor_index) {
                                found = true;
                                break;
                            }
                        }
                        if (!found) {
                            try tiles[closest_index].neighbors.append(neighbor_index);
                        }
                    }
                }
            }
        }
    }
}

fn findNeighborsDelaunay(tiles: []Tile, kdtree: *const KdTree, allocator: std.mem.Allocator) !void {
    for (tiles, 0..) |*tile, i| {
        const k_nearest = try KdTreeExt.findKNearest(kdtree, tile.center, 20, allocator);
        defer allocator.free(k_nearest);

        for (k_nearest) |neighbor_idx| {
            if (neighbor_idx == i) continue; // Skip self

            const neighbor = &tiles[neighbor_idx];

            if (try areVoronoiNeighbors(tile.center, neighbor.center, tiles, kdtree)) {
                var found = false;
                for (tile.neighbors.items) |n| {
                    if (n == neighbor_idx) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    try tile.neighbors.append(neighbor_idx);
                }
            }
        }
    }
}

fn areVoronoiNeighbors(center1: rl.Vector2, center2: rl.Vector2, tiles: []Tile, kdtree: *const KdTree) !bool {
    const midpoint = rl.Vector2{
        .x = (center1.x + center2.x) / 2,
        .y = (center1.y + center2.y) / 2,
    };

    const k_nearest = try KdTreeExt.findKNearest(kdtree, midpoint, 2, std.heap.page_allocator);
    defer std.heap.page_allocator.free(k_nearest);

    if (k_nearest.len < 2) return false;

    const closest1 = tiles[k_nearest[0]].center;
    const closest2 = tiles[k_nearest[1]].center;

    return (vectorsEqual(closest1, center1) and vectorsEqual(closest2, center2)) or
        (vectorsEqual(closest1, center2) and vectorsEqual(closest2, center1));
}

fn vectorsEqual(a: rl.Vector2, b: rl.Vector2) bool {
    const epsilon = 0.001;
    return @abs(a.x - b.x) < epsilon and @abs(a.y - b.y) < epsilon;
}

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

    var timer = try std.time.Timer.start();

    const numPoints = 1000; // Reduced for edge detection performance
    var tiles = ArrayList(Tile).init(allocator);
    defer {
        for (tiles.items) |*tile| {
            tile.deinit();
        }
        tiles.deinit();
    }

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
            .edges = ArrayList(VoronoiEdge).init(allocator),
            .neighbors = ArrayList(usize).init(allocator),
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
    try findNeighborsDelaunay(tiles.items, kdtree.?, allocator);
    try findVoronoiEdges(tiles.items, kdtree.?, screenWidth, screenHeight, allocator);

    const voronoiTexture = try rl.loadRenderTexture(screenWidth, screenHeight);
    defer rl.unloadRenderTexture(voronoiTexture);

    rl.beginTextureMode(voronoiTexture);
    rl.clearBackground(.white);

    // Draw Voronoi diagram
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

    const t = @as(f32, @floatFromInt(timer.lap())) / 1_000_000_000;
    std.debug.print("Time: {d:.3} seconds\n", .{t});

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(.white);
        rl.drawTextureRec(voronoiTexture.texture, .{ .x = 0, .y = 0, .width = screenWidth, .height = -screenHeight }, .{ .x = 0, .y = 0 }, .white);

        for (tiles.items) |tile| {
            for (tile.neighbors.items) |neighbor_idx| {
                const neighbor = tiles.items[neighbor_idx];
                rl.drawLineV(tile.center, neighbor.center, .red);
            }
        }
    }
}
