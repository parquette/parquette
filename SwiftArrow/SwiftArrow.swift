//
//  SwiftArrow.swift
//  SwiftArrow
//
//  Created by Marc Prud'hommeaux on 1/25/21.
//

import Foundation

public enum SwiftArrowError : Error {
    case missingFileError(url: URL)
}

/// Setup Rust logging. This can be called multiple times, from multiple threads.
func initRustLogging() {
    initialize_logging()
}

func arrowToJSON(arrowData: Data, arrowFile: URL, JSONFile: URL) throws -> Any {
    if FileManager.default.isDeletableFile(atPath: JSONFile.path) {
        try FileManager.default.removeItem(at: JSONFile)
    }

    try arrowData.write(to: arrowFile)

    arrow_to_json()

    let JSONData = try Data(contentsOf: JSONFile)
    return try JSONSerialization.jsonObject(with: JSONData, options: [])
}

func JSONToArrow(arrow: NSDictionary, JSONFile: URL, arrowFile: URL) throws -> Data {
    if FileManager.default.isDeletableFile(atPath: arrowFile.path) {
        try FileManager.default.removeItem(at: arrowFile)
    }

    let JSONData = try JSONSerialization.data(withJSONObject: arrow, options: [])

    try JSONData.write(to: JSONFile)

    json_to_arrow()

    let arrowData = try Data(contentsOf: arrowFile)
    return arrowData
}

enum SwiftRustError : Error {
    case generic(String?)

    /// Passes the given value through the SwiftRust error checking
    static func checking<T>(_ value: T!) throws -> T! {
        let errlen = last_error_length()
        if errlen <= 0 { return value }

        let buffer = UnsafeMutablePointer<Int8>.allocate(capacity: Int(errlen))
        defer { buffer.deallocate() }

        if last_error_message(buffer, errlen) != 0 {
            throw Self.generic(String(validatingUTF8: buffer))
        }

        return value
    }
}

extension ArrowSchemaArray {
    func roundTrip() -> ArrowSchemaArray {
        withUnsafePointer(to: self) {
            arrow_array_ffi_roundtrip($0)
        }
    }
}

extension ArrowArray {
    func argParamDemo(param: Int64) {
        arrow_array_ffi_arg_param_demo(self, param)
    }
}

class ArrowCSV {
    private let fileURL: URL

    init(fileURL: URL) {
        // ptr = request_create(url)
        self.fileURL = fileURL
    }

    deinit {
        // request_destroy(ptr)
    }

    func load(printRows: Int64 = 0) throws -> OpaquePointer? {
        try fileURL.path.withCString({
            try SwiftRustError.checking(arrow_load_csv($0, printRows))
        })
    }
}

// https://github.com/nickwilcox/recipe-swift-rust-callbacks/blob/main/wrapper.swift

private class WrapClosure<T> {
    fileprivate let closure: T
    init(closure: T) {
        self.closure = closure
    }
}

public func invokeCallbackBool(millis: UInt64, closure: @escaping (Bool) -> Void) {
    let wrappedClosure = WrapClosure(closure: closure)
    let userdata = Unmanaged.passRetained(wrappedClosure).toOpaque()
    let callback: @convention(c) (UnsafeMutableRawPointer?, Bool) -> Void = { (_ userdata: UnsafeMutableRawPointer?, _ success: Bool) in
        let wrappedClosure: WrapClosure<(Bool) -> Void> = Unmanaged.fromOpaque(userdata!).takeRetainedValue()
        wrappedClosure.closure(success)
    }
    let completion = CallbackBool(userdata: userdata, callback: callback)
    callback_bool_after(millis, completion)
}

public func invokeCallbackInt64(millis: UInt64, value: Int64, closure: @escaping (Int64) -> Void) {
    let wrappedClosure = WrapClosure(closure: closure)
    let userdata = Unmanaged.passRetained(wrappedClosure).toOpaque()
    let completion = CallbackInt64(userdata: userdata) { data, i in
        let wrappedClosure: WrapClosure<(Int64) -> Void> = Unmanaged.fromOpaque(data!).takeRetainedValue()
        wrappedClosure.closure(i)
    }
    callback_int64_after(millis, value, completion)
}

public class DFExecutionContext {
    let ptr: OpaquePointer

    public init() {
        ptr = datafusion_context_create()
    }

    deinit {
        datafusion_context_destroy(ptr)
    }

    /// Registers the given URL to a `.parquet` file as the given table name
    public func register(parquet: URL, tableName: String) throws {
        try SwiftRustError.checking(datafusion_context_register_parquet(ptr, parquet.path, tableName))
    }

    /// Registers the given URL to a `.csv` file as the given table name
    public func register(csv: URL, tableName: String) throws {
        try SwiftRustError.checking(datafusion_context_register_csv(ptr, csv.path, tableName))
    }

    /// Registers the given `.parquet` file directly
    public func load(parquet: URL) throws -> DFDataFrame? {
        try DFDataFrame(checking: datafusion_context_read_parquet(ptr, parquet.path))
    }

    /// Registers the given `.csv` file directly
    public func load(csv: URL) throws -> DFDataFrame? {
        try DFDataFrame(checking: datafusion_context_read_csv(ptr, csv.path))
    }

    /// Issues a SQL query against the context
    public func query(sql: String) throws -> DFDataFrame? {
        try DFDataFrame(checking: datafusion_context_execute_sql(ptr, sql))
    }
}

public class DFDataFrame {
    let ptr: OpaquePointer

    init(ptr: OpaquePointer) {
        self.ptr = ptr
    }

    init?(checking ptr: OpaquePointer?) throws {
        guard let ptr = try SwiftRustError.checking(ptr) else { return nil }
        self.ptr = ptr
    }

    deinit {
        datafusion_dataframe_destroy(ptr)
    }

    public func limit(count: UInt) throws -> DFDataFrame {
        DFDataFrame(ptr: try SwiftRustError.checking(datafusion_dataframe_limit(ptr, count)))
    }

    /// Executes the DataFrame and returns the count
    public func collectionCount() throws -> UInt {
        try SwiftRustError.checking(datafusion_dataframe_collect_count(ptr))
    }

}
