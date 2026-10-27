import AppKit

/// The event eggs' designs (`EventEgg`), chosen by the player among six each: a snowy tree in Santa's hat, a mirror
/// ball, a pearl pierced by Cupid's arrow, the Pokédex, a bunny in a flowery basket, a jack-o'-lantern, a hot-air
/// balloon, and the seasons' weather around an egg wearing the season's motif.
enum EventEggArt {
    typealias C = EggColor

    static func design(_ egg: EventEgg) -> EggDesign {
        switch egg {
        case .christmas: return christmas
        case .newYear: return newYear
        case .valentine: return valentine
        case .pokemonDay: return pokemonDay
        case .easter: return easter
        case .halloween: return halloween
        case .companion: return companion
        case .spring, .summer, .autumn, .winter: return season(egg)
        }
    }

    // MARK: Tools

    static func rgb(_ hex: Int) -> C {
        C(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    private static func h(_ i: Int, _ j: Int, _ seed: Int) -> Double { EggDesigns.hash(i, j, 0, seed: seed) }

    private static func dot(_ canvas: inout EggCanvas, _ x: Double, _ y: Double, _ c: C, behind: Bool = false) {
        EggDesigns.light(&canvas, x, y, c, behind: behind)
    }

    /// Particles falling over the loop, each its column and phase.
    private static func falling(_ canvas: inout EggCanvas, _ f: EggFrame, count: Int, seed: Int, speed: Int = 1,
                                sway: Double = 2.5, draw: (inout EggCanvas, Double, Double, Int, Double) -> Void) {
        for i in 0..<count {
            let x0: Double = 3 + h(i, 0, seed) * 58
            let age: Double = (f.t * Double(speed) + h(i, 1, seed)).truncatingRemainder(dividingBy: 1)
            draw(&canvas, x0 + sway * sin(age * 2 * .pi + Double(i)), -4 + age * 70, i, age)
        }
    }

    /// Particles rising around the egg's foot.
    private static func rising(_ canvas: inout EggCanvas, _ f: EggFrame, count: Int, seed: Int, spread: Double = 1,
                               draw: (inout EggCanvas, Double, Double, Int, Double) -> Void) {
        for i in 0..<count {
            let side: Double = (h(i, 0, seed) - 0.5) * 2 * spread
            let age: Double = (f.t + h(i, 1, seed)).truncatingRemainder(dividingBy: 1)
            let (bx, by) = f.pixel(side * 0.9, -0.7)
            draw(&canvas, bx + 3 * sin(age * 3 * .pi + Double(i)), by - age * 48, i, age)
        }
    }

    /// Whether a point lies in a heart centered at the origin, its point down, `s` across its half.
    static func inHeart(_ u0: Double, _ v0: Double, _ s: Double) -> Bool {
        let u: Double = u0 / s * 1.15, v: Double = v0 / s * 1.25 + 0.3
        let q: Double = u * u + v * v - 1
        return q * q * q - u * u * v * v * v <= 0
    }

    private static func heart(_ canvas: inout EggCanvas, _ x: Double, _ y: Double, _ s: Double, _ c: C) {
        canvas.fill(x - s - 1, y - s - 1, x + s + 1, y + s + 1) { (px: Double, py: Double) -> C? in
            inHeart(px - x, y - py, s) ? c : nil
        }
    }

    private static func snowflake(_ canvas: inout EggCanvas, _ x: Double, _ y: Double, _ r: Double, _ c: C, behind: Bool) {
        dot(&canvas, x, y, c, behind: behind)
        guard r >= 1.5 else { return }
        for k in 0..<6 {
            let a: Double = Double(k) * .pi / 3
            for step in 1...Int(r) { dot(&canvas, x + cos(a) * Double(step), y + sin(a) * Double(step), c, behind: behind) }
        }
    }

    private static func star5(_ canvas: inout EggCanvas, _ x: Double, _ y: Double, _ r: Double, _ c: C, turn: Double = 0) {
        var points: [(Double, Double)] = []
        for k in 0..<10 {
            let rr: Double = k.isMultiple(of: 2) ? r : r * 0.45
            let a: Double = -Double.pi / 2 + Double(k) * .pi / 5 + turn
            points.append((x + cos(a) * rr, y + sin(a) * rr))
        }
        canvas.polygon(points, c)
    }

    private static func leaf(_ canvas: inout EggCanvas, _ x: Double, _ y: Double, _ angle: Double, _ c: C, size: Double) {
        canvas.ellipse(x, y, size, size * 0.5, angle: angle, c, gloss: 0.2)
    }

    private static func flower(_ canvas: inout EggCanvas, _ x: Double, _ y: Double, _ petal: C, _ heart: C) {
        for k in 0..<5 {
            let a: Double = Double(k) * 2 * .pi / 5
            canvas.ellipse(x + cos(a) * 1.6, y + sin(a) * 1.6, 1.3, 1.3, petal, flat: true)
        }
        dot(&canvas, x, y, heart)
    }

    /// Light rays around a point, turning with the loop.
    private static func rays(_ canvas: inout EggCanvas, _ x: Double, _ y: Double, count: Int, inner: Double, outer: Double,
                             _ c: C, turn: Double) {
        for k in 0..<count {
            let a: Double = Double(k) / Double(count) * 2 * .pi + turn
            let long: Double = k.isMultiple(of: 2) ? outer : outer * 0.7
            EggDesigns.streak(&canvas, from: (x + cos(a) * inner, y + sin(a) * inner),
                              to: (x + cos(a) * long, y + sin(a) * long), c, behind: true)
        }
    }

    /// Where a surface point lies on a tiling of the egg's front map: its offset from its cell's center, and the cell.
    private static func tile(_ p: EggSurfacePoint, size: Double) -> (u: Double, v: Double, i: Int, j: Int) {
        let (a, y) = EggDesigns.front(p)
        let j = Int((y / size + 50).rounded(.down))
        let shift: Double = j.isMultiple(of: 2) ? 0.5 : 0
        let i = Int((a / size + 50 + shift).rounded(.down))
        return (a - (Double(i) - 50 - shift + 0.5) * size, y - (Double(j) - 50 + 0.5) * size, i, j)
    }

    // MARK: Christmas: the snowy tree in Santa's hat

    private static let red = rgb(0xD62839), green = rgb(0x2E8B57), gold = rgb(0xF2C14E), snow = rgb(0xF4F8FF)

    private static func snowfall(_ canvas: inout EggCanvas, _ f: EggFrame, front: Bool, count: Int) {
        falling(&canvas, f, count: count, seed: front ? 401 : 402) { c, x, y, i, _ in
            if i % 4 == 0 { snowflake(&c, x, y, 2, snow, behind: !front) } else { dot(&c, x, y, snow, behind: !front) }
        }
    }

    /// The tree's three tiers below the hat's brim: the tier's height above a point, light at its scalloped edge and
    /// darker down to the next one, a dusting of snow along each edge.
    private static func tree(_ p: EggSurfacePoint) -> C {
        let edges: [Double] = [0.24, -0.2, -0.6]
        var below: Double = 0
        for (k, e) in edges.enumerated() {
            let edge: Double = e + 0.07 * abs(sin(p.angle * 7))
            if p.y > edge - 0.5 || k == edges.count - 1 { below = edge - p.y; break }
        }
        if below < 0 { return green.mixed(with: .white, 0.12) }
        if below < 0.055 + 0.035 * abs(sin(p.angle * 14)) { return snow }
        let depth: Double = min(1, below / 0.5)
        let needles: Bool = sin(p.angle * 30 + p.y * 40) > 0.6
        return green.mixed(with: .white, max(0, 0.18 - depth * 0.4)).mixed(with: .black, depth * 0.45 + (needles ? 0.08 : 0))
    }

    /// The hat's brim: two rows of fluffy puffs.
    private static func brim(_ p: EggSurfacePoint) -> (dx: Double, dy: Double)? {
        EggDesigns.puff(p, count: 20, at: 0.32, radius: 0.1) ?? EggDesigns.puff(p, count: 20, at: 0.41, radius: 0.09, offset: 0.5)
    }

    /// The hat's tip: a tube tapering from the top of the hat, curving over to the side, the pom-pom at its very end,
    /// swinging with it.
    private static func hatTip(_ canvas: inout EggCanvas, _ f: EggFrame) {
        let swing: Double = 0.18 * sin(f.phase)
        let (sx, sy) = f.pixel(0, 0.9)
        let (cx, cy) = (sx + 7, sy - 7)
        let ex: Double = sx + 13 + 3 * cos(swing * 3), ey: Double = sy + 1 + 4 * sin(swing * 3)
        for k in 0...18 {
            let t: Double = Double(k) / 18
            let x: Double = (1 - t) * (1 - t) * sx + 2 * (1 - t) * t * cx + t * t * ex
            let y: Double = (1 - t) * (1 - t) * sy + 2 * (1 - t) * t * cy + t * t * ey
            canvas.ellipse(x, y, 5.5 - 3.5 * t, 5.5 - 3.5 * t, red.mixed(with: .black, 0.12 * t), gloss: 0.25)
        }
        canvas.ball(ex + 1, ey + 1.5, 4, snow, gloss: 0.15)
    }

    static var christmas: EggDesign {
        let lights: [C] = [red, gold, rgb(0x4DB8FF), rgb(0xFF7AE0)]
        var surface = EggSurface(albedo: { (p: EggSurfacePoint) -> C in
            if brim(p) != nil || abs(p.y - 0.36) < 0.08 { return snow }
            if p.y > 0.36 { return sin(p.angle * 3 + p.y * 4) > 0.7 ? red.mixed(with: .black, 0.18) : red }
            return tree(p)
        }, gloss: 0.3)
        surface.normal = { (n: EggVector, p: EggSurfacePoint) -> EggVector in EggDesigns.bulge(n, brim(p)) }
        surface.emission = { (p: EggSurfacePoint) -> C? in
            guard p.y < 0.22 else { return nil }
            let t = tile(p, size: 0.27)
            guard t.u * t.u + t.v * t.v < 0.004, h(t.i, t.j, 571) < 0.55 else { return nil }
            let k = abs(t.i * 7 + t.j * 3) % lights.count
            if t.u < -0.02 && t.v > 0.02 { return .white }
            return sin(p.phase * 2 + Double(k) * 1.6) > -0.3 ? lights[k] : lights[k].mixed(with: .black, 0.35)
        }
        return EggDesign(surface: surface, front: { canvas, f in
            hatTip(&canvas, f)
        }, outline: rgb(0x0F3020), glow: { canvas, f in
            snowfall(&canvas, f, front: false, count: 14)
            snowfall(&canvas, f, front: true, count: 6)
        })
    }

    // MARK: New Year: the mirror ball

    static var newYear: EggDesign {
        let silver = rgb(0xC9CED8)
        let surface = EggSurface(albedo: { (p: EggSurfacePoint) -> C in
            let (a, y) = EggDesigns.front(p)
            let ci: Double = a / 0.13 + 50, cj: Double = y / 0.13 + 50
            let i = Int(ci.rounded(.down)), j = Int(cj.rounded(.down))
            if sin(p.phase * 3 + Double(i * 5 + j * 3)) > 0.85 { return .white }
            if ci.truncatingRemainder(dividingBy: 1) < 0.12 || cj.truncatingRemainder(dividingBy: 1) < 0.12 {
                return silver.mixed(with: .black, 0.45)
            }
            return silver.mixed(with: .black, 0.25 * h(i, j, 504))
        }, gloss: 0.9, shininess: 80)
        let specks: [C] = [rgb(0xFF5FA2), rgb(0x6FD3FF), rgb(0xFFD54D), rgb(0x8CFF8C), rgb(0xB18CFF)]
        return EggDesign(surface: surface, front: { canvas, f in
            let (x, y) = f.pixel(0, 1.0)
            canvas.line(x, y, x, y - 8, width: 1, silver.mixed(with: .black, 0.3))
        }, outline: rgb(0x3A3F4A), glow: { canvas, f in
            for k in 0..<14 {
                let a: Double = Double(k) / 14 * 2 * .pi + f.phase
                let r: Double = 22 + 6 * h(k, 0, 505)
                dot(&canvas, 32 + cos(a) * r, 34 + sin(a) * r * 0.75, specks[k % specks.count], behind: true)
            }
        })
    }

    // MARK: Valentine's Day: the pearl and Cupid's arrow

    private static let pink = rgb(0xFF8FB8), loveRed = rgb(0xE5254F)

    static var valentine: EggDesign {
        let shaft = rgb(0xB0823F)
        let surface = EggSurface(albedo: { (p: EggSurfacePoint) -> C in
            let shift: Double = 0.5 + 0.5 * sin(p.normal.x * 3 + p.normal.y * 2 + p.phase)
            return pink.mixed(with: rgb(0xD9C7FF), shift * 0.6).mixed(with: .white, 0.35)
        }, gloss: 0.95, shininess: 90)
        return EggDesign(surface: surface, back: { canvas, f in
            let (x, y) = f.pixel(0, 0.1)
            let (sx, sy): (Double, Double) = (x - 25, y + 12 + 1.5 * sin(f.phase))
            canvas.line(sx + 3, sy - 1, x, y, width: 2.2, shaft)
            canvas.polygon([(sx - 2, sy - 5), (sx + 5, sy - 2), (sx - 3, sy + 3)], .white)
            canvas.polygon([(sx + 1, sy - 6), (sx + 8, sy - 3), (sx, sy + 2)], pink)
        }, front: { canvas, f in
            let (x, y) = f.pixel(0, 0.1)
            let (ex, ey): (Double, Double) = (x + 23, y - 11 - 1.5 * sin(f.phase))
            canvas.line(x + 8, y - 4, ex - 3, ey + 1.5, width: 2.2, shaft)
            heart(&canvas, ex, ey, 5, loveRed)
        }, outline: rgb(0x8A4A6A), glow: { canvas, f in
            rising(&canvas, f, count: 6, seed: 516, spread: 1.3) { c, x, y, i, age in
                guard age > 0.1 else { return }
                let s: Double = 2.5 + Double(i % 2)
                for dx in stride(from: -s, through: s, by: 0.5) {
                    for dy in stride(from: -s, through: s, by: 0.5) where inHeart(dx, -dy, s) && !inHeart(dx, -dy, s - 1) {
                        dot(&c, x + dx, y + dy, .white, behind: true)
                    }
                }
            }
        })
    }

    // MARK: Pokémon Day: the Pokédex

    static var pokemonDay: EggDesign {
        func lens(_ a: Double, _ y: Double) -> Double { ((a + 0.15) * (a + 0.15) + (y - 0.52) * (y - 0.52)).squareRoot() }
        var surface = EggSurface(albedo: { (p: EggSurfacePoint) -> C in
            let (a, y) = EggDesigns.front(p)
            if abs(y - 0.25) < 0.025 { return rgb(0x8A1010) }
            return lens(a, y) < 0.17 ? .white : rgb(0xDC1E2A)
        }, gloss: 0.6)
        surface.emission = { (p: EggSurfacePoint) -> C? in
            let (a, y) = EggDesigns.front(p)
            if lens(a, y) < 0.13 { return sin(p.phase * 3) > 0 ? rgb(0x5FD3FF) : rgb(0x2A7FD0) }
            let lights: [(Double, C)] = [(0.12, rgb(0xFF4040)), (0.24, rgb(0xFFD040)), (0.36, rgb(0x40D060))]
            for (x, c) in lights where (a - x) * (a - x) + (y - 0.6) * (y - 0.6) < 0.0025 { return c }
            return nil
        }
        return EggDesign(surface: surface, outline: rgb(0x4A0606))
    }

    // MARK: Easter: the bunny in the flowery basket

    static var easter: EggDesign {
        let wicker = rgb(0xC98F4E)
        let dark: C = wicker.mixed(with: .black, 0.3), light: C = wicker.mixed(with: .white, 0.25)
        let pastel: [C] = [rgb(0xFFB3C7), rgb(0xB5E3FF), rgb(0xFFF0A3), rgb(0xBDF5C8), rgb(0xD9C7FF)]
        let surface = EggSurface(albedo: { (p: EggSurfacePoint) -> C in
            let (a, y) = EggDesigns.front(p)
            return a * a + (y - 0.05) * (y - 0.05) < 0.003 ? rgb(0xFF8FB0) : rgb(0xFAFAFA)
        }, gloss: 0.3)
        return EggDesign(surface: surface, back: { canvas, f in
            // The handle, braided, arching behind the egg.
            let (x, y) = f.pixel(0, -0.32)
            var arc: [(Double, Double)] = []
            for k in 0...24 {
                let a: Double = .pi + Double(k) / 24 * .pi
                arc.append((x + cos(a) * 26, y + sin(a) * 30))
            }
            canvas.path(arc, width: 3.2, dark)
            canvas.path(arc, width: 1.6, light)
            // The ears, leaning out a little, one twitching.
            for (k, side) in [-1.0, 1.0].enumerated() {
                let twitch: Double = k == 1 ? 0.15 * max(0, sin(f.phase * 2)) : 0
                let (ex, ey) = f.pixel(side * 0.3, 0.86)
                let tilt: Double = -side * 0.42 - side * twitch
                canvas.ellipse(ex + side * 3, ey - 5, 3.4, 6.6, angle: tilt, rgb(0xFAFAFA), gloss: 0.2)
                canvas.ellipse(ex + side * 3, ey - 5, 1.7, 4.8, angle: tilt, rgb(0xFFB3C7), flat: true)
            }
        }, front: { canvas, f in
            let (x, y) = f.pixel(0, -0.32)
            // The basket: a bowl, wider at the rim, woven in rows and stakes.
            canvas.fill(x - 25, y, x + 25, y + 18) { (px: Double, py: Double) -> C? in
                let rel: Double = (py - y) / 18
                let half: Double = 25 - rel * rel * 7
                guard abs(px - x) < half else { return nil }
                let row = Int((py - y) / 3)
                if Int(px - x + 100) % 5 == 0 { return dark }
                let over: Bool = ((Int(px - x + 100) / 5) + row).isMultiple(of: 2)
                return (over ? light : wicker).mixed(with: .black, abs(px - x) / half * 0.25 + (Int(py) % 3 == 0 ? 0.15 : 0))
            }
            // Its braided rim, the grass spilling over it, the flowers.
            for k in 0..<26 {
                canvas.ellipse(x - 25 + Double(k) * 2, y + (k.isMultiple(of: 2) ? 0 : 1), 1.6, 1.4,
                               k.isMultiple(of: 2) ? light : dark, gloss: 0.3)
            }
            for k in 0..<18 {
                let gx: Double = x - 22 + Double(k) * 2.6
                canvas.line(gx, y + 1, gx + 1.5 * sin(Double(k) + f.phase), y - 4 - Double(k % 3), width: 1, rgb(0x5DBB5D))
            }
            for (k, dx) in [-17.0, -6, 8, 18].enumerated() { flower(&canvas, x + dx, y - 3, pastel[k % pastel.count], rgb(0xFFD84D)) }
        }, outline: rgb(0x7A6A70))
    }

    // MARK: Halloween: the jack-o'-lantern

    static var halloween: EggDesign {
        let pumpkin = rgb(0xF5821F)
        var surface = EggSurface(albedo: { (p: EggSurfacePoint) -> C in
            pumpkin.mixed(with: rgb(0xB8520A), abs(sin(p.angle * 4)) < 0.15 ? 0.6 : 0)
        }, gloss: 0.45)
        surface.normal = { (n: EggVector, p: EggSurfacePoint) -> EggVector in
            EggLight.normalize((n.x + 0.25 * sin(p.angle * 8), n.y, n.z))
        }
        surface.emission = { (p: EggSurfacePoint) -> C? in
            let (a, y) = EggDesigns.front(p)
            let flicker: C = sin(p.phase * 7) > 0 ? rgb(0xFFE36B) : rgb(0xFFB02E)
            for side in [-1.0, 1.0] {
                let ex: Double = a - side * 0.21, ey: Double = y - 0.18
                if ey > -0.1 && ey < 0.12 && abs(ex) < (0.12 - ey) * 0.75 { return flicker }
            }
            let mouth: Double = y + 0.22 + 0.06 * abs(sin(a * 14))
            return abs(mouth) < 0.08 && abs(a) < 0.36 ? flicker : nil
        }
        return EggDesign(surface: surface, front: { canvas, f in
            let (x, y) = f.pixel(0, 1.0)
            canvas.line(x, y, x + 2, y - 6, width: 2.4, rgb(0x5A6A2A))
            leaf(&canvas, x - 4, y - 3, 0.5, rgb(0x4A8A3A), size: 3)
        }, outline: rgb(0x4A2006))
    }

    // MARK: The friendship anniversary: the hot-air balloon

    static var companion: EggDesign {
        let gores: [C] = [rgb(0xFFB3C7), rgb(0xFFF0A3), rgb(0xB5E3FF), rgb(0xBDF5C8)]
        let surface = EggSurface(albedo: { (p: EggSurfacePoint) -> C in
            gores[Int((p.angle / (2 * .pi) * 8 + 16).rounded(.down)) % gores.count]
        }, gloss: 0.55)
        var design = EggDesign(surface: surface, back: { canvas, f in
            // Clouds drifting by, one whole width per loop so they come back where they left.
            for k in 0..<2 {
                let x: Double = (Double(k) * 42 + f.t * 84).truncatingRemainder(dividingBy: 84) - 12
                let y: Double = 12 + Double(k) * 30
                canvas.ellipse(x, y, 7, 3, .white, flat: true)
                canvas.ellipse(x + 4, y - 2, 4, 3, .white, flat: true)
            }
        }, front: { canvas, f in
            let (x, y) = f.pixel(0, -1.0)
            let swing: Double = 1.2 * sin(f.phase)
            canvas.line(x - 5, y, x - 4 + swing, y + 6, width: 0.8, rgb(0x6A4A2A))
            canvas.line(x + 5, y, x + 4 + swing, y + 6, width: 0.8, rgb(0x6A4A2A))
            canvas.fill(x - 5 + swing, y + 6, x + 5 + swing, y + 11) { (_: Double, py: Double) -> C? in
                Int(py).isMultiple(of: 2) ? rgb(0xC98F4E) : rgb(0xA86E35)
            }
        }, outline: rgb(0x5A4A6A))
        design.scale = 0.8
        design.center = 30
        return design
    }

    // MARK: The seasons: their weather around an egg wearing the season's motif

    private static func ground(_ s: EventEgg) -> C {
        switch s {
        case .spring: return rgb(0xFFB7D5).mixed(with: .white, 0.15)
        case .summer: return rgb(0x7FD36B).mixed(with: .white, 0.15)
        case .autumn: return rgb(0xF08A3A).mixed(with: .white, 0.15)
        default: return rgb(0x8DB6E6)
        }
    }

    /// The season's motif around a point, `size` across its half: a flower, a sun, a leaf, a snowflake.
    static func motif(_ s: EventEgg, _ u: Double, _ v: Double, size: Double) -> C? {
        let r: Double = (u * u + v * v).squareRoot(), a: Double = atan2(v, u)
        switch s {
        case .spring:
            if r < size * 0.22 { return rgb(0xFFD84D) }
            return r < size * (0.5 + 0.5 * abs(cos(a * 2.5))) ? rgb(0xFF8FB8) : nil
        case .summer:
            if r < size * 0.42 { return rgb(0xFFD84D) }
            return r < size && abs(sin(a * 4)) < 0.28 ? rgb(0xFF9F2E) : nil
        case .autumn:
            let lu: Double = (u + v) / 1.414, lv: Double = (v - u) / 1.414
            guard lu * lu / (size * size) + lv * lv / (size * size * 0.18) < 1 else { return nil }
            return abs(lv) < size * 0.07 ? rgb(0x8A3A1A) : rgb(0xE8632B)
        default:
            guard r < size else { return nil }
            for k in 0..<3 {
                let b: Double = Double(k) * .pi / 3
                if abs(u * sin(b) - v * cos(b)) < size * 0.1 { return .white }
            }
            return nil
        }
    }

    static func season(_ s: EventEgg) -> EggDesign {
        let base: C = ground(s)
        let surface = EggSurface(albedo: { (p: EggSurfacePoint) -> C in
            let shade: C = base.mixed(with: .white, 0.2 * (p.y + 1) / 2)
            let (a, y) = EggDesigns.front(p)
            if let big = motif(s, a, y - 0.05, size: 0.42) { return big }
            let t = tile(p, size: 0.32)
            guard h(t.i, t.j, 592) < 0.35, abs(a) > 0.45 || abs(y - 0.05) > 0.45 else { return shade }
            return motif(s, t.u, t.v, size: 0.07) ?? shade
        }, gloss: 0.55)
        return EggDesign(surface: surface, outline: base.mixed(with: .black, 0.6), glow: { canvas, f in
            switch s {
            case .spring:
                falling(&canvas, f, count: 14, seed: 561, speed: 2, sway: 0) { c, x, y, _, _ in
                    dot(&c, x, y, rgb(0x7FB8FF), behind: true)
                    dot(&c, x, y + 1, rgb(0x7FB8FF), behind: true)
                }
            case .summer:
                rays(&canvas, 32, 34, count: 16, inner: 26, outer: 31, rgb(0xFFD84D), turn: f.phase / 4)
            case .autumn:
                for k in 0..<3 {
                    let y: Double = 14 + Double(k) * 16, off: Double = (f.t * 84 + Double(k) * 28).truncatingRemainder(dividingBy: 84) - 10
                    for dx in stride(from: 0.0, to: 14, by: 1) { dot(&canvas, off + dx, y + 2 * sin((off + dx) / 4), rgb(0xE8E0D0), behind: true) }
                }
                falling(&canvas, f, count: 9, seed: 553, sway: 5) { c, x, y, i, age in
                    leaf(&c, x, y, age * 6 + Double(i), [rgb(0xE8632B), rgb(0xF2A93B), rgb(0xB8342A)][i % 3], size: 2.4)
                }
            default:
                falling(&canvas, f, count: 14, seed: 554) { c, x, y, i, _ in
                    if i % 4 == 0 { snowflake(&c, x, y, 2, .white, behind: true) } else { dot(&c, x, y, .white, behind: i % 2 == 0) }
                }
            }
        })
    }
}
