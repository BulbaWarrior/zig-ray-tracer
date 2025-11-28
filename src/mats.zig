const vector = @import("vec3.zig");
const vec3 = vector.new;
const Color = vector.Vec3(.arb);

const main = @import("main.zig");
const Ray = main.Ray;
const HitRecord = main.HitRecord;

const Lambertian = struct {
    albedo: Color,
    pub fn scatter(self: *const Lambertian, _: *const Ray, hit_record: *const HitRecord) ?Material.ScatterRecord {
        var scatter_direction = hit_record.normal.add(&vector.random_unit());
        if (scatter_direction.near_zero()) {
            scatter_direction = hit_record.normal.as(.arb);
        }

        return .{
            .scattered = .{ .orig = hit_record.point, .dir = scatter_direction },
            .attenuation = self.albedo,
        };
    }
};

const Metal = struct {
    albedo: Color,
    fuzziness: f64,
    pub fn scatter(self: *const Metal, ray_in: *const Ray, hit_record: *const HitRecord) ?Material.ScatterRecord {
        const fuzz = vector.random_unit().mul(self.fuzziness);
        const reflected = ray_in.dir.reflect(&hit_record.normal).unit_vector().add(&fuzz);

        if (reflected.dot(&hit_record.normal) < 0) {
            return null;
        }

        return .{
            .scattered = Ray{
                .orig = hit_record.point,
                .dir = reflected,
            },
            .attenuation = self.albedo,
        };
    }
};

const Dielectric = struct {
    refraction_index: f64,

    pub fn scatter(self: *const Dielectric, ray_in: *const Ray, hit_record: *const HitRecord) ?Material.ScatterRecord {
        var ri: f64 = undefined;
        if (hit_record.front_face) {
            ri = 1 / self.refraction_index;
        } else {
            ri = self.refraction_index;
        }

        const unit_dir = ray_in.dir.unit_vector();
        const refracted_dir = unit_dir.refract(&hit_record.normal, ri);
        if (refracted_dir) |rd| {
            const refracted = Ray{ .orig = hit_record.point, .dir = rd.as(.arb) };

            return .{
                .scattered = refracted,
                .attenuation = vec3(@splat(1)),
            };
        } else {
            const reflected = Ray{
                .orig = hit_record.point,
                .dir = unit_dir.reflect(&hit_record.normal).as(.arb),
            };
            return .{
                .scattered = reflected,
                .attenuation = vec3(@splat(1)),
            };
        }
    }
};

pub const Material = union(enum) {
    const ScatterRecord = struct { attenuation: Color, scattered: Ray };
    lambertian: Lambertian,
    metal: Metal,
    dielectric: Dielectric,
    pub fn scatter(self: *const Material, ray_in: *const Ray, hit_record: *const HitRecord) ?ScatterRecord {
        switch (self.*) {
            .lambertian => |l| return l.scatter(ray_in, hit_record),
            .metal => |m| return m.scatter(ray_in, hit_record),
            .dielectric => |d| return d.scatter(ray_in, hit_record),
        }
    }
};
