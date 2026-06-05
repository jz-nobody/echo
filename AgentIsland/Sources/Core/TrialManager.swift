import CryptoKit
import Foundation

@MainActor @Observable
final class TrialManager {

    enum LicenseStatus: Equatable {
        case trial(daysLeft: Int)
        case expired
        case activated(daysLeft: Int)
        case activationExpired
    }

    static let trialDuration: TimeInterval = 21 * 86400
    static let activationDuration: TimeInterval = 90 * 86400

    private static let validTokenHashes: Set<String> = [
        "b72acc65d8ff32c4070ee6996ea2f14f88b72404b716083ec7123d5e4779ad15",
        "8685d705335aeccae38aa19ddebd42774ed17a04c5f09a545450c8303af852c0",
        "b11f1be65d338562d6961774c3e8c913b05c1ae8f3214b144e7057fb3671c743",
        "2128d6589a21918fe6af3c0bb51bc012846da14a275be8356d9debb5e2bbb6ed",
        "f26240b7f26e278e157438f965b519eb4ff7c44b69c99c17a7148d6402d75bcc",
        "6d6ea505b48f1d6a8ab211249a2cb2eb1e5c966397b13a44ff0241e66eab7247",
        "bba35bdfe6140f2ed3410ffd14256611b3f67c665aaea581c92335c8694ad37f",
        "9c9ae4bfafb2448e862d7fd94f336579269a9dba2d0e3df692b7e89f380dd532",
        "46ae92980a9b395f5e77e4bfe923cc1dd209c2a91e929ea3f947a0d0f68c5672",
        "25c982ee8eadc80c175c9bd17ed00993d0f11359774b05fdcc7d79703040c83b",
        "f4301fae046e6710b8284089c94f9b0a25df89dbb3d9cf54e8b4dc2f385710a9",
        "1efdafbf6ff13e878c3b440fb6d3db5203e37729c7b530aa143a9edaefff703d",
        "1430a66f11590f0ecaf5399e43ff8ce74f3e86e86d5ca0e81801886eb52b4154",
        "b37429e4bc7103423851ac499ac26c6bc7656cf0a8a8d34c1320113cc707870c",
        "2c7d409b88301edbef33c86b815d5e3a881f3483702f03f43a344bfc3c20eedd",
        "b4b687e9c72aec0f3c5ca4b60b9ce19f8eee8132b24c834c849e1e403f347e97",
        "84c1ca90a9e7bed376a4b38e067bd6f9396eaacf61cc18ebe3c6c76ea4fe9af3",
        "3ed0961800dac980313e25b11396e73b603e846a50bcef57636ea33937a25879",
        "94bddfa48d46f9296ed048f595fdc891e98b94f13be3938423527800f1f7c1e7",
        "3e41dc4c0f45c537e7d1586f3b0e38db0820322d0959abc08de312d8bccdac12",
        "9993bdd6184e5b62a99fcccb44551877fb42259cd77d7e6b4d7a9ecc5e6ce613",
        "94741f36bfeff3910591614781899d27504939958cb6bf5279fcbf8afb6cd283",
        "cb04975dbcd1d92a83acbf74670fc6808b10fc492a5283cdb34324a4b8d1f7a5",
        "07fa0ac0e1635f9a8b152ce652e451e3ac5234d0b74c3613f701f69c657d842f",
        "1c8afc8824b94c94b3cf44a74a1b1c8bd4d47ec8ccd372de0bb5584cbad05137",
        "937c06be860d4d5721de97165ba4d75322dacd0f292337d9fb0ea27e88951674",
        "9efee0a6a8d3cc3e4f306171c17c3a3af6ed8f1446374a38f6160ce561152832",
        "b787b1e27624160f0cc5ea100516c03c0a82de75c1e24b558d40572cc4099879",
        "d1af0821c6892d2ae86a6524123cb934db6a17149f13a2f2b77233a035d9681b",
        "128498a24eb2aa03fd4a801ba89a85aac2887ca11dfc50814350b80619b4e2a8",
        "33902ccf3f0a199f2b6b9bcf4090d805c12c08fee59c3831c55cd08477d176c6",
        "9db7c2c9f94d3364aa7635e432d763056efd70a401745567861d79e6fe767225",
        "adea40337d2323aa554b0d0cd3488c86c922db64f3f6142bd76d2fc15ef5464d",
        "8954f3a0812c2941b2dd14de32fb76c5034d481495df5145ecc3f014d2f1594f",
        "43040e5aec4b6f19775a52c66577b758ec0345260d6aa51b170b0c5a18e505b8",
        "ccddf3dda640516ce67c5add8a918b5a7f331573e020e241a4e9273f35e57dcc",
        "c12986a34b428e8a5fa1e1bc6a9a4b263ff5b1295a74d94c12046008ee7fc1f2",
        "ecaaea2811be9517940c90ac9faba53a4edd544ed5c3b3501500fb52c3b6ed60",
        "26ead23cc3b09ff61f6df4455d4218742f0712fb2c6e4e811e516465efdc0efe",
        "398df12ec6eb6e7274cde5767fecadc294a71874666e7afd0196c4305290aafb",
        "c325838b986920bad03a106c398cad1b85953b433a6de711e3cb55f42ede966d",
        "eb12bbd6c4150aff772d95ff57c4706c4049c256c6d68864a784d8540e693ec9",
        "d550add5862f8ddf0a81a687db84eb0ad20311f4a6084972821bcc6a82c71c8b",
        "79e1ee52976b34509486e537ef2c4d1c56d479ab69a97909ced58e47da8cb6f6",
        "357e8290ab33395616e4c916852ac3c36f2ce455f2a53defb419e168baa372f9",
        "545f25a322ffee20a0940a154d10592c2371e31be444cea5f34be0019b489f75",
        "c0b811ee6f477914b0cfa9ea8a09e5c577586c6a508a19fe00cbda5e637e264b",
        "725685d78c10a8678084f51eed0e0a0e5cba194a2e665e185ffbbaf8992ca981",
        "2db96042fe51f4e97b771fae8b937d985e4570fc5ad0812a74d0e727206aa2c2",
        "b02345d0467e527d542ecd6cb26f09a489996aba5e10da0aa99852520a20b10b",
    ]

    private(set) var isLocked: Bool = false
    private(set) var status: LicenseStatus = .trial(daysLeft: 21)

    private let keychain: any KeychainStoring
    private let dateProvider: @Sendable () -> Date
    private var timer: Timer?

    private enum Keys {
        static let installDate = "installDate"
        static let activationToken = "activationToken"
        static let activationDate = "activationDate"
    }

    init(keychain: any KeychainStoring = KeychainStore(), dateProvider: @escaping @Sendable () -> Date = { Date() }) {
        self.keychain = keychain
        self.dateProvider = dateProvider
        bootstrap()
        refreshStatus()
        startPeriodicCheck()
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Public

    func activate(token: String) -> Bool {
        let hash = sha256Hex(token)
        guard Self.validTokenHashes.contains(hash) else { return false }

        let now = dateProvider()
        let tokenData = Data(token.utf8)
        let dateData = withUnsafeBytes(of: now.timeIntervalSince1970) { Data($0) }

        _ = keychain.write(key: Keys.activationToken, data: tokenData)
        _ = keychain.write(key: Keys.activationDate, data: dateData)

        refreshStatus()
        return true
    }

    var installDate: Date? {
        readDate(key: Keys.installDate)
    }

    var activationDate: Date? {
        readDate(key: Keys.activationDate)
    }

    // MARK: - Private

    private func bootstrap() {
        if readDate(key: Keys.installDate) == nil {
            let now = dateProvider()
            writeDate(now, key: Keys.installDate)
        }
    }

    func refreshStatus() {
        let now = dateProvider()

        if let actDate = readDate(key: Keys.activationDate),
           keychain.read(key: Keys.activationToken) != nil {
            let elapsed = now.timeIntervalSince(actDate)
            if elapsed < Self.activationDuration {
                let remaining = max(0, Self.activationDuration - elapsed)
                status = .activated(daysLeft: Int(remaining / 86400))
                isLocked = false
                return
            } else {
                status = .activationExpired
                isLocked = true
                return
            }
        }

        guard let install = readDate(key: Keys.installDate) else {
            status = .trial(daysLeft: 21)
            isLocked = false
            return
        }

        let elapsed = now.timeIntervalSince(install)
        if elapsed < Self.trialDuration {
            let remaining = max(0, Self.trialDuration - elapsed)
            status = .trial(daysLeft: Int(remaining / 86400))
            isLocked = false
        } else {
            status = .expired
            isLocked = true
        }
    }

    private func startPeriodicCheck() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshStatus()
            }
        }
    }

    private func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func readDate(key: String) -> Date? {
        guard let data = keychain.read(key: key),
              data.count == MemoryLayout<TimeInterval>.size else { return nil }
        let interval = data.withUnsafeBytes { $0.load(as: TimeInterval.self) }
        return Date(timeIntervalSince1970: interval)
    }

    private func writeDate(_ date: Date, key: String) {
        let data = withUnsafeBytes(of: date.timeIntervalSince1970) { Data($0) }
        _ = keychain.write(key: key, data: data)
    }
}
