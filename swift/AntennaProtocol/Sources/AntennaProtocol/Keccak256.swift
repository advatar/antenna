import Foundation

/// Minimal Keccak-256 implementation (Ethereum's keccak256).
///
/// This is **Keccak-256**, not NIST SHA3-256 (different padding).
/// - rate: 1088 bits (136 bytes)
/// - capacity: 512 bits
/// - output: 32 bytes
public enum Keccak256 {
    public static func hash(_ data: Data) -> Data {
        var state = [UInt64](repeating: 0, count: 25)
        let rate = 136

        // Absorb full blocks
        var offset = 0
        while offset + rate <= data.count {
            absorbBlock(&state, data[offset..<offset+rate])
            keccakF1600(&state)
            offset += rate
        }

        // Final block with Keccak padding (0x01 ... 0x80)
        var block = [UInt8](repeating: 0, count: rate)
        let remaining = data.count - offset
        if remaining > 0 {
            data[offset..<data.count].copyBytes(to: &block, count: remaining)
        }
        block[remaining] ^= 0x01
        block[rate - 1] ^= 0x80

        absorbBlock(&state, Data(block))
        keccakF1600(&state)

        // Squeeze 32 bytes
        var out = Data(count: 32)
        out.withUnsafeMutableBytes { outBytes in
            for i in 0..<4 { // 4 * 8 = 32
                let v = state[i].littleEndian
                withUnsafeBytes(of: v) { vBytes in
                    outBytes.baseAddress!.advanced(by: i * 8).copyMemory(from: vBytes.baseAddress!, byteCount: 8)
                }
            }
        }
        return out
    }

    private static func absorbBlock(_ state: inout [UInt64], _ block: Data.SubSequence) {
        // XOR block into state (little-endian)
        var i = 0
        var j = block.startIndex
        while i < 17 { // 17 * 8 = 136 bytes
            let chunk = block[j..<j+8]
            var word: UInt64 = 0
            _ = withUnsafeMutableBytes(of: &word) { wBytes in
                chunk.copyBytes(to: wBytes, count: 8)
            }
            state[i] ^= UInt64(littleEndian: word)
            i += 1
            j += 8
        }
    }

    private static let roundConstants: [UInt64] = [
        0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
        0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
        0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
        0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
        0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008
    ]

    private static let rotationOffsets: [[Int]] = [
        [ 0, 36,  3, 41, 18],
        [ 1, 44, 10, 45,  2],
        [62,  6, 43, 15, 61],
        [28, 55, 25, 21, 56],
        [27, 20, 39,  8, 14]
    ]

    private static func rotl(_ x: UInt64, _ n: Int) -> UInt64 {
        let shift = n & 63
        if shift == 0 { return x }
        return (x << UInt64(shift)) | (x >> UInt64(64 - shift))
    }

    private static func keccakF1600(_ a: inout [UInt64]) {
        // a is a flat 5x5 matrix: a[x + 5*y]
        for rc in roundConstants {
            // θ step
            var c = [UInt64](repeating: 0, count: 5)
            for x in 0..<5 {
                c[x] = a[x] ^ a[x + 5] ^ a[x + 10] ^ a[x + 15] ^ a[x + 20]
            }
            var d = [UInt64](repeating: 0, count: 5)
            for x in 0..<5 {
                d[x] = c[(x + 4) % 5] ^ rotl(c[(x + 1) % 5], 1)
            }
            for y in 0..<5 {
                for x in 0..<5 {
                    a[x + 5*y] ^= d[x]
                }
            }

            // ρ and π steps
            var b = [UInt64](repeating: 0, count: 25)
            for y in 0..<5 {
                for x in 0..<5 {
                    let v = a[x + 5*y]
                    let r = rotationOffsets[x][y]
                    let x2 = y
                    let y2 = (2*x + 3*y) % 5
                    b[x2 + 5*y2] = rotl(v, r)
                }
            }

            // χ step
            for y in 0..<5 {
                for x in 0..<5 {
                    a[x + 5*y] = b[x + 5*y] ^ ((~b[((x + 1) % 5) + 5*y]) & b[((x + 2) % 5) + 5*y])
                }
            }

            // ι step
            a[0] ^= rc
        }
    }
}
