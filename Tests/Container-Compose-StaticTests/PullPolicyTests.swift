import Testing
import Yams
@testable import ContainerComposeCore

@Suite("Pull policies")
struct PullPolicyTests {
    @Test func decisions() {
        #expect(PullPolicy.always.shouldPull(image: "app:1", local: true))
        #expect(!PullPolicy.never.shouldPull(image: "app:1", local: false))
        #expect(!PullPolicy.build.shouldPull(image: "app:1", local: false))
        for policy in [PullPolicy.missing, .ifNotPresent] {
            #expect(!policy.shouldPull(image: "app:1", local: true))
            #expect(policy.shouldPull(image: "app:1", local: false))
            #expect(policy.shouldPull(image: "localhost:5000/app", local: true))
            #expect(policy.shouldPull(image: "app:latest", local: true))
            #expect(!policy.shouldPull(image: "app@sha256:abc", local: true))
        }
    }
    @Test func decoding() throws {
        for value in ["always", "never", "missing", "if_not_present", "build"] {
            let service = try YAMLDecoder().decode(Service.self, from: "image: app:1\npull_policy: \(value)\n")
            #expect(service.pull_policy?.rawValue == value)
        }
        for value in ["latest", "daily", "weekly", "every_12h", "invalid"] {
            #expect(throws: (any Error).self) {
                try YAMLDecoder().decode(Service.self, from: "image: app:1\npull_policy: \(value)\n")
            }
        }
    }
}
