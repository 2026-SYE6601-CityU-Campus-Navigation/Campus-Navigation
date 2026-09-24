import Foundation

private final class FixtureBundleToken {}

enum TestFixtures {
    static func data(named name: String) throws -> Data {
        let bundle = Bundle(for: FixtureBundleToken.self)
        let nestedURL = bundle.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures"
        )
        let flatURL = bundle.url(forResource: name, withExtension: "json")

        guard let url = nestedURL ?? flatURL else {
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }
}

enum FixtureError: Error {
    case missing(String)
}
