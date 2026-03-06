const std = @import("std");
const vec3 = @import("../vec3.zig");
const Vec3 = vec3.Vec3;

const tracing = @import("../tracing.zig");
const HitRecord = tracing.HitRecord;
const Ray = tracing.Ray;
const Bounds = tracing.Bounds;

const Triangle = @This();

/// front face is counter-clockwise, I think
points: @Vector(3, *const Vec3(.arb)),

pub fn hit(self: *const Triangle, ray: *const Ray, bounds: Bounds) ?HitRecord {
    const e1: Vec3(.arb) = self.points[1].sub(self.points[0].*);
    const e2: Vec3(.arb) = self.points[2].sub(self.points[0].*);

    var norm = e1.cross(e2);

    // back face culling
    // if (norm.dot(ray.dir) > 0) return null;

    const ray_cross_e2 = ray.dir.cross(e2);
    const det = e1.dot(ray_cross_e2);

    // parallel case
    const epsilon = std.math.floatEps(f64);
    if (@abs(det) < epsilon) return null;

    const inv_det = 1 / det;
    const s = ray.orig.sub(self.points[0].*);

    // j and k are free parameters of the plane, defined by self.points[0] and vectors u and v
    const u = inv_det * s.dot(ray_cross_e2);

    // ray passes outside e1's bounds
    if (u < 0 or u > 1) return null;

    const s_cross_e1 = s.cross(e1);
    const v = inv_det * ray.dir.dot(s_cross_e1);

    // ray passes outside e2's bounds
    if (v < 0 or u + v > 1) return null;

    // ray intersects the triangle
    const t = inv_det * e2.dot(s_cross_e1);

    if (!bounds.surround(t)) return null;

    const front_face = norm.dot(ray.dir) < 0;
    if (!front_face) norm.reverse();
    return HitRecord{
        .t = t,
        .front_face = front_face,
        .normal = norm.unit_vector(),
        .point = ray.at(t),
    };
}
