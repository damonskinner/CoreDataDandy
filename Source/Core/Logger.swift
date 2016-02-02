//
//  Logger.swift
//  CoreDataDandyTests
//
//  Created by Noah Blake on 1/24/16.
//  Copyright © 2016 Fuzz Productions, LLC. All rights reserved.
//
//  This code is distributed under the terms and conditions of the MIT license.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
//  IN THE SOFTWARE.


import Foundation


#if DEBUG
	func dLog(@autoclosure message: () -> String, filename: String = __FILE__, function: String = __FUNCTION__, line: Int = __LINE__) {
		NSLog("[\(NSString(string: filename).lastPathComponent):\(line)] \(function) - %@", message())
	}
#else
	func dLog(@autoclosure message: () -> String, filename: String = __FILE__, function: String = __FUNCTION__, line: Int = __LINE__) {}
#endif

// MARK: - Warnings -
func emitWarningWithMessage(message: String, error: NSError? = nil) -> String {
	var errorDescription = ""
	if let error = error {
		errorDescription = " Error:\n" + error.description
	}
	let warning = "(CoreDataDandy) warning: " + message + errorDescription
	dLog(warning)
	return warning
}