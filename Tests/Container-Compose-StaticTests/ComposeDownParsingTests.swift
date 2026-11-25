import Testing
@testable import ContainerComposeCore

struct ComposeDownParsingTests {
    @Test func cleanupOptions() throws {
        let command = try ComposeDown.parse(["--remove-orphans", "--timeout", "3"])
        #expect(command.removeOrphans)
        #expect(command.timeout == 3)
    }

    @Test func rejectsNegativeTimeout() {
        #expect(throws: (any Error).self) {
            _ = try ComposeDown.parse(["--timeout", "-1"])
        }
    }
}
