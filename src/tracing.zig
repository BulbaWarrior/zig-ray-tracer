const std = @import("std");

const vec3 = @import("vec3.zig");
const Vec3 = vec3.Vec3;
const Axis = vec3.Axis;

const mats = @import("mats.zig");

const Material = mats.Material;
const Allocator = std.mem.Allocator;

pub const Model = @import("tracing/Model.zig");

pub const texture = @import("tracing/texture.zig");

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

    // TODO: the book says we might need padding
    pub fn overlap(self: *const Bounds, other: Bounds) ?Bounds {
        const min = @max(self.min, other.min);
        const max = @min(self.max, other.max);
        if (min <= max) return .{
            .min = min,
            .max = max,
        } else return null;
    }

    pub const empty = Bounds{ .min = std.math.inf(f64), .max = -std.math.inf(f64) };
    pub const universe = Bounds{ .min = -std.math.inf(f64), .max = std.math.inf(f64) };
};

pub const Bbox3D = struct {
    min: @Vector(3, f64),
    max: @Vector(3, f64),

    pub const empty = Bbox3D{
        .min = @splat(std.math.inf(f64)),
        .max = @splat(-std.math.inf(f64)),
    };

    // pub fn from_extrema(min: Vec3(.arb), max: Vec3(.arb)) Bbox3D {}
    pub fn axis_bounds(self: *const Bbox3D, axis: Axis) Bounds {
        const axis_index: usize = @intFromEnum(axis);
        return .{ .min = self.min[axis_index], .max = self.max[axis_index] };
    }

    pub fn merged(left: *const Bbox3D, right: *const Bbox3D) Bbox3D {
        return .{
            .min = @min(left.min, right.min),
            .max = @max(left.max, right.max),
        };
    }

    // TODO: test
    pub fn hit(self: *const Bbox3D, ray: *const Ray, bounds: Bounds) bool {
        const one: @TypeOf(ray.dir.inner) = @splat(1);
        const dir_inv = one / ray.dir.inner;
        const t0 = (self.min - ray.orig.inner) * dir_inv;
        const t1 = (self.max - ray.orig.inner) * dir_inv;
        const t_min = @min(t0, t1);
        const t_max = @max(t0, t1);
        const bounds_min = @reduce(.Max, t_min);
        const bounds_max = @reduce(.Min, t_max);
        const box_bounds = Bounds{ .min = bounds_min, .max = bounds_max };

        if (box_bounds.overlap(bounds)) |_| return true;
        return false;
    }

    pub fn less_then(axis: Axis, left: *const Bbox3D, right: *const Bbox3D) bool {
        return left.axis_bounds(axis).min < right.axis_bounds(axis).min;
    }

    pub fn longest_axis(self: *const Bbox3D) Axis {
        const lengths = self.max - self.min;
        // TODO: is this faster then looping over lenghts?
        const max: @TypeOf(lengths) = @splat(@reduce(.Max, lengths));
        const is_max = lengths == max;

        inline for (0..3) |i| {
            if (is_max[i]) return @enumFromInt(i);
        }
        // non of the values is maximal
        unreachable;
    }
};

pub const HitRecord = struct {
    point: Vec3(.arb),
    normal: Vec3(.unit),
    t: f64,
    // TODO: actually compute
    u: f64 = undefined,
    v: f64 = undefined,
    front_face: bool,
};

// TODO: direction needs to be polymorphic
pub const Ray = struct {
    orig: Vec3(.arb),
    dir: Vec3(.arb),

    pub fn at(self: *const Ray, t: f64) Vec3(.arb) {
        return self.orig.add(self.dir.mul(t));
    }

    pub fn color(self: *const Ray, max_depth: usize, world: *const BvhNode) Vec3(.color) {
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
        const t = (self.dir.unit_vector().coord(.y) + 1) * 0.5;
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

        // spherical coordinates,
        // fun fact: did you notice that phi (ϕ) and theta (θ) depict
        // longitude and latitude on a small globe?
        const phi = std.math.atan2(normal.coord(.z), -normal.coord(.x)) + std.math.pi;
        const theta = std.math.acos(-normal.coord(.y));
        const u = phi / (2 * std.math.pi);
        const v = theta / std.math.pi;
        std.debug.assert(0 <= u and u <= 1);
        std.debug.assert(0 <= v and v <= 1);
        return HitRecord{
            .t = root,
            .normal = normal,
            .point = hit_point,
            .front_face = front_face,
            .u = u,
            .v = v,
        };
    }
};
const Sphere = struct {
    center: Vec3(.arb),
    radius: f64,

    fn hit(self: *const Sphere, ray: *const Ray, bounds: Bounds) ?HitRecord {
        return ray.hit_sphere(self, bounds);
    }

    fn bounding_box(self: *const Sphere) Bbox3D {
        std.debug.assert(self.radius >= 0);
        const center = self.center.inner;
        const radius: @Vector(3, f64) = @splat(self.radius);
        return .{ .min = center - radius, .max = center + radius };
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

    pub fn bounding_box(self: *const Geometry) Bbox3D {
        return switch (self.*) {
            .sphere => |sphere| sphere.bounding_box(),
            .triangle => |tri| tri.bounding_box(),
        };
    }
};

pub const Object = struct {
    geometry: Geometry,
    material: *const Material,
};

pub const Objects = struct {
    list: std.MultiArrayList(Object),
    bbox: Bbox3D,

    pub const empty: Objects = .{
        .list = .empty,
        .bbox = .empty,
    };

    pub fn deinit(self: *Objects, gpa: Allocator) void {
        self.list.deinit(gpa);
    }

    pub fn append(self: *Objects, gpa: Allocator, obj: Object) !void {
        self.bbox = .merged(&self.bbox, &obj.geometry.bounding_box());

        try self.list.append(gpa, obj);
    }

    pub fn clear(self: *Objects) void {
        self.list.clearRetainingCapacity();
    }

    fn hit(self: *const Objects, ray: *const Ray, bounds: Bounds) ?struct { hit: HitRecord, material: *const Material } {
        // TODO: simple hitting test for now
        if (!self.bbox.hit(ray, bounds)) return null;
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

pub const BvhNode = union(enum) {
    leaf: *const Object,
    branch: struct {
        left: *const BvhNode,
        right: *const BvhNode,
        bbox: Bbox3D,
    },

    const Hit = struct {
        hit: HitRecord,
        material: *const Material,
    };

    pub fn hit(self: BvhNode, ray: *const Ray, bounds: Bounds) ?Hit {
        var res: ?Hit = null;
        switch (self) {
            .leaf => |object| {
                if (object.geometry.hit(ray, bounds)) |rec| return .{
                    .hit = rec,
                    .material = object.material,
                };
            },
            .branch => |branch| {
                if (!branch.bbox.hit(ray, bounds)) return null;
                var ray_bounds = bounds;
                if (branch.left.hit(ray, bounds)) |left_hit| {
                    res = left_hit;
                    ray_bounds.max = left_hit.hit.t;
                }
                if (branch.right.hit(ray, ray_bounds)) |right_hit| return right_hit;
            },
        }
        return res;
    }

    pub fn init(bounded_objects: []Object, arena: Allocator) !BvhNode {
        switch (bounded_objects.len) {
            0 => unreachable,
            1 => {
                return .{ .leaf = &bounded_objects[0] };
            },
            2 => {
                const leaves = try arena.alloc(BvhNode, 2);
                const left = &leaves[0];
                const right = &leaves[1];
                left.* = .{ .leaf = &bounded_objects[0] };
                right.* = .{ .leaf = &bounded_objects[1] };

                const bbox = left.leaf.geometry.bounding_box().merged(&right.leaf.geometry.bounding_box());
                return .{
                    .branch = .{
                        .left = left,
                        .right = right,
                        .bbox = bbox,
                    },
                };
            },
            else => {},
        }

        var bbox = Bbox3D.empty;
        for (bounded_objects) |obj| {
            bbox = bbox.merged(&obj.geometry.bounding_box());
        }

        const axis = bbox.longest_axis();

        const cmp = struct {
            fn less_then(ctx: Axis, left: Object, right: Object) bool {
                return Bbox3D.less_then(ctx, &left.geometry.bounding_box(), &right.geometry.bounding_box());
            }
        }.less_then;

        std.mem.sort(Object, bounded_objects, axis, cmp);
        const pivot = bounded_objects.len / 2;
        var nodes = try arena.alloc(BvhNode, 2);
        const left = &nodes[0];
        const right = &nodes[1];
        left.* = try BvhNode.init(bounded_objects[0..pivot], arena);
        right.* = try BvhNode.init(bounded_objects[pivot..], arena);
        return BvhNode{
            .branch = .{
                .left = left,
                .right = right,
                .bbox = bbox,
            },
        };
    }
};

// pub const Bvh = struct {
//     nodes: std.MultiArrayList(BvhNode),
//     root_id: usize,
//     objects: *Objects,
//
//     /// takes ownership of objects. Also shuffles them around, so all references are
//     /// invalidated
//     pub fn init(gpa: Allocator, objects: *Objects) !Bvh {
//         var nodes = std.MultiArrayList(BvhNode).empty;
//     }
//
//     pub fn deinit(self: *Bvh, gpa: Allocator) void {
//         self.nodes.deinit(gpa);
//         self.objects.deinit(gpa);
//     }
// };

test "basic usage" {
    const ally = std.testing.allocator;

    var objects = Objects.empty;

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
