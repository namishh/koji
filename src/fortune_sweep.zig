// fortune sweep algorithm for computing Voronoi diagrams instead of using kd-trees
// an alternate way, but not used in the current implementation. will return
const rl = @import("raylib");
const std = @import("std");

pub const EventType = enum {
    Site,
    Circle,
};

pub const Event = struct {
    type: EventType,
    point: rl.Vector2,
    depth: u32,
    site: rl.Vector2,
    arc: ?*BeachlineArc,
    y_bottom: f32,

    pub fn compare(context: void, a: Event, b: Event) std.math.Order {
        _ = context;
        if (a.point.y < b.point.y) return .lt;
        if (a.point.y > b.point.y) return .gt;
        if (a.point.x < b.point.x) return .lt;
        if (a.point.x > b.point.x) return .gt;
        return .eq;
    }
};

pub const BeachlineArc = struct {
    left: ?*BeachlineArc,
    parent: ?*BeachlineArc,
    right: ?*BeachlineArc,
    site: rl.Vector2,
    edge: ?*VoronoiEdge,
    is_valid: bool,
    circle_event: ?*Event,
};

pub const VoronoiEdge = struct {
    site1: rl.Vector2,
    site2: rl.Vector2,

    pub fn init(site1: rl.Vector2, site2: rl.Vector2) VoronoiEdge {
        return VoronoiEdge{
            .site1 = site1,
            .site2 = site2,
        };
    }
};

pub const Beachline = struct {
    root: ?*BeachlineArc,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Beachline {
        return Beachline{
            .root = null,
            .allocator = allocator,
        };
    }

    pub fn insert(self: *Beachline, site: rl.Vector2, sweep_y: f32) !*BeachlineArc {
        const new_arc = try self.allocator.create(BeachlineArc);
        new_arc.* = BeachlineArc{
            .left = null,
            .right = null,
            .parent = null,
            .site = site,
            .is_valid = true,
            .edge = null,
            .circle_event = null,
        };

        if (self.root == null) {
            self.root = new_arc;
            return new_arc;
        }

        const above_arc = self.findArcAbove(site.x, sweep_y);
        if (above_arc) |arc| {
            if (arc.circle_event) |event| {
                event.arc = null;
            }

            const left_arc = try self.allocator.create(BeachlineArc);
            const right_arc = try self.allocator.create(BeachlineArc);

            left_arc.* = BeachlineArc{
                .left = arc.left,
                .right = new_arc,
                .parent = arc,
                .site = arc.site,
                .edge = null,
                .circle_event = null,
                .is_valid = true,
            };

            right_arc.* = BeachlineArc{
                .left = new_arc,
                .right = arc.right,
                .parent = arc,
                .site = arc.site,
                .is_valid = true,
                .edge = null,
                .circle_event = null,
            };

            new_arc.left = left_arc;
            new_arc.right = right_arc;
            new_arc.parent = arc;

            arc.left = left_arc;
            arc.right = right_arc;

            return new_arc;
        }

        return new_arc;
    }

    pub fn findArcAbove(self: *Beachline, x: f32, sweep_y: f32) ?*BeachlineArc {
        var current = self.root;
        while (current) |arc| {
            const breakpoint_left = if (arc.left) |left| getBreakpoint(left.site, arc.site, sweep_y) else -std.math.inf(f32);
            const breakpoint_right = if (arc.right) |right| getBreakpoint(arc.site, right.site, sweep_y) else std.math.inf(f32);

            if (x >= breakpoint_left and x <= breakpoint_right) {
                return arc;
            } else if (x < breakpoint_left) {
                current = arc.left;
            } else {
                current = arc.right;
            }
        }
        return null;
    }

    pub fn getBreakpoint(site1: rl.Vector2, site2: rl.Vector2, sweep_y: f32) f32 {
        const d1 = site1.y - sweep_y;
        const d2 = site2.y - sweep_y;

        if (@abs(d1) < 1e-6) return site1.x;
        if (@abs(d2) < 1e-6) return site2.x;

        const a = 1.0 / (2.0 * d1) - 1.0 / (2.0 * d2);
        const b = site2.x / d2 - site1.x / d1;
        const c = (site1.x * site1.x + site1.y * site1.y - sweep_y * sweep_y) / (2.0 * d1) -
            (site2.x * site2.x + site2.y * site2.y - sweep_y * sweep_y) / (2.0 * d2);

        if (@abs(a) < 1e-6) {
            return -c / b;
        }

        const discriminant = b * b - 4.0 * a * c;
        if (discriminant < 0) return (site1.x + site2.x) / 2.0;

        const sqrt_disc = @sqrt(discriminant);
        const x1 = (-b + sqrt_disc) / (2.0 * a);
        const x2 = (-b - sqrt_disc) / (2.0 * a);

        return if (site1.y > site2.y) @max(x1, x2) else @min(x1, x2);
    }

    pub fn remove(self: *Beachline, arc: *BeachlineArc) void {
        arc.is_valid = false;

        arc.circle_event = null;

        var replacement: ?*BeachlineArc = null;
        if (arc.left != null and arc.right != null) {
            replacement = arc.right;
            while (replacement.?.left != null) {
                replacement = replacement.?.left;
            }
        } else {
            replacement = if (arc.left) |left| left else arc.right;
        }

        if (arc.parent) |parent| {
            if (parent.left == arc) {
                parent.left = replacement;
            } else {
                parent.right = replacement;
            }
            if (replacement) |r| r.parent = parent;
        } else {
            self.root = replacement;
            if (replacement) |r| r.parent = null;
        }

        self.allocator.destroy(arc);
    }

    pub fn deinit(self: *Beachline) void {
        self.freeNode(self.root);
    }

    fn freeNode(self: *Beachline, node: ?*BeachlineArc) void {
        if (node) |n| {
            self.freeNode(n.left);
            self.freeNode(n.right);
            if (n.circle_event) |event| {
                self.allocator.destroy(event);
            }
            self.allocator.destroy(n);
        }
    }
};

pub fn checkCircleEvent(a: rl.Vector2, b: rl.Vector2, c: rl.Vector2) ?struct { center: rl.Vector2, y_bottom: f32 } {
    const d = 2.0 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y));
    if (@abs(d) < 1e-6) return null;

    const ux = ((a.x * a.x + a.y * a.y) * (b.y - c.y) + (b.x * b.x + b.y * b.y) * (c.y - a.y) + (c.x * c.x + c.y * c.y) * (a.y - b.y)) / d;
    const uy = ((a.x * a.x + a.y * a.y) * (c.x - b.x) + (b.x * b.x + b.y * b.y) * (a.x - c.x) + (c.x * c.x + c.y * c.y) * (b.x - a.x)) / d;

    const center = rl.Vector2{ .x = ux, .y = uy };
    const radius = @sqrt((center.x - a.x) * (center.x - a.x) + (center.y - a.y) * (center.y - a.y));

    return .{ .center = center, .y_bottom = center.y + radius };
}

pub const VoronoiGenerator = struct {
    allocator: std.mem.Allocator,
    event_queue: std.PriorityQueue(Event, void, Event.compare),
    voronoi_edges: std.ArrayList(VoronoiEdge),
    beachline: Beachline,
    sweep_y: f32,

    pub fn init(allocator: std.mem.Allocator) !VoronoiGenerator {
        return VoronoiGenerator{
            .beachline = Beachline.init(allocator),
            .sweep_y = 0.0,
            .allocator = allocator,
            .event_queue = std.PriorityQueue(Event, void, Event.compare).init(allocator, {}),
            .voronoi_edges = std.ArrayList(VoronoiEdge).init(allocator),
        };
    }

    pub fn deinit(self: *VoronoiGenerator) void {
        while (self.event_queue.items.len > 0) {
            _ = self.event_queue.remove();
        }

        self.beachline.deinit();
        self.event_queue.deinit();
        self.voronoi_edges.deinit();
    }

    pub fn generate(self: *VoronoiGenerator, sites: []rl.Vector2) !void {
        for (sites) |site| {
            try self.event_queue.add(Event{
                .type = .Site,
                .point = site,
                .depth = 0,
                .site = site,
                .arc = null,
                .y_bottom = 0,
            });
        }

        while (self.event_queue.items.len > 0) {
            const event = self.event_queue.remove();
            self.sweep_y = event.point.y;

            switch (event.type) {
                .Site => try self.handleSiteEvent(event),
                .Circle => self.handleCircleEvent(event),
            }
        }
    }

    pub fn handleSiteEvent(self: *VoronoiGenerator, event: Event) !void {
        const new_arc = try self.beachline.insert(event.site, self.sweep_y);

        if (new_arc.left) |left| {
            if (left.left) |left_left| {
                try self.addCircleEvent(left_left, left, new_arc);
            }
        }

        if (new_arc.right) |right| {
            if (right.right) |right_right| {
                try self.addCircleEvent(new_arc, right, right_right);
            }
        }
    }

    pub fn handleCircleEvent(self: *VoronoiGenerator, event: Event) void {
        const arc = event.arc orelse return;

        // Check if arc is still valid
        if (!arc.is_valid) return;

        // Mark arc as invalid to prevent reuse
        arc.is_valid = false;

        const left_arc = arc.left;
        const right_arc = arc.right;

        if (left_arc != null and right_arc != null) {
            const edge = VoronoiEdge{
                .site1 = left_arc.?.site,
                .site2 = right_arc.?.site,
            };
            self.voronoi_edges.append(edge) catch {};
        }

        // Clear circle events for adjacent arcs BEFORE removing
        if (left_arc) |left| {
            left.circle_event = null;
        }
        if (right_arc) |right| {
            right.circle_event = null;
        }

        self.beachline.remove(arc);

        // Add new circle events for remaining arcs
        if (left_arc != null and right_arc != null) {
            if (left_arc.?.left) |ll| {
                self.addCircleEvent(ll, left_arc.?, right_arc.?) catch {};
            }
            if (right_arc.?.right) |rr| {
                self.addCircleEvent(left_arc.?, right_arc.?, rr) catch {};
            }
        }
    }

    fn addCircleEvent(self: *VoronoiGenerator, a_arc: *BeachlineArc, b_arc: *BeachlineArc, c_arc: *BeachlineArc) !void {
        const circle_info = checkCircleEvent(a_arc.site, b_arc.site, c_arc.site) orelse return;

        if (circle_info.y_bottom <= self.sweep_y) return;

        const circle_event = Event{
            .type = .Circle,
            .point = circle_info.center,
            .depth = 0,
            .site = rl.Vector2{ .x = 0, .y = 0 },
            .arc = b_arc,
            .y_bottom = circle_info.y_bottom,
        };

        b_arc.circle_event = try self.allocator.create(Event);
        b_arc.circle_event.?.* = circle_event;
        b_arc.circle_event.?.arc = b_arc;

        try self.event_queue.add(circle_event);
    }
};
