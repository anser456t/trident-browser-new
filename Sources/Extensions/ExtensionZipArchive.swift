import Foundation
import Compression

/// A minimal ZIP archive reader.
///
/// iOS provides no built-in unzip utility accessible from an app (no
/// `Process`/`NSTask` on-device, and no Foundation zip API), so extension
/// packages can't be extracted by shelling out the way a Mac tool would.
/// This reads the ZIP central directory directly and decompresses entries
/// itself using Apple's `Compression` framework, which does understand raw
/// DEFLATE (the only compression method a `.zip` normally uses besides
/// "stored"). It intentionally supports only what a WebExtension package
/// needs — no multi-disk archives, no encryption, no zip64 — and reports a
/// clear error for anything outside that rather than guessing.
enum ExtensionZipArchive {
    struct Entry {
        let path: String
        let data: Data
    }

    enum ArchiveError: LocalizedError {
        case notAZip
        case unsupportedCompression(UInt16)
        case corrupt(String)
        case pathTraversal(String)

        var errorDescription: String? {
            switch self {
            case .notAZip: return "This file isn't a valid ZIP archive."
            case .unsupportedCompression(let method): return "This ZIP uses an unsupported compression method (\(method))."
            case .corrupt(let detail): return "This ZIP archive is corrupt: \(detail)"
            case .pathTraversal(let path): return "This archive contains an unsafe file path (\"\(path)\") and was rejected."
            }
        }
    }

    /// Reads every entry from a ZIP file at `url` into memory. WebExtension
    /// packages are small (a handful of MB at most), so loading fully into
    /// memory rather than streaming is a reasonable simplification here.
    static func readEntries(at url: URL) throws -> [Entry] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try readEntries(from: data)
    }

    static func readEntries(from data: Data) throws -> [Entry] {
        // 1. Find the End Of Central Directory record by scanning backward
        //    for its signature (0x06054b50). It's always within the last
        //    ~64KB + 22 bytes (max comment length), so cap the scan there.
        let eocdSignature: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        let bytes = [UInt8](data)
        let searchFloor = max(0, bytes.count - 65557)
        guard let eocdStart = lastIndex(of: eocdSignature, in: bytes, from: searchFloor) else {
            throw ArchiveError.notAZip
        }

        func u16(_ offset: Int) -> UInt16 { UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8) }
        func u32(_ offset: Int) -> UInt32 {
            UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8)
                | (UInt32(bytes[offset + 2]) << 16) | (UInt32(bytes[offset + 3]) << 24)
        }

        guard eocdStart + 22 <= bytes.count else { throw ArchiveError.corrupt("truncated EOCD") }
        let entryCount = Int(u16(eocdStart + 10))
        let centralDirOffset = Int(u32(eocdStart + 16))
        guard centralDirOffset < bytes.count else { throw ArchiveError.corrupt("bad central directory offset") }

        var entries: [Entry] = []
        var offset = centralDirOffset
        let centralSignature: UInt32 = 0x02014b50

        for _ in 0..<entryCount {
            guard offset + 46 <= bytes.count, u32(offset) == centralSignature else {
                throw ArchiveError.corrupt("central directory entry signature mismatch")
            }
            let compressionMethod = u16(offset + 10)
            let compressedSize = Int(u32(offset + 20))
            let nameLength = Int(u16(offset + 28))
            let extraLength = Int(u16(offset + 30))
            let commentLength = Int(u16(offset + 32))
            let localHeaderOffset = Int(u32(offset + 42))

            guard offset + 46 + nameLength <= bytes.count else { throw ArchiveError.corrupt("truncated file name") }
            let nameBytes = bytes[(offset + 46)..<(offset + 46 + nameLength)]
            guard let path = String(bytes: nameBytes, encoding: .utf8) else {
                throw ArchiveError.corrupt("non-UTF8 file name")
            }
            try validatePath(path)

            if !path.hasSuffix("/") {
                let fileData = try readLocalEntry(
                    bytes: bytes, localHeaderOffset: localHeaderOffset,
                    compressionMethod: compressionMethod, compressedSize: compressedSize
                )
                entries.append(Entry(path: path, data: fileData))
            }

            offset += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    private static func readLocalEntry(bytes: [UInt8], localHeaderOffset: Int,
                                        compressionMethod: UInt16, compressedSize: Int) throws -> Data {
        func u16(_ offset: Int) -> UInt16 { UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8) }
        let localSignature: UInt32 = 0x04034b50
        func u32(_ offset: Int) -> UInt32 {
            UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8)
                | (UInt32(bytes[offset + 2]) << 16) | (UInt32(bytes[offset + 3]) << 24)
        }
        guard localHeaderOffset + 30 <= bytes.count, u32(localHeaderOffset) == localSignature else {
            throw ArchiveError.corrupt("local file header signature mismatch")
        }
        let nameLength = Int(u16(localHeaderOffset + 26))
        let extraLength = Int(u16(localHeaderOffset + 28))
        let dataStart = localHeaderOffset + 30 + nameLength + extraLength
        guard dataStart + compressedSize <= bytes.count else { throw ArchiveError.corrupt("truncated entry data") }
        let compressed = Data(bytes[dataStart..<(dataStart + compressedSize)])

        switch compressionMethod {
        case 0: // stored (no compression)
            return compressed
        case 8: // deflate
            return try inflate(compressed)
        default:
            throw ArchiveError.unsupportedCompression(compressionMethod)
        }
    }

    /// Raw DEFLATE decompression via Apple's Compression framework. Despite
    /// its name, `COMPRESSION_ZLIB` in Apple's implementation operates on
    /// raw DEFLATE streams (RFC 1951, no zlib/gzip wrapper) — which is
    /// exactly what ZIP's "deflate" method (8) stores. This is a
    /// well-known naming quirk of the framework, not a typo here.
    private static func inflate(_ compressed: Data) throws -> Data {
        // Output size is unknown up front; grow a buffer geometrically.
        var capacity = max(compressed.count * 4, 4096)
        while true {
            var result = Data(count: capacity)
            let produced: Int = result.withUnsafeMutableBytes { rawOut -> Int in
                compressed.withUnsafeBytes { rawIn -> Int in
                    guard let outPtr = rawOut.bindMemory(to: UInt8.self).baseAddress,
                          let inPtr = rawIn.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                    return compression_decode_buffer(outPtr, capacity, inPtr, compressed.count, nil, COMPRESSION_ZLIB)
                }
            }
            if produced < 0 { throw ArchiveError.corrupt("deflate decompression failed") }
            if produced < capacity {
                result.removeSubrange(produced..<result.count)
                return result
            }
            // Buffer wasn't big enough — grow and retry.
            capacity *= 2
            if capacity > 256 * 1024 * 1024 { throw ArchiveError.corrupt("entry too large") }
        }
    }

    private static func validatePath(_ path: String) throws {
        if path.hasPrefix("/") || path.contains("../") || path.split(separator: "/").contains("..") {
            throw ArchiveError.pathTraversal(path)
        }
    }

    private static func lastIndex(of pattern: [UInt8], in bytes: [UInt8], from floor: Int) -> Int? {
        guard bytes.count >= pattern.count else { return nil }
        var i = bytes.count - pattern.count
        while i >= floor {
            if Array(bytes[i..<(i + pattern.count)]) == pattern { return i }
            i -= 1
        }
        return nil
    }
}
