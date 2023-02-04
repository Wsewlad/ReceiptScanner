import Foundation

struct Parser<Input, Output> {
    let run: (inout Input) -> Output?
}

extension Parser {
    func run(_ input: Input) -> (match: Output?, rest: Input) {
        var input = input
        let match = self.run(&input)
        return (match, input)
    }
}

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
extension Parser where Input == Substring, Output == Int {
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

Parser.int.run("42 Hello World")

//MARK: - UInt64
extension Parser where Input == Substring, Output == UInt64 {
    static let uint64 = Self { input in
        let original = input

        var isFirstCharacter = true
        let intPrefix = input.prefix { character in
            defer { isFirstCharacter = false }
            return (character == "+") && isFirstCharacter || character.isNumber
        }

        guard let match = UInt64(intPrefix) else {
            input = original
            return nil
        }
        input.removeFirst(intPrefix.count)
        return match
    }
}


//MARK: - double
extension Parser where Input == Substring, Output == Double {
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
            if char == "." || char == "," { decimalCount += 1 }
            return char.isNumber || ((char == "." || char == ",") && decimalCount <= 1)
        }

        guard let match = Double(prefix.replacing(",", with: "."))
        else {
            input = original
            return nil
        }
        input.removeFirst(prefix.count)
        return match * sign
    }
}

Parser.double.run("42.3423 Hello world!")
Parser.double.run("42,3423 Hello world!")

//MARK: - char
extension Parser where Input == Substring, Output == Character {
    static let char = Self { input in
        guard !input.isEmpty else { return nil }
        return input.removeFirst()
    }
}

//MARK: - map
extension Parser {
    func map<NewOutput>(_ f: @escaping (Output) -> NewOutput) -> Parser<Input, NewOutput> {
        .init { input -> NewOutput? in
            self.run(&input).map(f)
        }
    }
}

//MARK: - flatMap
extension Parser {
    func flatMap<NewOutput>(_ f: @escaping (Output) -> Parser<Input, NewOutput>) -> Parser<Input, NewOutput> {
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
func zip<Input, Output1, Output2>(
    _ p1: Parser<Input, Output1>,
    _ p2: Parser<Input, Output2>
) -> Parser<Input, (Output1, Output2)> {
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

//MARK: - zeroOrMore
extension Parser {
    func zeroOrMore(
        seperatedBy separator: Parser<Input, Void> = .always(())
    ) -> Parser<Input, [Output]> {
        Parser<Input, [Output]> { input in
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

//MARK: - prefix
extension Parser
where Input: Collection,
      Input.Element: Equatable,
      Input.SubSequence == Input,
      Output == Void {
    static func prefix(_ p: Input.SubSequence) -> Self {
        Self { input in
            guard input.starts(with: p) else { return nil }
            input.removeFirst(p.count)
            return ()
        }
    }
}

//MARK: - prefix while
extension Parser
where Input: Collection,
      Input.SubSequence == Input,
      Output == Input {
          static func prefix(while p: @escaping (Input.Element) -> Bool) -> Self {
        Self { input in
            let output = input.prefix(while: p)
            input.removeFirst(output.count)
            return output
        }
    }
}

//MARK: - prefix upTo, through
extension Parser
where Input: Collection,
      Input.SubSequence == Input,
      Input.Element: Equatable,
      Output == Input {
    static func prefix(upTo subsequence: Input) -> Self {
        Self { input in
            guard !subsequence.isEmpty else { return subsequence }
            let original = input
            while !input.isEmpty {
                if input.starts(with: subsequence) {
//                    return original[..<input.startIndex]
                    let output = original[..<input.startIndex]
                    if output.isEmpty {
                        input = original
                        return nil
                    }
                    return output
                }
                input.removeFirst()
            }
            input = original
            return nil
        }
    }

    static func prefix(through subsequence: Input) -> Self {
        Self { input in
            guard !subsequence.isEmpty else { return subsequence }
            let original = input
            while !input.isEmpty {
                if input.starts(with: subsequence) {
                    let index = input.index(input.startIndex, offsetBy: subsequence.count)
                    input = input[index...]
//                    return original[..<index]
                    let output = original[..<index]
                    if original[..<input.startIndex].isEmpty {
                        input = original
                        return nil
                    }
                    return output
                }
                input.removeFirst()
            }
            input = original
            return nil
        }
    }
}

extension Parser: ExpressibleByUnicodeScalarLiteral where Input == Substring, Output == Void {}
extension Parser: ExpressibleByExtendedGraphemeClusterLiteral where Input == Substring, Output == Void {}
extension Parser: ExpressibleByStringLiteral where Input == Substring, Output == Void {
    typealias StringLiteralType = String

    init(stringLiteral value: String) {
        self = .prefix(value[...])
    }
}

extension Parser where Input == Substring, Output == Substring {
    static func prefix<B>(upToParser p: Parser<Input, B>) -> Self {
        Self { input -> Substring? in
            guard !input.isEmpty
            else { return nil }

            var original = input
            var endIndex = original.startIndex
            while p.run(&input) == nil {
                if endIndex <= original.endIndex {
                    endIndex = original.index(after: endIndex)
                } else {
                    input = original
                    return nil
                }
                input = input[endIndex...]
            }
            input = original[endIndex...]
//            return original[..<endIndex]
            
            let output = original[..<endIndex]
            if output.isEmpty {
                input = original
                return nil
            }
            return output
        }
    }

    static func prefix<B>(throughParser p: Parser<Input, B>) -> Self {
        Self { input -> Substring? in
            guard !input.isEmpty
            else { return nil }

            var original = input
            var endIndex = original.startIndex
            var output: B? = p.run(&input)
            while output == nil {
                if endIndex <= original.endIndex {
                    endIndex = original.index(after: endIndex)
                } else {
                    input = original
                    return nil
                }
                input = input[endIndex...]
                output = p.run(&input)
            }
            guard let endIndex = original.range(of: input)?.lowerBound
            else { return nil }

//            return original[..<endIndex]
            
            let result = original[..<endIndex]
            if original[..<input.startIndex].isEmpty {
                input = original
                return nil
            }
            return result
        }
    }
}


//MARK: - skip
extension Parser {
    static func skip(_ p: Self) -> Parser<Input, Void> {
        p.map { _ in () }
    }
    
    func skip<OtherOutput>(_ p: Parser<Input, OtherOutput>) -> Self {
        zip(self, p).map { a, _ in a }
    }
    
    func take<NewOutput>(_ p: Parser<Input, NewOutput>) -> Parser<Input, (Output, NewOutput)> {
        zip(self, p)
    }
    
    func take<A>(_ p: Parser<Input, A>) -> Parser<Input, A> where Output == Void {
        zip(self, p).map { _, b in b }
    }
    
    func take<A, B, C>(_ p: Parser<Input, C>) -> Parser<Input, (A, B, C)> where Output == (A, B) {
        zip(self, p).map { ab, c in (ab.0, ab.1, c)  }
    }
}

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

let zeroOrMOreSpaces = Parser<Substring, Void>.prefix(" ").zeroOrMore()

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

let currency = Parser<Substring, Currency>.oneOf(
    Currency.allCases.map { currency in Parser.prefix(currency.rawValue[...]).map { currency } }
)

let money = zip(currency, .double)
    .map(Money.init(currency:value:))

money.run("$200.5")
money.run("200.5")
money.run("₴200.5")

Parser.prefix([1, 2]).run([1, 2, 3, 4, 5][...])
Parser<ArraySlice<Int>, Void>.prefix([1, 2]).run([1, 2, 3, 4, 5])

//MARK: - Races
struct Race {
    let location: String
    let entranceFee: Money
    let path: [Coordinate]
}

let locationName = Parser<Substring, Substring>.prefix(while: { $0 != "," })

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

race.run(upcomingRaces[...])
races.run(upcomingRaces[...])


//MARK: - Test Logs parsing
let logs = """
Testing started
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

"""

let testCaseStartedLine = Parser<Substring, Substring>
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

let testResult = Parser.oneOf(testFaild, testPassed)
let testResults = testResult.zeroOrMore()



struct Product: Codable {
    struct Id: Hashable, Codable {
        var value: String
    }

    var id: Id
    var name: String
    var quantity: Double?
    var price: Double
    var cost: Double
}

let address = Parser<Substring, Substring>.prefix(upTo: "ПН")
let pn = Parser
    .skip("ПН")
    .skip(zeroOrMOreSpaces)
    .take(.uint64)
let chequeNumber = Parser.int
    .skip("/")
    .take(.int)
    .skip("/")
    .take(.int)
let price = Parser.double
    .skip(zeroOrMOreSpaces)
    .skip(.oneOf("Б", "A"))
    .skip(Parser.prefix("\n").zeroOrMore())
let anount = Parser.double
    .skip(zeroOrMOreSpaces)
    .skip(.oneOf("x", "X", "х", "Х"))
    .skip(zeroOrMOreSpaces)
    .take(.double)

let product1 = Parser.prefix(upToParser: anount)
    .take(anount)
    .skip(zeroOrMOreSpaces)
    .take(price)
    .map { (name, arg1, cost) in
        let (quantity, price) = arg1
        return Product(id: .init(value: String(name)), name: String(name), quantity: quantity, price: price, cost: cost)
    }


let product2 = Parser.prefix(upToParser: price)
    .take(price)
    .map { (name, cost) in
        Product(id: .init(value: String(name)), name: String(name), price: cost, cost: cost)
    }

let product3 = price
    .take(.prefix(upTo: " "))
    .map { cost, name in
        Product(id: .init(value: String(name)), name: String(name), price: cost, cost: cost)
    }

let products = Parser.oneOf([product2, product3, product1]).zeroOrMore()

let receiptParser = Parser.skip(address)
    .skip(pn)
    .skip(.prefix(upToParser: chequeNumber))
    .skip(chequeNumber)
//    .take(products)
//    .take(.oneOf([product1, product2, product3]))
//    .take(.oneOf([product1, product2, product3]))
//    .take(.oneOf([product1, product2, product3]))
//    .take(.oneOf([product1, product2, product3]))

let receipt = """
  ТОВ "СІЛЬПО-ФУД", магазин
м. Київ, вулиця Дорогожицька, будинок 2  ПН 407201926538  01
00001 Каса островська О./.
H UFK N 31/2155/296
Хл300КиївхлСімейнНар  14,59 Б
29,79 Б
Рул300КиївхлМакв/гВу  КартопляКгБіла  758 Х 7.59  13,34 Б
ЯБлукокгПіноваГолЧер
1,62 Х 20,99  34,00 Б
Сос275ГлобМортадВсВу  57,99 Б
Смет350MiMiMilk201/e  39,99 Б
ПакФасовМайНДГЕ
2 X 0,22  0,44 Б  #
Незабаром здійсниться  #
ваша дитяча мрія.  #
#
B.B. 28349266  #
Бали в моб. додатку  СУМА  190,14 ГРН
ПДВ Б  0,00%  0,00
- .  - -
КАРТКА  190,14 ГРН
...  -- - -  QR2029
ІДЕНТ. ЕКВАЙРА  ТЕРМІНАЛ  QR2029
КОМСІЯ  0,00
ПЛАТІЖНА СИСТЕМА  OR
ВИД ОПЕРАЦІЇ  ОПЛАТА
ЕПЗ  XXXXXX4642  828939
КОД ABT.  RRN  301718978596
КАСИР:
ДЕРЖАТЕЛЬ ЕПЗ:  #
#
Восток  17-01-2023 18:40:18
0633713 0609622  ОН 3000272824
ЗН КС00005950  ABOAAAVUAAAAABUAC69h  AAINWgIMKooXPi/xtpA=
ФІСКАЛЬНИЙ ЧЕК  {Екселліо
"""

dump(receiptParser.run(receipt[...]).match)
//print(receiptParser.run(receipt).rest)

let cityEnum = """
{
  "Kyiv": "м. Київ",
  "Odesa": "м. Одеса"
}
"""

let cityParser: Parser<Substring, String> = .oneOf(
    try! JSONDecoder().decode([String: String].self, from: cityEnum.data(using: .utf8)!).map { key, value in
            Parser.prefix(value[...]).map { key }
    }
)

cityParser.run("м. Київ, вулиця Дорогожицька, будинок 2")


extension Parser where Input == [String: String] {
    static func key(_ key: String, _ parser: Parser<Substring, Output>) -> Self {
        Self { dict in
            guard var value = dict[key]?[...]
            else { return nil }
            
            guard let output = parser.run(&value)
            else { return nil }
            
            dict[key] = value.isEmpty ? nil : String(value)
            return output
        }
    }
}

extension Parser where Input == Substring, Output == Substring {
    static var rest: Self {
        Self { input in
            let rest = input
            input = ""
            return rest
        }
    }
}

// /Applications/Xcode-14.2.0.app/Contents/Developer/Platforms/iPhoneOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot

let xcodePath = Parser.key("IPHONE_SIMULATOR_ROOT", .prefix(through: ".app"))
let username = Parser.key("SIMULATOR_HOST_HOME", Parser<Substring, Void>.prefix("/Users/").take(.rest))

xcodePath.take(username).run(ProcessInfo.processInfo.environment)


struct RequestData {
    var body: Data?
    var headers: [String: Substring]
    var method: String?
    var pathComponents: ArraySlice<Substring>
    var queryItems: [(name: String, value: Substring)]
}

extension Parser where Input == RequestData, Output == Void {
    static func method(_ method: String) -> Self {
        .init { input in
            guard input.method?.uppercased() == method.uppercased()
            else { return nil }
            input.method = nil
            return ()
        }
    }
}

extension Parser where Input == RequestData {
    static func path(_ parser: Parser<Substring, Output>) -> Self {
        .init { input in
            guard var firstComponent = input.pathComponents.first
            else { return nil }
            
            let output = parser.run(&firstComponent)
            guard firstComponent.isEmpty
            else { return nil }
            
            input.pathComponents.removeFirst()
            return output
        }
    }
}

extension Parser where Input == RequestData {
    static func query(name: String, _ parser: Parser<Substring, Output>) -> Self {
        .init { input in
            guard var index = input.queryItems.firstIndex(where: { n, value in n == name })
            else { return nil }
            
            let original = input.queryItems[index].value
            guard let output = parser.run(&input.queryItems[index].value)
            else { return nil }
            
            guard input.queryItems[index].value.isEmpty
            else {
                input.queryItems[index].value = original
                return nil
            }
            input.queryItems.remove(at: index)
            return output
        }
    }
}

extension Parser {
    static func optional<A>(_ parser: Parser<Input, A>) -> Self where Output == Optional<A> {
        .init { input in
            .some(parser.run(&input))
        }
    }
}

extension Parser where Input == RequestData, Output == Void {
    static let end = Self { input in
        guard input.pathComponents.isEmpty,
              input.method == nil
        else { return nil }
        
        input.body = nil
        input.queryItems = []
        input.headers = [:]
        return ()
    }
}

// GET /episodes/42?time=120
let episode = Parser.method("GET")
    .skip(.path("episodes"))
    .take(.path(.int))
    .take(.optional(.query(name: "time", .int)))
    .skip(.end)

let request = RequestData(
    body: nil,
    headers: ["User-Agent": "Safari"],
    method: "GET",
    pathComponents: ["episodes", "1", "comments"],
    queryItems: [(name: "time", value: "120")]
)

//episode.run(request)
enum Route {
    // GET .episodes/:int?time-:int
    case episodes(id: Int, time: Int?)
    
    // GET /episodes/:int/comments
    case episodesComments(id: Int)
}

let router = Parser.oneOf(
    Parser.method("GET")
        .skip(.path("episodes"))
        .take(.path(.int))
        .take(.optional(.query(name: "time", .int)))
        .skip(.end)
        .map(Route.episodes(id:time:)),

    Parser.method("GET")
        .skip(.path("episodes"))
        .take(.path(.int))
        .skip(.path("comments"))
        .skip(.end)
        .map(Route.episodesComments(id:))
)

//dump(
//router.run(request)
//)