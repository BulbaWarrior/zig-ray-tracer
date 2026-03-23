const std = @import("std");
const vec3 = @import("../vec3.zig");
const Vec3 = vec3.Vec3;

pub const Texture = union(enum) {
    solid_color: SolidColor,
    checker: Checker,
    gradient: Gradient,
    image: Image,

    pub fn value(self: *const Texture, u: f64, v: f64, point: Vec3(.arb)) Vec3(.color) {
        switch (self.*) {
            // tex is runtime-known variant of texture, tag is comtime-known
            // so this is static dispatch on all Texture variants
            inline else => |*tex, tag| {
                _ = tag;
                return tex.value(u, v, point);
            },
        }
    }
};

pub const SolidColor = struct {
    albedo: Vec3(.color),

    fn value(self: *const SolidColor, u: f64, v: f64, point: Vec3(.arb)) Vec3(.color) {
        _ = .{ u, v, point };
        return self.albedo;
    }
};

pub const Checker = struct {
    scale: f64,
    even: *const Texture,
    odd: *const Texture,

    fn value(self: *const Checker, u: f64, v: f64, point: Vec3(.arb)) Vec3(.color) {
        const scaled = point.mul(1 / self.scale);
        const floor_sum = @reduce(.Add, @floor(scaled.inner));
        const is_even = @rem(floor_sum, 2) == 0;
        return if (is_even)
            self.even.value(u, v, point)
        else
            self.odd.value(u, v, point);
    }
};

pub const Gradient = struct {
    fn value(self: *const Gradient, u: f64, v: f64, point: Vec3(.arb)) Vec3(.color) {
        _ = .{ self, point };
        return vec3.color(.{ u, v, 0.5 });
    }
};

pub const Image = struct {
    const zstbi = @import("zstbi");
    width: usize,
    height: usize,
    data: []f64,

    const num_components = 3;

    fn value(self: *const Image, u: f64, v: f64, point: Vec3(.arb)) Vec3(.color) {
        _ = point;
        const width_f: f64 = @floatFromInt(self.width);
        const height_f: f64 = @floatFromInt(self.height);

        const x: usize = @intFromFloat(u * (width_f - 1));
        // image pixels are stored top-to-bottom,
        // but v grows botom-to-top, so use (1-v)
        const y: usize = @intFromFloat((1 - v) * (height_f - 1));
        const start = num_components * (self.width * y + x);
        var pixel_data: @Vector(3, f64) = undefined;
        inline for (0..3) |i| {
            pixel_data[i] = self.data[start + i];
        }
        return vec3.color(pixel_data);
    }

    pub fn load(gpa: std.mem.Allocator, path: [:0]const u8) !Image {
        const forced_num_components = num_components;
        var zstbi_image = try zstbi.Image.loadFromFile(path, forced_num_components);
        // free zstbi-owned data because it uses global Allocator
        // configured in zstbi.init(), which may be different from
        // current gpa, in which case freeing elsewhere is awkward
        defer zstbi_image.deinit();
        const data = try gpa.alloc(f64, zstbi_image.data.len);

        for (zstbi_image.data, data) |int, *f| {
            f.* = @as(f64, @floatFromInt(int)) / 255;
        }

        return .{
            .data = data,
            .width = zstbi_image.width,
            .height = zstbi_image.height,
        };
    }

    pub fn deinit(self: *Image, gpa: std.mem.Allocator) void {
        gpa.free(self.data);
    }
};
