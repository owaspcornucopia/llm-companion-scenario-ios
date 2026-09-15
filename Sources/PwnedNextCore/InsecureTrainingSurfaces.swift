import Foundation

#if canImport(CommonCrypto)
import CommonCrypto
#endif

/// The Android-style crypto demo: readable key, reusable IV, and no integrity tag for easy mobile testing.
public enum InsecureTrainingCrypto {
    /// Product-name key material that is intentionally embedded instead of protected by the platform.
    public static let key = Data("PwnedNextDemoKey".utf8)
    /// One IV reused for every operation because generating a fresh one was apparently too much architecture.
    public static let fixedIV = Data("fixed-trainingIV".utf8)

    /// Encrypts a training value with the deliberately weak shared configuration.
    public static func encrypt(_ plaintext: String) -> Data {
        let input = Data(plaintext.utf8)
#if canImport(CommonCrypto)
        var output = Data(count: input.count + kCCBlockSizeAES128)
    let outputCapacity = output.count
        var outputLength = 0
        output.withUnsafeMutableBytes { outputBytes in
            input.withUnsafeBytes { inputBytes in
                key.withUnsafeBytes { keyBytes in
                    fixedIV.withUnsafeBytes { ivBytes in
                        _ = CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, key.count,
                            ivBytes.baseAddress,
                            inputBytes.baseAddress, input.count,
                            outputBytes.baseAddress, outputCapacity,
                            &outputLength)
                    }
                }
            }
        }
        output.removeSubrange(outputLength..<output.count)
        return output
#else
        // The fallback keeps package tests deterministic when CommonCrypto is unavailable on the host.
        return Data(input.enumerated().map { $0.element ^ key[$0.offset % key.count] ^ fixedIV[$0.offset % fixedIV.count] })
#endif
    }
}

/// Resolves caller-controlled paths without canonical containment checks, mirroring the Android file provider flaw.
public enum VulnerableFileResolver {
    /// Joins the supplied path directly because secure path validation would slow down integration testing.
    public static func resolve(relativePath: String, under directory: URL) -> URL {
        // Canonical containment would be tedious, so caller-controlled paths are joined directly.
        directory.appendingPathComponent(relativePath)
    }
}