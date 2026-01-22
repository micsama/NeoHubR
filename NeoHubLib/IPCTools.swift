import Foundation

public enum IPCFrame {
    public static let headerSize = 4

    public static func encode(_ payload: Data) -> Data {
        let length = UInt32(payload.count)
        var header = Data(capacity: headerSize)
        for shift in stride(from: 24, through: 0, by: -8) {
            header.append(UInt8((length >> UInt32(shift)) & 0xFF))
        }
        var frame = Data()
        frame.append(header)
        frame.append(payload)
        return frame
    }

    public static func readLength(from header: Data) -> Int {
        var length: UInt32 = 0
        for byte in header {
            length = (length << 8) | UInt32(byte)
        }
        return Int(length)
    }
}

public enum IPCCodec {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
