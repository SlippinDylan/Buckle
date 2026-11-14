import AppKit

@main
enum BrowserLauncherCheck {
    @MainActor
    static func main() {
        for chromium in [true, false] {
            let browser = Browser(
                id: "test.browser", name: "Test Browser", url: URL(filePath: "/Test.app"), chromium: chromium)
            for language in BrowserLanguage.allCases {
                let configuration = BrowserLauncher.launchConfiguration(for: browser, language: language)
                let expectedEnvironment = language == .japanese ? ["TZ": "Asia/Tokyo"] : [:]
                guard configuration.environment == expectedEnvironment else {
                    print(
                        "Browser launch did not pass the requested time zone: \(language.rawValue), chromium=\(chromium)"
                    )
                    exit(1)
                }
                let expectedArguments = chromium ? language.arguments : ["-AppleLanguages", "(\(language.rawValue))"]
                precondition(configuration.arguments == expectedArguments)
                precondition(configuration.createsNewApplicationInstance && configuration.activates)
            }
        }
        print("Browser language and time-zone launch configuration verified without starting browsers.")
    }
}
