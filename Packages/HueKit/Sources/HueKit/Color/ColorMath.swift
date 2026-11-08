import Foundation

/// Linear-ish RGB triple with components in 0...1.
public struct RGB: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let white = RGB(red: 1, green: 1, blue: 1)
}

/// Conversions between sRGB, CIE xy and color temperature, following Signify's
/// "Color conversion formulas RGB to XY and back".
public enum ColorMath {
    /// Gamut C, used when a light doesn't report its own.
    public static let fallbackGamut = Gamut(
        red: XY(x: 0.6915, y: 0.3083),
        green: XY(x: 0.17, y: 0.7),
        blue: XY(x: 0.1532, y: 0.0475)
    )

    // MARK: sRGB → xy

    public static func xy(from rgb: RGB, gamut: Gamut? = nil) -> XY {
        let r = linearize(rgb.red), g = linearize(rgb.green), b = linearize(rgb.blue)
        let x = r * 0.4124 + g * 0.3576 + b * 0.1805
        let y = r * 0.2126 + g * 0.7152 + b * 0.0722
        let z = r * 0.0193 + g * 0.1192 + b * 0.9505
        let sum = x + y + z
        // Black has no chromaticity; fall back to the D65 white point.
        let point = sum > 0 ? XY(x: x / sum, y: y / sum) : XY(x: 0.3127, y: 0.3290)
        return clamp(point, to: gamut ?? fallbackGamut)
    }

    // MARK: xy → sRGB

    /// Display color for `xy` at full intensity (brightest component = 1).
    public static func rgb(from xy: XY) -> RGB {
        guard xy.y > 0 else { return .white }
        let bigY = 1.0
        let bigX = bigY / xy.y * xy.x
        let bigZ = bigY / xy.y * (1 - xy.x - xy.y)

        var r = bigX * 3.2406 - bigY * 1.5372 - bigZ * 0.4986
        var g = -bigX * 0.9689 + bigY * 1.8758 + bigZ * 0.0415
        var b = bigX * 0.0557 - bigY * 0.2040 + bigZ * 1.0570

        // Out-of-gamut points produce negatives; clip, then normalize before gamma.
        r = max(r, 0); g = max(g, 0); b = max(b, 0)
        let maximum = max(r, g, b)
        if maximum > 1 { r /= maximum; g /= maximum; b /= maximum }

        let rgb = RGB(red: gammaCorrect(r), green: gammaCorrect(g), blue: gammaCorrect(b))
        let peak = max(rgb.red, rgb.green, rgb.blue)
        guard peak > 0 else { return .white }
        return RGB(red: rgb.red / peak, green: rgb.green / peak, blue: rgb.blue / peak)
    }

    // MARK: Color temperature

    public static func mirek(fromKelvin kelvin: Double) -> Int {
        Int((1_000_000 / kelvin).rounded())
    }

    public static func kelvin(fromMirek mirek: Int) -> Double {
        1_000_000 / Double(max(mirek, 1))
    }

    /// Approximate display color for a white temperature (Tanner Helland's fit).
    public static func rgb(fromMirek mirek: Int) -> RGB {
        let temperature = kelvin(fromMirek: mirek) / 100
        let red: Double
        let green: Double
        let blue: Double

        if temperature <= 66 {
            red = 255
            green = 99.4708025861 * log(temperature) - 161.1195681661
        } else {
            red = 329.698727446 * pow(temperature - 60, -0.1332047592)
            green = 288.1221695283 * pow(temperature - 60, -0.0755148492)
        }

        if temperature >= 66 {
            blue = 255
        } else if temperature <= 19 {
            blue = 0
        } else {
            blue = 138.5177312231 * log(temperature - 10) - 305.0447927307
        }

        func unit(_ value: Double) -> Double { min(max(value / 255, 0), 1) }
        return RGB(red: unit(red), green: unit(green), blue: unit(blue))
    }

    // MARK: Gamut

    public static func isInside(_ point: XY, _ gamut: Gamut) -> Bool {
        let v1 = XY(x: gamut.green.x - gamut.red.x, y: gamut.green.y - gamut.red.y)
        let v2 = XY(x: gamut.blue.x - gamut.red.x, y: gamut.blue.y - gamut.red.y)
        let q = XY(x: point.x - gamut.red.x, y: point.y - gamut.red.y)
        let denominator = cross(v1, v2)
        guard denominator != 0 else { return false }
        let s = cross(q, v2) / denominator
        let t = cross(v1, q) / denominator
        return s >= 0 && t >= 0 && s + t <= 1
    }

    /// The closest point inside the gamut triangle.
    public static func clamp(_ point: XY, to gamut: Gamut) -> XY {
        guard !isInside(point, gamut) else { return point }
        let candidates = [
            closestPoint(on: gamut.red, gamut.green, to: point),
            closestPoint(on: gamut.blue, gamut.red, to: point),
            closestPoint(on: gamut.green, gamut.blue, to: point),
        ]
        return candidates.min { distance($0, point) < distance($1, point) }!
    }

    // MARK: Helpers

    private static func linearize(_ c: Double) -> Double {
        c > 0.04045 ? pow((c + 0.055) / 1.055, 2.4) : c / 12.92
    }

    private static func gammaCorrect(_ c: Double) -> Double {
        c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    private static func cross(_ a: XY, _ b: XY) -> Double { a.x * b.y - a.y * b.x }

    private static func distance(_ a: XY, _ b: XY) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }

    private static func closestPoint(on a: XY, _ b: XY, to p: XY) -> XY {
        let ap = XY(x: p.x - a.x, y: p.y - a.y)
        let ab = XY(x: b.x - a.x, y: b.y - a.y)
        let lengthSquared = ab.x * ab.x + ab.y * ab.y
        guard lengthSquared > 0 else { return a }
        let t = min(max((ap.x * ab.x + ap.y * ab.y) / lengthSquared, 0), 1)
        return XY(x: a.x + ab.x * t, y: a.y + ab.y * t)
    }
}
