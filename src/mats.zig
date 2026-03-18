const vec3 = @import("vec3.zig");
const Color = vec3.Vec3(.color);
const color = vec3.color;

const main = @import("main.zig");
const tracing = @import("tracing.zig");
const Ray = tracing.Ray;
const HitRecord = tracing.HitRecord;

const Lambertian = struct {
    texture: *const tracing.texture.Texture,
    pub fn scatter(self: *const Lambertian, _: *const Ray, hit_record: *const HitRecord) ?Material.ScatterRecord {
        var scatter_direction = hit_record.normal.add(vec3.random_unit());
        if (scatter_direction.near_zero()) {
            scatter_direction = hit_record.normal.as(.arb);
        }

        return .{
            .scattered = .{ .orig = hit_record.point, .dir = scatter_direction },
            .attenuation = self.texture.value(hit_record.u, hit_record.v, hit_record.point),
        };
    }
};

const Metal = struct {
    albedo: Color,
    fuzziness: f64,
    pub fn scatter(self: *const Metal, ray_in: *const Ray, hit_record: *const HitRecord) ?Material.ScatterRecord {
        const fuzz = vec3.random_unit().mul(self.fuzziness);
        const reflected = ray_in.dir.reflect(hit_record.normal).unit_vector().as(.arb).add(fuzz);

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
        const ri: f64 = if (hit_record.front_face)
            1 / self.refraction_index
        else
            self.refraction_index;

        const unit_dir = ray_in.dir.unit_vector();
        const refracted_dir = unit_dir.refract(&hit_record.normal, ri);
        if (refracted_dir) |rd| {
            const refracted = Ray{ .orig = hit_record.point, .dir = rd.as(.arb) };

            return .{
                .scattered = refracted,
                .attenuation = color(@splat(1)),
            };
        } else {
            const reflected = Ray{
                .orig = hit_record.point,
                .dir = unit_dir.reflect(hit_record.normal).as(.arb),
            };
            return .{
                .scattered = reflected,
                .attenuation = color(@splat(1)),
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
