import XCTest
@testable import PhaseTraining

/// The Library's muscle tiles and the muscle chip badge both read the
/// MuscleBucket table; these pin the two invariants a new bucket or tile
/// could break without any screen erroring.
final class LibraryTileInvariantTests: XCTestCase {

    /// Every bucket is reachable from exactly one Library tile, so no muscle
    /// is hidden from browse and none is listed twice.
    func test_everyBucketBelongsToExactlyOneTile() {
        let owners = Dictionary(grouping: LibraryTile.allCases.flatMap { tile in tile.members.map { ($0, tile) } },
                                by: \.0)
        for bucket in MuscleBucket.allCases {
            XCTAssertEqual(owners[bucket]?.count, 1, "\(bucket) is in \(owners[bucket]?.map(\.1) ?? []) tiles")
        }
    }

    /// The badge's primary slug maps back to its own bucket; a slug renamed in
    /// one table and not the other would draw the wrong region.
    func test_primarySlugRoundTripsToItsBucket() {
        for bucket in MuscleBucket.allCases {
            XCTAssertEqual(MuscleBucket.bucket(forSlug: bucket.primarySlug), bucket, "\(bucket).primarySlug")
            XCTAssertTrue(bucket.memberSlugs.contains(bucket.primarySlug), "\(bucket) primary slug not a member")
        }
    }

    /// Tiles query by the union of their members' slugs.
    func test_tileSlugsAreTheUnionOfItsMembers() {
        for tile in LibraryTile.allCases {
            XCTAssertEqual(Set(tile.memberSlugs), Set(tile.members.flatMap(\.memberSlugs)), "\(tile)")
            XCTAssertFalse(tile.memberSlugs.isEmpty, "\(tile) queries nothing")
        }
    }

    func test_everyTileFigureIsOneOfItsMembers() {
        for tile in LibraryTile.allCases {
            XCTAssertTrue(tile.members.contains(tile.figureBucket), "\(tile) figure \(tile.figureBucket)")
        }
    }

    func test_everyTileFigureHasABundledImage() {
        for tile in LibraryTile.allCases {
            let bucket = tile.figureBucket
            let name = "MuscleChips/\(bucket.rawValue)-\(bucket.naturalSide == .front ? "front" : "back")"
            XCTAssertNotNil(UIImage(named: name), "\(tile) missing \(name)")
        }
    }

    /// Template rendering keeps only alpha, so figures are compared by their
    /// alpha channel; PNGs that differ only in RGB draw the same shape.
    func test_tileFiguresAreDistinct() throws {
        var seen: [[UInt8]: LibraryTile] = [:]
        for tile in LibraryTile.allCases {
            let image = try XCTUnwrap(Self.figureImage(for: tile)?.cgImage, "\(tile) has no image")
            let alpha = try XCTUnwrap(Self.alphaChannel(of: image), "\(tile) alpha unreadable")
            if let other = seen[alpha] {
                XCTFail("\(tile) and \(other) draw identical figures")
            }
            seen[alpha] = tile
        }
    }

    /// The highlighted muscle is the only fully opaque region; the body around
    /// it sits at partial alpha, so most drawn pixels are below 250.
    func test_tileFigureHighlightIsAMinorityOfTheBody() throws {
        for tile in LibraryTile.allCases {
            let image = try XCTUnwrap(Self.figureImage(for: tile)?.cgImage, "\(tile) has no image")
            let alpha = try XCTUnwrap(Self.alphaChannel(of: image), "\(tile) alpha unreadable")
            let visible = alpha.filter { $0 > 0 }.count
            let opaque = alpha.filter { $0 >= 250 }.count
            XCTAssertGreaterThan(visible, 0, "\(tile) draws nothing")
            let share = Double(opaque) / Double(max(visible, 1))
            XCTAssertLessThan(share, 0.5, "\(tile) opaque share \(share)")
        }
    }

    private static func figureImage(for tile: LibraryTile) -> UIImage? {
        let bucket = tile.figureBucket
        return UIImage(named: "MuscleChips/\(bucket.rawValue)-\(bucket.naturalSide == .front ? "front" : "back")")
    }

    private static func alphaChannel(of image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    }
}
