import Foundation

#if canImport(CommonCrypto)
import CommonCrypto
#endif

public enum InsecureTrainingCrypto {
    public static let key = Data("PwnedNextDemoKey".utf8)
    public static let fixedIV = Data("fixed-trainingIV".utf8)

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
        return Data(input.enumerated().map { $0.element ^ key[$0.offset % key.count] ^ fixedIV[$0.offset % fixedIV.count] })
#endif
    }
}

public enum AFileResolver {
    public static func resolve(relativePath: String, under directory: URL) -> URL {
        directory.appendingPathComponent(relativePath)
    }
}