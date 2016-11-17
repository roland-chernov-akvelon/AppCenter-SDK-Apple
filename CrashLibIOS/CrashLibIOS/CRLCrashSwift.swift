/*
 * Copyright (c) Microsoft Corporation. All rights reserved.
 */

import Foundation

class CRLCrashSwift: CRLCrash {
    override var category: String {
        return "Various";
    }
    override var title: String {
        return "Swift";
    }
    override var desc: String {
        return "Trigger a crash from inside a Swift method.";
    }
    override func crash() {
        let buf: UnsafeMutablePointer<UInt>? = nil;

        buf![1] = 1;
    }
}
