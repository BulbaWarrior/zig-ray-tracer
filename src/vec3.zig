const std = @import("std");
// const Vec3 = @This();

const VecType = enum {
    arb,
    unit,
};

pub fn Vec3(vec_type: VecType) type {
    return struct {
        inner: @Vector(3, f64),

        const Self = @This();

        // for conversions between vec types, caller must validate the invariants hold
        pub fn as(self: *const Self, comptime v_type: VecType) Vec3(v_type) {
            return .{ .inner = self.inner };
        }

        pub fn linear_to_gamma(self: *Self) void {
            self.inner = @sqrt(self.inner);
        }

        pub fn near_zero(self: *Self) bool {
            if (vec_type == .unit) {
                return false;
            }
            const s: @TypeOf(self.inner) = @splat(1e-8);
            return @reduce(.And, self.inner < s);
        }

        pub fn clamp(self: *const Self, min: f64, max: f64) Vec3(.arb) {
            const max_v: @TypeOf(self.inner) = @splat(max);
            const min_v: @TypeOf(self.inner) = @splat(min);

            const clamped_above = @min(self.inner, max_v);
            const clamped = @max(clamped_above, min_v);
            return .{
                .inner = clamped,
            };
        }

        pub fn reflect(self: *const Self, normal: *const Vec3(.unit)) Vec3(.arb) {
            return self.sub(&normal.mul(2 * self.dot(normal)));
        }

        fn reflectance(cosine: f64, refraction_coeff: f64) f64 {
            // Shlick's approximation for reflectance
            var r0 = (1 - refraction_coeff) / (1 + refraction_coeff);
            r0 *= r0;
            const b = 1 - cosine;
            const b_5 = b * b * b * b * b;
            return r0 + (1 - r0) * b_5;
        }

        pub fn refract(self: *const Self, normal: *const Vec3(.unit), refraction_coeff: f64) ?Vec3(.arb) {
            const cos_theta = @min(self.mul(-1).dot(normal), 1.0);
            const sin_theta = @sqrt(1 - cos_theta * cos_theta);

            if (refraction_coeff * sin_theta > 1 or reflectance(cos_theta, refraction_coeff) > std.crypto.random.float(f64)) {
                return null;
            }

            const out_perp = self.add(&normal.mul(cos_theta)).mul(refraction_coeff);
            const out_parallel = normal.mul(-@sqrt(@abs(1 - out_perp.length_squared())));
            return out_perp.add(&out_parallel);
        }

        pub fn eq(self: *const Self, other: anytype) bool {
            return @reduce(.And, self.inner == other.inner);
        }

        pub fn add(self: *const Self, other: anytype) Vec3(.arb) {
            return .{
                .inner = self.inner + other.inner,
            };
        }

        pub fn sub(self: *const Self, other: anytype) Vec3(.arb) {
            return .{
                .inner = self.inner - other.inner,
            };
        }

        pub fn mul(self: *const Self, scalar: f64) Vec3(.arb) {
            const splatted: @TypeOf(self.inner) = @splat(scalar);
            return .{
                .inner = self.inner * splatted,
            };
        }

        pub fn div(self: *const Self, scalar: f64) Vec3(.arb) {
            const splatted: @TypeOf(self.inner) = @splat(scalar);
            return .{
                .inner = self.inner / splatted,
            };
        }

        pub fn mut_add(self: *Self, other: anytype) void {
            if (vec_type == .unit) {
                @compileError("this will (likely) no longer be unit vector, cast to arb");
            }
            self.inner += other.inner;
        }

        pub fn mut_sub(self: *Self, other: anytype) void {
            if (vec_type == .unit) {
                @compileError("this will (likely) no longer be unit vector, cast to arb");
            }
            self.inner -= other.inner;
        }

        pub fn mut_mul(self: *Self, scalar: f64) void {
            if (vec_type == .unit) {
                @compileError("this will (likely) no longer be unit vector, cast to arb");
            }
            self.inner *= @splat(scalar);
        }

        pub fn mut_div(self: *Self, scalar: f64) void {
            if (vec_type == .unit) {
                @compileError("this will (likely) no longer be unit vector, cast to arb");
            }
            self.inner /= @splat(scalar);
        }

        pub fn reverse(self: *Self) void {
            self.inner *= @splat(-1);
        }

        pub fn x(self: *const Self) f64 {
            return self.inner[0];
        }

        pub fn y(self: *const Self) f64 {
            return self.inner[1];
        }

        pub fn z(self: *const Self) f64 {
            return self.inner[2];
        }

        pub fn length_squared(self: *const Self) f64 {
            if (vec_type == .unit) return 1;
            return @reduce(.Add, self.inner * self.inner);
        }

        pub fn length(self: *const Self) f64 {
            if (vec_type == .unit) return 1;
            return @sqrt(self.length_squared());
        }

        pub fn dot(self: *const Self, other: anytype) f64 {
            return @reduce(.Add, self.inner * other.inner);
        }

        pub fn unit_vector(self: *const Self) Vec3(.unit) {
            return self.div(self.length()).as(.unit);
        }

        pub fn cross(self: *const Self, other: *const type) Vec3(.arb) {
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
    };
}

pub fn random() Vec3(.arb) {
    // TODO: ask for noise?
    return .{ .inner = .{
        std.crypto.random.float(f64),
        std.crypto.random.float(f64),
        std.crypto.random.float(f64),
    } };
}

/// all values are in [0, 1)
pub fn random_unit() Vec3(.unit) {
    while (true) {
        var out: Vec3(.arb) = random().sub(&new(@splat(0.5))).mul(2);
        const len_squared = out.length_squared();
        if (1e-160 < len_squared and len_squared <= 1) {
            out.mut_div(@sqrt(len_squared));
            return out.as(.unit);
        }
    }
}

pub fn unit_on_hemisphere(normal: *const Vec3(.unit)) Vec3(.unit) {
    var out = random_unit();
    if (out.dot(normal) < 0) {
        out.mut_mul(-1);
    }
    return out;
}

pub fn new(inner: @Vector(3, f64)) Vec3(.arb) {
    return .{
        .inner = inner,
    };
}

test "alias" {
    const u: Vec3(.unit) = new(@splat(0)).as(.unit);
    std.debug.print("{}", u);
}
