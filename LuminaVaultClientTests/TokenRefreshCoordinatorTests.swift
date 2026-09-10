// LuminaVaultClient/LuminaVaultClientTests/TokenRefreshCoordinatorTests.swift
import XCTest
@testable import LuminaVaultClient

final class TokenRefreshCoordinatorTests: XCTestCase {
    func testSingleFlightCollapsesConcurrentCallers() async throws {
        let coordinator = TokenRefreshCoordinator()
        let counter = Counter()

        // Three concurrent callers. Whichever one the scheduler lets in first
        // performs the refresh; the other two must join it. The three
        // operations are deliberately identical: an earlier version gave
        // `b` and `c` sentinel tokens and asserted on `a`'s, which assumed
        // `a` always wins the race — it does not on the CI runner, and the
        // test failed while single-flight itself held.
        @Sendable func refresh() async throws -> String {
            await counter.increment()
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            return "tok-\(await counter.value)"
        }
        async let a = coordinator.refresh(using: refresh)
        async let b = coordinator.refresh(using: refresh)
        async let c = coordinator.refresh(using: refresh)

        let (ra, rb, rc) = try await (a, b, c)
        let invocations = await counter.value
        XCTAssertEqual(invocations, 1, "Only one refresh operation should run for concurrent callers")
        XCTAssertEqual(ra, rb)
        XCTAssertEqual(rb, rc)
        XCTAssertEqual(ra, "tok-1", "every caller receives the token from the single refresh that ran")
    }

    func testSequentialCallersAfterCompletionStartFreshRefresh() async throws {
        let coordinator = TokenRefreshCoordinator()
        let counter = Counter()

        let first = try await coordinator.refresh {
            await counter.increment()
            return "first"
        }
        let second = try await coordinator.refresh {
            await counter.increment()
            return "second"
        }

        XCTAssertEqual(first, "first")
        XCTAssertEqual(second, "second")
        let invocations = await counter.value
        XCTAssertEqual(invocations, 2, "Sequential callers each get their own refresh attempt")
    }

    func testRefreshFailurePropagatesToAllCallers() async {
        let coordinator = TokenRefreshCoordinator()
        struct Boom: Error {}

        async let a: Void = {
            do {
                _ = try await coordinator.refresh { throw Boom() }
                XCTFail("Expected failure")
            } catch is Boom {
                // pass
            } catch {
                XCTFail("Wrong error: \(error)")
            }
        }()
        async let b: Void = {
            do {
                _ = try await coordinator.refresh { throw Boom() }
                XCTFail("Expected failure")
            } catch is Boom {
                // pass
            } catch {
                XCTFail("Wrong error: \(error)")
            }
        }()

        _ = await (a, b)
    }
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}
