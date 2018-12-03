import XCTest

import AWSLambdaRuntimeTests

var tests = [XCTestCaseEntry]()
tests += AWSLambdaRuntimeTests.allTests()
XCTMain(tests)