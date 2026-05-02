import Darwin
import Foundation

private let version = "0.10.0"
private let metadataItemUserTags = "kMDItemUserTags"
private let metadataItemPath = "kMDItemPath"
private let metadataItemDisplayName = "kMDItemDisplayName"
private let finderPreferencesPathEnvironmentKey = "TAG_FINDER_PREFERENCES_PATH"
private let metadataQueryTimeout: TimeInterval = 30.0

private enum OperationMode: Equatable {
    case none
    case unknown
    case set
    case add
    case remove
    case match
    case find
    case usage
    case list
}

private struct OutputFlags: OptionSet {
    let rawValue: Int

    static let name = OutputFlags(rawValue: 1 << 0)
    static let tags = OutputFlags(rawValue: 1 << 1)
    static let garrulous = OutputFlags(rawValue: 1 << 2)
    static let slashDirectory = OutputFlags(rawValue: 1 << 3)
    static let nulTerminate = OutputFlags(rawValue: 1 << 4)
}

private enum SearchScope {
    case none
    case home
    case local
    case network
}

private struct TagName: Hashable {
    let visibleName: String
    private let comparableName: String

    init(_ tag: String) {
        visibleName = tag
        comparableName = tag.lowercased()
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(comparableName)
    }

    static func == (lhs: TagName, rhs: TagName) -> Bool {
        lhs.comparableName == rhs.comparableName
    }
}

private final class FinderTagColorProvider {
    private let colorsEscape = "\u{001B}["
    private lazy var colorsNone = colorsEscape + "m"
    private lazy var colorsGray = colorsEscape + "48;5;241m"
    private lazy var colorsGreen = colorsEscape + "42m"
    private lazy var colorsPurple = colorsEscape + "48;5;129m"
    private lazy var colorsBlue = colorsEscape + "44m"
    private lazy var colorsYellow = colorsEscape + "43m"
    private lazy var colorsRed = colorsEscape + "41m"
    private lazy var colorsOrange = colorsEscape + "48;5;208m"

    var resetSequence: String {
        colorsNone
    }

    func colors() -> [TagName: String] {
        var colors = defaultFinderTagColors()
        if let finderColors = tagColorsFromFinderPreferences(at: finderTagPreferencesURL()) {
            colors.merge(finderColors) { _, finderColor in finderColor }
        }
        return colors
    }

    private func defaultFinderTagColors() -> [TagName: String] {
        [
            TagName("Gray"): colorsGray,
            TagName("Green"): colorsGreen,
            TagName("Purple"): colorsPurple,
            TagName("Blue"): colorsBlue,
            TagName("Yellow"): colorsYellow,
            TagName("Red"): colorsRed,
            TagName("Orange"): colorsOrange
        ]
    }

    private func finderTagPreferencesURL() -> URL? {
        if let overridePath = ProcessInfo.processInfo.environment[finderPreferencesPathEnvironmentKey], !overridePath.isEmpty {
            return URL(fileURLWithPath: overridePath)
        }

        if let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            return libraryURL.appendingPathComponent("SyncedPreferences/com.apple.finder.plist")
        }

        let home = NSHomeDirectory()
        guard !home.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: home).appendingPathComponent("Library/SyncedPreferences/com.apple.finder.plist")
    }

    private func tagColorsFromFinderPreferences(at url: URL?) -> [TagName: String]? {
        guard let url, let data = try? Data(contentsOf: url) else {
            return nil
        }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        let values = plist["values"] as? [String: Any]
        let finderTagDict = values?["FinderTagDict"] as? [String: Any]
        let value = finderTagDict?["value"] as? [String: Any]
        return tagColors(from: value?["FinderTags"] as? [[String: Any]])
    }

    private func tagColors(from tagEntries: [[String: Any]]?) -> [TagName: String]? {
        guard let tagEntries else {
            return nil
        }

        var colors: [TagName: String] = [:]
        for entry in tagEntries {
            guard let tag = entry["n"] as? String,
                  let colorCode = entry["l"] as? NSNumber,
                  let colorSequence = terminalColorSequence(forFinderColorCode: colorCode.intValue) else {
                continue
            }
            colors[TagName(tag)] = colorSequence
        }
        return colors
    }

    private func terminalColorSequence(forFinderColorCode colorCode: Int) -> String? {
        switch colorCode {
        case 1: return colorsGray
        case 2: return colorsGreen
        case 3: return colorsPurple
        case 4: return colorsBlue
        case 5: return colorsYellow
        case 6: return colorsRed
        case 7: return colorsOrange
        default: return nil
        }
    }
}

private final class MetadataQueryObserver: NSObject {
    private(set) var finished = false

    @objc func queryComplete(_ notification: Notification) {
        (notification.object as? NSMetadataQuery)?.stop()
        finished = true
    }
}

private final class TagCLI {
    private var operationMode: OperationMode = .unknown
    private var outputFlags: OutputFlags = []
    private var searchScope: SearchScope = .none
    private var displayAllFiles = false
    private var recurseDirectories = false
    private var enterDirectories = false
    private var tags = Set<TagName>()
    private var urls: [URL] = []
    private var tagColors: [TagName: String] = [:]
    private var colorOutputEnabled = false
    private var exitStatus = 0
    private var shouldStop = false
    private let colorProvider = FinderTagColorProvider()

    func run(arguments: [String]) -> Int32 {
        let parseStatus = parse(arguments: arguments)
        if parseStatus != 0 || operationMode == .none {
            return Int32(parseStatus)
        }
        return Int32(performOperation())
    }

    private func parse(arguments: [String]) -> Int {
        reset()

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" {
                index += 1
                break
            }
            guard argument.hasPrefix("-"), argument != "-" else {
                break
            }

            if argument.hasPrefix("--") {
                let status = parseLongOption(argument, arguments: arguments, index: &index)
                if status != 0 {
                    return status
                }
            } else {
                let status = parseShortOptions(argument, arguments: arguments, index: &index)
                if status != 0 {
                    return status
                }
            }
            index += 1
        }

        if operationMode == .unknown {
            operationMode = .list
        }

        outputFlags = defaultOutputFlags(for: operationMode)
        applyOutputOverrides()

        if colorRequested {
            colorOutputEnabled = isatty(STDOUT_FILENO) != 0
            tagColors = colorProvider.colors()
        }

        return parseFilenameArguments(Array(arguments[index...]))
    }

    private var nameFlag = 0
    private var tagsFlag = 0
    private var garrulousFlag = 0
    private var slashRequested = false
    private var colorRequested = false
    private var nulTerminateRequested = false

    private func reset() {
        operationMode = .unknown
        outputFlags = []
        searchScope = .none
        displayAllFiles = false
        recurseDirectories = false
        enterDirectories = false
        tags = []
        urls = []
        tagColors = [:]
        colorOutputEnabled = false
        exitStatus = 0
        shouldStop = false
        nameFlag = 0
        tagsFlag = 0
        garrulousFlag = 0
        slashRequested = false
        colorRequested = false
        nulTerminateRequested = false
    }

    private func parseLongOption(_ argument: String, arguments: [String], index: inout Int) -> Int {
        let optionText = String(argument.dropFirst(2))
        let pieces = optionText.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        let name = String(pieces[0])
        let inlineValue = pieces.count > 1 ? String(pieces[1]) : nil

        switch name {
        case "set": return setOperation(.set, value: requiredValue(inlineValue, arguments: arguments, index: &index))
        case "add": return setOperation(.add, value: requiredValue(inlineValue, arguments: arguments, index: &index))
        case "remove": return setOperation(.remove, value: requiredValue(inlineValue, arguments: arguments, index: &index))
        case "match": return setOperation(.match, value: requiredValue(inlineValue, arguments: arguments, index: &index))
        case "find": return setOperation(.find, value: requiredValue(inlineValue, arguments: arguments, index: &index))
        case "usage":
            let value = inlineValue ?? optionalValue(arguments: arguments, index: &index) ?? "*"
            return setOperation(.usage, value: value)
        case "list": return setOperation(.list, value: nil)
        case "all": displayAllFiles = true
        case "enter": enterDirectories = true
        case "recursive", "descend": recurseDirectories = true
        case "name": nameFlag = 2
        case "no-name": nameFlag = 1
        case "tags": tagsFlag = 2
        case "no-tags": tagsFlag = 1
        case "garrulous": garrulousFlag = 2
        case "no-garrulous": garrulousFlag = 1
        case "color": colorRequested = true
        case "slash": slashRequested = true
        case "nul": nulTerminateRequested = true
        case "home": searchScope = .home
        case "local": searchScope = .local
        case "network": searchScope = .network
        case "help":
            operationMode = .none
            displayHelp()
        case "version":
            operationMode = .none
            displayVersion()
        default:
            displayHelp()
            operationMode = .none
        }
        return 0
    }

    private func parseShortOptions(_ argument: String, arguments: [String], index: inout Int) -> Int {
        let chars = Array(argument.dropFirst())
        var charIndex = 0
        while charIndex < chars.count {
            let char = chars[charIndex]
            switch char {
            case "s", "a", "r", "m", "f":
                let value = valueForShortArgument(chars: chars, charIndex: charIndex, arguments: arguments, index: &index)
                let mode: OperationMode = ["s": .set, "a": .add, "r": .remove, "m": .match, "f": .find][char]!
                return setOperation(mode, value: value)
            case "u":
                let value = optionalValueForShortArgument(chars: chars, charIndex: charIndex, arguments: arguments, index: &index) ?? "*"
                return setOperation(.usage, value: value)
            case "l": return setOperation(.list, value: nil)
            case "A": displayAllFiles = true
            case "e": enterDirectories = true
            case "R", "d": recurseDirectories = true
            case "n": nameFlag = 2
            case "N": nameFlag = 1
            case "t": tagsFlag = 2
            case "T": tagsFlag = 1
            case "g": garrulousFlag = 2
            case "G": garrulousFlag = 1
            case "c": colorRequested = true
            case "p": slashRequested = true
            case "0": nulTerminateRequested = true
            case "h":
                operationMode = .none
                displayHelp()
            case "v":
                operationMode = .none
                displayVersion()
            default:
                operationMode = .none
                displayHelp()
            }
            charIndex += 1
        }
        return 0
    }

    private func setOperation(_ mode: OperationMode, value: String?) -> Int {
        guard operationMode == .unknown else {
            printError("\(programName()): Operation mode cannot be respecified")
            return 1
        }
        operationMode = mode
        if let value {
            parseTagsArgument(value)
        }
        return 0
    }

    private func requiredValue(_ inlineValue: String?, arguments: [String], index: inout Int) -> String? {
        if let inlineValue {
            return inlineValue
        }
        guard index + 1 < arguments.count else {
            return ""
        }
        index += 1
        return arguments[index]
    }

    private func optionalValue(arguments: [String], index: inout Int) -> String? {
        guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("-") else {
            return nil
        }
        index += 1
        return arguments[index]
    }

    private func valueForShortArgument(chars: [Character], charIndex: Int, arguments: [String], index: inout Int) -> String? {
        if charIndex + 1 < chars.count {
            return String(chars[(charIndex + 1)...])
        }
        return requiredValue(nil, arguments: arguments, index: &index)
    }

    private func optionalValueForShortArgument(chars: [Character], charIndex: Int, arguments: [String], index: inout Int) -> String? {
        if charIndex + 1 < chars.count {
            return String(chars[(charIndex + 1)...])
        }
        return optionalValue(arguments: arguments, index: &index)
    }

    private func applyOutputOverrides() {
        if nameFlag != 0 {
            outputFlags.remove(.name)
            if nameFlag == 2 { outputFlags.insert(.name) }
        }
        if tagsFlag != 0 {
            outputFlags.remove(.tags)
            if tagsFlag == 2 { outputFlags.insert(.tags) }
        }
        if garrulousFlag != 0 {
            outputFlags.remove(.garrulous)
            if garrulousFlag == 2 { outputFlags.insert(.garrulous) }
        }
        if slashRequested { outputFlags.insert(.slashDirectory) }
        if nulTerminateRequested { outputFlags.insert(.nulTerminate) }
    }

    private func defaultOutputFlags(for mode: OperationMode) -> OutputFlags {
        switch mode {
        case .match, .find:
            return [.name]
        case .list:
            return [.name, .tags]
        default:
            return []
        }
    }

    private func parseFilenameArguments(_ arguments: [String]) -> Int {
        urls = arguments.compactMap { path in
            guard !path.isEmpty else { return nil }
            return URL(fileURLWithPath: path)
        }
        return 0
    }

    private func parseTagsArgument(_ argument: String) {
        tags = Set(argument.split(separator: ",", omittingEmptySubsequences: false).compactMap { component in
            let trimmed = component.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : TagName(trimmed)
        })
    }

    private func performOperation() -> Int {
        switch operationMode {
        case .set: doSet()
        case .add: doAdd()
        case .remove: doRemove()
        case .match: doMatch()
        case .find: doFind()
        case .usage: doUsage()
        case .list: doList()
        case .none, .unknown: break
        }
        return exitStatus
    }

    private func doSet() {
        guard !urls.isEmpty else { return }
        let tagArray = tagArray(from: tags)
        enumerateURLs { url in
            do {
                var mutableURL = url
                try mutableURL.setTagNames(tagArray)
            } catch {
                reportFatalError(error, on: url)
            }
        }
    }

    private func doAdd() {
        guard !tags.isEmpty, !urls.isEmpty else { return }
        enumerateURLs { url in
            do {
                var tagSet = tagSet(from: try tags(for: url))
                tagSet.formUnion(tags)
                var mutableURL = url
                try mutableURL.setTagNames(tagArray(from: tagSet))
            } catch {
                reportFatalError(error, on: url)
            }
        }
    }

    private func doRemove() {
        guard !tags.isEmpty, !urls.isEmpty else { return }
        let matchAny = wildcard(in: tags)
        enumerateURLs { url in
            do {
                let revisedTags: [String]
                if matchAny {
                    revisedTags = []
                } else {
                    var tagSet = tagSet(from: try tags(for: url))
                    tagSet.subtract(tags)
                    revisedTags = tagArray(from: tagSet)
                }
                var mutableURL = url
                try mutableURL.setTagNames(revisedTags)
            } catch {
                reportFatalError(error, on: url)
            }
        }
    }

    private func doMatch() {
        let matchAny = wildcard(in: tags)
        let matchNone = tags.isEmpty
        enumerateURLs { url in
            do {
                let tagArray = try tags(for: url)
                let tagCount = tagArray.count
                if (matchAny && tagCount > 0)
                    || (matchNone && tagCount == 0)
                    || (!matchNone && tags.isSubset(of: tagSet(from: tagArray))) {
                    emit(url: url, tags: tagArray)
                }
            } catch {
                reportFatalError(error, on: url)
            }
        }
    }

    private func doList() {
        enumerateURLs { url in
            do {
                emit(url: url, tags: try tags(for: url))
            } catch {
                reportFatalError(error, on: url)
            }
        }
    }

    private func doFind() {
        findGuts(usageMode: false)
    }

    private func doUsage() {
        findGuts(usageMode: true)
    }

    private func findGuts(usageMode: Bool) {
        guard let metadataQuery = performMetadataSearch(for: tags, usageMode: usageMode), !shouldStop else {
            return
        }

        if usageMode {
            let valueLists = metadataQuery.valueLists as NSDictionary
            guard let tuples = valueLists[metadataItemUserTags] as? [NSMetadataQueryAttributeValueTuple] else {
                return
            }
            for tuple in tuples {
                let tag = tuple.value is NSNull ? "<no_tag>" : String(describing: tuple.value)
                print("\(tuple.count)\t\(displayString(forTag: tag))")
            }
        } else {
            for result in metadataQuery.results {
                guard let item = result as? NSMetadataItem,
                      let path = item.value(forAttribute: metadataItemPath) as? String else {
                    continue
                }
                let tagArray = item.value(forAttribute: metadataItemUserTags) as? [String] ?? []
                emit(url: URL(fileURLWithPath: path), tags: tagArray)
            }
        }
    }

    private func performMetadataSearch(for tagSet: Set<TagName>, usageMode: Bool) -> NSMetadataQuery? {
        let metadataQuery = NSMetadataQuery()
        let observer = MetadataQueryObserver()

        NotificationCenter.default.addObserver(
            observer,
            selector: #selector(MetadataQueryObserver.queryComplete(_:)),
            name: NSNotification.Name.NSMetadataQueryDidFinishGathering,
            object: metadataQuery
        )
        defer {
            NotificationCenter.default.removeObserver(
                observer,
                name: NSNotification.Name.NSMetadataQueryDidFinishGathering,
                object: metadataQuery
            )
        }

        metadataQuery.predicate = queryPredicate(for: tagSet)
        metadataQuery.searchScopes = searchScopes()
        metadataQuery.sortDescriptors = [NSSortDescriptor(key: metadataItemDisplayName, ascending: true)]
        if usageMode {
            metadataQuery.valueListAttributes = [metadataItemUserTags]
        }
        metadataQuery.operationQueue = .main

        guard metadataQuery.start() else {
            reportFatalError("Metadata query could not be started", on: nil)
            return nil
        }

        let deadline = Date(timeIntervalSinceNow: metadataQueryTimeout)
        while !observer.finished && deadline.timeIntervalSinceNow > 0 {
            let nextRunDate = min(Date(timeIntervalSinceNow: 0.1), deadline)
            if !RunLoop.current.run(mode: .default, before: nextRunDate) {
                break
            }
        }

        if !observer.finished {
            metadataQuery.stop()
            reportFatalError("Metadata query timed out; Spotlight may be disabled, unavailable, or still indexing", on: nil)
            return nil
        }

        return metadataQuery
    }

    private func queryPredicate(for tagSet: Set<TagName>) -> NSPredicate {
        if wildcard(in: tagSet) {
            return NSPredicate(format: "%K LIKE '*'", metadataItemUserTags)
        }
        if tagSet.isEmpty {
            return NSPredicate(format: "NOT %K LIKE '*'", metadataItemUserTags)
        }
        if tagSet.count == 1, let tag = tagSet.first {
            return NSPredicate(format: "%K ==[c] %@", metadataItemUserTags, tag.visibleName)
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: tagSet.map {
            NSPredicate(format: "%K ==[c] %@", metadataItemUserTags, $0.visibleName)
        })
    }

    private func searchScopes() -> [Any] {
        var result: [Any] = urls
        switch searchScope {
        case .none:
            break
        case .home:
            result.append(NSMetadataQueryUserHomeScope)
        case .local:
            result.append(NSMetadataQueryLocalComputerScope)
        case .network:
            result.append(NSMetadataQueryLocalComputerScope)
            result.append(NSMetadataQueryNetworkScope)
        }
        return result
    }

    private func enumerateURLs(_ block: (URL) -> Void) {
        if urls.isEmpty {
            enumerateDirectory(URL(fileURLWithPath: FileManager.default.currentDirectoryPath), block)
            return
        }

        for url in urls {
            if shouldStop { break }
            block(url)
            if enterDirectories || recurseDirectories {
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDirectory {
                    enumerateDirectory(url, block)
                }
            }
        }
    }

    private func enumerateDirectory(_ directoryURL: URL, _ block: (URL) -> Void) {
        var options: FileManager.DirectoryEnumerationOptions = []
        if !displayAllFiles {
            options.insert(.skipsHiddenFiles)
        }
        if !recurseDirectories {
            options.insert(.skipsSubdirectoryDescendants)
        }

        let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.tagNamesKey],
            options: options
        ) { [weak self] url, error in
            self?.reportFatalError(error, on: url)
            return false
        }

        let baseURLString = directoryURL.absoluteString
        while let fullURL = enumerator?.nextObject() as? URL {
            if shouldStop { break }
            if fullURL.absoluteString.hasPrefix(baseURLString) {
                let relativePart = String(fullURL.absoluteString.dropFirst(baseURLString.count))
                block(URL(string: relativePart, relativeTo: directoryURL) ?? fullURL)
            } else {
                block(fullURL)
            }
        }
    }

    private func tags(for url: URL) throws -> [String] {
        let values = try url.resourceValues(forKeys: [.tagNamesKey])
        return values.tagNames ?? []
    }

    private func emit(url: URL, tags tagArray: [String]) {
        let lineTerminator = outputFlags.contains(.nulTerminate) ? "\0" : "\n"
        var fileName: String?
        if outputFlags.contains(.name) {
            var suffix = ""
            if outputFlags.contains(.slashDirectory) {
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDirectory {
                    suffix = "/"
                }
            }
            fileName = "\(url.relativePath)\(suffix)"
        }

        let tagsOnSeparateLines = outputFlags.contains(.garrulous)
        let printTags = outputFlags.contains(.tags) && !tagArray.isEmpty

        if let fileName {
            let fileField = printTags && !tagsOnSeparateLines ? padded(fileName, toMinimumLength: 31) : fileName
            printWithoutNewline(fileField)
        }

        if printTags {
            var needLineTerminator = false
            let tagSeparator: String
            var separator: String
            if tagsOnSeparateLines {
                needLineTerminator = fileName != nil
                tagSeparator = fileName != nil ? "    " : ""
                separator = tagSeparator
            } else {
                tagSeparator = ","
                separator = fileName != nil ? "\t" : ""
            }

            for tag in tagArray.sorted() {
                if needLineTerminator {
                    printWithoutNewline(lineTerminator)
                }
                printWithoutNewline("\(separator)\(displayString(forTag: tag))")
                separator = tagSeparator
                needLineTerminator = tagsOnSeparateLines
            }
        }

        if fileName != nil || printTags {
            printWithoutNewline(lineTerminator)
        }
    }

    private func displayString(forTag tag: String) -> String {
        guard colorOutputEnabled, let colorSequence = tagColors[TagName(tag)] else {
            return tag
        }
        return "\(colorSequence)\(tag)\(colorProvider.resetSequence)"
    }

    private func tagSet(from tagArray: [String]) -> Set<TagName> {
        Set(tagArray.map(TagName.init))
    }

    private func tagArray(from tagSet: Set<TagName>) -> [String] {
        tagSet.map(\.visibleName)
    }

    private func wildcard(in tagSet: Set<TagName>) -> Bool {
        tagSet.contains(TagName("*"))
    }

    private func padded(_ string: String, toMinimumLength minLength: Int) -> String {
        guard string.count < minLength else {
            return string
        }
        return string.padding(toLength: minLength, withPad: "    ", startingAt: 0)
    }

    private func reportFatalError(_ error: Error, on url: URL?) {
        reportFatalError((error as NSError).localizedDescription, on: url)
    }

    private func reportFatalError(_ message: String, on url: URL?) {
        if let path = url?.relativePath, !path.isEmpty {
            printError("\(programName()): \(path): \(message)")
        } else {
            printError("\(programName()): \(message)")
        }
        exitStatus = 2
        shouldStop = true
    }

    private func displayVersion() {
        print("\(programName()) v\(version)")
    }

    private func displayHelp() {
        printWithoutNewline("""
        \(programName()) - A tool for manipulating and querying file tags.
          usage:
            tag -a | --add <tags> <path>...     Add tags to file
            tag -r | --remove <tags> <path>...  Remove tags from file
            tag -s | --set <tags> <path>...     Set tags on file
            tag -m | --match <tags> <path>...   Display files with matching tags
            tag -f | --find <tags> <path>...    Find all files with tags (-A, -e, -R ignored)
            tag -u | --usage <tags> <path>...   Display tags used, with usage counts
            tag -l | --list <path>...           List the tags on file
          <tags> is a comma-separated list of tag names; use * to match/find any tag.
          additional options:
                -v | --version      Display version
                -h | --help         Display this help
                -A | --all          Display invisible files while enumerating
                -e | --enter        Enter and enumerate directories provided
                -R | --recursive    Recursively process directories
                -n | --name         Turn on filename display in output (default)
                -N | --no-name      Turn off filename display in output (list, find, match)
                -t | --tags         Turn on tags display in output (find, match)
                -T | --no-tags      Turn off tags display in output (list)
                -g | --garrulous    Display tags each on own line (list, find, match)
                -G | --no-garrulous Display tags comma-separated after filename (default)
                -c | --color        Display tags in color
                -p | --slash        Terminate each directory name with a slash
                -0 | --nul          Terminate lines with NUL (\\0) for use with xargs -0
                     --home         Find tagged files in user home directory
                     --local        Find tagged files in home + local filesystems
                     --network      Find tagged files in home + local + network filesystems
        """)
    }

    private func programName() -> String {
        URL(fileURLWithPath: CommandLine.arguments.first ?? "tag").lastPathComponent
    }
}

private func printWithoutNewline(_ string: String) {
    FileHandle.standardOutput.write(Data(string.utf8))
}

private func printError(_ string: String) {
    FileHandle.standardError.write(Data((string + "\n").utf8))
}

private extension URL {
    mutating func setTagNames(_ tagNames: [String]) throws {
        try (self as NSURL).setResourceValue(tagNames, forKey: .tagNamesKey)
    }
}

exit(TagCLI().run(arguments: Array(CommandLine.arguments.dropFirst())))
