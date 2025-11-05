const std = @import("std");
const ray_tracing = @import("ray_tracing");

const Allocator = std.mem.Allocator;

const Vec3 = @import("vec3.zig");
const vec3 = Vec3.new;

pub fn main() !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);

    const stdout = &stdout_writer.interface;

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const ally = arena.allocator();
    var world = Objects{ .list = .empty };
    defer world.deinit(ally);

    var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
    const rng = prng.random();

    const material_ground = Material{
        .lambertian = .{ .albedo = vec3(.{ 0.8, 0.8, 0.0 }) },
    };
    const material_left = Material{
        .metal = .{ .albedo = vec3(.{ 0.8, 0.8, 0.8 }) },
    };
    const material_center = Material{
        .lambertian = .{ .albedo = vec3(.{ 0.1, 0.2, 0.5 }) },
    };
    const material_right = Material{
        .metal = .{ .albedo = vec3(.{ 0.8, 0.6, 0.2 }) },
    };

    try world.append(ally, .{ .material = material_ground, .geometry = .{ .sphere = .{
        .center = vec3(.{ 0, -100.5, -1 }),
        .radius = 100,
    } } });

    try world.append(ally, .{ .material = material_left, .geometry = .{ .sphere = .{
        .center = vec3(.{ -1, 0, -1 }),
        .radius = 0.5,
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

    const pixels = try ally.alloc(Vec3, Camera.image_width * Camera.image_height);
    defer ally.free(pixels);

    try Camera.render(&world, stderr, rng, &thread_pool, pixels);

    const color_steps = 255;
    try stdout.print("P6\n{d} {d}\n{d}\n", .{ Camera.image_width, Camera.image_height, color_steps });
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
        const written = try stdout.write(&data);
        std.debug.assert(written == 3);
    }
    try stdout.flush();
}

const Bounds = struct {
    min: f64,
    max: f64,

    fn contain(bounds: *const Bounds, t: f64) bool {
        return bounds.min <= t and t <= bounds.max;
    }

    fn surround(bounds: *const Bounds, t: f64) bool {
        return bounds.min < t and t < bounds.max;
    }

    fn size(self: *const Bounds) f64 {
        return self.max - self.min;
    }

    fn clamp(self: *const Bounds, x: f64) f64 {
        if (x < self.min) return self.min;
        if (x > self.max) return self.max;
        return x;
    }

    pub const empty = Bounds{ .min = std.math.inf(f64), .max = -std.math.inf(f64) };
    pub const universe = Bounds{ .min = -std.math.inf(f64), .max = std.math.inf(f64) };
};

const HitRecord = struct {
    point: Vec3,
    /// always unit
    normal: Vec3,
    t: f64,
    front_face: bool,
};

const Ray = struct {
    orig: Vec3,
    dir: Vec3,

    fn at(self: *const Ray, t: f64) Vec3 {
        return self.orig.add(&self.dir.mul(t));
    }

    fn color(self: *const Ray, max_depth: usize, world: *const Objects) Vec3 {
        if (max_depth <= 0) {
            return vec3(@splat(0));
        }

        const bounds = Bounds{
            .min = 0.001,
            .max = std.math.inf(f64),
        };

        if (world.hit(self, bounds)) |record| {
            const material = record.material;
            const scatter_record = material.scatter(self, &record.hit);
            const scattered = scatter_record.scattered;
            const attenuation = scatter_record.attenuation;
            const col = scattered.color(max_depth - 1, world).inner * attenuation.inner;
            return vec3(col);
        }

        const white = vec3(.{ 1, 1, 1 });
        const blue = vec3(.{ 0.5, 0.7, 1 });
        const t = (self.dir.unit_vector().y() + 1) * 0.5;
        return white.mul(1 - t).add(&blue.mul(t));
    }

    fn hit_sphere(ray: *const Ray, sphere: *const Sphere, bounds: Bounds) ?HitRecord {
        const oc = sphere.center.sub(&ray.orig);
        const a = ray.dir.length_squared();
        const h = ray.dir.dot(&oc);
        const c = oc.length_squared() - (sphere.radius * sphere.radius);

        const discriminant = h * h - a * c;
        if (discriminant < 0) {
            return null;
        }
        const discriminant_sqrt = @sqrt(discriminant);
        var root = (h - discriminant_sqrt) / a;
        if (!bounds.surround(root)) {
            root = (h + discriminant_sqrt) / a;
        }
        if (!bounds.surround(root)) {
            return null;
        }

        const hit_point = ray.at(root);
        var normal = hit_point.sub(&sphere.center).div(sphere.radius);
        const front_face = ray.dir.dot(&normal) < 0;

        if (!front_face) {
            normal.mut_mul(-1);
        }
        return HitRecord{ .t = root, .normal = normal, .point = hit_point, .front_face = front_face };
    }
};

const Sphere = struct {
    center: Vec3,
    radius: f64,

    fn hit(self: *const Sphere, ray: *const Ray, bounds: Bounds) ?HitRecord {
        return ray.hit_sphere(self, bounds);
    }
};

const Geometry = union(enum) {
    sphere: Sphere,

    pub fn hit(self: *const Geometry, ray: *const Ray, bounds: Bounds) ?HitRecord {
        const maybe_record: ?HitRecord = hit: switch (self.*) {
            Geometry.sphere => |obj| {
                break :hit obj.hit(ray, bounds);
            },
        };

        if (maybe_record) |record| {
            std.debug.assert(record.normal.length() <= 1);
            std.debug.assert(ray.dir.dot(&record.normal) < 0);
        }

        return maybe_record;
    }
};

const Lambertian = struct {
    albedo: Vec3,
    pub fn scatter(self: *const Lambertian, _: *const Ray, hit_record: *const HitRecord) Material.ScatterRecord {
        var scatter_direction = hit_record.normal.add(&Vec3.random_unit());
        if (scatter_direction.near_zero()) {
            scatter_direction = hit_record.normal;
        }

        return .{
            .scattered = .{ .orig = hit_record.point, .dir = scatter_direction },
            .attenuation = self.albedo,
        };
    }
};

const Metal = struct {
    albedo: Vec3,
    pub fn scatter(self: *const Metal, ray_in: *const Ray, hit_record: *const HitRecord) Material.ScatterRecord {
        const reflected = ray_in.dir.reflect(&hit_record.normal);
        return .{
            .scattered = Ray{
                .orig = hit_record.point,
                .dir = reflected,
            },
            .attenuation = self.albedo,
        };
    }
};

const Material = union(enum) {
    const ScatterRecord = struct { attenuation: Vec3, scattered: Ray };
    lambertian: Lambertian,
    metal: Metal,
    pub fn scatter(self: *const Material, ray_in: *const Ray, hit_record: *const HitRecord) ScatterRecord {
        switch (self.*) {
            .lambertian => |l| return l.scatter(ray_in, hit_record),
            .metal => |m| return m.scatter(ray_in, hit_record),
        }
    }
};

const Object = struct {
    geometry: Geometry,
    material: Material,
};

const Objects = struct {
    list: std.MultiArrayList(Object),

    pub fn deinit(self: *Objects, gpa: Allocator) void {
        self.list.deinit(gpa);
    }

    pub fn append(self: *Objects, gpa: Allocator, obj: Object) !void {
        try self.list.append(gpa, obj);
    }

    pub fn clear(self: *Objects) void {
        self.list.clearRetainingCapacity();
    }

    fn hit(self: *const Objects, ray: *const Ray, bounds: Bounds) ?struct { hit: HitRecord, material: *Material } {
        const slice = self.list.slice();
        var closest_hit: ?HitRecord = null;
        var closest_index: usize = undefined;

        for (slice.items(.geometry), 0..) |geom, i| {
            const cur_bounds = Bounds{ .min = bounds.min, .max = if (closest_hit) |h| h.t else bounds.max };
            const record = switch (geom) {
                Geometry.sphere => geom.sphere.hit(ray, cur_bounds),
            };

            if (record) |rec| {
                closest_hit = rec;
                closest_index = i;
            }
        }

        if (closest_hit) |rec| {
            const material = &slice.items(.material)[closest_index];
            return .{
                .hit = rec,
                .material = material,
            };
        } else return null;
    }
};

test "basic usage" {
    const ally = std.testing.allocator;

    var objects = Objects{
        .list = .empty,
    };

    defer objects.deinit(ally);

    const ray = Ray{
        .orig = vec3(@splat(0)),
        .dir = vec3(.{ 0, 0, -1 }),
    };
    try objects.append(ally, .{ .sphere = .{ .center = vec3(.{ 0, 0, -1 }), .radius = 0.5 } });
    const rec = objects.hit(&ray, .{ .max = 1000, .min = -1000 });

    std.debug.assert(rec.?.front_face == true);
}

test "call through object" {
    const obj = Geometry{ .sphere = Sphere{
        .center = vec3(.{ 0, 0, -1 }),
        .radius = 0.5,
    } };
    const ray = Ray{
        .orig = vec3(.{ 0, 0, 0 }),
        .dir = vec3(.{ 0, 0, -1 }),
    };

    const rec = obj.hit(&ray, .{ .max = 1000, .min = -1000 });
    _ = rec.?;
}

const Camera = struct {
    const aspect_ratio = 16.0 / 9.0;
    const image_width: usize = 1920;
    const image_width_f: f64 = @floatFromInt(image_width);
    const image_height: usize = @intFromFloat(image_width_f / aspect_ratio);

    const viewport_height = 2.0;
    const viewport_width = viewport_height * (image_width_f / image_height);
    const focal_length = 1.0;

    const cam_center = vec3(.{ 0, 0, 0 });

    const viewport_u = vec3(.{ viewport_width, 0, 0 });

    const viewport_v = vec3(.{ 0, -viewport_height, 0 });
    const pixel_delta_u = viewport_u.div(image_width);

    const pixel_delta_v = viewport_v.div(image_height);

    const viewport_upper_left = cam_center
        .sub(&vec3(.{ 0, 0, focal_length }))
        .sub(&viewport_u.div(2))
        .sub(&viewport_v.div(2));

    const pixel00_loc =
        viewport_upper_left.add(&pixel_delta_u.add(&pixel_delta_v).mul(0.5));

    const samples_per_pixel = 200;
    const max_depth = 50;

    fn render(world: *const Objects, progress_writer: *std.Io.Writer, rng: std.Random, thread_pool: *std.Thread.Pool, image_buf: []Vec3) !void {
        comptime std.debug.assert(image_height > 1);
        if (image_buf.len < image_width * image_height) {
            return error.ImageBufferTooSmall;
        }

        // calculate
        try progress_writer.print("caclulating...\n", .{});
        try progress_writer.flush();

        var wg = std.Thread.WaitGroup{};
        // NOTE: this uses the same seed for every pixel
        var noise: [samples_per_pixel * 2]f64 = undefined; // TODO: vectorize / compute at comptime?
        for (0..noise.len) |i| {
            noise[i] = rng.float(f64);
        }

        for (0..image_height) |y| {
            for (0..image_width) |x| {
                const PoolTask = struct {
                    fn doIt(pixel_x: usize, pixel_y: usize, pixel: *Vec3, task_noise: *[samples_per_pixel * 2]f64, task_world: *const Objects) void {
                        // I guess rng is now raced?
                        const pixel_center = pixel00_loc.add(&pixel_delta_u.mul(@floatFromInt(pixel_x))).add(&pixel_delta_v.mul(@floatFromInt(pixel_y)));
                        const ray_direction = pixel_center.sub(&cam_center);
                        var ray = Ray{
                            .orig = cam_center,
                            .dir = undefined,
                        };

                        var pixel_color = vec3(@splat(0));

                        for (0..samples_per_pixel) |i| {
                            // sample in square distribution
                            const offset = pixel_delta_u.mul(task_noise[i] - 0.5).add(&pixel_delta_v.mul(task_noise[2 * i] - 0.5));
                            ray.dir = ray_direction.add(&offset);
                            pixel_color.mut_add(&ray.color(max_depth, task_world));
                        }
                        pixel_color.mut_div(samples_per_pixel);
                        pixel.* = pixel_color;
                    }
                };
                thread_pool.spawnWg(&wg, PoolTask.doIt, .{ x, y, &image_buf[y * image_width + x], &noise, world });
            }
        }

        try progress_writer.print("threads spawned\n", .{});
        try progress_writer.flush();
        thread_pool.waitAndWork(&wg);

        try progress_writer.print("calculation finished, writing\n", .{});
        try progress_writer.flush();
    }
};
