import AppKit
import SwiftUI

/// The egg's shape: a surface of revolution about the vertical axis. `radius(y)` for y from -1 (bottom) to 1 (top),
/// widest a little below the middle, narrower toward the top, like a hen's egg.
enum EggProfile {
    /// Width over height.
    static let aspect: Double = 0.76
    /// How much narrower the top is than the bottom.
    static let taper: Double = 0.2

    /// The radius at height `y`, for a height of 2 (y in -1...1).
    static func radius(_ y: Double) -> Double {
        guard abs(y) < 1 else { return 0 }
        return aspect * (1 - y * y).squareRoot() * (1 - taper * y)
    }

    /// d radius / dy.
    static func slope(_ y: Double) -> Double {
        let s = max(1e-6, (1 - y * y).squareRoot())
        return aspect * ((-y / s) * (1 - taper * y) - taper * s)
    }
}

/// The egg's outline in a box (the glow of the rarer eggs).
struct EggShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = rect.height / 2, cx = rect.midX, cy = rect.midY
        var p = Path()
        let steps = 64
        for i in 0...steps {
            let y = 1 - 2 * Double(i) / Double(steps)
            let point = CGPoint(x: cx + EggProfile.radius(y) * scale, y: cy - y * scale)
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        for i in (0...steps).reversed() {
            let y = 1 - 2 * Double(i) / Double(steps)
            p.addLine(to: CGPoint(x: cx - EggProfile.radius(y) * scale, y: cy - y * scale))
        }
        p.closeSubpath()
        return p
    }
}

/// Which egg it is: what it guarantees decides its look. A plain egg and a type's egg have spots on a cream shell, in
/// the type's color for a type; a rarity's egg has a shell in the rarity's color with cream spots.
enum EggKind: Hashable, Sendable {
    case plain
    case tier(Rarity)
    case type(PokemonType)
    /// The Type: Null Egg, reward for all of Silvally's Memories.
    case typeNull

    /// The egg a guarantee hatches from: the type when there is one, else the rarity.
    init(tier: Rarity?, type: PokemonType? = nil) {
        if let type { self = .type(type) } else if let tier { self = .tier(tier) } else { self = .plain }
    }

    var isColoredShell: Bool { if case .tier = self { return true } else { return false } }

    /// What is painted on the shell.
    var pattern: EggPattern { self == .typeNull ? .helmetChimera : .spots }

    /// Cream, the rarity's color, or cream barely tinted with the type's.
    var shell: EggColor {
        switch self {
        case .plain: return .cream
        case .tier(let rarity): return EggColor(rarityColor(rarity)).mixed(with: .white, 0.12)
        case .type(let type): return EggColor.cream.mixed(with: EggColor(type.color), 0.1)
        case .typeNull: return EggColor(0.84, 0.84, 0.86)
        }
    }

    var marks: EggColor {
        switch self {
        case .plain: return .eggGreen
        case .tier: return .cream
        case .type(let type): return EggColor(type.color)
        case .typeNull: return EggColor(0.33, 0.35, 0.40)
        }
    }

    /// The rarer guarantees glow in their color.
    var glow: Color? {
        if case .tier(let rarity) = self { return rarityColor(rarity) }
        return nil
    }
}

/// What the renderer paints on the shell.
enum EggPattern: CaseIterable, Hashable, Sendable {
    /// Round spots in `EggKind.marks`.
    case spots
    /// A riveted metal helmet over the top, like Type: Null's mask.
    case helmet
    /// Steel plates: a seam down the front and around the middle, rivets along them.
    case riveted
    /// Spots in many types' colors: the egg gathers every Memory.
    case chimera
    /// The helmet over the top, the many-colored spots below.
    case helmetChimera
}

/// An sRGB color the renderer can mix per pixel.
struct EggColor: Hashable, Sendable {
    var r, g, b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    init(_ color: Color) {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .gray
        self.init(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
    }
    func mixed(with other: EggColor, _ t: Double) -> EggColor {
        EggColor(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
    }
    static let white = EggColor(1, 1, 1)
    static let black = EggColor(0, 0, 0)
    static let cream = EggColor(0.98, 0.95, 0.86)
    static let eggGreen = EggColor(0.45, 0.76, 0.42)
}

/// The egg drawn like the 3D sprites around it, rendered once per kind: per pixel, the front of the egg lit from the
/// top left with a soft two-tone diffuse, a small highlight and a rim light, spots painted on the surface so they follow
/// its curve; hard edges and a one-pixel dark outline, the GIFs' grain. Its idle loop floats it gently and turns it a
/// little on itself; SpriteView plays it like a GIF.
enum EggRenderer {
    /// Pixels across: about a small Pokémon's GIF (Togepi's), the sprites' own density.
    static let pixels = 52
    /// The idle loop: frames and their delay (about 2.2 s).
    static let frameCount = 24
    static let frameDelay: TimeInterval = 0.09

    @MainActor private static var stills: [EggKind: NSImage] = [:]
    @MainActor private static var loops: [EggKind: [(image: NSImage, delay: TimeInterval)]] = [:]

    /// The egg at rest: the first frame of its loop.
    @MainActor
    static func still(_ kind: EggKind) -> NSImage {
        if let cached = stills[kind] { return cached }
        let image = nsImage(render(kind, yaw: 0, tilt: 0, lift: 0))
        stills[kind] = image
        return image
    }

    /// The idle loop: up and down by two pixels, turning ±30° on itself, rocking ±5°.
    @MainActor
    static func idleFrames(_ kind: EggKind) -> [(image: NSImage, delay: TimeInterval)] {
        if let cached = loops[kind] { return cached }
        let frames = (0..<frameCount).map { i -> (image: NSImage, delay: TimeInterval) in
            let phase = 2 * Double.pi * Double(i) / Double(frameCount)
            let image = nsImage(render(kind, yaw: 0.52 * sin(phase), tilt: 0.09 * cos(phase),
                                       lift: Int((2 * sin(phase)).rounded())))
            return (image, frameDelay)
        }
        loops[kind] = frames
        return frames
    }

    private static func nsImage(_ image: CGImage?) -> NSImage {
        guard let image else { return NSImage(size: NSSize(width: pixels, height: pixels)) }
        return NSImage(cgImage: image, size: NSSize(width: pixels, height: pixels))
    }

    /// Spots as surface positions: (angle around the axis in radians, 0 facing the viewer; height y; radius).
    static let spots: [(Double, Double, Double)] = [
        (-0.55, 0.15, 0.22), (0.62, 0.42, 0.17), (0.48, -0.32, 0.25), (-0.35, -0.55, 0.19), (0.05, 0.72, 0.12),
        (-1.15, -0.1, 0.16), (1.2, 0.05, 0.15), (0.0, -0.05, 0.1), (-0.8, 0.62, 0.11), (2.0, 0.3, 0.2),
        (-2.1, -0.3, 0.2), (2.9, -0.2, 0.22), (1.7, -0.6, 0.15), (-1.9, 0.55, 0.13),
    ]

    /// One frame. `yaw` turns the egg about its axis (radians), `tilt` rocks it in the image plane, `lift` raises it.
    /// `pattern` overrides the kind's (design proposals).
    static func render(_ kind: EggKind, pattern: EggPattern? = nil, yaw: Double, tilt: Double, lift: Int) -> CGImage? {
        let pattern = pattern ?? kind.pattern
        let n = pixels
        var data = [UInt8](repeating: 0, count: n * n * 4)
        // The egg's height (2 units) spans 44 of the 52 pixels: room to float and rock.
        let unitsPerPixel = 2 / 44.0
        let light = normalize((-0.55, 0.62, 0.56))
        let half = normalize((light.0, light.1, light.2 + 1))
        // Glossier: the colored shells and metal.
        let colored = kind.isColoredShell || pattern == .helmet || pattern == .riveted || pattern == .helmetChimera
        let shell = kind.shell, marks = kind.marks
        let painter = SurfacePainter(pattern: pattern, shell: shell, marks: marks)
        let (sinT, cosT) = (sin(tilt), cos(tilt))
        let (sinY, cosY) = (sin(yaw), cos(yaw))
        let samples = [(-0.25, -0.25), (0.25, -0.25), (-0.25, 0.25), (0.25, 0.25)]
        for py in 0..<n {
            for px in 0..<n {
                var rgb = (0.0, 0.0, 0.0)
                var coverage = 0.0
                for (sx, sy) in samples {
                    let u = (Double(px) + 0.5 + sx - Double(n) / 2) * unitsPerPixel
                    let v = (Double(n) / 2 - Double(py) - 0.5 - sy - Double(lift)) * unitsPerPixel + 0.04
                    // Into the egg's frame: undo the rock.
                    let x = u * cosT + v * sinT, y = -u * sinT + v * cosT
                    let r = EggProfile.radius(y)
                    guard r > 0, abs(x) < r else { continue }
                    let z = (r * r - x * x).squareRoot()
                    let n0 = normalize((x, -r * EggProfile.slope(y), z))
                    // The normal back into the image's frame: the light stays put.
                    let normal = (n0.0 * cosT - n0.1 * sinT, n0.0 * sinT + n0.1 * cosT, n0.2)
                    // The surface turned by the yaw carries the marks.
                    let albedo = painter.color(x: x * cosY + z * sinY, y: y, z: -x * sinY + z * cosY)
                    let nl = normal.0 * light.0 + normal.1 * light.1 + normal.2 * light.2
                    let diffuse = 0.6 + 0.4 * smoothstep(-0.15, 0.4, nl)
                    let nh = max(0, normal.0 * half.0 + normal.1 * half.1 + normal.2 * half.2)
                    let specular = pow(nh, colored ? 60 : 40) * (colored ? 0.55 : 0.4)
                    let rim = pow(1 - max(0, normal.2), 3) * 0.16
                    let shade = diffuse * (0.88 + 0.12 * smoothstep(-1, -0.2, y))
                    rgb.0 += min(1, albedo.r * shade + specular + rim * 0.85)
                    rgb.1 += min(1, albedo.g * shade + specular + rim * 0.9)
                    rgb.2 += min(1, albedo.b * shade + specular + rim)
                    coverage += 1
                }
                // Hard edges like the GIF sprites: a pixel is egg or not.
                guard coverage >= Double(samples.count) / 2 else { continue }
                let i = (py * n + px) * 4
                data[i] = UInt8(min(255, rgb.0 / coverage * 255))
                data[i + 1] = UInt8(min(255, rgb.1 / coverage * 255))
                data[i + 2] = UInt8(min(255, rgb.2 / coverage * 255))
                data[i + 3] = 255
            }
        }
        outline(&data, n: n, color: (pattern == .spots || pattern == .chimera ? shell : marks).mixed(with: .black, 0.7))
        let provider = CGDataProvider(data: Data(data) as CFData)
        return provider.flatMap {
            CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                    provider: $0, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
    }

    /// The shell's color at a point of its surface, for one pattern.
    private struct SurfacePainter {
        let pattern: EggPattern
        let shell: EggColor
        let marks: EggColor
        /// The many-colored spots: Fire, Water, Grass, Electric, Psychic, Dragon, Fairy, Dark, cycling.
        let chimeraColors: [EggColor] = [PokemonType.fire, .water, .grass, .electric, .psychic, .dragon, .fairy, .dark]
            .map { EggColor($0.color) }
        static let steel = EggColor(0.36, 0.38, 0.43)
        static let steelLight = EggColor(0.62, 0.64, 0.69)
        static let rivet = EggColor(0.86, 0.85, 0.80)
        static let seam = EggColor(0.22, 0.23, 0.27)

        func color(x: Double, y: Double, z: Double) -> EggColor {
            let angle = atan2(x, z)
            switch pattern {
            case .spots:
                return shell.mixed(with: marks, spot(x, y, z).mask)
            case .chimera:
                return chimera(x, y, z)
            case .helmet:
                return helmet(angle: angle, y: y) ?? shell
            case .helmetChimera:
                return helmet(angle: angle, y: y) ?? chimera(x, y, z)
            case .riveted:
                let gray = EggColor(0.62, 0.64, 0.68)
                // A seam down the front and one around the middle, rivets along both.
                let front = abs(angle) < 0.07, middle = abs(y + 0.05) < 0.025
                if front || middle { return Self.seam }
                for k in -6...6 {
                    let ry = -0.05 + 0.18 * Double(k)
                    if abs(ry) < 0.95, distance(angle: angle, y: y, toAngle: 0.17, y: ry) < 0.045 { return Self.rivet }
                    if abs(ry) < 0.95, distance(angle: angle, y: y, toAngle: -0.17, y: ry) < 0.045 { return Self.rivet }
                }
                for k in 0..<16 where distance(angle: angle, y: y, toAngle: Double(k) * .pi / 8, y: 0.06) < 0.045 {
                    return Self.rivet
                }
                return gray
            }
        }

        /// The helmet over the top: its rim waves a little, rivets line it, a ridge runs up the front.
        private func helmet(angle: Double, y: Double) -> EggColor? {
            let rim = 0.1 + 0.06 * cos(angle)
            guard y > rim else { return nil }
            if y < rim + 0.035 { return Self.seam }
            for k in 0..<12 where distance(angle: angle, y: y, toAngle: Double(k) * .pi / 6, y: rim + 0.11) < 0.045 {
                return Self.rivet
            }
            if abs(angle) < 0.13, y > rim + 0.16 { return Self.steelLight }
            return Self.steel
        }

        private func chimera(_ x: Double, _ y: Double, _ z: Double) -> EggColor {
            let hit = spot(x, y, z)
            return shell.mixed(with: chimeraColors[hit.index % chimeraColors.count], hit.mask)
        }

        /// The nearest spot covering this point, and how much it covers it.
        private func spot(_ x: Double, _ y: Double, _ z: Double) -> (mask: Double, index: Int) {
            var best = (mask: 0.0, index: 0)
            for (index, (theta, sy, radius)) in EggRenderer.spots.enumerated() {
                let sr = EggProfile.radius(sy)
                let dx = x - sr * sin(theta), dy = y - sy, dz = z - sr * cos(theta)
                let mask = 1 - EggRenderer.smoothstep(radius * 0.86, radius, (dx * dx + dy * dy + dz * dz).squareRoot())
                if mask > best.mask { best = (mask, index) }
            }
            return best
        }

        /// Distance on the surface's map (angle around, height), the angle weighted by the radius there.
        private func distance(angle: Double, y: Double, toAngle target: Double, y ty: Double) -> Double {
            var d = abs(angle - target).truncatingRemainder(dividingBy: 2 * .pi)
            if d > .pi { d = 2 * .pi - d }
            let r = EggProfile.radius(y)
            return ((d * r) * (d * r) + (y - ty) * (y - ty)).squareRoot()
        }
    }

    /// The models' fine dark outline: every egg pixel next to an empty one.
    private static func outline(_ data: inout [UInt8], n: Int, color: EggColor) {
        func isEmpty(_ x: Int, _ y: Int, _ data: [UInt8]) -> Bool {
            if x < 0 || y < 0 || x >= n || y >= n { return true }
            return data[(y * n + x) * 4 + 3] == 0
        }
        var edge: [Int] = []
        for py in 0..<n {
            for px in 0..<n where !isEmpty(px, py, data) {
                if isEmpty(px - 1, py, data) || isEmpty(px + 1, py, data)
                    || isEmpty(px, py - 1, data) || isEmpty(px, py + 1, data) {
                    edge.append((py * n + px) * 4)
                }
            }
        }
        for i in edge {
            data[i] = UInt8(color.r * 255); data[i + 1] = UInt8(color.g * 255); data[i + 2] = UInt8(color.b * 255)
        }
    }

    private static func normalize(_ v: (Double, Double, Double)) -> (Double, Double, Double) {
        let l = max(1e-9, (v.0 * v.0 + v.1 * v.1 + v.2 * v.2).squareRoot())
        return (v.0 / l, v.1 / l, v.2 / l)
    }
    fileprivate static func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - e0) / (e1 - e0)))
        return t * t * (3 - 2 * t)
    }
}

extension CompanionStore {
    /// The egg being incubated: what it guarantees decides its look.
    var eggKind: EggKind { EggKind(tier: eggGuarantee, type: eggTypeGuarantee) }
}
