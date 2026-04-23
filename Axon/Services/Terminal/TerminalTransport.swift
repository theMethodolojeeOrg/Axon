//
//  TerminalTransport.swift
//  Axon
//
//  Transport abstraction for local and bridge-backed terminal sessions.
//

import Foundation
import Combine

@MainActor
protocol TerminalTransport: AnyObject {
    var outputPublisher: AnyPublisher<String, Never> { get }
    var exitPublisher: AnyPublisher<Int?, Never> { get }

    func start(cwd: String, cols: Int, rows: Int) async throws -> TerminalSessionStartResult
    func sendInput(_ data: String) async throws
    func resize(cols: Int, rows: Int) async throws
    func close() async
}

extension Encodable {
    func bridgeAnyCodable() throws -> AnyCodable {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode(AnyCodable.self, from: data)
    }
}

extension AnyCodable {
    func decodeBridgeValue<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
