import XCTest
@testable import Nabu

/// Unit tests for the token-registration state machine
/// (`PushRegistrationPhase`) — the pure core of the APNs lifecycle.
final class PushRegistrationTests: XCTestCase {

    func testHappyPathToRegistered() {
        var phase = PushRegistrationPhase.idle
        phase = phase.applying(.enableRequested)
        XCTAssertEqual(phase, .awaitingAuthorization)
        phase = phase.applying(.authorizationGranted)
        XCTAssertEqual(phase, .awaitingToken)
        phase = phase.applying(.tokenReceived("cafe01"))
        XCTAssertEqual(phase, .registering(token: "cafe01"))
        phase = phase.applying(.registerSucceeded)
        XCTAssertEqual(phase, .registered(token: "cafe01"))
    }

    func testAuthorizationDenied() {
        let phase = PushRegistrationPhase.awaitingAuthorization
            .applying(.authorizationDenied)
        XCTAssertEqual(phase, .denied)
    }

    func testDeniedIsRetryable() {
        let phase = PushRegistrationPhase.denied.applying(.enableRequested)
        XCTAssertEqual(phase, .awaitingAuthorization)
    }

    func testRegisterFailureIsRetryable() {
        var phase = PushRegistrationPhase.registering(token: "cafe01")
            .applying(.registerFailed("500"))
        XCTAssertEqual(phase, .failed("500"))
        phase = phase.applying(.enableRequested)
        XCTAssertEqual(phase, .awaitingAuthorization)
    }

    func testLaunchSyncSkipsPrePrompt() {
        // syncIfAuthorized: permission already granted → straight to
        // awaitingToken without the pre-prompt.
        let phase = PushRegistrationPhase.idle.applying(.authorizationGranted)
        XCTAssertEqual(phase, .awaitingToken)
    }

    func testEnableRequestedDoesNotDropRegistration() {
        let phase = PushRegistrationPhase.registered(token: "cafe01")
            .applying(.enableRequested)
        XCTAssertEqual(phase, .registered(token: "cafe01"))
    }

    func testRegisterSucceededOutsideRegisteringIsNoop() {
        let phase = PushRegistrationPhase.idle.applying(.registerSucceeded)
        XCTAssertEqual(phase, .idle)
    }

    func testUnregisteredResetsToIdle() {
        let phase = PushRegistrationPhase.registered(token: "cafe01")
            .applying(.unregistered)
        XCTAssertEqual(phase, .idle)
    }

    func testTokenRefreshWhileRegistered() {
        // Apple can rotate the token on a later launch; the machine re-enters
        // registering with the fresh token.
        let phase = PushRegistrationPhase.registered(token: "old")
            .applying(.tokenReceived("new"))
        XCTAssertEqual(phase, .registering(token: "new"))
    }
}
