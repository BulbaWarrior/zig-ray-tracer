const std = @import("std");
const ray_tracing = @import("ray_tracing");

const Allocator = std.mem.Allocator;

const vector = @import("vec3.zig");
const vec3 = vector.vec3;
const color = vector.color;

const Vec3 = vector.Vec3;
const Color = vector.Vec3(.color);

const Material = @import("mats.zig").Material;

const Camera = @import("Camera.zig");
pub const tracing = @import("tracing.zig");

const Model = tracing.Model;

pub fn main() !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);

    const stdout = &stdout_writer.interface;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const ally = arena.allocator();

    var objects = std.ArrayList(tracing.Object).empty;
    defer objects.deinit(ally);

    const material_ground = Material{
        .lambertian = .{ .albedo = color(.{ 0.8, 0.8, 0.0 }) },
    };
    const material_left = Material{
        .dielectric = .{ .refraction_index = 1.5 },
    };
    const material_bubble = Material{
        .dielectric = .{ .refraction_index = 1.0 / 1.5 },
    };

    const material_center = Material{
        .lambertian = .{ .albedo = color(.{ 0.1, 0.2, 0.5 }) },
    };
    const material_right = Material{
        .metal = .{ .albedo = color(.{ 0.8, 0.6, 0.2 }), .fuzziness = 0.05 },
    };

    try objects.append(ally, .{ .material = &material_ground, .geometry = .{ .sphere = .{
        .center = vec3(.{ 0, -100.5, -1 }),
        .radius = 100,
    } } });

    try objects.append(ally, .{ .material = &material_left, .geometry = .{ .sphere = .{
        .center = vec3(.{ -1, 0, -1 }),
        .radius = 0.5,
    } } });

    try objects.append(ally, .{ .material = &material_bubble, .geometry = .{ .sphere = .{
        .center = vec3(.{ -1, 0, -1 }),
        .radius = 0.4,
    } } });

    try objects.append(ally, .{ .material = &material_center, .geometry = .{ .sphere = .{
        .center = vec3(.{ 0, 0, -1.2 }),
        .radius = 0.5,
    } } });

    try objects.append(ally, .{ .material = &material_right, .geometry = .{ .sphere = .{
        .center = vec3(.{ 1, 0, -1 }),
        .radius = 0.5,
    } } });

    const points = .{ &vec3(.{ -0.5, 0, -0.5 }), &vec3(.{ 0.5, 0, -0.5 }), &vec3(.{ 0, 1, -0.5 }) };
    try objects.append(ally, .{
        .material = &material_right,
        .geometry = .{ .triangle = .{ .points = points } },
    });

    // var teapot = try Model.load(ally);
    // defer teapot.deinit(ally);
    //
    // for (teapot.triangles.items) |tri| {
    //     try objects.append(ally, .{
    //         .geometry = .{ .triangle = tri },
    //         .material = &material_left,
    //     });
    // }

    var bvh_arena = std.heap.ArenaAllocator.init(ally);
    defer bvh_arena.deinit();
    const bvh_allocator = bvh_arena.allocator();
    const world = try tracing.BvhNode.init(objects.items, bvh_allocator);

    var thread_pool: std.Thread.Pool = undefined;
    try thread_pool.init(.{ .allocator = ally });
    defer thread_pool.deinit();

    const builtin = @import("builtin");
    const cam = Camera.init(.{
        .image_width = if (builtin.mode == .Debug) 480 else 720,
        .samples_per_pixel = if (builtin.mode == .Debug) 20 else 200,
        .max_depth = 50,
        .vfov = 90,
        .orientation = .{
            // .look_from = vec3(.{ -3, 3, 4 }),

            .look_from = vec3(.{ 0, 0, 1 }),
            .look_at = vec3(.{ 0, 0, -1 }),
            .up = vec3(.{ 0, 1, 0 }),
        },
    }, &world);
    const pixels = try cam.alloc_frame(ally);
    defer ally.free(pixels);

    var progress = std.Progress.start(.{});
    var render = progress.start("render", 0);
    try cam.render(&render, &thread_pool, pixels, ally);
    render.end();

    var writing = progress.start("writing", 0);
    const color_steps = 255;
    try stdout.print("P6\n{d} {d}\n{d}\n", .{ cam.image_width, cam.image_height, color_steps });
    for (0..pixels.len) |i| {
        var pixel = &pixels[i];
        //dither
        // pixel.* = pixel.add(&Vec3.random_unit().mul(0.05)).clamp(0, 1);
        pixel.linear_to_gamma();
        pixel.mut_mul(color_steps + 0.999);
        const r: u8 = @intFromFloat(pixel.coord(.x));
        const g: u8 = @intFromFloat(pixel.coord(.y));
        const b: u8 = @intFromFloat(pixel.coord(.z));
        const data: [3]u8 = .{ r, g, b };
        try stdout.writeAll(&data);
    }
    try stdout.flush();
    writing.end();
}
