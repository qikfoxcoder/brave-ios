// Copyright 2022 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation

extension Sequence {
    func asyncForEach(_ operation: (Element) async throws -> Void) async rethrows {
        for element in self {
            try await operation(element)
        }
    }
    
    func asyncConcurrentForEach(_ operation: @escaping (Element) async throws -> Void) async rethrows {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for element in self {
                group.addTask { try await operation(element) }
            }
            
            try await group.waitForAll()
        }
    }
    
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var results = [T]()
        for element in self {
            try await results.append(transform(element))
        }
        return results
    }
    
    func asyncConcurrentMap<T>(_ transform: @escaping (Element) async throws -> T) async rethrows -> [T] {
        try await withThrowingTaskGroup(of: T.self) { group in
            for element in self {
                group.addTask { try await transform(element) }
            }
            
            var results = [T]()
            for try await result in group {
                results.append(result)
            }
            return results
        }
    }
    
    func asyncCompactMap<T>(_ transform: (Element) async throws -> T?) async rethrows -> [T] {
        var results = [T]()
        for element in self {
            if let result = try await transform(element) {
                results.append(result)
            }
        }
        return results
    }
    
    func asyncConcurrentCompactMap<T>(_ transform: @escaping (Element) async throws -> T?) async rethrows -> [T] {
        try await withThrowingTaskGroup(of: T?.self) { group in
            for element in self {
                group.addTask {
                    try await transform(element)
                }
            }
            
            var results = [T]()
            for try await result in group {
                if let result = result {
                    results.append(result)
                }
            }
            return results
        }
    }
}
