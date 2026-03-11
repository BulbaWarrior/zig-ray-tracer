const std = @import("std");
// const Vec3 = @This();

pub const VecType = enum {
    arb,
    unit,
    color,
};

pub const Axis = enum {
    x,
    y,
    z,
};

pub fn Vec3(vec_type: VecType) type {
    return struct {
        inner: @Vector(3, f64),

        const Self = @This();

        /// for conversions between vec types, caller must validate the invariants hold
        pub fn as(self: *const Self, comptime v_type: VecType) Vec3(v_type) {
            return .{ .inner = self.inner };
        }

        pub fn linear_to_gamma(self: *Self) void {
            if (vec_type != .color) @compileError("color function");
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

        pub fn reflect(self: *const Self, normal: Vec3(.unit)) Self {
            switch (vec_type) {
                .color => @compileError("why the fuck are you reflecting color?"),
                .arb, .unit => {},
            }
            const norm = normal.as(vec_type);
            const proj = norm.mul(2 * self.dot(norm)).as(.arb);
            // final cast should be fine, as reflecting a unit vec gives a unit vec
            return self.as(.arb).sub(proj).as(vec_type);
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
            const norm = normal.as(.arb);
            const cos_theta: f64 = @min(self.mul(-1).dot(norm), 1.0);
            const sin_theta: f64 = @sqrt(1 - cos_theta * cos_theta);

            if (refraction_coeff * sin_theta > 1 or reflectance(cos_theta, refraction_coeff) > std.crypto.random.float(f64)) {
                return null;
            }

            const out_perp = self.as(.arb).add(norm.mul(cos_theta)).mul(refraction_coeff);
            const out_parallel = norm.mul(-@sqrt(@abs(1 - out_perp.length_squared())));
            return out_perp.add(out_parallel);
        }

        pub fn eq(self: *const Self, other: anytype) bool {
            return @reduce(.And, self.inner == other.inner);
        }

        const bin_result: VecType = switch (vec_type) {
            .unit => .arb,
            // stays same
            else => vec_type,
        };

        pub fn add(self: *const Self, other: Self) Vec3(bin_result) {
            return .{
                .inner = self.inner + other.inner,
            };
        }

        pub fn sub(self: *const Self, other: Self) Vec3(bin_result) {
            return .{
                .inner = self.inner - other.inner,
            };
        }

        pub fn mul(self: *const Self, scalar: f64) Vec3(bin_result) {
            const splatted: @TypeOf(self.inner) = @splat(scalar);
            return .{
                .inner = self.inner * splatted,
            };
        }

        pub fn div(self: *const Self, scalar: f64) Vec3(bin_result) {
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

        pub fn coord(self: *const Self, comptime axis: Axis) f64 {
            switch (axis) {
                .x => return self.inner[0],
                .y => return self.inner[1],
                .z => return self.inner[2],
            }
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

        pub fn cross(self: *const Self, other: anytype) Vec3(.arb) {
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
        var out: Vec3(.arb) = random().sub(vec3(@splat(0.5))).mul(2);
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

pub fn random_in_unit_disk() Vec3(.arb) {
    var out: Vec3(.arb) = undefined;
    while (true) {
        out.inner = .{ std.crypto.random.float(f64), std.crypto.random.float(f64), 0 };
        if (out.length_squared() < 1) {
            return out;
        }
    }
}

pub fn vec3(inner: @Vector(3, f64)) Vec3(.arb) {
    return .{
        .inner = inner,
    };
}

pub fn color(inner: @Vector(3, f64)) Vec3(.color) {
    return .{
        .inner = inner,
    };
}

test "alias" {
    const u: Vec3(.unit) = vec3(@splat(0)).as(.unit);
    std.debug.print("{}", u);
}

test {
    const subtypes = [_]VecType{ .unit, .color, .arb };
    inline for (subtypes) |subtype| {
        _ = Vec3(subtype);
    }
}
