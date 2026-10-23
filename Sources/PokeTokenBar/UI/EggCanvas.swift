import AppKit
import CoreGraphics

typealias EggVector = (x: Double, y: Double, z: Double)

/// A pixel canvas for the custom eggs: hard-edged shapes painted pixel by pixel, lit like the 3D sprites, then one
/// dark outline around everything.
struct EggCanvas {
    let size: Int
    private(set) var pixels: [UInt8]

    init(size: Int) {
        self.size = size
        pixels = [UInt8](repeating: 0, count: size * size * 4)
    }

    func isEmpty(_ x: Int, _ y: Int) -> Bool {
        if x < 0 || y < 0 || x >= size || y >= size { return true }
        return pixels[(y * size + x) * 4 + 3] == 0
    }

    mutating func set(_ x: Int, _ y: Int, _ c: EggColor) {
        guard x >= 0, y >= 0, x < size, y < size else { return }
        let i = (y * size + x) * 4
        pixels[i] = UInt8(max(0, min(255, c.r * 255)))
        pixels[i + 1] = UInt8(max(0, min(255, c.g * 255)))
        pixels[i + 2] = UInt8(max(0, min(255, c.b * 255)))
        pixels[i + 3] = 255
    }

    mutating func clear(_ x: Int, _ y: Int) {
        guard x >= 0, y >= 0, x < size, y < size else { return }
        let i = (y * size + x) * 4
        pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0; pixels[i + 3] = 0
    }

    /// Paints every pixel of the box whose center the shader colors.
    mutating func fill(_ minX: Double, _ minY: Double, _ maxX: Double, _ maxY: Double,
                       _ shader: (Double, Double) -> EggColor?) {
        let x0 = max(0, Int(minX.rounded(.down))), x1 = min(size - 1, Int(maxX.rounded(.up)))
        let y0 = max(0, Int(minY.rounded(.down))), y1 = min(size - 1, Int(maxY.rounded(.up)))
        guard x0 <= x1, y0 <= y1 else { return }
        for y in y0...y1 {
            for x in x0...x1 {
                if let c = shader(Double(x) + 0.5, Double(y) + 0.5) { set(x, y, c) }
            }
        }
    }

    /// A ball, lit like a sphere.
    mutating func ball(_ cx: Double, _ cy: Double, _ r: Double, _ color: EggColor, gloss: Double = 0.25) {
        fill(cx - r, cy - r, cx + r, cy + r) { x, y in
            let nx = (x - cx) / r, ny = (cy - y) / r
            guard nx * nx + ny * ny <= 1 else { return nil }
            return EggLight.shade(color, nx: nx, ny: ny, gloss: gloss)
        }
    }

    /// An ellipse turned by `angle` (radians, counterclockwise), lit like a flattened ball.
    mutating func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, angle: Double = 0,
                          _ color: EggColor, gloss: Double = 0.15, flat: Bool = false) {
        let (s, c) = (sin(angle), cos(angle))
        let r = max(rx, ry)
        fill(cx - r, cy - r, cx + r, cy + r) { x, y in
            let dx = x - cx, dy = cy - y
            let lx = (dx * c + dy * s) / rx, ly = (-dx * s + dy * c) / ry
            guard lx * lx + ly * ly <= 1 else { return nil }
            if flat { return color }
            return EggLight.shade(color, nx: lx * c - ly * s, ny: lx * s + ly * c, gloss: gloss)
        }
    }

    /// A filled polygon (points in pixels), shaded light toward its top left.
    mutating func polygon(_ points: [(Double, Double)], _ color: EggColor, shade: Bool = true) {
        guard points.count > 2 else { return }
        let xs = points.map(\.0), ys = points.map(\.1)
        let (minX, maxX, minY, maxY) = (xs.min()!, xs.max()!, ys.min()!, ys.max()!)
        let w = max(1, maxX - minX), h = max(1, maxY - minY)
        fill(minX, minY, maxX, maxY) { x, y in
            guard Self.contains(points, x, y) else { return nil }
            guard shade else { return color }
            // Lighter toward the top left of the shape, darker toward its bottom right.
            let t = ((x - minX) / w + (y - minY) / h) / 2
            return color.mixed(with: .white, max(0, 0.25 - t * 0.5)).mixed(with: .black, max(0, (t - 0.55) * 0.5))
        }
    }

    /// A thick segment.
    mutating func line(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, width: Double, _ color: EggColor) {
        let half = width / 2
        fill(min(x0, x1) - half, min(y0, y1) - half, max(x0, x1) + half, max(y0, y1) + half) { x, y in
            let vx = x1 - x0, vy = y1 - y0
            let t = max(0, min(1, ((x - x0) * vx + (y - y0) * vy) / max(1e-9, vx * vx + vy * vy)))
            let dx = x - (x0 + t * vx), dy = y - (y0 + t * vy)
            return dx * dx + dy * dy <= half * half ? color : nil
        }
    }

    /// A polyline of thick segments.
    mutating func path(_ points: [(Double, Double)], width: Double, _ color: EggColor) {
        for (a, b) in zip(points, points.dropFirst()) { line(a.0, a.1, b.0, b.1, width: width, color) }
    }

    /// A flame: a round base, a tongue tapering to its tip; three nested colors from the edge in.
    mutating func flame(baseX: Double, baseY: Double, height: Double, width: Double, lean: Double,
                        outer: EggColor, middle: EggColor, core: EggColor) {
        for (scale, color) in [(1.0, outer), (0.68, middle), (0.38, core)] {
            let h = height * scale, w = width * scale
            let tipX = baseX + lean * h, tipY = baseY - h
            fill(min(baseX, tipX) - w, tipY, max(baseX, tipX) + w, baseY + w) { x, y in
                // Position along the flame (0 at the base, 1 at the tip) and across it.
                let t = (baseY - y) / max(1, h)
                let axis = baseX + lean * h * max(0, t)
                if t < 0 {
                    let dx = x - baseX, dy = y - baseY
                    return dx * dx + dy * dy <= w * w ? color : nil
                }
                guard t <= 1 else { return nil }
                return abs(x - axis) <= w * pow(1 - t, 0.8) ? color : nil
            }
        }
    }

    /// A four-point sparkle.
    mutating func sparkle(_ cx: Double, _ cy: Double, _ r: Double, _ color: EggColor) {
        fill(cx - r, cy - r, cx + r, cy + r) { x, y in
            let dx = abs(x - cx), dy = abs(y - cy)
            return (dx < 0.9 && dy <= r) || (dy < 0.9 && dx <= r) || (dx + dy <= r * 0.45) ? color : nil
        }
    }

    static func contains(_ points: [(Double, Double)], _ x: Double, _ y: Double) -> Bool {
        var inside = false
        var j = points.count - 1
        for i in 0..<points.count {
            let (xi, yi) = points[i], (xj, yj) = points[j]
            if (yi > y) != (yj > y), x < (xj - xi) * (y - yi) / (yj - yi) + xi { inside.toggle() }
            j = i
        }
        return inside
    }

    /// The models' fine dark outline: every painted pixel next to an empty one.
    mutating func outline(_ color: EggColor) {
        var edge: [(Int, Int)] = []
        for y in 0..<size {
            for x in 0..<size where !isEmpty(x, y) {
                if isEmpty(x - 1, y) || isEmpty(x + 1, y) || isEmpty(x, y - 1) || isEmpty(x, y + 1) { edge.append((x, y)) }
            }
        }
        for (x, y) in edge { set(x, y, color) }
    }

    func image() -> CGImage? {
        let provider = CGDataProvider(data: Data(pixels) as CFData)
        return provider.flatMap {
            CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                    provider: $0, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
    }
}

/// The light the eggs and their decorations share: from the top left and front.
enum EggLight {
    static let direction: EggVector = normalize((-0.55, 0.62, 0.56))
    static let half: EggVector = normalize((direction.x, direction.y, direction.z + 1))

    /// A color lit at a normal: two soft tones like the models' toon shading, a highlight, a cool rim.
    static func shade(_ albedo: EggColor, normal n: EggVector, gloss: Double = 0.4, shininess: Double = 40,
                      occlusion: Double = 1) -> EggColor {
        let nl = n.x * direction.x + n.y * direction.y + n.z * direction.z
        let diffuse = (0.6 + 0.4 * smoothstep(-0.15, 0.4, nl)) * occlusion
        let nh = max(0, n.x * half.x + n.y * half.y + n.z * half.z)
        let specular = pow(nh, shininess) * gloss
        let rim = pow(1 - max(0, n.z), 3) * 0.16
        return EggColor(min(1, albedo.r * diffuse + specular + rim * 0.85),
                        min(1, albedo.g * diffuse + specular + rim * 0.9),
                        min(1, albedo.b * diffuse + specular + rim))
    }

    /// A ball's normal from a point of its disc (`nx`, `ny` in -1...1, y up).
    static func shade(_ albedo: EggColor, nx: Double, ny: Double, gloss: Double) -> EggColor {
        let nz = max(0, 1 - nx * nx - ny * ny).squareRoot()
        return shade(albedo, normal: (nx, ny, nz), gloss: gloss, shininess: 30)
    }

    static func normalize(_ v: EggVector) -> EggVector {
        let l = max(1e-9, (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot())
        return (v.x / l, v.y / l, v.z / l)
    }

    static func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - e0) / (e1 - e0)))
        return t * t * (3 - 2 * t)
    }

    /// Deterministic value noise in 0...1.
    static func noise(_ x: Double, _ y: Double) -> Double {
        func hash(_ i: Int, _ j: Int) -> Double {
            var h = UInt64(bitPattern: Int64(i &* 374_761_393 &+ j &* 668_265_263))
            h = (h ^ (h >> 13)) &* 1_274_126_177
            return Double((h ^ (h >> 16)) & 0xFFFF) / 65535
        }
        let xi = Int(x.rounded(.down)), yi = Int(y.rounded(.down))
        let fx = x - Double(xi), fy = y - Double(yi)
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        let a = hash(xi, yi), b = hash(xi + 1, yi), c = hash(xi, yi + 1), d = hash(xi + 1, yi + 1)
        return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy
    }
}
