import Foundation
import CryptoKit
import Security

enum ChatGPTError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}
enum ChatGPTOAuth {
    static let issuer = "https://auth.openai.com"
    static let resource = "https://api.openai.com/v1"
    static func base64URL(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    static func decode(_ value: String) throws -> Data {
        let padded = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + String(repeating: "=", count: (4-value.count%4)%4)
        guard let data = Data(base64Encoded: padded) else { throw ChatGPTError.message("Invalid identity token encoding.") }; return data
    }
    static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw ChatGPTError.message("Could not create secure sign-in values.") }
        return base64URL(Data(bytes))
    }
    static func challenge(_ verifier: String) -> String { base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))) }
    static func query(_ url: URL, expectedState: String) throws -> [String:String] {
        guard url.path == "/auth/callback", let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { throw ChatGPTError.message("Invalid sign-in callback.") }
        var result: [String:String] = [:]
        for item in items {
            guard result[item.name] == nil, let value = item.value else { throw ChatGPTError.message("Ambiguous sign-in callback.") }
            result[item.name] = value
        }
        guard result["state"] == expectedState else { throw ChatGPTError.message("Sign-in state did not match.") }
        return result
    }
    static func form(_ fields: [String:String]) -> Data {
        var components = URLComponents()
        components.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
    }
    static func claims(_ payload: [String:Any], client: String, nonce: String?, now: Date = .now) throws -> String {
        let audiences = (payload["aud"] as? [String]) ?? [payload["aud"] as? String ?? ""]
        guard payload["iss"] as? String == issuer, audiences.contains(client),
              let expiry = payload["exp"] as? Double, expiry > now.timeIntervalSince1970,
              let subject = payload["sub"] as? String, !subject.isEmpty,
              nonce == nil || payload["nonce"] as? String == nonce else { throw ChatGPTError.message("Identity validation failed (issuer, audience, expiry or nonce).") }
        if let notBefore = payload["nbf"] as? Double, notBefore > now.timeIntervalSince1970 + 30 { throw ChatGPTError.message("Identity token is not yet valid.") }
        if audiences.count > 1, payload["azp"] as? String != client { throw ChatGPTError.message("Identity token has a different authorized client.") }
        return subject
    }
    private static func der(_ tag: UInt8, _ value: Data) -> Data {
        let count = value.count
        let length: Data
        if count < 128 { length = Data([UInt8(count)]) }
        else { var n = count; var bytes: [UInt8] = []; while n > 0 { bytes.insert(UInt8(n & 255), at: 0); n >>= 8 }; length = Data([0x80 | UInt8(bytes.count)] + bytes) }
        return Data([tag]) + length + value
    }
    static func verify(_ token: String, client: String, nonce: String?, jwks: [[String:Any]]) throws -> [String:Any] {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3,
              let header = try JSONSerialization.jsonObject(with: decode(parts[0])) as? [String:Any],
              header["alg"] as? String == "RS256", header["crit"] == nil,
              let kid = header["kid"] as? String,
              let jwk = jwks.first(where: { $0["kid"] as? String == kid && $0["kty"] as? String == "RSA" }),
              (jwk["alg"] as? String ?? "RS256") == "RS256",
              (jwk["use"] as? String ?? "sig") == "sig",
              let modulus = jwk["n"] as? String, let exponent = jwk["e"] as? String else { throw ChatGPTError.message("Unsupported identity signing key.") }
        func integer(_ value: String) throws -> Data { var data = try decode(value); while data.first == 0 && data.count > 1 { data.removeFirst() }; if let first = data.first, first & 0x80 != 0 { data.insert(0, at: 0) }; return der(0x02, data) }
        let keyData = try der(0x30, integer(modulus) + integer(exponent))
        let attributes: [String:Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeyClass as String: kSecAttrKeyClassPublic]
        guard let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, nil),
              SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256, Data((parts[0]+"."+parts[1]).utf8) as CFData, try decode(parts[2]) as CFData, nil),
              let payload = try JSONSerialization.jsonObject(with: decode(parts[1])) as? [String:Any] else { throw ChatGPTError.message("Identity token signature could not be verified.") }
        _ = try claims(payload, client: client, nonce: nonce)
        return payload
    }
}
