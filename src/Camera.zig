const std = @import("std");
pub const Camera = @This();
const vec3 = @import("vec3.zig");
const Vec3 = vec3.Vec3;
const Pixel = Vec3(.color);

const tracing = @import("tracing.zig");
const Objects = tracing.Objects;
const Ray = tracing.Ray;

const CameraOptions = struct {
    aspect_ratio: f64 = 16.0 / 9.0,
    image_width: usize = 1920,
    samples_per_pixel: usize = 200,
    max_depth: usize = 50,
    /// in degrees
    vfov: f64 = 90,
    /// variation angle of rays through each pixel, in degrees
    orientation: OrientationOptions = .{},
    focus: FocusOptions = .{},
};

const FocusOptions = struct {
    /// variation angle of rays through each pixel, in degrees
    defocus_angle: f64 = 0,
    focus_dist: f64 = 10,
};

const OrientationOptions = struct {
    look_from: Vec3(.arb) = vec3.vec3(.{ 0, 0, 0 }),
    look_at: Vec3(.arb) = vec3.vec3(.{ 0, 0, -1 }),
    up: Vec3(.arb) = vec3.vec3(.{ 0, 1, 0 }),
};

aspect_ratio: f64,
image_width: usize,
image_height: usize,

center: Vec3(.arb),
focus_dist: f64,
defocus_angle: f64,

samples_per_pixel: usize,
max_depth: usize,

viewport: Viewport,
pixel: PixelMeta,
frame_basis: FrameBasis,
defocus_disk: DefocusDisk,
world: *const Objects,

const DefocusDisk = struct {
    /// horizontal radius
    u: Vec3(.arb),
    /// vertical radius
    v: Vec3(.arb),
};

const FrameBasis = struct {
    /// camera right
    u: Vec3(.unit),
    /// camera up
    v: Vec3(.unit),
    /// behind camera
    w: Vec3(.unit),
};

const PixelMeta = struct {
    delta_u: Vec3(.arb),
    delta_v: Vec3(.arb),
    loc00: Vec3(.arb),
};

const Viewport = struct {
    width: f64,
    height: f64,
    u: Vec3(.arb),
    v: Vec3(.arb),
    top_left: Vec3(.arb),
};

pub fn init(options: CameraOptions, world: *const Objects) Camera {
    const orientation = options.orientation;

    const image_width_f: f64 = @floatFromInt(options.image_width);
    const image_height_f: f64 = image_width_f / options.aspect_ratio;
    const image_height: usize = @intFromFloat(image_height_f);

    const frame_basis = basis: {
        const w = orientation.look_from.sub(orientation.look_at).unit_vector();
        const u = orientation.up.cross(w).unit_vector();
        const v = w.cross(u).unit_vector();

        break :basis FrameBasis{ .w = w, .u = u, .v = v };
    };

    const focus_dist = options.focus.focus_dist;

    const viewport = blk: {
        const theta = std.math.degreesToRadians(options.vfov);
        const h = std.math.tan(theta / 2);
        const height = 2 * h * focus_dist;
        const width = height * (image_width_f / image_height_f);
        const u = frame_basis.u.mul(width);
        const v = frame_basis.v.mul(-height);
        const top_left = orientation.look_from
            .sub(frame_basis.w.mul(focus_dist))
            .sub(u.div(2))
            .sub(v.div(2));

        break :blk Viewport{
            .width = width,
            .height = height,
            .u = u,
            .v = v,
            .top_left = top_left,
        };
    };

    const defocus_disk = blk: {
        const radius = focus_dist * std.math.tan(std.math.degreesToRadians(options.focus.defocus_angle / 2));
        break :blk DefocusDisk{
            .u = viewport.u.mul(radius),
            .v = viewport.v.mul(radius),
        };
    };

    const pixel_meta = blk: {
        var meta = PixelMeta{
            .delta_u = viewport.u.div(image_width_f),
            .delta_v = viewport.v.div(@floatFromInt(image_height)),
            .loc00 = undefined,
        };
        meta.loc00 = viewport.top_left.add(meta.delta_u.add(meta.delta_v).div(2));
        break :blk meta;
    };

    return .{
        .aspect_ratio = options.aspect_ratio,
        .image_width = options.image_width,
        .image_height = image_height,
        .center = options.orientation.look_from,
        .focus_dist = focus_dist,
        .defocus_angle = options.focus.defocus_angle,
        .defocus_disk = defocus_disk,
        .samples_per_pixel = options.samples_per_pixel,
        .max_depth = options.max_depth,
        .pixel = pixel_meta,
        .viewport = viewport,
        .frame_basis = frame_basis,
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

    const calculate = progress.start("calculate", self.image_height);

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
        thread_pool.waitAndWork(&wg);
        wg.reset();
        calculate.completeOne();
    }
    calculate.end();
}

fn pixel_at(self: *const Camera, x: usize, y: usize) Vec3(.arb) {
    return self.pixel.loc00
        .add(self.pixel.delta_u.mul(@floatFromInt(x)))
        .add(self.pixel.delta_v.mul(@floatFromInt(y)));
}

fn defocus_disk_sample(self: *const Camera) Vec3(.arb) {
    const rand = vec3.random_in_unit_disk();
    const disk_point = self.defocus_disk.u.mul(rand.inner[0])
        .add(self.defocus_disk.v.mul(rand.inner[1]));
    return self.center.add(disk_point);
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

        const pixel_center = self.cam.pixel_at(self.x, self.y);
        for (0..self.cam.samples_per_pixel) |i| {
            // sample in square distribution
            const offset = self.cam.pixel.delta_u.mul(self.noise[i * 2] - 0.5)
                .add(self.cam.pixel.delta_v.mul(self.noise[i * 2 + 1] - 0.5));

            const origin = switch (self.cam.defocus_angle == 0) {
                true => self.cam.center,
                false => self.cam.defocus_disk_sample(),
            };

            const ray = Ray{
                .dir = pixel_center.add(offset).sub(origin),
                .orig = origin,
            };

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
