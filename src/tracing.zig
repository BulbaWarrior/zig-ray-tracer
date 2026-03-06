const std = @import("std");

const vec3 = @import("vec3.zig");
const Vec3 = vec3.Vec3;

const mats = @import("mats.zig");

const Material = mats.Material;
const Allocator = std.mem.Allocator;

pub const Model = @import("tracing/Model.zig");

pub const Bounds = struct {
    min: f64,
    max: f64,

    pub fn contain(bounds: *const Bounds, t: f64) bool {
        return bounds.min <= t and t <= bounds.max;
    }

    pub fn surround(bounds: *const Bounds, t: f64) bool {
        return bounds.min < t and t < bounds.max;
    }

    pub fn size(self: *const Bounds) f64 {
        return self.max - self.min;
    }

    pub fn clamp(self: *const Bounds, x: f64) f64 {
        if (x < self.min) return self.min;
        if (x > self.max) return self.max;
        return x;
    }

    pub const empty = Bounds{ .min = std.math.inf(f64), .max = -std.math.inf(f64) };
    pub const universe = Bounds{ .min = -std.math.inf(f64), .max = std.math.inf(f64) };
};

pub const HitRecord = struct {
    point: Vec3(.arb),
    normal: Vec3(.unit),
    t: f64,
    front_face: bool,
};

// TODO: direction needs to be polymorphic
pub const Ray = struct {
    orig: Vec3(.arb),
    dir: Vec3(.arb),

    pub fn at(self: *const Ray, t: f64) Vec3(.arb) {
        return self.orig.add(self.dir.mul(t));
    }

    pub fn color(self: *const Ray, max_depth: usize, world: *const Objects) Vec3(.color) {
        if (max_depth <= 0) {
            return vec3.color(@splat(0));
        }

        const bounds = Bounds{
            .min = 0.001,
            .max = std.math.inf(f64),
        };

        if (world.hit(self, bounds)) |record| {
            const material = record.material;
            const scatter_record = material.scatter(self, &record.hit) orelse return vec3.color(@splat(0));

            const scattered = scatter_record.scattered;
            const attenuation = scatter_record.attenuation;
            const col = scattered.color(max_depth - 1, world).inner * attenuation.inner;
            return vec3.color(col);
        }

        const white = vec3.color(.{ 1, 1, 1 });
        const blue = vec3.color(.{ 0.5, 0.7, 1 });
        const t = (self.dir.unit_vector().y() + 1) * 0.5;
        return white.mul(1 - t).add(blue.mul(t));
    }

    fn hit_sphere(ray: *const Ray, sphere: *const Sphere, bounds: Bounds) ?HitRecord {
        const oc = sphere.center.sub(ray.orig);
        const a = ray.dir.length_squared();
        const h = ray.dir.dot(oc);
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
        var normal = hit_point.sub(sphere.center).div(sphere.radius).as(.unit);
        const front_face = ray.dir.dot(&normal) < 0;

        if (!front_face) {
            normal.reverse();
        }
        return HitRecord{ .t = root, .normal = normal, .point = hit_point, .front_face = front_face };
    }
};
const Sphere = struct {
    center: Vec3(.arb),
    radius: f64,

    fn hit(self: *const Sphere, ray: *const Ray, bounds: Bounds) ?HitRecord {
        return ray.hit_sphere(self, bounds);
    }
};

pub const Triangle = @import("tracing/Triangle.zig");

pub const Geometry = union(enum) {
    sphere: Sphere,
    triangle: Triangle,

    pub fn hit(self: *const Geometry, ray: *const Ray, bounds: Bounds) ?HitRecord {
        const maybe_record: ?HitRecord = switch (self.*) {
            Geometry.sphere => |sphere| sphere.hit(ray, bounds),
            Geometry.triangle => |tri| tri.hit(ray, bounds),
        };

        if (maybe_record) |record| {
            std.debug.assert(ray.dir.dot(&record.normal) < 0);
        }

        return maybe_record;
    }
};

pub const Object = struct {
    geometry: Geometry,
    material: *const Material,
};

pub const Objects = struct {
    list: std.MultiArrayList(Object),

    pub const empty: Objects = .{ .list = .empty };
    pub fn deinit(self: *Objects, gpa: Allocator) void {
        self.list.deinit(gpa);
    }

    pub fn append(self: *Objects, gpa: Allocator, obj: Object) !void {
        try self.list.append(gpa, obj);
    }

    pub fn clear(self: *Objects) void {
        self.list.clearRetainingCapacity();
    }

    fn hit(self: *const Objects, ray: *const Ray, bounds: Bounds) ?struct { hit: HitRecord, material: *const Material } {
        const slice = self.list.slice();
        var closest_hit: ?HitRecord = null;
        var closest_index: usize = undefined;

        for (slice.items(.geometry), 0..) |geom, i| {
            const cur_bounds = Bounds{ .min = bounds.min, .max = if (closest_hit) |h| h.t else bounds.max };
            const record = geom.hit(ray, cur_bounds);

            if (record) |rec| {
                closest_hit = rec;
                closest_index = i;
            }
        }

        if (closest_hit) |rec| {
            const material = slice.items(.material)[closest_index];
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
        .orig = vec3.vec3(@splat(0)),
        .dir = vec3.vec3(.{ 0, 0, -1 }),
    };
    try objects.append(ally, .{ .geometry = .{ .sphere = .{ .center = vec3.vec3(.{ 0, 0, -1 }), .radius = 0.5 } }, .material = &.{ .lambertian = .{ .albedo = vec3.vec3(@splat(1.0)) } } });
    const rec = objects.hit(&ray, .{ .max = 1000, .min = -1000 });

    std.debug.assert(rec.?.hit.front_face == true);
}

test "call through object" {
    const obj = Geometry{ .sphere = Sphere{
        .center = vec3.vec3(.{ 0, 0, -1 }),
        .radius = 0.5,
    } };
    const ray = Ray{
        .orig = vec3.vec3(.{ 0, 0, 0 }),
        .dir = vec3.vec3(.{ 0, 0, -1 }),
    };

    const rec = obj.hit(&ray, .{ .max = 1000, .min = -1000 });
    _ = rec.?;
}
