//
//  TextScannerTests.swift
//  
//
//  Created by  Vladyslav Fil on 22.05.2023.
//

import XCTest
@testable import LikVision

final class TextScannerTests: XCTestCase {
    
    var sut: TextScanner!

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        sut = TextScanner()
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        sut = nil
    }

    func testTextScanner_whenParseDataFromUIImageMethodCalled_delegateParseMethodShouldBeCalled() throws {
        // Arrange
        let mockReceiptParser = MockReceiptParser()
        sut.delegate = mockReceiptParser
        
        let image = try XCTUnwrap(UIImage(named: "silpo-1", in: Bundle.module, compatibleWith: nil))
        
        // Act
        sut.parseData(from: image)
        
        // Assert
        wait(for: [mockReceiptParser.expectation], timeout: 8)
        XCTAssertTrue(mockReceiptParser.isParseMethodCalled, "The delegate's parse method should be called.")
    }
}
