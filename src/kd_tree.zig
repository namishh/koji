const rl = @import("raylib");
const std = @import("std");

pub const SortContext = struct {
    points: []rl.Vector2,
    axis: u32,
};

fn sortByAxis(context: SortContext, a: usize, b: usize) bool {
    const coord_a = if (context.axis == 0) context.points[a].x else context.points[a].y;
    const coord_b = if (context.axis == 0) context.points[b].x else context.points[b].y;
    return coord_a < coord_b;
}

pub const KdTree = struct {
    point: rl.Vector2,
    color_index: usize,
    left: ?*KdTree,
    right: ?*KdTree,
    depth: u32,

    pub fn build(allocator: std.mem.Allocator, points: []rl.Vector2, indices: []usize, depth: u32) !?*KdTree {
        if (points.len == 0) return null;

        const axis = depth % 2;

        var point_indices = try allocator.alloc(usize, points.len);
        defer allocator.free(point_indices);
        for (0..points.len) |i| point_indices[i] = i;

        std.sort.heap(usize, point_indices, SortContext{ .points = points, .axis = axis }, sortByAxis);

        const median = points.len / 2;
        const median_idx = point_indices[median];

        var node = try allocator.create(KdTree);
        node.point = points[median_idx];
        node.color_index = indices[median_idx];
        node.depth = depth;

        var left_points = try allocator.alloc(rl.Vector2, median);
        var left_indices = try allocator.alloc(usize, median);
        var right_points = try allocator.alloc(rl.Vector2, points.len - median - 1);
        var right_indices = try allocator.alloc(usize, points.len - median - 1);
        defer allocator.free(left_points);
        defer allocator.free(left_indices);
        defer allocator.free(right_points);
        defer allocator.free(right_indices);

        for (0..median) |i| {
            left_points[i] = points[point_indices[i]];
            left_indices[i] = indices[point_indices[i]];
        }
        for (0..points.len - median - 1) |i| {
            right_points[i] = points[point_indices[median + 1 + i]];
            right_indices[i] = indices[point_indices[median + 1 + i]];
        }

        node.left = try build(allocator, left_points, left_indices, depth + 1);
        node.right = try build(allocator, right_points, right_indices, depth + 1);

        return node;
    }

    pub fn findNearest(self: *const KdTree, target: rl.Vector2, best_dist: *f32, best_index: *usize) void {
        const dist = target.distance(self.point);
        if (dist < best_dist.*) {
            best_dist.* = dist;
            best_index.* = self.color_index;
        }

        const axis = self.depth % 2;
        const target_coord = if (axis == 0) target.x else target.y;
        const node_coord = if (axis == 0) self.point.x else self.point.y;

        const primary = if (target_coord < node_coord) self.left else self.right;
        const secondary = if (target_coord < node_coord) self.right else self.left;

        if (primary) |p| p.findNearest(target, best_dist, best_index);

        if (secondary != null and @abs(target_coord - node_coord) < best_dist.*) {
            secondary.?.findNearest(target, best_dist, best_index);
        }
    }

    pub fn deinitKdTree(
        self: *KdTree,
        allocator: std.mem.Allocator,
    ) void {
        if (self.left) |left| deinitKdTree(left, allocator);
        if (self.right) |right| deinitKdTree(right, allocator);
        allocator.destroy(self);
    }
};
