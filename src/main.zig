const std = @import("std");
const ray_tracing = @import("ray_tracing");

const Allocator = std.mem.Allocator;

const vector = @import("vec3.zig");
const vec3 = vector.vec3;

const Vec3 = vector.Vec3;
const Color = vector.Vec3(.color);

const Material = @import("mats.zig").Material;

const Camera = @import("Camera.zig");
const tracing = @import("tracing.zig");

pub fn main() !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);

    const stdout = &stdout_writer.interface;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const ally = arena.allocator();
    var world = tracing.Objects{ .list = .empty };
    defer world.deinit(ally);

    const material_ground = Material{
        .lambertian = .{ .albedo = vec3(.{ 0.8, 0.8, 0.0 }) },
    };
    const material_left = Material{
        .dielectric = .{ .refraction_index = 1.5 },
    };
    const material_bubble = Material{
        .dielectric = .{ .refraction_index = 1.0 / 1.5 },
    };

    const material_center = Material{
        .lambertian = .{ .albedo = vec3(.{ 0.1, 0.2, 0.5 }) },
    };
    const material_right = Material{
        .metal = .{ .albedo = vec3(.{ 0.8, 0.6, 0.2 }), .fuzziness = 0.05 },
    };

    try world.append(ally, .{ .material = material_ground, .geometry = .{ .sphere = .{
        .center = vec3(.{ 0, -100.5, -1 }),
        .radius = 100,
    } } });

    try world.append(ally, .{ .material = material_left, .geometry = .{ .sphere = .{
        .center = vec3(.{ -1, 0, -1 }),
        .radius = 0.5,
    } } });

    try world.append(ally, .{ .material = material_bubble, .geometry = .{ .sphere = .{
        .center = vec3(.{ -1, 0, -1 }),
        .radius = 0.4,
    } } });

    try world.append(ally, .{ .material = material_center, .geometry = .{ .sphere = .{
        .center = vec3(.{ 0, 0, -1.2 }),
        .radius = 0.5,
    } } });

    try world.append(ally, .{ .material = material_right, .geometry = .{ .sphere = .{
        .center = vec3(.{ 1, 0, -1 }),
        .radius = 0.5,
    } } });

    var thread_pool: std.Thread.Pool = undefined;
    try thread_pool.init(.{ .allocator = ally });
    defer thread_pool.deinit();

    const cam = Camera.init(.{
        .image_width = 720,
        .samples_per_pixel = 20,
        .vfov = 25,
        .orientation = .{
            .look_from = vec3(.{ -2, 2, 1 }),
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
        const r: u8 = @intFromFloat(pixel.x());
        const g: u8 = @intFromFloat(pixel.y());
        const b: u8 = @intFromFloat(pixel.z());
        const data: [3]u8 = .{ r, g, b };
        try stdout.writeAll(&data);
    }
    try stdout.flush();
    writing.end();
}
//
// const OldCamera = struct {
//     const aspect_ratio = 16.0 / 9.0;
//     const image_width: usize = 1920;
//     const image_width_f: f64 = @floatFromInt(image_width);
//     const image_height: usize = @intFromFloat(image_width_f / aspect_ratio);
//
//     const viewport_height = 2.0;
//     const viewport_width = viewport_height * (image_width_f / image_height);
//     const focal_length = 1.0;
//
//     const cam_center = vec3(.{ 0, 0, 0 });
//
//     const viewport_u = vec3(.{ viewport_width, 0, 0 });
//
//     const viewport_v = vec3(.{ 0, -viewport_height, 0 });
//     const pixel_delta_u = viewport_u.div(image_width);
//
//     const pixel_delta_v = viewport_v.div(image_height);
//
//     const viewport_upper_left = cam_center
//         .sub(vec3(.{ 0, 0, focal_length }))
//         .sub(viewport_u.div(2))
//         .sub(viewport_v.div(2));
//
//     const pixel00_loc =
//         viewport_upper_left.add(pixel_delta_u.add(pixel_delta_v).mul(0.5));
//
//     const samples_per_pixel = 200;
//     const max_depth = 50;
//
//     fn render(world: *const Objects, progress_writer: *std.Io.Writer, thread_pool: *std.Thread.Pool, image_buf: []Color) !void {
//         comptime std.debug.assert(image_height > 1);
//         if (image_buf.len < image_width * image_height) {
//             return error.ImageBufferTooSmall;
//         }
//
//         // calculate
//         try progress_writer.print("caclulating...\n", .{});
//         try progress_writer.flush();
//
//         var wg = std.Thread.WaitGroup{};
//         // NOTE: this uses the same seed for every pixel
//         var noise: [samples_per_pixel * 2]f64 = undefined; // TODO: vectorize / compute at comptime?
//         for (0..noise.len) |i| {
//             noise[i] = std.crypto.random.float(f64);
//         }
//
//         for (0..image_height) |y| {
//             for (0..image_width) |x| {
//                 const PoolTask = struct {
//                     fn doIt(pixel_x: usize, pixel_y: usize, pixel: *Color, task_noise: *[samples_per_pixel * 2]f64, task_world: *const Objects) void {
//                         // I guess rng is now raced?
//                         const pixel_center = pixel00_loc.add(pixel_delta_u.mul(@floatFromInt(pixel_x))).add(pixel_delta_v.mul(@floatFromInt(pixel_y)));
//                         const ray_direction = pixel_center.sub(cam_center);
//                         var ray = Ray{
//                             .orig = cam_center,
//                             .dir = undefined,
//                         };
//
//                         var pixel_color = vec3(@splat(0));
//
//                         for (0..samples_per_pixel) |i| {
//                             // sample in square distribution
//                             const offset = pixel_delta_u.mul(task_noise[i] - 0.5).add(pixel_delta_v.mul(task_noise[2 * i] - 0.5));
//                             ray.dir = ray_direction.add(offset);
//                             pixel_color.mut_add(&ray.color(max_depth, task_world));
//                         }
//                         pixel_color.mut_div(samples_per_pixel);
//                         pixel.* = pixel_color.as(.color);
//                     }
//                 };
//                 thread_pool.spawnWg(&wg, PoolTask.doIt, .{ x, y, &image_buf[y * image_width + x], &noise, world });
//             }
//         }
//
//         try progress_writer.print("threads spawned\n", .{});
//         try progress_writer.flush();
//         thread_pool.waitAndWork(&wg);
//
//         try progress_writer.print("calculation finished, writing\n", .{});
//         try progress_writer.flush();
//     }
// };
