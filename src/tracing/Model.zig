const std = @import("std");
const vec3 = @import("../vec3.zig");
const Vec3 = vec3.Vec3;

const tracing = @import("../tracing.zig");
const Triangle = tracing.Triangle;

const Model = @This();

const ArrayList = std.ArrayList;
const fmt = std.fmt;
const Allocator = std.mem.Allocator;

const Vertex = Vec3(.arb);

vertices: std.ArrayList(Vertex),
triangles: std.ArrayList(Triangle),

pub fn load(gpa: Allocator) !Model {
    const file = try std.fs.cwd().openFile("teapot_bezier0.tris", .{ .mode = .read_only });
    var buf: [1024]u8 = undefined;
    var file_reader = file.reader(&buf);
    const reader = &file_reader.interface;
    const len = try reader.takeSentinel('\n');
    const num_tris = try fmt.parseInt(usize, len, 10);

    var points = try ArrayList(Vertex).initCapacity(gpa, num_tris * 3);
    errdefer points.deinit(gpa);
    var triangles = try ArrayList(Triangle).initCapacity(gpa, num_tris);
    errdefer triangles.deinit(gpa);

    for (0..num_tris) |_| {
        const tri_points = try points.addManyAsArray(gpa, 3);
        const tri = try read_triangle(reader, tri_points);
        const tri_owned = try triangles.addOne(gpa);
        tri_owned.* = tri;
    }

    return .{
        .triangles = triangles,
        .vertices = points,
    };
}

test {
    const gpa = std.testing.allocator;
    const model = try Model.load(gpa);
    defer model.deinit(gpa);

    try std.testing.expect(false);
}

fn read_triangle(reader: *std.Io.Reader, buf: *[3]Vertex) !Triangle {
    inline for (0..3) |vertex_i| {
        const vertex_line = try reader.takeSentinel('\n');
        var coords = std.mem.splitScalar(u8, vertex_line, ' ');
        var point: @Vector(3, f64) = undefined;

        inline for (0..3) |coord_i| {
            const coord = try fmt.parseFloat(f64, coords.next() orelse return error.IncompleteVertex);
            point[coord_i] = coord;
        }
        std.debug.assert(coords.next() == null);
        buf[vertex_i] = Vertex{
            .inner = point,
        };
    }
    _ = try reader.takeSentinel('\n');
    return .{ .points = .{ &buf[0], &buf[1], &buf[2] } };
}

pub fn deinit(self: *Model, gpa: Allocator) void {
    self.triangles.deinit(gpa);
    self.vertices.deinit(gpa);
}
