import Foundation

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
