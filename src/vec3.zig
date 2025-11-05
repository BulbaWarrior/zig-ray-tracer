const std = @import("std");
const Vec3 = @This();

inner: @Vector(3, f64),

pub fn new(inner: @Vector(3, f64)) Vec3 {
    return Vec3{
        .inner = inner,
    };
}

pub fn linear_to_gamma(self: *Vec3) void {
    self.inner = @sqrt(self.inner);
}

/// all values are in [0, 1)
pub fn random() Vec3 {
    // TODO: ask for noise?
    return .{ .inner = .{
        std.crypto.random.float(f64),
        std.crypto.random.float(f64),
        std.crypto.random.float(f64),
    } };
}

pub fn random_unit() Vec3 {
    while (true) {
        var out = random().sub(&new(@splat(0.5))).mul(2);
        const len_squared = out.length_squared();
        if (1e-160 < len_squared and len_squared <= 1) {
            out.mut_div(@sqrt(len_squared));
            return out;
        }
    }
}

pub fn near_zero(self: *Vec3) bool {
    const s: @TypeOf(self.inner) = @splat(1e-8);
    return @reduce(.And, self.inner < s);
}

pub fn clamp(self: *const Vec3, min: f64, max: f64) Vec3 {
    const max_v: @TypeOf(self.inner) = @splat(max);
    const min_v: @TypeOf(self.inner) = @splat(min);

    const clamped_above = @min(self.inner, max_v);
    const clamped = @max(clamped_above, min_v);
    return .{
        .inner = clamped,
    };
}

pub fn unit_on_hemisphere(normal: *const Vec3) Vec3 {
    var out = random_unit();
    if (out.dot(normal) < 0) {
        out.mut_mul(-1);
    }
    return out;
}

pub fn reflect(self: *const Vec3, normal: *const Vec3) Vec3 {
    return self.sub(&normal.mul(2 * self.dot(normal)));
}

pub fn eq(self: *const Vec3, other: *const Vec3) bool {
    return @reduce(.And, self.inner == other.inner);
}

pub fn add(self: *const Vec3, other: *const Vec3) Vec3 {
    return Vec3{
        .inner = self.inner + other.inner,
    };
}

pub fn sub(self: *const Vec3, other: *const Vec3) Vec3 {
    return Vec3{
        .inner = self.inner - other.inner,
    };
}

pub fn mul(self: *const Vec3, scalar: f64) Vec3 {
    const splatted: @TypeOf(self.inner) = @splat(scalar);
    return Vec3{
        .inner = self.inner * splatted,
    };
}

pub fn div(self: *const Vec3, scalar: f64) Vec3 {
    const splatted: @TypeOf(self.inner) = @splat(scalar);
    return Vec3{
        .inner = self.inner / splatted,
    };
}

pub fn mut_add(self: *Vec3, other: *const Vec3) void {
    self.inner += other.inner;
}

pub fn mut_sub(self: *Vec3, other: *const Vec3) void {
    self.inner -= other.inner;
}

pub fn mut_mul(self: *Vec3, scalar: f64) void {
    self.inner *= @splat(scalar);
}

pub fn mut_div(self: *Vec3, scalar: f64) void {
    self.inner /= @splat(scalar);
}

pub fn x(self: *const Vec3) f64 {
    return self.inner[0];
}

pub fn y(self: *const Vec3) f64 {
    return self.inner[1];
}

pub fn z(self: *const Vec3) f64 {
    return self.inner[2];
}

pub fn length_squared(self: *const Vec3) f64 {
    return @reduce(.Add, self.inner * self.inner);
}

pub fn length(self: *const Vec3) f64 {
    return @sqrt(self.length_squared());
}

pub fn dot(self: *const Vec3, other: *const Vec3) f64 {
    return @reduce(.Add, self.inner * other.inner);
}

pub fn unit_vector(self: *const Vec3) Vec3 {
    return self.div(self.length());
}

pub fn cross(self: *const Vec3, other: *const Vec3) Vec3 {
    const u = &self.inner;
    const v = &other.inner;
    const res = .{
        u[1] * v[2] - u[2] * v[1],
        u[2] * v[0] - u[0] * v[2],
        u[0] * v[1] - u[1] * v[0],
    };

    return .{
        .inner = res,
    };
}
