// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Network

/// Serves only this playback's generated playlists and allowlisted BBC media.
/// All traffic stays on the Apple TV; padded fragments are normalized in memory.
final class LocalHLSServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.beebplayer.Beeb.local-hls")
    private var listener: NWListener?
    private var connections = [ObjectIdentifier: NWConnection]()
    private var resources = [ObjectIdentifier: Task<Void, Never>]()
    private var resourceHandler: (@Sendable (String) async throws -> Data?)?
    private var downloads = [ObjectIdentifier: URLSessionDataTask]()
    private var playlists = [String: Data]()
    private var media = [String: URL]()
    private let session: URLSession
    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }
    func start(playlists: [String: Data], media: [String: URL] = [:], resourceHandler: (@Sendable (String) async throws -> Data?)? = nil) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    self.playlists = playlists; self.media = media; self.resourceHandler = resourceHandler
                    let parameters = NWParameters.tcp
                    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
                    let listener = try NWListener(using: parameters, on: .any)
                    self.listener = listener
                    let prefix = "/" + UUID().uuidString.lowercased()
                    var resumed = false
                    listener.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            if !resumed, let port = listener.port { resumed = true; continuation.resume(returning: URL(string: "http://127.0.0.1:\(port.rawValue)\(prefix)/master.m3u8")!); listener.stateUpdateHandler = nil }
                        case .failed(let error):
                            if !resumed { resumed = true; continuation.resume(throwing: error) }
                        case .cancelled:
                            if !resumed { resumed = true; continuation.resume(throwing: CancellationError()) }
                        default: break
                        }
                    }
                    listener.newConnectionHandler = { connection in
                        let id = ObjectIdentifier(connection); self.connections[id] = connection
                        connection.stateUpdateHandler = { state in
                            switch state {
                            case .cancelled, .failed:
                                self.connections.removeValue(forKey: id)
                                self.downloads.removeValue(forKey: id)?.cancel()
                                self.resources.removeValue(forKey: id)?.cancel()
                            default: break
                            }
                        }
                        connection.start(queue: self.queue)
                        self.receive(connection, prefix: prefix, accumulated: Data())
                    }
                    listener.start(queue: self.queue)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    private func receive(_ connection: NWConnection, prefix: String, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, complete, error in
            var received = accumulated; if let data { received.append(data) }
            guard error == nil, received.count <= 16384 else { connection.cancel(); return }
            guard received.range(of: Data("\r\n\r\n".utf8)) != nil else {
                if complete { connection.cancel() } else { self.receive(connection, prefix: prefix, accumulated: received) }; return
            }
            let lines = String(decoding: received, as: UTF8.self).components(separatedBy: "\r\n")
            let request = lines.first?.split(separator: " ") ?? []
            let method = request.first.map(String.init) ?? "", path = request.count > 1 ? String(request[1]).components(separatedBy: "?")[0] : ""
            let key = path.hasPrefix(prefix + "/") ? String(path.dropFirst(prefix.count)) : ""
            let range = lines.first { $0.lowercased().hasPrefix("range:") }.map { String($0.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
            guard method == "GET" || method == "HEAD" else { self.send(connection, status: "405 Method Not Allowed", data: Data(), type: "text/plain"); return }
            if let body = self.playlists[key] {
                self.send(connection, data: body, type: key.hasSuffix(".vtt") ? "text/vtt; charset=utf-8" : "application/vnd.apple.mpegurl", head: method == "HEAD", range: range)
            } else if let remote = self.media[key], remote.scheme == "https" {
                let id = ObjectIdentifier(connection)
                let task = self.session.dataTask(with: remote) { data, response, error in
                    self.queue.async {
                        self.downloads.removeValue(forKey: id)
                        guard self.connections[id] != nil else { return }
                        guard error == nil, let response = response as? HTTPURLResponse, response.statusCode == 200,
                              let data, data.count <= 64 * 1024 * 1024 else {
                            self.send(connection, status: "502 Bad Gateway", data: Data("BBC media request failed.".utf8), type: "text/plain"); return
                        }
                        do {
                            let body = key.hasSuffix(".m4s") ? try FMP4Normalizer.normalize(data) : data
                            self.send(connection, data: body, type: "video/mp4", head: method == "HEAD", range: range)
                        } catch {
                            self.send(connection, status: "502 Bad Gateway", data: Data("Unsupported UHD fragment.".utf8), type: "text/plain")
                        }
                    }
                }
                self.downloads[id] = task; task.resume()
            } else if !key.isEmpty, let handler = self.resourceHandler {
                let id = ObjectIdentifier(connection)
                self.resources[id] = Task {
                    let body = try? await handler(key)
                    guard !Task.isCancelled else { return }
                    self.queue.async {
                        self.resources.removeValue(forKey: id)
                        guard self.connections[id] != nil else { return }
                        if let body {
                            self.send(connection, data: body, type: key.hasSuffix(".vtt") ? "text/vtt; charset=utf-8" : "application/vnd.apple.mpegurl", head: method == "HEAD", range: range)
                        } else { self.send(connection, status: "404 Not Found", data: Data(), type: "text/plain") }
                    }
                }
            } else { self.send(connection, status: "404 Not Found", data: Data(), type: "text/plain") }
        }
    }
    private func send(_ connection: NWConnection, status: String = "200 OK", data: Data, type: String, head: Bool = false, range: String? = nil) {
        var status = status, body = data, extra = ""
        if let range, status == "200 OK" {
            // Apply ranges after normalization so offsets describe the bytes AVPlayer receives.
            guard let bounds = Self.byteRange(range, count: data.count) else {
                let response = Data("HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */\(data.count)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() }); return
            }
            status = "206 Partial Content"; body = data.subdata(in: bounds)
            extra = "Content-Range: bytes \(bounds.lowerBound)-\(bounds.upperBound-1)/\(data.count)\r\n"
        }
        var response = Data("HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nAccept-Ranges: bytes\r\n\(extra)Cache-Control: no-store\r\nConnection: close\r\n\r\n".utf8)
        if !head { response.append(body) }
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
    static func byteRange(_ input: String, count: Int) -> Range<Int>? {
        guard input.hasPrefix("bytes="), count > 0 else { return nil }
        let pieces = input.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 2 else { return nil }
        if pieces[0].isEmpty {
            guard let suffix = Int(pieces[1]), suffix > 0 else { return nil }
            return max(0, count - suffix)..<count
        }
        guard let start = Int(pieces[0]), start >= 0, start < count else { return nil }
        let end: Int
        if pieces[1].isEmpty { end = count - 1 }
        else { guard let value = Int(pieces[1]), value >= start else { return nil }; end = min(count - 1, value) }
        return start..<end+1
    }
    func update(playlists: [String: Data], media: [String: URL]) {
        queue.async { self.playlists = playlists; self.media = media }
    }
    func stop() {
        queue.async {
            self.listener?.newConnectionHandler = nil
            self.listener?.cancel(); self.listener = nil
            self.playlists.removeAll(); self.media.removeAll(); self.resourceHandler = nil
            for task in self.resources.values { task.cancel() }; self.resources.removeAll()
            for task in self.downloads.values { task.cancel() }; self.downloads.removeAll()
            for connection in self.connections.values { connection.cancel() }; self.connections.removeAll()
        }
    }
    deinit { listener?.cancel(); session.invalidateAndCancel() }
}
