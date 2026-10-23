import Foundation
import Security

@main struct AuthChecks {
    static func main() throws {
        func reject(_ action: () throws -> Void) {
            do { try action(); fatalError("Accepted an invalid OAuth identity/callback") } catch { }
        }
        precondition(ChatGPTOAuth.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let good = URL(string: "http://127.0.0.1:1455/auth/callback?code=test&state=expected&client_id=oaiapp_test")!
        let callback = try ChatGPTOAuth.query(good, expectedState: "expected")
        precondition(callback["code"] == "test")
        reject { _ = try ChatGPTOAuth.query(good, expectedState: "different") }
        reject { _ = try ChatGPTOAuth.query(URL(string: "http://127.0.0.1/auth/callback?state=expected&code=a&code=b")!, expectedState: "expected") }
        reject { _ = try ChatGPTOAuth.query(URL(string: "http://127.0.0.1/wrong?state=expected")!, expectedState: "expected") }
        let fields = String(data: ChatGPTOAuth.form(["code":"a+b&c=d", "redirect_uri":"http://127.0.0.1:1455/auth/callback"]), encoding: .utf8)!
        precondition(fields.contains("a%2Bb%26c%3Dd"))
        let attributes: [String:Any] = [kSecAttrKeyType as String:kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String:2048]
        let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, nil)!
        let publicKey = SecKeyCopyPublicKey(privateKey)!
        let der = SecKeyCopyExternalRepresentation(publicKey, nil)! as Data
        var offset = 0
        func read() -> (UInt8, Data) {
            let tag = der[offset]; offset += 1
            let first = Int(der[offset]); offset += 1
            var length = first
            if first >= 128 { length = 0; for _ in 0..<(first & 127) { length = (length << 8) | Int(der[offset]); offset += 1 } }
            let bytes = der.subdata(in: offset..<offset+length); offset += length
            return (tag, bytes)
        }
        // Enter the PKCS#1 sequence; its integers form a JWKS RSA public key.
        _ = read(); offset = 1
        let first = Int(der[offset]); offset += 1; if first >= 128 { offset += first & 127 }
        let n = read().1.drop(while: { $0 == 0 }), e = read().1.drop(while: { $0 == 0 })
        let key: [String:Any] = ["kid":"fixture", "kty":"RSA", "alg":"RS256", "n":ChatGPTOAuth.base64URL(Data(n)), "e":ChatGPTOAuth.base64URL(Data(e))]
        let header = ChatGPTOAuth.base64URL(try JSONSerialization.data(withJSONObject: ["alg":"RS256", "kid":"fixture"]))
        let claims: [String:Any] = ["iss":ChatGPTOAuth.issuer, "sub":"fixture-subject", "aud":"fixture-client", "nonce":"fixture-nonce", "exp":Date.now.addingTimeInterval(3600).timeIntervalSince1970]
        let payload = ChatGPTOAuth.base64URL(try JSONSerialization.data(withJSONObject: claims))
        let content = header+"."+payload
        let signature = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, Data(content.utf8) as CFData, nil)! as Data
        let token = content+"."+ChatGPTOAuth.base64URL(signature)
        let verified = try ChatGPTOAuth.verify(token, client: "fixture-client", nonce: "fixture-nonce", jwks: [key])
        precondition(verified["sub"] as? String == "fixture-subject")
        reject { _ = try ChatGPTOAuth.verify(token, client: "wrong-client", nonce: "fixture-nonce", jwks: [key]) }
        reject { _ = try ChatGPTOAuth.verify(token, client: "fixture-client", nonce: "wrong-nonce", jwks: [key]) }
        var changed = claims; changed["sub"] = "tampered"
        let tampered = header+"."+ChatGPTOAuth.base64URL(try JSONSerialization.data(withJSONObject: changed))+"."+ChatGPTOAuth.base64URL(signature)
        reject { _ = try ChatGPTOAuth.verify(tampered, client: "fixture-client", nonce: "fixture-nonce", jwks: [key]) }
        changed = claims; changed["exp"] = 0
        reject { _ = try ChatGPTOAuth.claims(changed, client: "fixture-client", nonce: "fixture-nonce") }
        changed = claims; changed["iss"] = "https://example.com"
        reject { _ = try ChatGPTOAuth.claims(changed, client: "fixture-client", nonce: "fixture-nonce") }
        print("PASS: RFC PKCE, callback state/path/duplicate rejection, form escaping, signed RSA JWT, tamper/audience/nonce/expiry/issuer rejection.")
    }
}
