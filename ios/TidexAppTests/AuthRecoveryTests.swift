import XCTest

@testable import Tidex

// The only test here checked how a Supabase Storage duplicate error maps. The upload now goes
// through Convex and has no such error, so the test is gone. The file is left for the project
// file owner to remove.
internal final class AuthRecoveryTests: XCTestCase {}
