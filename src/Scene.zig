const std = @import("std");
const ArrayList = std.ArrayList;
const tracing = @import("tracing.zig");
const Texture = tracing.texture.Texture;
const Material = @import("mats.zig").Material;

const vector = @import("vec3.zig");
const color = vector.color;
const vec3 = vector.vec3;

const Scene = @This();
const Model = tracing.Model;

stuff_arena: std.heap.ArenaAllocator,
objects: ArrayList(tracing.Object),
bvh_arena: std.heap.ArenaAllocator,
world: tracing.BvhNode,

pub fn deinit(self: *Scene, gpa: std.mem.Allocator) void {
    self.bvh_arena.deinit();
    self.objects.deinit(gpa);
    self.stuff_arena.deinit();
}

fn new(gpa: std.mem.Allocator, val: anytype) !*@TypeOf(val) {
    const ptr = try gpa.create(@TypeOf(val));
    ptr.* = val;
    return ptr;
}

pub fn spheres(gpa: std.mem.Allocator) !Scene {
    var objects = ArrayList(tracing.Object).empty;
    errdefer objects.deinit(gpa);

    var stuff_arena = std.heap.ArenaAllocator.init(gpa);
    errdefer stuff_arena.deinit();
    const stuff = stuff_arena.allocator();

    const floor_texture = try new(stuff, Texture{
        .checker = .{
            .scale = 0.5,
            .odd = try new(stuff, Texture{ .solid_color = .{ .albedo = color(.{ 0, 0.8, 0.8 }) } }),
            .even = try new(stuff, Texture{ .solid_color = .{ .albedo = color(.{ 0.8, 0.8, 0 }) } }),
        },
    });

    const material_ground = try new(stuff, Material{
        .lambertian = .{ .texture = floor_texture },
    });

    const material_left = try new(stuff, Material{
        .dielectric = .{ .refraction_index = 1.5 },
    });

    const material_bubble = try new(stuff, Material{
        .dielectric = .{ .refraction_index = 1.0 / 1.5 },
    });

    const material_center = try new(stuff, Material{
        .lambertian = .{
            .texture = try new(stuff, Texture{
                .solid_color = .{ .albedo = color(.{ 0.1, 0.2, 0.5 }) },
            }),
        },
    });

    const material_right = try new(stuff, Material{
        .metal = .{ .albedo = color(.{ 0.8, 0.6, 0.2 }), .fuzziness = 0.05 },
    });

    try objects.append(gpa, .{ .material = material_ground, .geometry = .{ .sphere = .{
        .center = vec3(.{ 0, -100.5, -1 }),
        .radius = 100,
    } } });

    try objects.append(gpa, .{ .material = material_left, .geometry = .{ .sphere = .{
        .center = vec3(.{ -1, 0, -1 }),
        .radius = 0.5,
    } } });

    try objects.append(gpa, .{ .material = material_bubble, .geometry = .{ .sphere = .{
        .center = vec3(.{ -1, 0, -1 }),
        .radius = 0.4,
    } } });

    try objects.append(gpa, .{ .material = material_center, .geometry = .{ .sphere = .{
        .center = vec3(.{ 0, 0, -1.2 }),
        .radius = 0.5,
    } } });

    try objects.append(gpa, .{ .material = material_right, .geometry = .{ .sphere = .{
        .center = vec3(.{ 1, 0, -1 }),
        .radius = 0.5,
    } } });

    const points: @Vector(3, *vector.Vec3(.arb)) = .{
        try new(stuff, vec3(.{ -0.5, 0, -0.5 })),
        try new(stuff, vec3(.{ 0.5, 0, -0.5 })),
        try new(stuff, vec3(.{ 0, 1, -0.5 })),
    };
    try objects.append(gpa, .{
        .material = material_right,
        .geometry = .{ .triangle = .{ .points = points } },
    });

    var teapot = try Model.load(stuff);
    errdefer teapot.deinit(gpa);

    for (teapot.triangles.items) |tri| {
        try objects.append(gpa, .{
            .geometry = .{ .triangle = tri },
            .material = material_left,
        });
    }

    var bvh_arena = std.heap.ArenaAllocator.init(gpa);
    errdefer bvh_arena.deinit();
    const bvh_allocator = bvh_arena.allocator();
    const world = try tracing.BvhNode.init(objects.items, bvh_allocator);
    return Scene{
        .world = world,
        .bvh_arena = bvh_arena,
        .objects = objects,
        .stuff_arena = stuff_arena,
    };
}

pub fn globe(gpa: std.mem.Allocator) !Scene {
    var stuff_arena = std.heap.ArenaAllocator.init(gpa);
    errdefer stuff_arena.deinit();
    const stuff = stuff_arena.allocator();

    var earth_image = try tracing.texture.Image.load(gpa, "earthmap.jpg");
    errdefer earth_image.deinit(gpa);
    const earth_texture = try new(stuff, Texture{ .image = earth_image });
    const earth_material = try new(stuff, Material{ .lambertian = .{ .texture = earth_texture } });

    var objects = ArrayList(tracing.Object).empty;
    try objects.append(gpa, .{
        .geometry = .{
            .sphere = .{ .center = vec3(.{ 0, 0, 0 }), .radius = 2 },
        },
        .material = earth_material,
    });

    var bvh_arena = std.heap.ArenaAllocator.init(gpa);
    errdefer bvh_arena.deinit();
    const bvh_allocator = bvh_arena.allocator();
    const world = try tracing.BvhNode.init(objects.items, bvh_allocator);

    return Scene{
        .world = world,
        .bvh_arena = bvh_arena,
        .objects = objects,
        .stuff_arena = stuff_arena,
    };
}
