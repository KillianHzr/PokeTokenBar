import Foundation

/// The Fossil Egg's design (`FossilDig`): an egg of amber, an Omanyte's fossil shell caught inside. The amber is seen
/// through: each pixel follows the eye's ray into the egg, which darkens with the depth of resin it crosses, catches
/// the gold flakes and bubbles it passes, and stops on the shell, modeled in 3D as a coiled spiral whose whorls
/// grow outward, ribbed, so it turns with the egg.
enum FossilEggArt {
    typealias C = EggColor

    private static func rgb(_ hex: Int) -> C {
        C(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    private static let honey = rgb(0xFFC93E), resin = rgb(0xE97A00), deep = rgb(0x8E2A00), glow = rgb(0xFFE88E)
    private static let shell = rgb(0x3E1C06), ridge = rgb(0xE2A45C)

    // MARK: The shell

    /// Center of the coil, in the egg's frame (x right, y up, z toward the eye at rest), slightly below the middle.
    private static let center: EggVector = (0, -0.05, 0.16)
    /// The coil's centerline: r = a·e^(bθ), three whorls, each 1.9 times the one inside it.
    private static let growth = log(1.9) / (2 * .pi)
    private static let innermost = 0.06
    /// A whorl's section: round across the coil, thinner front to back, as an ammonite is.
    private static let tube = 0.31, thinness = 0.62

    /// Distance from a point to the shell (negative inside), and the whorl angle there (its ribs).
    private static func shellDistance(_ p: EggVector) -> (distance: Double, theta: Double) {
        let x = p.x - center.x, y = p.y - center.y, z = p.z - center.z
        let rho = (x * x + y * y).squareRoot()
        var phi = atan2(y, x)
        if phi < 0 { phi += 2 * .pi }
        var best = (distance: Double.infinity, theta: 0.0)
        for k in 0..<3 {
            let theta = phi + 2 * .pi * Double(k)
            let r = innermost * exp(growth * theta)
            // Ribs across each whorl, a little proud of it.
            let rib = 0.02 * r / 0.3 * max(0, cos(theta * 11))
            let d = ((rho - r) * (rho - r) + (z / thinness) * (z / thinness)).squareRoot() - (tube * r + rib)
            if d < best.distance { best = (d, theta) }
        }
        return best
    }

    private static let bound = innermost * exp(growth * 6 * .pi) * (1 + tube) + 0.02

    // MARK: The amber

    /// Gold flakes ("sun spangles") and bubbles caught in the resin: points in the egg's frame.
    private static let flakes: [EggVector] = (0..<9).map { i in
        let a = EggDesigns.hash(i, 1, 0, seed: 701) * 2 * .pi, h = EggDesigns.hash(i, 2, 0, seed: 701) * 1.5 - 0.75
        let r = 0.2 + EggDesigns.hash(i, 3, 0, seed: 701) * 0.4
        return (r * cos(a), h, r * sin(a))
    }

    private static func inside(_ p: EggVector) -> Bool {
        guard abs(p.y) < 1 else { return false }
        let r = EggProfile.radius(p.y)
        return p.x * p.x + p.z * p.z < r * r
    }

    /// What the eye sees at a point of the surface: the ray goes in, through the resin, to the shell or out the back.
    private static func seen(_ p: EggSurfacePoint) -> C {
        let d: EggVector = (-sin(p.yaw), 0, -cos(p.yaw))
        let step = 0.022
        var travel = 0.0, flake: C? = nil
        // How cloudy the resin is along the ray: flow lines of denser and clearer amber, as it set.
        var cloud = 0.0
        var point: EggVector = (p.x, p.y, p.z)
        // The shell's bounding sphere: only march where the ray can meet it, then on to the back.
        while travel < 2.2 {
            point = (p.x + d.x * travel, p.y + d.y * travel, p.z + d.z * travel)
            guard travel == 0 || inside(point) else { break }
            let dc = ((point.x - center.x) * (point.x - center.x) + (point.y - center.y) * (point.y - center.y)
                      + (point.z - center.z) * (point.z - center.z)).squareRoot()
            cloud += (0.5 + 0.5 * sin(point.y * 13 + sin(point.x * 5 + point.z * 4) * 2.2)) * step
            if dc < bound {
                let hit = shellDistance(point)
                if hit.distance < 0.004 { return lit(point, theta: hit.theta, depth: travel) }
            }
            if flake == nil {
                for (i, f) in flakes.enumerated() {
                    let dx = point.x - f.x, dy = point.y - f.y, dz = point.z - f.z
                    if dx * dx + dy * dy + dz * dz < 0.0011 {
                        let twinkle = 0.5 + 0.5 * sin(p.phase * 2 + Double(i) * 1.7)
                        flake = rgb(0xFFD25A).mixed(with: rgb(0xFFF6D8), twinkle)
                        break
                    }
                }
            }
            travel += step
        }
        // No shell: the resin's color for the depth crossed, light where it is thin, and the light it scatters
        // glowing in the middle.
        let depth = min(1, travel / 1.5)
        var body = honey.mixed(with: resin, min(1, depth * 1.5)).mixed(with: deep, max(0, depth - 0.5) * 1.6)
        let streak = travel > 0 ? cloud / travel - 0.5 : 0
        body = streak > 0 ? body.mixed(with: glow, streak * 0.55) : body.mixed(with: deep, -streak * 0.45)
        let facing = max(0, p.normal.z)
        body = body.mixed(with: glow, facing * facing * facing * 0.35)
        guard let flake else { return body }
        return body.mixed(with: flake, 0.8)
    }

    /// The shell at a point, lit from the top left, its ribs lighter, dimmed by the resin in front of it.
    private static func lit(_ p: EggVector, theta: Double, depth: Double) -> C {
        let e = 0.006
        let n = EggLight.normalize((shellDistance((p.x + e, p.y, p.z)).distance - shellDistance((p.x - e, p.y, p.z)).distance,
                                    shellDistance((p.x, p.y + e, p.z)).distance - shellDistance((p.x, p.y - e, p.z)).distance,
                                    shellDistance((p.x, p.y, p.z + e)).distance - shellDistance((p.x, p.y, p.z - e)).distance))
        let light = EggLight.normalize((-0.4, 0.5, 0.78))
        let diffuse = max(0, n.x * light.x + n.y * light.y + n.z * light.z)
        let rib = max(0, cos(theta * 11))
        let base = shell.mixed(with: ridge, rib * rib * 0.85)
        let shaded = base.mixed(with: .black, (1 - diffuse) * 0.6).mixed(with: rgb(0xFFDDA0), diffuse * diffuse * diffuse * 0.4)
        // Seen through amber: tinted, and more so the deeper it lies.
        return shaded.mixed(with: resin, 0.1 + min(0.35, depth * 0.35))
    }

    static var design: EggDesign {
        let surface = EggSurface(albedo: { (p: EggSurfacePoint) -> C in seen(p) }, gloss: 0.95, shininess: 90)
        return EggDesign(surface: surface, outline: rgb(0x5A2404), glow: { canvas, f in
            // A few motes of gold drifting up around it.
            for i in 0..<5 {
                let age = (f.t + EggDesigns.hash(i, 1, 0, seed: 702)).truncatingRemainder(dividingBy: 1)
                guard age > 0.15, age < 0.85 else { continue }
                let side = (EggDesigns.hash(i, 0, 0, seed: 702) - 0.5) * 2.4
                let (x, y) = f.pixel(side, -0.7)
                EggDesigns.light(&canvas, x + 2 * sin(age * 9 + Double(i)), y - age * 46,
                                 i % 2 == 0 ? rgb(0xFFD478) : rgb(0xFFF1C2), behind: true)
            }
        })
    }
}
