import Foundation

struct Parser<Output> {
    let run: (inout Substring) -> Output?
}

extension Parser {
    func run(_ input: String) -> (match: Output?, rest: Substring) {
        var input = input[...]
        let match = self.run(&input)
        return (match, input)
    }
}




//MARK: - prefix
extension Parser where Output == Void {
    static func prefix(_ p: String) -> Self {
        Self { input in
            guard input.hasPrefix(p) else { return nil }
            input.removeFirst(p.count)
            return ()
        }
    }
}

extension Parser: ExpressibleByUnicodeScalarLiteral where Output == Void {}
extension Parser: ExpressibleByExtendedGraphemeClusterLiteral where Output == Void {}
extension Parser: ExpressibleByStringLiteral where Output == Void {
    typealias StringLiteralType = String
    
    init(stringLiteral value: String) {
        self = .prefix(value)
    }
}

Parser.prefix("cat").run("cat dog")
Parser.prefix("cat").run("dog cat")





//MARK: - always, never
extension Parser {
    static func always(_ output: Output) -> Self {
        Self { _ in output }
    }
    
    static var never: Self {
        Self { _ in nil }
    }
}



//MARK: - int
extension Parser where Output == Int {
    static let int = Self { input in
        let original = input

        var isFirstCharacter = true
        let intPrefix = input.prefix { character in
            defer { isFirstCharacter = false }
            return (character == "-" || character == "+") && isFirstCharacter || character.isNumber
        }

        guard let match = Int(intPrefix) else {
            input = original
            return nil
        }
        input.removeFirst(intPrefix.count)
        return match
    }
}

Parser.int.run("42")
Parser.int.run("42 Hello World")
Parser.int.run("-42 Hello World")
Parser.int.run("--42 Hello World")
Parser.int.run("+42 Hello World")




//MARK: - double
extension Parser where Output == Double {
    static let double = Self { input in
        var sign: Double = 1.0
        let original = input
        if input.first == "-" {
            sign = -1
            input.removeFirst()
        }  else if input.first == "+" {
            input.removeFirst()
        }
        
        var decimalCount = 0
        let prefix = input.prefix { char in
            if char == "." { decimalCount += 1 }
            return char.isNumber || (char == "." && decimalCount <= 1)
        }
        
        guard let match = Double(prefix)
        else {
            input = original
            return nil
        }
        input.removeFirst(prefix.count)
        return match * sign
    }
}

Parser.double.run("42")
Parser.double.run("42.3423423423")
Parser.double.run("42.3423423423 Hello world!")
Parser.double.run("42.4.5.6.3.2")
Parser.double.run(".42")
Parser.double.run("-42")
Parser.double.run("+42")




//MARK: - char
extension Parser where Output == Character {
    static let char = Self { input in
        guard !input.isEmpty else { return nil }
        return input.removeFirst()
    }
}

Parser.char.run("Hello")
Parser.char.run("")




//MARK: - map
extension Parser {
    func map<NewOutput>(_ f: @escaping (Output) -> NewOutput) -> Parser<NewOutput> {
        .init { input -> NewOutput? in
            self.run(&input).map(f)
        }
    }
}

let even = Parser.int.map { $0.isMultiple(of: 2) }
even.run("123 Hello")
even.run("124 Hello")




//MARK: - flatMap
extension Parser {
    func flatMap<NewOutput>(_ f: @escaping (Output) -> Parser<NewOutput>) -> Parser<NewOutput> {
        return .init { input -> NewOutput? in
            let original = input
            let output = self.run(&input)
            let newParser = output.map(f)
            guard let newOutput = newParser?.run(&input) else {
                input = original
                return nil
            }
            return newOutput
        }
    }
}





//MARK: - zip
func zip<Output1, Output2>(
    _ p1: Parser<Output1>,
    _ p2: Parser<Output2>
) -> Parser<(Output1, Output2)> {
    .init { input -> (Output1, Output2)? in
        let original = input
        guard let output1 = p1.run(&input) else { return nil }
        guard let output2 = p2.run(&input)
        else {
            input = original
            return nil
        }
        return (output1, output2)
    }
}

func zip<A, B, C>(
    _ a: Parser<A>,
    _ b: Parser<B>,
    _ c: Parser<C>
) -> Parser<(A, B, C)> {
    return zip(a, zip(b, c))
        .map { a, bc in (a, bc.0, bc.1) }
}

func zip<A, B, C, D>(
    _ a: Parser<A>,
    _ b: Parser<B>,
    _ c: Parser<C>,
    _ d: Parser<D>
) -> Parser<(A, B, C, D)> {
    return zip(a, b, zip(c, d))
        .map { a, b, cd in (a, b, cd.0, cd.1) }
}

func zip<A, B, C, D, E>(
    _ a: Parser<A>,
    _ b: Parser<B>,
    _ c: Parser<C>,
    _ d: Parser<D>,
    _ e: Parser<E>
) -> Parser<(A, B, C, D, E)> {
    return zip(a, b, c, zip(d, e))
        .map { a, b, c, de in (a, b, c, de.0, de.1) }
}

func zip<A, B, C, D, E, F>(
    _ a: Parser<A>,
    _ b: Parser<B>,
    _ c: Parser<C>,
    _ d: Parser<D>,
    _ e: Parser<E>,
    _ f: Parser<F>
) -> Parser<(A, B, C, D, E, F)> {
    return zip(a, b, c, d, zip(e, f))
        .map { a, b, c, d, ef in (a, b, c, d, ef.0, ef.1) }
}

func zip<A, B, C, D, E, F, G>(
    _ a: Parser<A>,
    _ b: Parser<B>,
    _ c: Parser<C>,
    _ d: Parser<D>,
    _ e: Parser<E>,
    _ f: Parser<F>,
    _ g: Parser<G>
) -> Parser<(A, B, C, D, E, F, G)> {
    return zip(a, b, c, d, e, zip(f, g))
        .map { a, b, c, d, e, fg in (a, b, c, d, e, fg.0, fg.1) }
}




//MARK: - oneOf
extension Parser {
    static func oneOf(_ ps: [Self]) -> Self {
        return .init { input in
            for p in ps {
                if let match = p.run(&input) {
                    return match
                }
            }
            return nil
        }
    }
    
    static func oneOf(_ ps: Self...) -> Self {
        self.oneOf(ps)
    }
}





//MARK: - prefix while
extension Parser where Output == Substring {
    static func prefix(while p: @escaping (Character) -> Bool) -> Self {
        Self { input in
            let output = input.prefix(while: p)
            input.removeFirst(output.count)
            return output
        }
    }
}





//MARK: - zeroOrMore
extension Parser {
    func zeroOrMore(
        seperatedBy separator: Parser<Void> = ""
    ) -> Parser<[Output]> {
        Parser<[Output]> { input in
            var rest = input
            var matches: [Output] = []
            while let match = self.run(&input) {
                rest = input
                matches.append(match)
                if separator.run(&input) == nil {
                    return matches
                }
            }
            input = rest
            return matches
        }
    }
}




//MARK: - skip
extension Parser {
    func skip<B>(_ p: Parser<B>) -> Self {
        zip(self, p).map { a, _ in a }
    }
}

//MARK: - take
extension Parser {
    func take<NewOutput>(_ p: Parser<NewOutput>) -> Parser<(Output, NewOutput)> {
        zip(self, p)
    }
}

extension Parser {
    static func skip(_ p: Self) -> Parser<Void> {
        p.map { _ in () }
    }
}

extension Parser where Output == Void {
    func take<A>(_ p: Parser<A>) -> Parser<A> {
        zip(self, p).map { _, b in b }
    }
}

extension Parser {
    func take<A, B, C>(_ p: Parser<C>) -> Parser<(A, B, C)> where Output == (A, B) {
        zip(self, p).map { ab, c in (ab.0, ab.1, c)  }
    }
}




let evenInt = Parser.int
    .flatMap { n in
        n.isMultiple(of: 2) ? .always(n) : .never
    }

evenInt.run("124 hello")




let temperature = Parser.int
    .skip("°F")
temperature.run("100°F")





//MARK: - Coordinate
"40.6782° N, 73.9442° W"

struct Coordinate {
    let latitude: Double
    let longitude: Double
}

let northSouth = Parser.char.flatMap {
    $0 == "N" ? .always(1.0)
    : $0 == "S" ? .always(-1)
    : .never
}

let eastWest = Parser.char.flatMap {
    $0 == "E" ? .always(1.0)
    : $0 == "W" ? .always(-1)
    : .never
}

let zeroOrMOreSpaces = Parser.prefix(" ").zeroOrMore()

let latitude = Parser.double
    .skip("°")
    .skip(zeroOrMOreSpaces)
    .take(northSouth)
    .map(*)

let longtitude = Parser.double
    .skip("°")
    .skip(zeroOrMOreSpaces)
    .take(eastWest)
    .map(*)

let coord = latitude
    .skip(",")
    .skip(zeroOrMOreSpaces)
    .take(longtitude)
    .map(Coordinate.init)

coord.run("40.6782° N, 73.9442° W")
coord.run("40.6782°   N,   73.9442° W")





//MARK: - Currency
enum Currency: String, CaseIterable {
    case usd = "$"
    case eur = "€"
    case gbp = "£"
    case uah = "₴"
}

struct Money {
    let currency: Currency
    let value: Double
}

let currency = Parser.oneOf(
    Currency.allCases.map { currency in Parser.prefix(currency.rawValue).map { currency } }
)

let money = zip(currency, .double)
    .map(Money.init(currency:value:))

money.run("$200.5")
money.run("200.5")
money.run("₴200.5")




//MARK: - Races
struct Race {
    let location: String
    let entranceFee: Money
    let path: [Coordinate]
}

let locationName = Parser.prefix(while: { $0 != "," })

let race = locationName
    .map(String.init)
    .skip(", ")
    .take(money)
    .skip("\n")
    .take(coord.zeroOrMore(seperatedBy: "\n"))
    .map(Race.init(location:entranceFee:path:))

let races = race.zeroOrMore(seperatedBy: "\n---\n")

let upcomingRaces = """
New York City, $300
40.60248° N, 74.06433° W
40.61807° N, 74.02966° W
40.64953° N, 74.00929° W
40.67884° N, 73.98198° W
40.69894° N, 73.95701° W
40.72791° N, 73.95314° W
40.74882° N, 73.94221° W
40.75740° N, 73.95309° W
40.76149° N, 73.96142° W
40.77111° N, 73.95362° W
40.80260° N, 73.93061° W
40.80409° N, 73.92893° W
40.81432° N, 73.93292° W
40.80325° N, 73.94472° W
40.77392° N, 73.96917° W
40.77293° N, 73.97671° W
---
Berlin, €100
13.36015° N, 52.51516° E
13.33999° N, 52.51381° E
13.32539° N, 52.51797° E
13.33696° N, 52.52507° E
13.36454° N, 52.52278° E
13.38152° N, 52.52295° E
13.40072° N, 52.52969° E
13.42555° N, 52.51508° E
13.41858° N, 52.49862° E
13.40929° N, 52.48882° E
13.37968° N, 52.49247° E
13.34898° N, 52.48942° E
13.34103° N, 52.47626° E
13.32851° N, 52.47122° E
13.30852° N, 52.46797° E
13.28742° N, 52.47214° E
13.29091° N, 52.48270° E
13.31084° N, 52.49275° E
13.32052° N, 52.50190° E
13.34577° N, 52.50134° E
13.36903° N, 52.50701° E
13.39155° N, 52.51046° E
13.37256° N, 52.51598° E
---
London, £500
51.48205° N, 0.04283° E
51.47439° N, 0.02170° E
51.47618° N, 0.02199° E
51.49295° N, 0.05658° E
51.47542° N, 0.03019° E
51.47537° N, 0.03015° E
51.47435° N, 0.03733° E
51.47954° N, 0.04866° E
51.48604° N, 0.06293° E
51.49314° N, 0.06104° E
51.49248° N, 0.04740° E
51.48888° N, 0.03564° E
51.48655° N, 0.01830° E
51.48085° N, 0.02223° W
51.49210° N, 0.04510° W
51.49324° N, 0.04699° W
51.50959° N, 0.05491° W
51.50961° N, 0.05390° W
51.49950° N, 0.01356° W
51.50898° N, 0.02341° W
51.51069° N, 0.04225° W
51.51056° N, 0.04353° W
51.50946° N, 0.07810° W
51.51121° N, 0.09786° W
51.50964° N, 0.11870° W
51.50273° N, 0.13850° W
51.50095° N, 0.12411° W
"""

race.run(upcomingRaces)
races.run(upcomingRaces)





//MARK: - prefix upTo, through
extension Parser where Output == Substring {
    static func prefix(upTo substring: Substring) -> Self {
        Self { input in
            guard let endIndex = input.range(of: substring)?.lowerBound
            else { return nil }
            
            let match = input[..<endIndex]
            
            input = input[endIndex...]
            
            return match
        }
    }
    
    static func prefix(through substring: Substring) -> Self {
        Self { input in
            guard let endIndex = input.range(of: substring)?.upperBound
            else { return nil }
            
            let match = input[..<endIndex]
            
            input = input[endIndex...]
            
            return match
        }
    }
}





//MARK: - Test Logs parsing
let logs = """
Testing started
2023-01-28 21:28:29.056803+0200 VoiceMemos[12044:277672] [SceneConfiguration] Info.plist configuration "(no name)" for UIWindowSceneSessionRoleApplication contained UISceneDelegateClassName key, but could not load class with name "VoiceMemos.SceneDelegate".
2023-01-28 21:28:29.059268+0200 VoiceMemos[12044:277672] [SceneConfiguration] Info.plist configuration "(no name)" for UIWindowSceneSessionRoleApplication contained UISceneDelegateClassName key, but could not load class with name "VoiceMemos.SceneDelegate".
2023-01-28 21:28:29.061754+0200 VoiceMemos[12044:277672] [SceneConfiguration] Info.plist configuration "(no name)" for UIWindowSceneSessionRoleApplication contained UISceneDelegateClassName key, but could not load class with name "VoiceMemos.SceneDelegate".
Test Suite 'All tests' started at 2023-01-28 21:28:30.920
Test Suite 'VoiceMemosTests.xctest' started at 2023-01-28 21:28:30.922
Test Suite 'VoiceMemosTests' started at 2023-01-28 21:28:30.923
Test Case '-[VoiceMemosTests.VoiceMemosTests testDeleteMemoWhilePlaying]' started.
Test Case '-[VoiceMemosTests.VoiceMemosTests testDeleteMemoWhilePlaying]' passed (12.834 seconds).
Test Case '-[VoiceMemosTests.VoiceMemosTests testDeleteMemo]' started.
Test Case '-[VoiceMemosTests.VoiceMemosTests testDeleteMemo]' passed (2.750 seconds).
Test Case '-[VoiceMemosTests.VoiceMemosTests testPermissionDenied]' started.
Test Case '-[VoiceMemosTests.VoiceMemosTests testPermissionDenied]' passed (7.598 seconds).
Test Case '-[VoiceMemosTests.VoiceMemosTests testPlayMemoFailure]' started.
/Users/vladyslavfil/iOS_Developer/swift-composable-architecture/Examples/VoiceMemos/VoiceMemosTests/VoiceMemosTests.swift:238: error: -[VoiceMemosTests.VoiceMemosTests testPlayMemoFailure] : A state change does not match expectation: …

      VoiceMemos.State(
    −   alert: nil,
    +   alert: AlertState(title: "Voice memo playback failed."),
        audioRecorderPermission: VoiceMemos.State.RecorderPermission.undetermined,
        recordingMemo: nil,
        voiceMemos: […]
      )

(Expected: −, Actual: +)
Test Case '-[VoiceMemosTests.VoiceMemosTests testPlayMemoFailure]' failed (3.499 seconds).
Test Case '-[VoiceMemosTests.VoiceMemosTests testPlayMemoHappyPath]' started.
Test Case '-[VoiceMemosTests.VoiceMemosTests testPlayMemoHappyPath]' passed (10.506 seconds).
Test Case '-[VoiceMemosTests.VoiceMemosTests testRecordMemoFailure_NonExhaustive]' started.
VoiceMemosTests.swift:164: Expected failure in -[VoiceMemosTests.VoiceMemosTests testRecordMemoFailure_NonExhaustive]: Skipped assertions: …

Must handle 1 received action before sending an action: …

Unhandled actions: [
  [0]: VoiceMemos.Action.recordPermissionResponse(true)
]
TestStore.swift:901: Expected failure in -[VoiceMemosTests.VoiceMemosTests testRecordMemoFailure_NonExhaustive]: Skipped assertions: …

1 received action was skipped:

VoiceMemos.Action.recordPermissionResponse(true)
VoiceMemosTests.swift:166: Expected failure in -[VoiceMemosTests.VoiceMemosTests testRecordMemoFailure_NonExhaustive]: Skipped assertions: …

1 received action was skipped:

[
  [0]: VoiceMemos.Action.recordingMemo(
    RecordingMemo.Action.audioRecorderDidFinish(
      TaskResult.failure(VoiceMemosTests.SomeError())
    )
  )
]
VoiceMemosTests.swift:164: Expected failure in -[VoiceMemosTests.VoiceMemosTests testRecordMemoFailure_NonExhaustive]: Skipped assertions: …

An effect returned for this action is still running. It must complete before the end of the test. …

To fix, inspect any effects the reducer returns for this action and ensure that all of them complete by the end of the test. There are a few reasons why an effect may not have completed:

• If using async/await in your effect, it may need a little bit of time to properly finish. To fix you can simply perform "await store.finish()" at the end of your test.

• If an effect uses a clock/scheduler (via "receive(on:)", "delay", "debounce", etc.), make sure that you wait enough time for it to perform the effect. If you are using a test clock/scheduler, advance it so that the effects may complete, or consider using an immediate clock/scheduler to immediately perform the effect instead.

• If you are returning a long-living effect (timers, notifications, subjects, etc.), then make sure those effects are torn down by marking the effect ".cancellable" and returning a corresponding cancellation effect ("Effect.cancel") from another action, or, if your effect is driven by a Combine subject, send it a completion.
Test Case '-[VoiceMemosTests.VoiceMemosTests testRecordMemoFailure_NonExhaustive]' passed (14.799 seconds).
Test Case '-[VoiceMemosTests.VoiceMemosTests testRecordMemoFailure]' started.
/Users/vladyslavfil/iOS_Developer/swift-composable-architecture/Examples/VoiceMemos/VoiceMemosTests/VoiceMemosTests.swift:133: error: -[VoiceMemosTests.VoiceMemosTests testRecordMemoFailure] : A state change does not match expectation: …

      VoiceMemos.State(
    −   alert: nil,
    +   alert: AlertState(title: "Voice memo recording failed."),
        audioRecorderPermission: VoiceMemos.State.RecorderPermission.allowed,
        recordingMemo: nil,
        voiceMemos: []
      )

(Expected: −, Actual: +)
Test Case '-[VoiceMemosTests.VoiceMemosTests testRecordMemoFailure]' failed (4.741 seconds).
Test Case '-[VoiceMemosTests.VoiceMemosTests testRecordMemoHappyPath]' started.
Test Case '-[VoiceMemosTests.VoiceMemosTests testRecordMemoHappyPath]' passed (12.549 seconds).
Test Case '-[VoiceMemosTests.VoiceMemosTests testStopMemo]' started.
Test Case '-[VoiceMemosTests.VoiceMemosTests testStopMemo]' passed (4.053 seconds).
Test Suite 'VoiceMemosTests' failed at 2023-01-28 21:29:44.258.
     Executed 9 tests, with 2 failures (0 unexpected) in 73.329 (73.335) seconds
Test Suite 'VoiceMemosTests.xctest' failed at 2023-01-28 21:29:44.259.
     Executed 9 tests, with 2 failures (0 unexpected) in 73.329 (73.338) seconds
Test Suite 'All tests' failed at 2023-01-28 21:29:44.261.
     Executed 9 tests, with 2 failures (0 unexpected) in 73.329 (73.341) seconds
2023-01-28 21:32:20.125 xcodebuild[11725:272180] [MT] IDETestOperationsObserverDebug: 399.172 elapsed -- Testing started completed.
2023-01-28 21:32:20.125 xcodebuild[11725:272180] [MT] IDETestOperationsObserverDebug: 0.000 sec, +0.000 sec -- start
2023-01-28 21:32:20.125 xcodebuild[11725:272180] [MT] IDETestOperationsObserverDebug: 399.173 sec, +399.173 sec -- end

Test session results, code coverage, and logs:
    /Users/vladyslavfil/Library/Developer/Xcode/DerivedData/ComposableArchitecture-gmelkzmfzlvpcpfeupqrszzczdkg/Logs/Test/Test-VoiceMemos-2023.01.28_21-25-28-+0200.xcresult

Failing tests:
    VoiceMemosTests.testPlayMemoFailure()
    VoiceMemosTests.testRecordMemoFailure()

"""

let testCaseStartedLine = Parser
    .skip(.prefix(upTo: "Test Case '-["))
    .take(.prefix(through: "\n"))
    .map { $0.split(separator: " ")[3].dropLast(2) }

let fileName = Parser
    .skip("/")
    .take(.prefix(through: ".swift"))
    .flatMap { path in
        path.split(separator: "/").last.map(Parser.always) ?? .never
    }

let testCaseBody = fileName
    .skip(":")
    .take(.int)
    .skip(.prefix(through: "] : "))
    .take(Parser.prefix(upTo: "Test Case '-[").map { $0.dropLast() })


let testCaseFinishedLine = Parser
    .skip(.prefix(through: " ("))
    .take(.double)
    .skip(" seconds).\n")

enum TestResult {
    case failed(failureMessage: Substring, file: Substring, line: Int, testName: Substring, time: TimeInterval)
    case passed(testName: Substring, time: TimeInterval)
}

let testFaild = testCaseStartedLine
    .take(testCaseBody)
    .take(testCaseFinishedLine)
    .map { testName, bodyData, time in
        TestResult.failed(
            failureMessage: bodyData.2,
            file: bodyData.0,
            line: bodyData.1,
            testName: testName,
            time: time
        )
    }

let testPassed = testCaseStartedLine
            .take(testCaseFinishedLine)
            .map(TestResult.passed(testName:time:))

let testResult: Parser<TestResult> = .oneOf(testFaild, testPassed)
let testResults: Parser<[TestResult]> = testResult.zeroOrMore()

func format(result: TestResult) -> String {
    switch result {
    case let .failed(failureMessage, file, line, testName, time):
        var output = "\(file):\(line), \(testName) failed in \(time) seconds."
        output.append("\n")
        output.append("  ┃")
        output.append("\n")
        output.append(
            failureMessage
                .split(separator: "\n")
                .map { "  ┃  \($0)" }
                .joined(separator: "\n")
        )
        output.append("\n")
        output.append("  ┃")
        output.append("\n")
        output.append("  ┗━━──────────────")
        output.append("\n")
        return output
    case let .passed(testName, time):
        return "\(testName) passed in \(time) seconds."
    }
}

testResults.run(logs).match?.forEach {
    print(format(result: $0))
}
