import AppKit
import SwiftUI

/// Where the egg stands in one frame of its idle loop, and how to place things around it.
struct EggFrame {
    let phase: Double           // 0..<2π over the loop
    let yaw: Double
    let tilt: Double
    let lift: Int               // pixels up
    let cx: Double
    let cy: Double
    /// Egg units (its height is 2) per pixel.
    let unitsPerPixel: Double

    /// A point of the egg's frame (x right, y up, in egg units) in pixels.
    func pixel(_ ex: Double, _ ey: Double) -> (Double, Double) {
        let (s, c) = (sin(tilt), cos(tilt))
        let u = ex * c - ey * s, v = ex * s + ey * c
        return (cx + u / unitsPerPixel, cy - v / unitsPerPixel - Double(lift))
    }

    /// The egg's radius at height `ey`, in pixels.
    func radius(_ ey: Double) -> Double { EggProfile.radius(ey) / unitsPerPixel }

    /// The loop as 0..<1.
    var t: Double { phase / (2 * .pi) }
}

/// A point of the egg's surface: turned by the yaw for what is painted on it.
struct EggSurfacePoint {
    let x, y, z: Double
    /// Around the axis, 0 facing the viewer.
    let angle: Double
    /// The normal, in the image's frame (for the light).
    let normal: EggVector
    let px: Int, py: Int
}

/// What the egg's own surface looks like in a design.
struct EggSurface {
    var albedo: (EggSurfacePoint) -> EggColor
    /// Bumps, facets.
    var normal: ((EggVector, EggSurfacePoint) -> EggVector)? = nil
    /// The silhouette's radius scale at a height, on a side (-1 left, 1 right).
    var silhouette: ((Double, Double) -> Double)? = nil
    /// False leaves the pixel empty (a ghost's tail, a dithered fade).
    var keep: ((EggSurfacePoint) -> Bool)? = nil
    var gloss: Double = 0.4
    var shininess: Double = 40
    /// A crack around the top, at a height for each angle around: the cap above it lifts by `gap` egg units.
    var cap: ((Double) -> Double)? = nil
    var capGap: (Double) -> Double = { _ in 0 }
}

/// A custom egg: its surface, what is drawn behind and in front of it, its outline.
struct EggDesign {
    var surface: EggSurface
    var back: (inout EggCanvas, EggFrame) -> Void = { _, _ in }
    var front: (inout EggCanvas, EggFrame) -> Void = { _, _ in }
    var outline: EggColor
}

/// The custom eggs: one per type and Type: Null's, each its own shape and things around it, rendered like the plain
/// eggs (`EggRenderer`) on a wider canvas so flames, wings or a ring fit.
enum EggDesigns {
    /// Pixels across: the egg is 48 pixels tall in it, the rest is room for what surrounds it.
    static let pixels = 64
    static let eggHeight = 48.0

    /// One frame of a design's idle loop.
    static func render(_ design: EggDesign, phase: Double) -> CGImage? {
        var canvas = EggCanvas(size: pixels)
        let frame = EggFrame(phase: phase, yaw: 0.52 * sin(phase), tilt: 0.09 * cos(phase),
                             lift: Int((2 * sin(phase)).rounded()), cx: Double(pixels) / 2, cy: 35,
                             unitsPerPixel: 2 / eggHeight)
        design.back(&canvas, frame)
        drawEgg(&canvas, frame, design.surface)
        design.front(&canvas, frame)
        canvas.outline(design.outline)
        return canvas.image()
    }

    /// The egg itself: per pixel, its front surface, lit, its marks turned with the yaw.
    static func drawEgg(_ canvas: inout EggCanvas, _ f: EggFrame, _ surface: EggSurface) {
        let samples = [(-0.25, -0.25), (0.25, -0.25), (-0.25, 0.25), (0.25, 0.25)]
        let (sinT, cosT) = (sin(f.tilt), cos(f.tilt)), (sinY, cosY) = (sin(f.yaw), cos(f.yaw))
        let upp = f.unitsPerPixel
        // Hit the egg at a point of the image (u, v in egg units): its surface point, or nil.
        func hit(_ u: Double, _ v: Double, _ px: Int, _ py: Int) -> EggSurfacePoint? {
            let x = u * cosT + v * sinT, y = -u * sinT + v * cosT
            let scale = surface.silhouette?(y, x < 0 ? -1 : 1) ?? 1
            let r = EggProfile.radius(y) * scale
            guard r > 0, abs(x) < r else { return nil }
            let z = (r * r - x * x).squareRoot()
            let n0 = EggLight.normalize((x, -r * EggProfile.slope(y) * scale, z))
            let normal: EggVector = (n0.x * cosT - n0.y * sinT, n0.x * sinT + n0.y * cosT, n0.z)
            let tx = x * cosY + z * sinY, tz = -x * sinY + z * cosY
            return EggSurfacePoint(x: tx, y: y, z: tz, angle: atan2(tx, tz), normal: normal, px: px, py: py)
        }
        for py in 0..<canvas.size {
            for px in 0..<canvas.size {
                var sum = (0.0, 0.0, 0.0), count = 0.0
                for (sx, sy) in samples {
                    let u = (Double(px) + 0.5 + sx - f.cx) * upp
                    let v = (f.cy - Double(py) - 0.5 - sy - Double(f.lift)) * upp
                    var point: EggSurfacePoint?
                    if let cap = surface.cap {
                        // The cap, lifted, over the crack; the rest below it.
                        let gap = surface.capGap(f.phase)
                        if let top = hit(u, v - gap, px, py), top.y >= cap(top.angle) { point = top }
                        else if let low = hit(u, v, px, py), low.y < cap(low.angle) { point = low }
                    } else {
                        point = hit(u, v, px, py)
                    }
                    guard let p = point, surface.keep?(p) ?? true else { continue }
                    let n = surface.normal?(p.normal, p) ?? p.normal
                    let occlusion = 0.88 + 0.12 * EggLight.smoothstep(-1, -0.2, p.y)
                    let c = EggLight.shade(surface.albedo(p), normal: n, gloss: surface.gloss,
                                           shininess: surface.shininess, occlusion: occlusion)
                    sum.0 += c.r; sum.1 += c.g; sum.2 += c.b
                    count += 1
                }
                guard count >= 2 else { continue }
                canvas.set(px, py, EggColor(sum.0 / count, sum.1 / count, sum.2 / count))
            }
        }
    }

    // MARK: Surface helpers

    /// Spots at surface positions (angle around, height, radius): how much one covers a point.
    static func spots(_ p: EggSurfacePoint, _ list: [(Double, Double, Double)]) -> Double {
        var mask = 0.0
        for (theta, sy, radius) in list {
            let sr = EggProfile.radius(sy)
            let dx = p.x - sr * sin(theta), dy = p.y - sy, dz = p.z - sr * cos(theta)
            mask = max(mask, 1 - EggLight.smoothstep(radius * 0.86, radius, (dx * dx + dy * dy + dz * dz).squareRoot()))
        }
        return mask
    }

    /// A point's place on the surface's map around the front: (across, up), in egg units.
    static func front(_ p: EggSurfacePoint) -> (Double, Double) { (p.angle * EggProfile.radius(p.y), p.y) }

    static func color(_ type: PokemonType) -> EggColor { EggColor(type.color) }

    // MARK: The designs

    static func design(for kind: EggKind) -> EggDesign? {
        switch kind {
        case .type(let type): return design(for: type)
        case .typeNull: return typeNull
        case .plain, .tier: return nil
        }
    }

    static func design(for type: PokemonType) -> EggDesign {
        switch type {
        case .normal: return normal
        case .fire: return fire
        case .water: return water
        case .electric: return electric
        case .grass: return grass
        case .ice: return ice
        case .fighting: return fighting
        case .poison: return poison
        case .ground: return ground
        case .flying: return flying
        case .psychic: return psychic
        case .bug: return bug
        case .rock: return rock
        case .ghost: return ghost
        case .dragon: return dragon
        case .dark: return dark
        case .steel: return steel
        case .fairy: return fairy
        }
    }

    /// Cracked around the top: the cap lifts off and settles back, about to hatch.
    static var normal: EggDesign {
        let shell = EggColor(0.93, 0.89, 0.80), spot = EggColor(0.66, 0.6, 0.52)
        let list: [(Double, Double, Double)] = [(-0.5, -0.2, 0.2), (0.55, -0.45, 0.17), (0.1, -0.7, 0.13), (-1.4, -0.5, 0.18)]
        var surface = EggSurface(albedo: { p in shell.mixed(with: spot, spots(p, list)) })
        // A zigzag crack a little above the middle.
        surface.cap = { angle in 0.28 + 0.08 * abs((angle / (2 * .pi) * 9).truncatingRemainder(dividingBy: 1) * 2 - 1) }
        surface.capGap = { phase in 0.04 + 0.1 * max(0, sin(phase)) }
        return EggDesign(surface: surface, outline: EggColor(0.36, 0.32, 0.27))
    }

    /// Flames rise all around it and lick its sides; the shell glows like an ember.
    static var fire: EggDesign {
        let red = EggColor(0.86, 0.27, 0.12), orange = EggColor(1, 0.58, 0.16), yellow = EggColor(1, 0.88, 0.38)
        let surface = EggSurface(albedo: { p in
            let heat = EggLight.smoothstep(0.6, -0.9, p.y)
            let base = red.mixed(with: orange, heat * 0.7)
            return base.mixed(with: yellow, spots(p, [(-0.5, -0.4, 0.16), (0.5, -0.1, 0.12), (0.1, 0.4, 0.1),
                                                      (1.3, -0.5, 0.15), (-1.4, 0.2, 0.13)]) * 0.85)
        }, gloss: 0.35)
        return EggDesign(surface: surface, back: { canvas, f in
            // Tongues around the egg, from its sides up over its top, each flickering on its own beat.
            let spots: [(Double, Double, Double)] = [(-0.95, -0.55, 0.9), (-1, 0.05, 1.1), (-0.85, 0.55, 1.0),
                                                     (-0.45, 0.92, 1.15), (0.05, 1.05, 1.3), (0.5, 0.9, 1.1),
                                                     (0.88, 0.5, 1.0), (1, 0.0, 1.1), (0.95, -0.55, 0.9)]
            for (i, (sx, sy, size)) in spots.enumerated() {
                let side = sx
                let (bx, by) = f.pixel(sx * EggProfile.radius(sy) * 0.95 / max(0.3, abs(sx)), sy)
                let flicker = 0.75 + 0.25 * sin(f.phase * 3 + Double(i) * 1.7)
                canvas.flame(baseX: bx, baseY: by, height: 11 * size * flicker, width: 3.6 * size,
                             lean: side * 0.35 + 0.1 * sin(f.phase * 2 + Double(i)), outer: red, middle: orange, core: yellow)
            }
        }, front: { canvas, f in
            for (i, sx) in [-0.55, 0.6].enumerated() {
                let (bx, by) = f.pixel(sx, -0.86)
                let flicker = 0.7 + 0.3 * sin(f.phase * 3 + Double(i) * 2.3)
                canvas.flame(baseX: bx, baseY: by + 3, height: 8 * flicker, width: 2.6, lean: sx * 0.3,
                             outer: red, middle: orange, core: yellow)
            }
        }, outline: EggColor(0.42, 0.1, 0.05))
    }

    /// A drop's pointed top, waves around it, bubbles rising beside it.
    static var water: EggDesign {
        let light = EggColor(0.62, 0.84, 0.98), deep = color(.water), foam = EggColor(0.93, 0.98, 1)
        var surface = EggSurface(albedo: { p in
            var c = light.mixed(with: deep, EggLight.smoothstep(0.7, -0.9, p.y) * 0.6)
            for (center, width) in [(-0.35, 0.07), (0.05, 0.05), (-0.7, 0.06)] {
                let wave = center + 0.06 * sin(p.angle * 4)
                if abs(p.y - wave) < width { c = deep.mixed(with: .black, 0.1) }
                if abs(p.y - wave - width - 0.02) < 0.018 { c = foam }
            }
            return c
        }, gloss: 0.6, shininess: 60)
        // Pointier at the top, like a drop.
        surface.silhouette = { y, _ in y > 0.35 ? 1 - (y - 0.35) * 0.45 : 1 }
        return EggDesign(surface: surface, front: { canvas, f in
            for i in 0..<5 {
                let t = (f.t + Double(i) / 5).truncatingRemainder(dividingBy: 1)
                let side = i.isMultiple(of: 2) ? -1.0 : 1.0
                let x = f.cx + side * (21 + 3 * sin(t * 9 + Double(i))), y = 60 - t * 50
                let r = 2 + Double(i % 3) * 0.8
                canvas.fill(x - r - 1, y - r - 1, x + r + 1, y + r + 1) { px, py in
                    let d = ((px - x) * (px - x) + (py - y) * (py - y)).squareRoot()
                    if d > r + 0.5 { return nil }
                    if px < x - r * 0.3, py < y - r * 0.3, d < r * 0.6 { return .white }
                    return d > r - 1.2 ? EggColor(0.55, 0.8, 1) : nil
                }
            }
        }, outline: EggColor(0.1, 0.25, 0.5))
    }

    /// A lightning band around it; sparks crackle on and off around it.
    static var electric: EggDesign {
        let yellow = color(.electric), black = EggColor(0.16, 0.14, 0.1)
        let surface = EggSurface(albedo: { p in
            let saw = abs((p.angle / (2 * .pi) * 6 + 10).truncatingRemainder(dividingBy: 1) * 2 - 1)
            let edge = -0.02 + 0.2 * (saw - 0.5)
            if abs(p.y - edge) < 0.075 { return black }
            return yellow.mixed(with: .white, EggLight.smoothstep(-0.2, 0.9, p.y) * 0.25)
        }, gloss: 0.45)
        return EggDesign(surface: surface, back: { canvas, f in
            for i in 0..<4 where sin(f.phase * 4 + Double(i) * 1.9) > 0.1 {
                let a = Double(i) * .pi / 2 + 0.6 + f.phase * 0.3
                let x = f.cx + cos(a) * 25, y = f.cy - 2 + sin(a) * 23 - Double(f.lift)
                let s = 3.5
                canvas.path([(x - s, y - s), (x + 0.5, y - 0.5), (x - 0.5, y + 0.5), (x + s, y + s)], width: 1.6,
                            EggColor(1, 0.97, 0.55))
            }
        }, outline: EggColor(0.36, 0.28, 0.02))
    }

    /// Leaf veins on the shell; two leaves sprout from the top and sway.
    static var grass: EggDesign {
        let green = color(.grass), dark = color(.grass).mixed(with: .black, 0.3), light = EggColor(0.8, 0.95, 0.62)
        let surface = EggSurface(albedo: { p in
            let base = light.mixed(with: green, EggLight.smoothstep(0.9, -0.6, p.y))
            let vein = abs(sin(p.angle * 3)) < 0.1 && p.y < 0.75
            return vein ? dark : base
        }, gloss: 0.3)
        return EggDesign(surface: surface, front: { canvas, f in
            let (tx, ty) = f.pixel(0, 0.95)
            for side in [-1.0, 1.0] {
                let sway = 0.18 * sin(f.phase + (side < 0 ? 0 : 1.2))
                let angle = .pi / 2 + side * 0.75 + sway
                let len = 13.0
                let cx = tx + cos(angle) * len / 2, cy = ty - sin(angle) * len / 2
                canvas.ellipse(cx, cy, len / 2, 3.3, angle: angle, green.mixed(with: .white, 0.12), gloss: 0.1)
                canvas.line(tx, ty, tx + cos(angle) * len * 0.85, ty - sin(angle) * len * 0.85, width: 0.9, dark)
            }
            canvas.line(tx, ty + 1, tx, ty - 3, width: 1.6, dark)
        }, outline: EggColor(0.12, 0.3, 0.1))
    }

    /// Crystal facets, a crown of ice on top, snowflakes drifting down.
    static var ice: EggDesign {
        let ice = EggColor(0.72, 0.9, 0.98), deep = color(.ice).mixed(with: EggColor(0.3, 0.5, 1), 0.15)
        var surface = EggSurface(albedo: { p in
            if p.y > 0.62 + 0.06 * sin(p.angle * 7) { return .white }
            return ice.mixed(with: deep, EggLight.smoothstep(0.5, -1, p.y) * 0.6)
        }, gloss: 0.7, shininess: 80)
        // Facets: the normal snapped to a coarse lattice.
        surface.normal = { n, _ in EggLight.normalize(((n.x * 3).rounded() / 3, (n.y * 3).rounded() / 3, max(0.2, (n.z * 3).rounded() / 3))) }
        return EggDesign(surface: surface, front: { canvas, f in
            let (tx, ty) = f.pixel(0, 0.9)
            for (dx, h) in [(-5.0, 6.0), (0.0, 10.0), (5.0, 7.0), (-9.0, 4.0), (9.0, 4.0)] {
                let base = ty + abs(dx) * 0.35 + 2
                canvas.polygon([(tx + dx - 2.2, base), (tx + dx + 2.2, base), (tx + dx, base - h)], EggColor(0.8, 0.95, 1))
            }
            for i in 0..<4 {
                let t = (f.t + Double(i) / 4).truncatingRemainder(dividingBy: 1)
                let x = f.cx + (i < 2 ? -1.0 : 1.0) * (18 + Double(i % 2) * 6) + 2 * sin(t * 6), y = 6 + t * 50
                canvas.sparkle(x, y, 1.6, .white)
            }
        }, outline: EggColor(0.2, 0.4, 0.55))
    }

    /// A red headband knotted on the side, its tails flapping.
    static var fighting: EggDesign {
        let shell = EggColor(0.95, 0.9, 0.82), band = EggColor(0.86, 0.17, 0.15)
        let surface = EggSurface(albedo: { p in
            let edge = 0.38 + 0.02 * sin(p.angle * 2)
            return abs(p.y - edge) < 0.1 ? band : shell
        }, gloss: 0.3)
        return EggDesign(surface: surface, front: { canvas, f in
            // The knot on the right, where the band leaves the egg, and two tails waving away.
            let (kx, ky) = f.pixel(EggProfile.radius(0.38) * 0.93, 0.38)
            for (i, spread) in [-0.35, 0.3].enumerated() {
                let wave = 2 * sin(f.phase * 2 + Double(i))
                let tipX = kx + 13, tipY = ky + spread * 16 + wave
                canvas.polygon([(kx, ky - 1.8), (tipX, tipY - 2), (tipX - 1.5, tipY + 2), (kx, ky + 1.8)], band)
            }
            canvas.ball(kx, ky, 3, band)
        }, outline: EggColor(0.34, 0.08, 0.07))
    }

    /// Toxic bubbles on the shell; drops of goo gather under it and fall.
    static var poison: EggDesign {
        let purple = color(.poison), dark = color(.poison).mixed(with: .black, 0.4), goo = EggColor(0.75, 0.45, 0.85)
        let list: [(Double, Double, Double)] = [(-0.5, 0.2, 0.2), (0.45, -0.25, 0.24), (0.0, 0.6, 0.13),
                                                (-0.3, -0.6, 0.16), (1.3, 0.3, 0.18), (-1.4, -0.3, 0.2)]
        let surface = EggSurface(albedo: { p in
            let m = spots(p, list)
            return purple.mixed(with: dark, m).mixed(with: goo, m > 0.2 && m < 0.6 ? 0.6 : 0)
        }, gloss: 0.55, shininess: 50)
        return EggDesign(surface: surface, front: { canvas, f in
            for (i, sx) in [-0.35, 0.3].enumerated() {
                let t = (f.t + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                let (bx, by) = f.pixel(sx, -0.9)
                let stretch = min(t, 0.6) / 0.6
                canvas.ellipse(bx, by + 1 + stretch * 2, 1.8, 1.5 + stretch * 2.2, goo, gloss: 0.4)
                if t > 0.6 { canvas.ball(bx, by + 5 + (t - 0.6) * 25, 1.6, goo, gloss: 0.5) }
            }
            for i in 0..<2 {
                let t = (f.t * 1.5 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                if t < 0.8 { canvas.ball(f.cx + (i == 0 ? -8 : 7), 10 - t * 6, 1 + t * 1.6, goo, gloss: 0.6) }
            }
        }, outline: EggColor(0.25, 0.08, 0.3))
    }

    /// Half buried in a mound of earth, cracked, dust rising at its edges.
    static var ground: EggDesign {
        let sand = EggColor(0.9, 0.8, 0.55), earth = color(.ground).mixed(with: .black, 0.15)
        let crack = EggColor(0.42, 0.3, 0.15)
        let surface = EggSurface(albedo: { p in
            let (a, y) = front(p)
            let line1 = abs(a - (0.12 + 0.1 * abs(((y * 6).truncatingRemainder(dividingBy: 1)) * 2 - 1))) < 0.025 && y > 0
            let line2 = abs(a + 0.4 - 0.08 * sin(y * 14)) < 0.022 && y < 0.5 && y > -0.3
            return line1 || line2 ? crack : sand.mixed(with: earth, EggLight.smoothstep(0.6, -0.8, p.y) * 0.5)
        }, gloss: 0.2)
        return EggDesign(surface: surface, front: { canvas, f in
            // The mound stays on the ground while the egg wobbles in it.
            let cx = f.cx, cy = 58.0
            canvas.fill(cx - 28, cy - 9, cx + 28, cy + 6) { x, y in
                let dx = (x - cx) / 27, dy = (y - cy) / 8
                guard dx * dx + dy * dy <= 1, y > cy - 8 + 3 * dx * dx else { return nil }
                let top = EggLight.smoothstep(cy - 4, cy - 8, y)
                let grain = EggLight.noise(x * 0.7, y * 0.7) > 0.72 ? 0.12 : 0
                return earth.mixed(with: EggColor(0.86, 0.7, 0.45), top * 0.6).mixed(with: .black, grain)
            }
            for i in 0..<3 where sin(f.phase * 2 + Double(i) * 2) > 0.3 {
                canvas.ball(cx + Double(i - 1) * 20, 50 - 3 * sin(f.phase + Double(i)), 1.2, EggColor(0.8, 0.68, 0.45))
            }
        }, outline: EggColor(0.32, 0.22, 0.1))
    }

    /// Two feathered wings at its sides, beating.
    static var flying: EggDesign {
        let sky = EggColor(0.75, 0.86, 1), white = EggColor(0.98, 0.99, 1), feather = EggColor(0.93, 0.95, 1)
        let surface = EggSurface(albedo: { p in
            sky.mixed(with: white, EggLight.smoothstep(-0.6, 0.7, p.y) * 0.7 + spots(p, [(-0.5, -0.4, 0.2), (0.6, 0.1, 0.16), (0.1, -0.75, 0.13)]) * 0.5)
        }, gloss: 0.35)
        return EggDesign(surface: surface, back: { canvas, f in
            let beat = sin(f.phase * 2)
            for side in [-1.0, 1.0] {
                let (rx, ry) = f.pixel(side * EggProfile.radius(0.2) * 0.92, 0.2)
                // Feathers fanned from up and out to straight out, rising and falling with the beat.
                for k in 0..<4 {
                    let spread = 1.0 - Double(k) * 0.3 + beat * 0.3
                    let angle = side > 0 ? spread : .pi - spread
                    let len = 18.0 - Double(k) * 1.5
                    canvas.ellipse(rx + cos(angle) * len / 2, ry - sin(angle) * len / 2, len / 2, 3.2, angle: angle,
                                   k.isMultiple(of: 2) ? feather : white, gloss: 0.1)
                }
            }
        }, outline: EggColor(0.35, 0.45, 0.65))
    }

    /// A hypnotic spiral turning on its front; a ring orbits it.
    static var psychic: EggDesign {
        let pink = color(.psychic).mixed(with: .white, 0.25), magenta = color(.psychic).mixed(with: .black, 0.1)
        return EggDesign(surface: EggSurface(albedo: { p in
            let (a, y) = front(p)
            let dx = a, dy = y - 0.05
            let r = (dx * dx + dy * dy).squareRoot()
            guard r < 0.42 else { return pink }
            // Rotates with the loop: four turns from the middle out.
            let spin = (atan2(dy, dx) / (2 * .pi) + r * 2.6 - 0 + 10).truncatingRemainder(dividingBy: 1)
            return spin < 0.5 ? magenta : pink.mixed(with: .white, 0.3)
        }, gloss: 0.45), back: { canvas, f in ring(&canvas, f, behind: true, magenta) },
        front: { canvas, f in ring(&canvas, f, behind: false, magenta) },
        outline: EggColor(0.4, 0.1, 0.25))
    }

    /// The psychic ring: its back half behind the egg, its front half over it, three orbs going round.
    private static func ring(_ canvas: inout EggCanvas, _ f: EggFrame, behind: Bool, _ color: EggColor) {
        let cx = f.cx, cy = f.cy + 2 - Double(f.lift)
        let rx = 28.0, ry = 7.0, tilt = -0.18
        let (s, c) = (sin(tilt), cos(tilt))
        func point(_ a: Double) -> (Double, Double) {
            let x = cos(a) * rx, y = sin(a) * ry
            return (cx + x * c - y * s, cy + x * s + y * c)
        }
        // sin(a) > 0 is the near side.
        for step in 0..<160 {
            let a = Double(step) / 160 * 2 * .pi
            guard (sin(a) > 0) != behind else { continue }
            let (x, y) = point(a)
            canvas.ball(x, y, 1.1, EggColor(0.85, 0.7, 1), gloss: 0)
        }
        for k in 0..<3 {
            let a = f.phase + Double(k) * 2 * .pi / 3
            guard (sin(a) > 0) != behind else { continue }
            let (x, y) = point(a)
            canvas.ball(x, y, 2.2, color.mixed(with: .white, 0.3), gloss: 0.5)
        }
    }

    /// Segments like a larva's; two antennae bobbing on top.
    static var bug: EggDesign {
        let lime = color(.bug).mixed(with: .white, 0.15), band = color(.bug).mixed(with: .black, 0.3)
        let surface = EggSurface(albedo: { p in
            let seg = ((p.y + 1) * 3.2).truncatingRemainder(dividingBy: 1)
            if seg < 0.14 { return band }
            return lime.mixed(with: band, spots(p, [(-0.45, 0.2, 0.08), (0.45, 0.2, 0.08)]))
        }, gloss: 0.35)
        return EggDesign(surface: surface, front: { canvas, f in
            let (tx, ty) = f.pixel(0, 0.97)
            for side in [-1.0, 1.0] {
                let bob = 1.5 * sin(f.phase * 2 + side)
                let mid = (tx + side * 4, ty - 7 + bob * 0.5), tip = (tx + side * 9, ty - 11 + bob)
                canvas.path([(tx + side * 1.5, ty + 1), mid, tip], width: 1.3, band)
                canvas.ball(tip.0, tip.1, 2, band.mixed(with: .white, 0.2))
            }
        }, outline: EggColor(0.22, 0.3, 0.05))
    }

    /// Its lower half is rough stone, its top an egg cracking out of it; pebbles bounce at its foot.
    static var rock: EggDesign {
        let shell = EggColor(0.93, 0.9, 0.82), stone = color(.rock).mixed(with: EggColor(0.5, 0.48, 0.45), 0.5)
        let crack = EggColor(0.4, 0.35, 0.3)
        func border(_ angle: Double) -> Double { 0.02 + 0.12 * EggLight.noise(angle * 2.2 + 5, 1.5) }
        var surface = EggSurface(albedo: { p in
            if p.y < border(p.angle) {
                let speck = EggLight.noise(p.angle * 9, p.y * 9) > 0.7 ? 0.12 : 0
                return stone.mixed(with: .black, speck)
            }
            let (a, y) = front(p)
            if abs(a - 0.05 - 0.06 * sin(y * 20)) < 0.022 && y < 0.6 { return crack }
            return shell
        }, gloss: 0.25)
        // Lumps along the stone's outline and facets on its faces.
        surface.silhouette = { y, side in
            y < 0.1 ? 1 + 0.1 * (EggLight.noise(y * 5 + 3, side * 4 + 7) - 0.4) : 1
        }
        surface.normal = { n, p in
            guard p.y < border(p.angle) else { return n }
            let jx = (EggLight.noise(p.angle * 3, p.y * 3) - 0.5) * 0.7, jy = (EggLight.noise(p.angle * 3 + 9, p.y * 3) - 0.5) * 0.7
            return EggLight.normalize((((n.x + jx) * 2).rounded() / 2, ((n.y + jy) * 2).rounded() / 2, max(0.3, n.z)))
        }
        return EggDesign(surface: surface, front: { canvas, f in
            for (i, dx) in [-14.0, 15.0].enumerated() {
                let hop = abs(sin(f.phase * 2 + Double(i) * 1.4)) * 3
                canvas.ellipse(f.cx + dx, 59 - hop, 2.6, 2, stone.mixed(with: .white, 0.1), gloss: 0.1)
            }
        }, outline: EggColor(0.25, 0.23, 0.2))
    }

    /// Its bottom melts into a wavy ghost's tail, fading out; it watches you; wisps drift around.
    static var ghost: EggDesign {
        let purple = color(.ghost).mixed(with: .white, 0.15), eye = EggColor(0.12, 0.05, 0.18)
        var surface = EggSurface(albedo: { p in
            let (a, y) = front(p)
            for side in [-1.0, 1.0] {
                let dx = (a - side * 0.17) / 0.075, dy = (y - 0.28) / 0.12
                if dx * dx + dy * dy < 1 { return eye }
            }
            return purple.mixed(with: .white, EggLight.smoothstep(0, 0.9, y) * 0.2)
        }, gloss: 0.5)
        surface.keep = { p in
            // A wavy tail, and the lower part checkered out like a fade.
            let edge = -0.72 + 0.12 * sin(Double(p.px) * 0.7 + Double(p.py) * 0)
            if p.y < edge { return false }
            if p.y < -0.35 { return (p.px + p.py).isMultiple(of: 2) || p.y > -0.45 }
            return true
        }
        return EggDesign(surface: surface, back: { canvas, f in
            for i in 0..<2 {
                let t = (f.t + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                let x = f.cx + (i == 0 ? -22.0 : 21) + 2 * sin(t * 2 * .pi * 2), y = 48 - t * 36
                canvas.flame(baseX: x, baseY: y, height: 7, width: 2.4, lean: 0.2 * sin(t * 6),
                             outer: purple.mixed(with: .black, 0.2), middle: purple, core: EggColor(0.95, 0.85, 1))
            }
        }, outline: EggColor(0.22, 0.12, 0.3))
    }

    /// Scales over its shell, horns on its head, fins down its sides.
    static var dragon: EggDesign {
        let blue = color(.dragon), rim = color(.dragon).mixed(with: .white, 0.4), belly = EggColor(0.98, 0.9, 0.7)
        let surface = EggSurface(albedo: { p in
            let y = p.y
            let row = ((y + 1) * 4).rounded(.down)
            let col = p.angle * 2.6 + (row.truncatingRemainder(dividingBy: 2) == 0 ? 0.5 : 0)
            let fx = col - col.rounded(.down) - 0.5, fy = (y + 1) * 4 - row
            let d = fx * fx + (fy - 0.25) * (fy - 0.25)
            return d > 0.2 ? rim : blue.mixed(with: .white, max(0, 0.12 - d * 0.5))
        }, gloss: 0.4)
        return EggDesign(surface: surface, back: { canvas, f in
            for side in [-1.0, 1.0] {
                for (k, ey) in [0.35, 0.0, -0.35].enumerated() {
                    let (x, y) = f.pixel(side * EggProfile.radius(ey) * 0.9, ey)
                    let h = 6.0 - Double(k)
                    canvas.polygon([(x, y - 3), (x + side * h, y - 4 + sin(f.phase + Double(k)) * 0.8), (x, y + 2)], rim)
                }
            }
        }, front: { canvas, f in
            for side in [-1.0, 1.0] {
                let (bx, by) = f.pixel(side * 0.28, 0.84)
                // Curving back and out.
                canvas.polygon([(bx - 3, by + 2), (bx + 3, by + 2), (bx + side * 6, by - 7), (bx + side * 9, by - 13),
                                (bx + side * 3.5, by - 6)], belly)
            }
        }, outline: EggColor(0.12, 0.08, 0.35))
    }

    /// A shell like the night, a crescent moon glowing on it; dark smoke drifts around.
    static var dark: EggDesign {
        let night = EggColor(0.22, 0.2, 0.28), moon = EggColor(1, 0.86, 0.45)
        let surface = EggSurface(albedo: { p in
            let (a, y) = front(p)
            let d1 = ((a - 0.02) * (a - 0.02) + (y - 0.2) * (y - 0.2)).squareRoot()
            let d2 = ((a - 0.12) * (a - 0.12) + (y - 0.27) * (y - 0.27)).squareRoot()
            if d1 < 0.26 && d2 > 0.22 { return moon }
            let star = EggLight.noise(p.angle * 14, p.y * 14) > 0.9
            return star ? EggColor(0.7, 0.7, 0.85) : night
        }, gloss: 0.5, shininess: 60)
        return EggDesign(surface: surface, back: { canvas, f in
            for i in 0..<5 {
                let t = (f.t + Double(i) / 5).truncatingRemainder(dividingBy: 1)
                let a = Double(i) * 1.3 + t * 2
                let x = f.cx + cos(a) * 22, y = 52 - t * 30
                canvas.ball(x, y, 3.5 - t * 2, EggColor(0.32, 0.26, 0.4).mixed(with: .black, t * 0.3), gloss: 0)
            }
        }, outline: EggColor(0.08, 0.06, 0.12))
    }

    /// Chrome reflecting a sky and a horizon; a toothed gear rim around its middle.
    static var steel: EggDesign {
        let sky = EggColor(0.86, 0.9, 0.95), ground = EggColor(0.36, 0.38, 0.44), bolt = EggColor(0.55, 0.57, 0.62)
        let step = Double.pi / 6
        func onBolt(_ angle: Double) -> Bool {
            let offset: Double = (angle + 20 * .pi).truncatingRemainder(dividingBy: step)
            return offset < 0.08 || offset > step - 0.08
        }
        var surface = EggSurface(albedo: { p in
            if abs(p.y) < 0.09 { return onBolt(p.angle) ? bolt.mixed(with: .white, 0.3) : bolt }
            // The reflected view's height: the sky above the horizon, the ground under it, a bright line between.
            let ry: Double = 2 * p.normal.z * p.normal.y
            if abs(ry - 0.05) < 0.06 { return .white }
            return ry > 0.05 ? sky.mixed(with: EggColor(0.6, 0.7, 0.85), ry * 0.6) : ground
        }, gloss: 0.8, shininess: 90)
        // Teeth stand out of the outline around the middle.
        surface.silhouette = { y, _ in
            guard abs(y) < 0.09 else { return 1 }
            let tooth: Int = Int(((y + 0.09) * 40).rounded(.down))
            return tooth.isMultiple(of: 2) ? 1.11 : 1.07
        }
        return EggDesign(surface: surface, outline: EggColor(0.15, 0.16, 0.2))
    }

    /// Hearts on a pastel shell, a bow on top, sparkles twinkling around.
    static var fairy: EggDesign {
        let pastel = EggColor(1, 0.9, 0.95), pink = color(.fairy), bow = EggColor(0.98, 0.5, 0.72)
        let hearts: [(Double, Double)] = [(-0.45, 0.1), (0.45, -0.35), (0.05, -0.6), (0.2, 0.45), (-1.4, -0.3), (1.5, 0.2)]
        let surface = EggSurface(albedo: { p in
            for (theta, hy) in hearts {
                var da = p.angle - theta
                if da > .pi { da -= 2 * .pi }; if da < -.pi { da += 2 * .pi }
                let x = da * EggProfile.radius(p.y) / 0.13, y = (p.y - hy) / 0.13
                // The heart curve: (x² + y² - 1)³ - x² y³ < 0.
                let q = x * x + y * y - 1
                if q * q * q - x * x * y * y * y < 0 { return pink }
            }
            return pastel
        }, gloss: 0.45)
        return EggDesign(surface: surface, back: { canvas, f in
            for i in 0..<4 {
                let a = Double(i) * .pi / 2 + 0.7
                let twinkle = max(0, sin(f.phase * 2 + Double(i) * 1.6))
                if twinkle > 0.1 { canvas.sparkle(f.cx + cos(a) * 25, f.cy + sin(a) * 22, 1 + twinkle * 2.4, EggColor(1, 0.95, 0.6)) }
            }
        }, front: { canvas, f in
            let (bx, by) = f.pixel(0, 0.93)
            let flap = 0.8 * sin(f.phase * 2)
            canvas.polygon([(bx, by), (bx - 9, by - 5 - flap), (bx - 8, by + 4)], bow)
            canvas.polygon([(bx, by), (bx + 9, by - 5 + flap), (bx + 8, by + 4)], bow)
            canvas.ball(bx, by, 2.4, bow.mixed(with: .white, 0.2))
        }, outline: EggColor(0.45, 0.15, 0.3))
    }

    /// Type: Null's: riveted steel plates, a knight's helm over the top with a visor and a crest.
    static var typeNull: EggDesign {
        let plate = EggColor(0.62, 0.64, 0.68), seam = EggColor(0.22, 0.23, 0.27), rivet = EggColor(0.86, 0.85, 0.8)
        let helm = EggColor(0.4, 0.42, 0.47), visor = EggColor(0.1, 0.11, 0.14), glow = EggColor(0.4, 0.9, 0.85)
        func helmRim(_ angle: Double) -> Double { 0.05 + 0.05 * cos(angle) }
        var surface = EggSurface(albedo: { p in
            let (a, y) = front(p)
            if y > helmRim(p.angle) {
                if y < helmRim(p.angle) + 0.04 { return seam }
                if abs(y - 0.36) < 0.05 && abs(a) < 0.45 {
                    return abs(abs(a) - 0.16) < 0.06 ? glow : visor
                }
                if abs(a) < 0.06 && y > 0.4 { return helm.mixed(with: .white, 0.35) }
                return helm
            }
            if abs(a) < 0.035 || abs(y + 0.4) < 0.02 { return seam }
            for k in -4...4 where abs(a - 0.11) < 0.04 && abs(y - (-0.4 + Double(k) * 0.18)) < 0.04 { return rivet }
            for k in -4...4 where abs(a + 0.11) < 0.04 && abs(y - (-0.4 + Double(k) * 0.18)) < 0.04 { return rivet }
            return plate
        }, gloss: 0.6, shininess: 70)
        // The helm is a little wider than the egg below it.
        surface.silhouette = { y, _ in y > 0.08 ? 1.07 : 1 }
        return EggDesign(surface: surface, back: { canvas, f in
            // The crest: a plume of blades over the helm, swaying.
            let (tx, ty) = f.pixel(0, 0.98)
            for k in -3...3 {
                let sway = 0.08 * sin(f.phase + Double(k))
                let angle = .pi / 2 - Double(k) * 0.3 + sway
                let len = 19.0 - Double(abs(k)) * 2.6
                canvas.polygon([(tx - 2.4, ty + 3), (tx + 2.4, ty + 3),
                                (tx + cos(angle) * len, ty - sin(angle) * len)],
                               k.isMultiple(of: 2) ? EggColor(0.32, 0.34, 0.38) : EggColor(0.24, 0.5, 0.52))
            }
        }, outline: EggColor(0.12, 0.13, 0.16))
    }

    // MARK: Frames

    @MainActor private static var stillCache: [EggKind: NSImage] = [:]
    @MainActor private static var loopCache: [EggKind: [(image: NSImage, delay: TimeInterval)]] = [:]

    @MainActor
    static func still(_ kind: EggKind) -> NSImage? {
        if let cached = stillCache[kind] { return cached }
        guard let design = design(for: kind), let image = render(design, phase: 0) else { return nil }
        let still = NSImage(cgImage: image, size: NSSize(width: pixels, height: pixels))
        stillCache[kind] = still
        return still
    }

    @MainActor
    static func idleFrames(_ kind: EggKind) -> [(image: NSImage, delay: TimeInterval)]? {
        if let cached = loopCache[kind] { return cached }
        guard let design = design(for: kind) else { return nil }
        let frames = (0..<EggRenderer.frameCount).compactMap { i -> (image: NSImage, delay: TimeInterval)? in
            let phase = 2 * Double.pi * Double(i) / Double(EggRenderer.frameCount)
            return render(design, phase: phase).map {
                (NSImage(cgImage: $0, size: NSSize(width: pixels, height: pixels)), EggRenderer.frameDelay)
            }
        }
        loopCache[kind] = frames
        return frames
    }
}
