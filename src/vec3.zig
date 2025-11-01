const std = @import("std");
const Vec3 = @This();

inner: @Vector(3, f64),

pub fn new(inner: @Vector(3, f64)) Vec3 {
    return Vec3{
        .inner = inner,
    };
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

pub fn write_color(self: *const Vec3, writer: *std.Io.Writer) !void {
    const rbyte: u8 = @intFromFloat(255.999 * self.x());
    const gbyte: u8 = @intFromFloat(255.999 * self.y());
    const bbyte: u8 = @intFromFloat(255.999 * self.z());

    const bytes: [3]u8 = .{ rbyte, gbyte, bbyte };
    _ = try writer.write(&bytes);
    // return writer.print("{b}{b}{b}\n", .{ rbyte, gbyte, bbyte });
}
