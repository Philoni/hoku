import Foundation
import Security
import Synchronization

/// Signify's private root CAs. Bridges chain to one of these; nothing else is trusted.
/// Source: developers.meethue.com "Using HTTPS" (also bundled by openHAB and openhue-go).
enum HueRootCA {
    static let certificates: [SecCertificate] = {
        let pems = [
            // CN=root-bridge, O=Philips Hue, C=NL — valid 2017-01-01 to 2038-01-19
            """
            MIICMjCCAdigAwIBAgIUO7FSLbaxikuXAljzVaurLXWmFw4wCgYIKoZIzj0EAwIw\
            OTELMAkGA1UEBhMCTkwxFDASBgNVBAoMC1BoaWxpcHMgSHVlMRQwEgYDVQQDDAty\
            b290LWJyaWRnZTAiGA8yMDE3MDEwMTAwMDAwMFoYDzIwMzgwMTE5MDMxNDA3WjA5\
            MQswCQYDVQQGEwJOTDEUMBIGA1UECgwLUGhpbGlwcyBIdWUxFDASBgNVBAMMC3Jv\
            b3QtYnJpZGdlMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEjNw2tx2AplOf9x86\
            aTdvEcL1FU65QDxziKvBpW9XXSIcibAeQiKxegpq8Exbr9v6LBnYbna2VcaK0G22\
            jOKkTqOBuTCBtjAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBhjAdBgNV\
            HQ4EFgQUZ2ONTFrDT6o8ItRnKfqWKnHFGmQwdAYDVR0jBG0wa4AUZ2ONTFrDT6o8\
            ItRnKfqWKnHFGmShPaQ7MDkxCzAJBgNVBAYTAk5MMRQwEgYDVQQKDAtQaGlsaXBz\
            IEh1ZTEUMBIGA1UEAwwLcm9vdC1icmlkZ2WCFDuxUi22sYpLlwJY81Wrqy11phcO\
            MAoGCCqGSM49BAMCA0gAMEUCIEBYYEOsa07TH7E5MJnGw557lVkORgit2Rm1h3B2\
            sFgDAiEA1Fj/C3AN5psFMjo0//mrQebo0eKd3aWRx+pQY08mk48=
            """,
            // CN=Hue Root CA 01, O=Signify Hue, C=NL — valid 2025-02-25 to 2050-12-31
            """
            MIIBzDCCAXOgAwIBAgICEAAwCgYIKoZIzj0EAwIwPDELMAkGA1UEBhMCTkwxFDAS\
            BgNVBAoMC1NpZ25pZnkgSHVlMRcwFQYDVQQDDA5IdWUgUm9vdCBDQSAwMTAgFw0y\
            NTAyMjUwMDAwMDBaGA8yMDUwMTIzMTIzNTk1OVowPDELMAkGA1UEBhMCTkwxFDAS\
            BgNVBAoMC1NpZ25pZnkgSHVlMRcwFQYDVQQDDA5IdWUgUm9vdCBDQSAwMTBZMBMG\
            ByqGSM49AgEGCCqGSM49AwEHA0IABFfOO0jfSAUXGQ9kjEDzyBrcMQ3ItyA5krE+\
            cyvb1Y3xFti7KlAad8UOnAx0FBLn7HZrlmIwm1QnX0fK3LPM13mjYzBhMB0GA1Ud\
            DgQWBBTF1pSpsCASX/z0VHLigxU2CAaqoTAfBgNVHSMEGDAWgBTF1pSpsCASX/z0\
            VHLigxU2CAaqoTAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBBjAKBggq\
            hkjOPQQDAgNHADBEAiAk7duT+IHbOGO4UUuGLAEpyYejGZK9Z7V9oSfnvuQ5BQIg\
            IYSgwwxHXm73/JgcU9lAM6c8Bmu3UE3kBIUwBs1qXFw=
            """,
        ]
        return pems.map { pem in
            guard let data = Data(base64Encoded: pem, options: .ignoreUnknownCharacters),
                  let certificate = SecCertificateCreateWithData(nil, data as CFData)
            else {
                fatalError("Bundled Hue root CA could not be decoded")
            }
            return certificate
        }
    }()
}

/// Validates bridge certificates: the chain must end in a Hue root CA, and once the
/// bridge ID is known, the leaf's common name must match it (case-insensitively —
/// newer bridges use upper case). The cert has no IP SAN, so hostname checks are skipped.
public final class BridgeTrustEvaluator: NSObject, URLSessionTaskDelegate, Sendable {
    private let expectedBridgeIDs = Mutex<[String: String]>([:])
    private let observedBridgeIDs = Mutex<[String: String]>([:])

    override public init() {}

    /// Pins `bridgeID` for connections to `host`.
    public func pin(host: String, bridgeID: String) {
        expectedBridgeIDs.withLock { $0[host] = bridgeID.lowercased() }
    }

    /// The lower-cased certificate common name last seen for `host`.
    public func observedBridgeID(for host: String) -> String? {
        observedBridgeIDs.withLock { $0[host] }
    }

    /// Streaming tasks (`bytes(for:)`) deliver the server-trust challenge here and do
    /// not fall back to the session-level method, so both must be implemented.
    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        await urlSession(session, didReceive: challenge)
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            return (.performDefaultHandling, nil)
        }

        let host = challenge.protectionSpace.host
        let expectedID = expectedBridgeIDs.withLock { $0[host] }
        guard let commonName = Self.evaluate(trust),
              expectedID == nil || commonName == expectedID
        else {
            return (.cancelAuthenticationChallenge, nil)
        }
        observedBridgeIDs.withLock { $0[host] = commonName }
        return (.useCredential, URLCredential(trust: trust))
    }

    /// Returns the leaf's lower-cased common name if the chain ends in a Hue root CA.
    static func evaluate(_ trust: SecTrust) -> String? {
        // Fail closed if any setup step fails, otherwise SecTrust would fall back to system roots.
        guard SecTrustSetAnchorCertificates(trust, HueRootCA.certificates as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
              SecTrustSetPolicies(trust, SecPolicyCreateBasicX509()) == errSecSuccess,
              SecTrustEvaluateWithError(trust, nil),
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first
        else {
            return nil
        }
        var commonName: CFString?
        SecCertificateCopyCommonName(leaf, &commonName)
        return (commonName as String?)?.lowercased()
    }
}
