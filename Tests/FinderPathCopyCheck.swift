import AppKit
import OSLog
import os.lock

@main
enum FinderPathCopyCheck {
    @MainActor static func main() async throws {
        try await verifyNewTextFileCallbacks()
        try await verifyBackgroundMenuCallbacks()
        try await verifyConcurrentMenuPublication()
        try verifySharedLanguage()
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let urls = [URL(fileURLWithPath: "/tmp/中文 '$(literal); #?.txt"), URL(fileURLWithPath: "/Volumes/Test Folder")]
        try FinderPathCopy.write(urls, to: board)
        precondition(board.string(forType: .string) == urls.map(\.path).joined(separator: "\n"))
        precondition(!board.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]))
        guard let remote = URL(string: "https://example.com") else { preconditionFailure("Invalid test URL") }
        for files in [[URL](), [remote]] {
            do {
                try FinderPathCopy.write(files, to: board)
                preconditionFailure("Invalid path copy replaced clipboard")
            } catch FinderActionRequest.RequestError.invalidFiles {}
            precondition(board.string(forType: .string) == urls.map(\.path).joined(separator: "\n"))
        }
        print(
            "Finder proxy menu actions preserve signed snapshots, reject stale tags, and accept background callbacks without changing the user clipboard."
        )
    }

    @MainActor private static func verifyNewTextFileCallbacks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { do { try FileManager.default.removeItem(at: root) } catch { preconditionFailure("\(error)") } }
        let store = FinderConfigurationStore(directory: root.appendingPathComponent("configuration"))
        try store.save(FinderConfiguration(newTextFileEnabled: true))
        try store.prepareNewTextFileKey()
        let key = try store.loadNewTextFileKey()
        var received: [URL] = []
        let finder = BuckleFinderSync(observeDirectories: { _ in }, openRequest: { url, _ in received.append(url) })
        let menu = finder.makeMenu(for: .container(root), store: store)
        guard let item = menu.items.first, let selector = item.action else {
            preconditionFailure("Missing new text file action")
        }
        precondition(menu.items.count == 1)
        let proxy = NSMenuItem(title: item.title, action: selector, keyEquivalent: "")
        proxy.tag = item.tag
        _ = finder.perform(selector, with: proxy)
        // Duplicate delivery must retain the same request ID, even though signing occurs at click time.
        _ = finder.perform(selector, with: proxy)
        let deadline = ContinuousClock.now + .seconds(2)
        while received.count < 2, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        precondition(received.count == 2)
        let requests = try received.map(FinderNewTextFileRequest.init(url:))
        for request in requests {
            try request.validate(key: key, now: Date())
            precondition(request.target.directory == root.standardizedFileURL.resolvingSymlinksInPath())
        }
        precondition(requests[0].target.requestID == requests[1].target.requestID)
        let file = root.appendingPathComponent("ordinary.txt")
        try Data().write(to: file)
        precondition(finder.makeMenu(for: .items([file]), store: store).items.isEmpty)
        _ = finder.perform(selector, with: proxy)
        try await Task.sleep(for: .milliseconds(20))
        precondition(received.count == 2, "Expired file creation tag accepted")
    }

    @MainActor private static func verifyBackgroundMenuCallbacks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: root) } catch { preconditionFailure("\(error)") }
        }
        let store = FinderConfigurationStore(directory: root.appendingPathComponent("configuration"))
        try store.save(
            FinderConfiguration(
                airDropEnabled: true, terminalEnabled: true, copyPathEnabled: true, moveEnabled: true))
        try store.prepareMoveKey()
        let key = try store.loadMoveKey()
        let clipboardChangeCount = NSPasteboard.general.changeCount
        let files = [root]
        var receivedRequests: [URL] = []
        var copiedFiles: [[URL]] = []
        let openRequest: @MainActor @Sendable (URL, Logger) -> Void = { received, _ in
            MainActor.preconditionIsolated()
            precondition(Thread.isMainThread)
            receivedRequests.append(received)
        }
        let copyFiles: @MainActor @Sendable ([URL], Logger) -> Void = { received, _ in
            MainActor.preconditionIsolated()
            precondition(Thread.isMainThread)
            copiedFiles.append(received)
        }
        // Finder sends a new item across XPC, preserving tag/action but dropping representedObject.
        await Task.detached {
            var observedDirectories: Set<URL> = []
            let finder = BuckleFinderSync(
                observeDirectories: { observedDirectories = $0 }, openRequest: openRequest, copyFiles: copyFiles)
            precondition(observedDirectories == [URL(fileURLWithPath: "/")])
            precondition(!Thread.isMainThread)
            let firstMenu = finder.makeMenu(for: .items(files), store: store)
            precondition(firstMenu.items.count == 4, "Missing Finder menu actions")
            let proxies = firstMenu.items.map { item in
                precondition(item.tag > 0 && item.representedObject == nil)
                let proxy = NSMenuItem(title: item.title, action: item.action, keyEquivalent: "")
                proxy.tag = item.tag
                return proxy
            }
            precondition(Set(proxies.map(\.tag)).count == 4)
            for proxy in proxies {
                guard let action = proxy.action else { preconditionFailure("Missing menu action") }
                precondition(finder.responds(to: action))
                _ = finder.perform(action, with: proxy)
            }
            // Already accepted callbacks must retain their snapshots through this replacement.
            let secondMenu = finder.makeMenu(for: .container(root), store: store)
            let firstTags = Set(proxies.map(\.tag))
            precondition(secondMenu.items.allSatisfy { !firstTags.contains($0.tag) })
            for proxy in proxies {
                guard let action = proxy.action else { preconditionFailure("Missing menu action") }
                _ = finder.perform(action, with: proxy)
            }
            let invalid = NSMenuItem()
            invalid.representedObject = files
            _ = finder.perform(NSSelectorFromString("performAction:"), with: invalid)
            _ = finder.perform(NSSelectorFromString("copyPath:"), with: invalid)
            // A current container action must still resolve after rejecting stale and forged senders.
            guard let item = secondMenu.items.first(where: { $0.action == NSSelectorFromString("copyPath:") }) else {
                preconditionFailure("Missing Copy Path action")
            }
            let proxy = NSMenuItem(title: item.title, action: item.action, keyEquivalent: "")
            proxy.tag = item.tag
            _ = finder.perform(NSSelectorFromString("copyPath:"), with: proxy)
        }.value
        let deadline = ContinuousClock.now + .seconds(2)
        while receivedRequests.count < 3 || copiedFiles.count < 2, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(
            receivedRequests.count == 3 && copiedFiles == [files, files], "Proxy callbacks were lost or repeated")
        let requests = try receivedRequests.map(FinderActionRequest.init(url:))
        precondition(Set(requests.map(\.action)) == [.airDrop, .terminal, .move])
        for request in requests {
            precondition(request.files == files)
            if request.action == .move {
                precondition(request.clipboardChangeCount == clipboardChangeCount)
                let authentic = try request.authenticates(using: key)
                precondition(authentic)
            }
        }
    }
    @MainActor private static func verifyConcurrentMenuPublication() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: root) } catch { preconditionFailure("\(error)") }
        }
        let folders = ["A", "B", "C"].map { root.appendingPathComponent($0) }
        for folder in folders {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let store = FinderConfigurationStore(directory: root.appendingPathComponent("configuration"))
        try store.save(
            FinderConfiguration(
                airDropEnabled: true, terminalEnabled: true, copyPathEnabled: true, moveEnabled: true))
        try store.prepareMoveKey()
        var requests: [URL] = []
        var copies: [[URL]] = []
        let finder = BuckleFinderSync(
            observeDirectories: { _ in }, openRequest: { request, _ in requests.append(request) },
            copyFiles: { files, _ in copies.append(files) })
        let copySelector = NSSelectorFromString("copyPath:")
        let first = finder.makeMenu(for: .items([folders[0]]), store: store)
        guard let firstItem = first.items.first(where: { $0.action == copySelector }) else {
            preconditionFailure("Missing first menu Copy Path")
        }
        let firstProxy = NSMenuItem(title: "A", action: copySelector, keyEquivalent: "")
        firstProxy.tag = firstItem.tag
        let entered = DispatchSemaphore(value: 0)
        let resume = DispatchSemaphore(value: 0)
        let worker = ConcurrentMenuBuild(
            finder: finder, folder: folders[1], store: store, entered: entered, resume: resume)
        let finished = worker.finished
        // Use Foundation's Objective-C thread entry, matching Finder's callback boundary without unsafe casts.
        let thread = Thread(target: worker, selector: #selector(ConcurrentMenuBuild.run), object: nil)
        thread.start()
        // Semaphore waits stay off MainActor, where accepted callbacks must be delivered.
        await Task.detached {
            precondition(entered.wait(timeout: .now() + 5) == .success, "Concurrent menu did not begin loading")
        }.value
        _ = finder.perform(copySelector, with: firstProxy)
        let third = finder.makeMenu(for: .items([folders[2]]), store: store)
        guard let thirdItem = third.items.first(where: { $0.action == copySelector }) else {
            preconditionFailure("Missing third menu Copy Path")
        }
        let thirdProxy = NSMenuItem(title: "C", action: copySelector, keyEquivalent: "")
        thirdProxy.tag = thirdItem.tag
        _ = finder.perform(copySelector, with: thirdProxy)
        resume.signal()
        await Task.detached {
            precondition(finished.wait(timeout: .now() + 5) == .success, "Concurrent menu did not complete")
        }.value
        let completed = worker.items.withLock { $0 }
        precondition(completed.count == 4)
        // B completes last: all of B becomes active together, while both previous menus expire.
        _ = finder.perform(copySelector, with: firstProxy)
        _ = finder.perform(copySelector, with: thirdProxy)
        let previousTags = Set(first.items.map(\.tag) + third.items.map(\.tag))
        for (tag, actionName) in completed {
            precondition(!previousTags.contains(tag))
            let action = NSSelectorFromString(actionName)
            let proxy = NSMenuItem(title: "B", action: action, keyEquivalent: "")
            proxy.tag = tag
            _ = finder.perform(action, with: proxy)
        }
        let deadline = ContinuousClock.now + .seconds(2)
        while requests.count < 3 || copies.count < 3, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(copies.count == 3, "Concurrent menu publication lost a valid click or accepted an expired tag")
        precondition(Set(copies.map { $0[0] }) == Set(folders), "Concurrent callback copied the wrong folder")
        let decoded = try requests.map(FinderActionRequest.init(url:))
        precondition(decoded.count == 3 && decoded.allSatisfy { $0.files == [folders[1]] })
        precondition(Set(decoded.map(\.action)) == [.airDrop, .terminal, .move])
    }

    private static func verifySharedLanguage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        defer {
            do { try FileManager.default.removeItem(at: root) } catch { preconditionFailure("\(error)") }
        }
        let contents = root.appendingPathComponent("Contents")
        for (language, title) in [("en", "Open in Terminal"), ("ja", "ターミナルで開く")] {
            let directory = contents.appendingPathComponent("Resources/\(language).lproj")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("\"finder.terminal.title\" = \"\(title)\";".utf8)
                .write(to: directory.appendingPathComponent("Localizable.strings"))
        }
        let info = ["CFBundleIdentifier": "Buckle.FinderLanguageCheck", "CFBundleDevelopmentRegion": "en"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        guard let bundle = Bundle(url: root) else { preconditionFailure("Missing localization test bundle") }
        precondition(localized("finder.terminal.title", language: "ja", bundle: bundle) == "ターミナルで開く")
        precondition(localized("finder.terminal.title", language: "en", bundle: bundle) == "Open in Terminal")
    }

}

// Foundation's target/selector thread API models the Objective-C callback that Swift Tasks cannot send.
private final class ConcurrentMenuBuild: NSObject {
    let finder: BuckleFinderSync
    let folder: URL
    let store: FinderConfigurationStore
    let entered: DispatchSemaphore
    let resume: DispatchSemaphore
    let finished = DispatchSemaphore(value: 0)
    let items = OSAllocatedUnfairLock(initialState: [(Int, String)]())

    init(
        finder: BuckleFinderSync, folder: URL, store: FinderConfigurationStore,
        entered: DispatchSemaphore, resume: DispatchSemaphore
    ) {
        self.finder = finder
        self.folder = folder
        self.store = store
        self.entered = entered
        self.resume = resume
    }

    @objc func run() {
        let menu = finder.makeMenu(
            for: .items([folder]), store: store,
            loadConfiguration: { [entered, resume] store in
                entered.signal()
                precondition(resume.wait(timeout: .now() + 5) == .success, "Menu configuration was not resumed")
                return try store.load()
            })
        let snapshots = menu.items.map { item -> (Int, String) in
            guard let action = item.action else { preconditionFailure("Missing concurrent menu action") }
            return (item.tag, NSStringFromSelector(action))
        }
        items.withLock { $0 = snapshots }
        finished.signal()
    }
}
