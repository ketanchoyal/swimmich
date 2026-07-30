import XCTest
@testable import ImmichSwiftUI

final class AppLockViewModelTests: XCTestCase {

    private func resetDefaults() {
        UserDefaults.standard.removeObject(forKey: AppLockViewModel.enabledKey)
    }

    override func tearDown() {
        resetDefaults()
    }

    // AC-108(a): init with isEnabled=true (persisted) → isLocked=true (fresh-launch locked).
    @MainActor
    func test_AC_108a_initEnabledIsLocked() {
        resetDefaults()
        UserDefaults.standard.set(true, forKey: AppLockViewModel.enabledKey)
        let vm = AppLockViewModel(evaluator: { true })
        XCTAssertTrue(vm.isEnabled)
        XCTAssertTrue(vm.isLocked, "fresh launch with feature on must start locked (AC-113)")
    }

    // AC-108(b): setEnabled(false) → isLocked=false (FM-2 mitigation).
    @MainActor
    func test_AC_108b_setEnabledFalseUnlocks() {
        resetDefaults()
        UserDefaults.standard.set(true, forKey: AppLockViewModel.enabledKey)
        let vm = AppLockViewModel(evaluator: { true })
        XCTAssertTrue(vm.isLocked)

        vm.setEnabled(false)
        XCTAssertFalse(vm.isEnabled)
        XCTAssertFalse(vm.isLocked, "disabling must release any active lock")
        XCTAssertFalse(UserDefaults.standard.bool(forKey: AppLockViewModel.enabledKey))
    }

    // AC-108(c): enabled + lock() → isLocked=true.
    @MainActor
    func test_AC_108c_lockSetsIsLocked() {
        resetDefaults()
        let vm = AppLockViewModel(evaluator: { true })
        XCTAssertFalse(vm.isLocked)

        vm.setEnabled(true)
        XCTAssertFalse(vm.isLocked, "setEnabled(true) alone does not lock")

        vm.lock()
        XCTAssertTrue(vm.isLocked)
    }

    // AC-108(d): authenticate(fake=true) → isLocked=false, returns true.
    @MainActor
    func test_AC_108d_authenticateSuccessUnlocks() async {
        resetDefaults()
        let vm = AppLockViewModel(evaluator: { true })
        vm.setEnabled(true)
        vm.lock()
        XCTAssertTrue(vm.isLocked)

        let ok = await vm.authenticate()
        XCTAssertTrue(ok)
        XCTAssertFalse(vm.isLocked)
        XCTAssertFalse(vm.isAuthenticating)
    }

    // AC-108(e): authenticate(fake=false) → isLocked stays true, returns false.
    @MainActor
    func test_AC_108e_authenticateFailureStaysLocked() async {
        resetDefaults()
        let vm = AppLockViewModel(evaluator: { false })
        vm.setEnabled(true)
        vm.lock()
        XCTAssertTrue(vm.isLocked)

        let ok = await vm.authenticate()
        XCTAssertFalse(ok)
        XCTAssertTrue(vm.isLocked, "failed auth must keep the lock")
    }

    // AC-108(f): lock() during isAuthenticating==true is a no-op (FM-1).
    @MainActor
    func test_AC_108f_lockDuringAuthIsNoOp() async {
        resetDefaults()

        // Evaluator blocks on a continuation held inside an actor; we release
        // it from the test body, so isAuthenticating is reliably true when we
        // call lock().
        actor Latch {
            private var continuation: CheckedContinuation<Bool, Never>?
            func wait() async -> Bool {
                await withCheckedContinuation { self.continuation = $0 }
            }
            func release(_ value: Bool) {
                continuation?.resume(returning: value)
                continuation = nil
            }
        }
        let latch = Latch()
        let evaluator: @Sendable () async -> Bool = { await latch.wait() }

        let vm = AppLockViewModel(evaluator: evaluator)
        vm.setEnabled(true)
        XCTAssertTrue(vm.isEnabled)

        async let authResult: Bool = vm.authenticate()
        // Spin until the evaluator has flipped isAuthenticating.
        for _ in 0..<200 where !vm.isAuthenticating {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(vm.isAuthenticating, "evaluator should be blocking → isAuthenticating true")

        let lockedBefore = vm.isLocked
        vm.lock() // MUST be a no-op while authenticating.
        XCTAssertEqual(vm.isLocked, lockedBefore, "lock() must not fire during auth (FM-1)")

        await latch.release(true)
        let ok = await authResult
        XCTAssertTrue(ok)
        XCTAssertFalse(vm.isLocked)
    }

    // AC-111: default evaluator wiring is the LAContext-backed system path
    // (verified by source grep AC-100/AC-106; here we assert the default
    // init compiles and the type matches the injectable signature).
    @MainActor
    func test_AC_111_defaultEvaluatorCompiles() {
        resetDefaults()
        let vm = AppLockViewModel() // uses AppLockViewModel.systemEvaluator by default
        XCTAssertFalse(vm.isEnabled)
        XCTAssertFalse(vm.isLocked)
    }
}
