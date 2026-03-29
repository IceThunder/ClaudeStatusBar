import Foundation
import Security

struct Component: Decodable {
    let name: String
    let status: String
}

struct ComponentsResponse: Decodable {
    let page: Page
    let components: [Component]
}

struct Page: Decodable {
    let id: String
    let name: String
    let url: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, url
        case updatedAt = "updated_at"
    }
}

class StatusService {
    static let shared = StatusService()

    private let apiURL = "https://status.claude.com/api/v2/components.json"

    func fetchComponents(completion: @escaping ([Component]) -> Void) {
        guard let url = URL(string: apiURL) else {
            completion([])
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            guard error == nil,
                  let data = data else {
                completion([])
                return
            }

            do {
                let decoder = JSONDecoder()
                let response = try decoder.decode(ComponentsResponse.self, from: data)
                DispatchQueue.main.async {
                    completion(response.components)
                }
            } catch {
                completion([])
            }
        }.resume()
    }
}

// MARK: - Foxcode Status Service

struct FoxcodeMonitor {
    let id: Int
    let name: String
    let groupName: String
    let status: Int  // 1 = 在线, 0 = 离线
    let ping: Int?  // 毫秒
    let lastCheck: String
}

struct FoxcodeGroup: Decodable {
    let id: Int
    let name: String
    let monitorList: [FoxcodeMonitorItem]

    enum CodingKeys: String, CodingKey {
        case id, name
        case monitorList = "monitorList"
    }
}

struct FoxcodeMonitorItem: Decodable {
    let id: Int
    let name: String

    enum CodingKeys: String, CodingKey {
        case id, name
    }
}

struct FoxcodeStatusPage: Decodable {
    let config: FoxcodeConfig?
    let publicGroupList: [FoxcodeGroup]?

    enum CodingKeys: String, CodingKey {
        case config
        case publicGroupList = "publicGroupList"
    }
}

struct FoxcodeConfig: Decodable {
    let slug: String
    let title: String
}

struct FoxcodeHeartbeat: Decodable {
    let status: Int
    let time: String
    let msg: String
    let ping: Int?
}

class FoxcodeStatusService {
    static let shared = FoxcodeStatusService()

    private let baseURL = "https://status.rjj.cc"
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    func fetchStatus(completion: @escaping ([FoxcodeMonitor]) -> Void) {
        let groupURL = "\(baseURL)/api/status-page/foxcode"
        let heartbeatURL = "\(baseURL)/api/status-page/heartbeat/foxcode"

        guard let groupURL = URL(string: groupURL),
              let heartbeatURL = URL(string: heartbeatURL) else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        let groupTask = session.dataTask(with: groupURL) { data, response, error in
            guard error == nil, let data = data else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            do {
                let statusPage = try JSONDecoder().decode(FoxcodeStatusPage.self, from: data)
                let groups = statusPage.publicGroupList ?? []

                self.fetchHeartbeats(url: heartbeatURL, groups: groups, completion: completion)
            } catch {
                DispatchQueue.main.async { completion([]) }
            }
        }
        groupTask.resume()
    }

    private func fetchHeartbeats(url: URL, groups: [FoxcodeGroup], completion: @escaping ([FoxcodeMonitor]) -> Void) {
        let heartbeatTask = session.dataTask(with: url) { data, response, error in
            guard let data = data else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            do {
                let heartbeatData = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let heartbeatList = heartbeatData?["heartbeatList"] as? [String: [[String: Any]]] ?? [:]

                var monitors: [FoxcodeMonitor] = []

                for group in groups {
                    for monitorItem in group.monitorList {
                        let monitorId = String(monitorItem.id)
                        let heartbeats = heartbeatList[monitorId] ?? []
                        guard let latest = heartbeats.last else { continue }

                        let status = (latest["status"] as? NSNumber)?.intValue ?? 0
                        let ping = (latest["ping"] as? NSNumber)?.intValue
                        let time = latest["time"] as? String ?? ""

                        let monitor = FoxcodeMonitor(
                            id: monitorItem.id,
                            name: monitorItem.name,
                            groupName: group.name,
                            status: status,
                            ping: ping,
                            lastCheck: time
                        )
                        monitors.append(monitor)
                    }
                }

                DispatchQueue.main.async {
                    completion(monitors)
                }
            } catch {
                DispatchQueue.main.async { completion([]) }
            }
        }
        heartbeatTask.resume()
    }
}

// MARK: - ZENMUX Status Service

struct ZenmuxSubscriptionDetail: Decodable {
    let plan: ZenmuxPlan
    let currency: String
    let baseUsdPerFlow: Double
    let effectiveUsdPerFlow: Double
    let accountStatus: String
    let quota5Hour: ZenmuxQuota
    let quota7Day: ZenmuxQuota
    let quotaMonthly: ZenmuxMonthlyQuota

    enum CodingKeys: String, CodingKey {
        case plan, currency
        case baseUsdPerFlow = "base_usd_per_flow"
        case effectiveUsdPerFlow = "effective_usd_per_flow"
        case accountStatus = "account_status"
        case quota5Hour = "quota_5_hour"
        case quota7Day = "quota_7_day"
        case quotaMonthly = "quota_monthly"
    }
}

struct ZenmuxPlan: Decodable {
    let tier: String
    let amountUsd: Double
    let interval: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case tier, interval
        case amountUsd = "amount_usd"
        case expiresAt = "expires_at"
    }
}

struct ZenmuxQuota: Decodable {
    let maxFlows: Double
    let maxValueUsd: Double
    let usedFlows: Double?
    let remainingFlows: Double?
    let usagePercentage: Double?
    let resetsAt: String?
    let usedValueUsd: Double?

    enum CodingKeys: String, CodingKey {
        case maxFlows = "max_flows"
        case maxValueUsd = "max_value_usd"
        case usedFlows = "used_flows"
        case remainingFlows = "remaining_flows"
        case usagePercentage = "usage_percentage"
        case resetsAt = "resets_at"
        case usedValueUsd = "used_value_usd"
    }
}

struct ZenmuxMonthlyQuota: Decodable {
    let maxFlows: Double
    let maxValueUsd: Double

    enum CodingKeys: String, CodingKey {
        case maxFlows = "max_flows"
        case maxValueUsd = "max_value_usd"
    }
}

struct ZenmuxResponse: Decodable {
    let success: Bool
    let message: String?
    let data: ZenmuxSubscriptionDetail?
}

class ZenmuxService {
    static let shared = ZenmuxService()

    private let apiURL = "https://zenmux.ai/api/v1/management/subscription/detail"
    private let keychainService = "com.statusbar.zenmux"
    private let keychainAccount = "management_key"

    var hasAPIKey: Bool {
        return getAPIKey() != nil
    }

    func getAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseOperationPrompt as String: "验证以访问 ZENMUX API Key"
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else {
            return nil
        }
        return key
    }

    func saveAPIKey(_ key: String?) {
        deleteAPIKey()

        guard let key = key, !key.isEmpty,
              let data = key.data(using: .utf8) else {
            return
        }

        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            &error
        ) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: accessControl
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    func fetchSubscription(completion: @escaping (ZenmuxSubscriptionDetail?) -> Void) {
        guard let key = getAPIKey(),
              let url = URL(string: apiURL) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil, let data = data else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            do {
                let decoded = try JSONDecoder().decode(ZenmuxResponse.self, from: data)
                if decoded.success, let detail = decoded.data {
                    DispatchQueue.main.async { completion(detail) }
                } else {
                    DispatchQueue.main.async { completion(nil) }
                }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }.resume()
    }
}
