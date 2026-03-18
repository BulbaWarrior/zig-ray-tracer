const std = @import("std");
const vec3 = @import("../vec3.zig");
const Vec3 = vec3.Vec3;

pub const Texture = union(enum) {
    solid_color: SolidColor,
    checker: Checker,

    pub fn value(self: Texture, u: f64, v: f64, point: Vec3(.arb)) Vec3(.color) {
        switch (self) {
            // tex is runtime-known variant of texture, tag is comtime-known
            // so this is static dispatch on all Texture variants
            inline else => |tex, tag| {
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
