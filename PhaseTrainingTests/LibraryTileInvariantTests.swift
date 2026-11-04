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
}
