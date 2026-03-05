const std = @import("std");
pub const Camera = @This();
const vec3 = @import("vec3.zig");
const Vec3 = vec3.Vec3;
const Pixel = Vec3(.color);

const tracing = @import("tracing.zig");
const Objects = tracing.Objects;

const CameraOptions = struct {
    aspect_ratio: f64 = 16.0 / 9.0,
    image_width: usize = 1920,
    cam_center: Vec3(.arb) = vec3.vec3(.{ 0, 0, 0 }),
    samples_per_pixel: usize = 200,
    max_depth: usize = 50,
};

const Ray = tracing.Ray;

const viewport_height = 2;
const focal_length = 1;

aspect_ratio: f64,
image_width: usize,
image_height: usize,
viewport_width: f64,
cam_center: Vec3(.arb),
samples_per_pixel: usize,
max_depth: usize,
viewport_u: Vec3(.arb),
viewport_v: Vec3(.arb),
pixel_delta_u: Vec3(.arb),
pixel_delta_v: Vec3(.arb),
world: *const Objects,

pub fn init(options: CameraOptions, world: *const Objects) Camera {
    const image_width_f: f64 = @floatFromInt(options.image_width);
    const image_height_f: f64 = image_width_f / options.aspect_ratio;
    const image_height: usize = @intFromFloat(image_height_f);
    const viewport_width = viewport_height * (image_width_f / image_height_f);
    const viewport_u = vec3.vec3(.{ viewport_width, 0, 0 });
    const viewport_v = vec3.vec3(.{ 0, -viewport_height, 0 });
    const pixel_delta_u = viewport_u.div(image_width_f);
    const pixel_delta_v = viewport_v.div(@floatFromInt(image_height));
    return .{
        .aspect_ratio = options.aspect_ratio,
        .image_width = options.image_width,
        .image_height = image_height,
        .viewport_width = viewport_width,
        .cam_center = options.cam_center,
        .samples_per_pixel = options.samples_per_pixel,
        .max_depth = options.max_depth,
        .viewport_v = viewport_v,
        .viewport_u = viewport_u,
        .pixel_delta_v = pixel_delta_v,
        .pixel_delta_u = pixel_delta_u,
        .world = world,
    };
}

/// allocates an appropriate buffer for specified resolution,
/// the caller owns the buffer
pub fn alloc_frame(self: *const Camera, gpa: std.mem.Allocator) ![]Pixel {
    return gpa.alloc(Pixel, self.image_width * self.image_height);
}

pub fn render(
    self: *const Camera,
    progress: *std.Progress.Node,
    thread_pool: *std.Thread.Pool,
    image_buf: []Pixel,
    gpa: std.mem.Allocator,
) !void {
    std.debug.assert(self.image_height > 1);
    if (image_buf.len < self.image_width * self.image_height) {
        return error.ImageBufferTooSmall;
    }

    const gen_noise = progress.start("generate_noise", 0);

    var noise = try gpa.alloc(f64, self.samples_per_pixel * 2);
    for (0..noise.len) |i| {
        noise[i] = std.crypto.random.float(f64);
    }
    gen_noise.end();

    const calculate = progress.start("calculate", 0);

    var wg = std.Thread.WaitGroup{};

    for (0..self.image_height) |y| {
        for (0..self.image_width) |x| {
            const task = PoolTask{
                .x = x,
                .y = y,
                .pixel = &image_buf[y * self.image_width + x],
                .noise = noise,
                .cam = self,
            };
            thread_pool.spawnWg(&wg, PoolTask.run, .{task});
        }
    }
    thread_pool.waitAndWork(&wg);
    calculate.end();
}

fn ray_direction_to(self: *const Camera, x: usize, y: usize) Vec3(.arb) {
    const viewport_upper_left = self.cam_center
        .sub(vec3.vec3(.{ 0, 0, focal_length }))
        .sub(self.viewport_u.div(2))
        .sub(self.viewport_v.div(2));

    const pixel00_loc = viewport_upper_left.add(self.pixel_delta_u.add(self.pixel_delta_v).mul(0.5));

    const pixel_center = pixel00_loc
        .add(self.pixel_delta_u.mul(@floatFromInt(x)))
        .add(self.pixel_delta_v.mul(@floatFromInt(y)));
    return pixel_center.sub(self.cam_center);
}

const PoolTask = struct {
    x: usize,
    y: usize,
    pixel: *Pixel,
    noise: []const f64,
    cam: *const Camera,

    fn run(self: PoolTask) void {
        std.debug.assert(self.noise.len == self.cam.samples_per_pixel * 2);

        var pixel = vec3.color(@splat(0));

        const straight_ray_dir = self.cam.ray_direction_to(self.x, self.y);
        var ray = Ray{
            .orig = self.cam.cam_center,
            .dir = undefined,
        };

        for (0..self.cam.samples_per_pixel) |i| {
            // sample in square distribution
            const offset = self.cam.pixel_delta_u.mul(self.noise[i * 2] - 0.5)
                .add(self.cam.pixel_delta_v.mul(self.noise[i * 2 + 1] - 0.5));
            ray.dir = straight_ray_dir
                .add(offset);

            pixel.mut_add(ray.color(self.cam.max_depth, self.cam.world));
        }

        pixel.mut_div(@floatFromInt(self.cam.samples_per_pixel));
        self.pixel.* = pixel;
    }
};

test {
    const ally = std.testing.allocator;
    const world = Objects.empty;
    const cam = Camera.init(.{}, &world);
    const buff = try cam.alloc_frame(ally);
    defer ally.free(buff);
}
