import Testing
import Yams
@testable import ContainerComposeCore

struct ImagePreparationTests {
    enum PullFailure: Error { case unavailable }

    @Test(arguments: [nil, "missing", "if_not_present"] as [String?])
    func failedPullBuilds(policy: String?) async throws {
        for cached in [false, true] {
            let service = try YAMLDecoder().decode(Service.self, from:
                "image: example:latest\nbuild: .\n" + (policy.map { "pull_policy: \($0)\n" } ?? ""))
            var calls: [String] = []
            let result = try await ComposeUp.prepareServiceImage(service, serviceName: "app", rebuild: false,
                isLocal: { cached },
                pull: { calls.append("pull"); throw PullFailure.unavailable },
                build: { force in calls.append("build:\(force)"); return "built" })
            #expect(result == "built")
            #expect(calls == ["pull", "build:true"])
        }
    }

    @Test(arguments: ["always", "never", "build"])
    func otherPolicies(policy: String) async throws {
        let service = try YAMLDecoder().decode(Service.self, from:
            "image: example:latest\nbuild: .\npull_policy: \(policy)\n")
        var calls: [String] = []
        do {
            _ = try await ComposeUp.prepareServiceImage(service, serviceName: "app", rebuild: false,
                isLocal: { true },
                pull: { calls.append("pull"); throw PullFailure.unavailable },
                build: { force in calls.append("build:\(force)"); return "built" })
            #expect(policy != "always")
        } catch is PullFailure {
            #expect(policy == "always")
        }
        #expect(calls == (policy == "always" ? ["pull"] : policy == "build" ? ["build:false"] : []))
    }
}
