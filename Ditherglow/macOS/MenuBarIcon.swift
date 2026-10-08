import AppKit

/// The menu bar icon: the app icon's orb as 16×16 pixel art, one pixel per point.
/// The shading is a 4×4 Bayer dither on which pixels are lit, since a template image has no tones.
enum MenuBarIcon {
    /// Lit from the upper right; the shadow side dithers away inside the rim.
    private static let lit = [
        "................",
        "......####......",
        "....########....",
        "...#.#.#.####...",
        "..#.#.########..",
        "..#..#.#######..",
        ".#..#.#########.",
        ".#.....#.#.#.##.",
        ".#..#.#.#######.",
        ".#.......#.#.##.",
        "..#...#.#.#.##..",
        "..#........#.#..",
        "...#......#.#...",
        "....##....##....",
        "......####......",
        "................",
    ]

    /// The wallpaper is off: the sun's outline only.
    private static let unlit = [
        "................",
        "......####......",
        "....##....##....",
        "...#........#...",
        "..#..........#..",
        "..#..........#..",
        ".#............#.",
        ".#............#.",
        ".#............#.",
        ".#............#.",
        "..#..........#..",
        "..#..........#..",
        "...#........#...",
        "....##....##....",
        "......####......",
        "................",
    ]

    static func image(enabled: Bool) -> NSImage {
        let rows = enabled ? lit : unlit
        // Drawn per backing scale, so each pixel stays a crisp 1×1 pt square on Retina too.
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            NSColor.black.setFill()
            for (y, row) in rows.enumerated() {
                for (x, pixel) in row.enumerated() where pixel == "#" {
                    NSRect(x: x, y: y, width: 1, height: 1).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
