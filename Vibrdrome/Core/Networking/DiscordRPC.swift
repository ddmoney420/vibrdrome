#if os(macOS)
import Foundation
import os.log

// MARK: - Discord Presence Info

/// Data needed to update Discord Rich Presence.
struct DiscordPresenceInfo: Sendable {
    let title: String
    let artist: String
    let album: String?
    let isPlaying: Bool
    let elapsed: TimeInterval?
    let duration: TimeInterval?
}

// MARK: - Discord RPC Client

/// Manages Discord Rich Presence via IPC unix domain sockets.
/// macOS only. Resilient to Discord not running.
actor DiscordRPCClient {
    static let shared = DiscordRPCClient()

    // Replace with your Discord Application ID from https://discord.com/developers/applications
    private let applicationId = "1491666224378019911"

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.vibrdrome", category: "DiscordRPC")

    private var socketFD: Int32?
    private var isConnected = false
    private var reconnectTask: Task<Void, Never>?
    private var shouldReconnect = true

    // MARK: - IPC Protocol

    private enum Opcode: UInt32 {
        case handshake = 0
        case frame = 1
        case close = 2
    }

    // MARK: - Connection

    /// Connect to Discord IPC socket. Tries pipes 0 through 9.
    func connect() {
        guard !isConnected else { return }

        // macOS uses $TMPDIR (user-specific), not /tmp
        let tmpDir = NSTemporaryDirectory()
        logger.info("Attempting Discord IPC connection, tmpDir: \(tmpDir)")

        for pipeIndex in 0...9 {
            let path = "\(tmpDir)discord-ipc-\(pipeIndex)"

            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { continue }

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)

            let pathBytes = path.utf8CString
            guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
                Darwin.close(fd)
                continue
            }

            withUnsafeMutablePointer(to: &addr.sun_path) { sunPathPtr in
                sunPathPtr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                    pathBytes.withUnsafeBufferPointer { src in
                        _ = memcpy(dest, src.baseAddress!, pathBytes.count)
                    }
                }
            }

            let addrLen = socklen_t(MemoryLayout<sa_family_t>.size + pathBytes.count)
            let result = withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    Darwin.connect(fd, sockaddrPtr, addrLen)
                }
            }

            if result == 0 {
                socketFD = fd
                logger.info("Connected to Discord IPC pipe \(pipeIndex)")

                if performHandshake() {
                    isConnected = true
                    return
                } else {
                    Darwin.close(fd)
                    socketFD = nil
                }
            } else {
                Darwin.close(fd)
            }
        }

        logger.debug("Discord not available (no IPC socket found)")
        scheduleReconnect()
    }

    /// Disconnect from Discord IPC.
    func disconnect() {
        shouldReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        closeSocket()
    }

    /// Clear presence and disconnect.
    func clearPresence() {
        guard isConnected else { return }

        let payload: [String: Any] = [
            "cmd": "SET_ACTIVITY",
            "args": [
                "pid": ProcessInfo.processInfo.processIdentifier
            ],
            "nonce": UUID().uuidString,
        ]

        sendFrame(payload)
    }

    /// Update Discord Rich Presence with current playback info.
    func updatePresence(_ info: DiscordPresenceInfo) {
        if !isConnected {
            connect()
            guard isConnected else { return }
        }

        var activity: [String: Any] = [
            "details": info.title,
            "state": "by \(info.artist)",
        ]

        // Assets
        var assets: [String: Any] = [
            "large_image": "vibrdrome_icon",
        ]
        if let album = info.album, !album.isEmpty {
            assets["large_text"] = album
        }
        if info.isPlaying {
            assets["small_image"] = "play"
            assets["small_text"] = "Playing"
        } else {
            assets["small_image"] = "pause"
            assets["small_text"] = "Paused"
        }
        activity["assets"] = assets

        // Timestamps - show elapsed time when playing
        if info.isPlaying, let elapsed = info.elapsed {
            let startTimestamp = Int(Date().timeIntervalSince1970 - elapsed)
            var timestamps: [String: Any] = ["start": startTimestamp]
            if let duration = info.duration {
                timestamps["end"] = startTimestamp + Int(duration)
            }
            activity["timestamps"] = timestamps
        }

        let payload: [String: Any] = [
            "cmd": "SET_ACTIVITY",
            "args": [
                "pid": ProcessInfo.processInfo.processIdentifier,
                "activity": activity,
            ],
            "nonce": UUID().uuidString,
        ]

        if !sendFrame(payload) {
            handleDisconnect()
        }
    }

    // MARK: - Private

    private func performHandshake() -> Bool {
        let handshake: [String: Any] = [
            "v": 1,
            "client_id": applicationId,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: handshake) else {
            logger.error("Failed to serialize handshake")
            return false
        }

        return sendPacket(opcode: .handshake, data: data) && readResponse()
    }

    @discardableResult
    private func sendFrame(_ payload: [String: Any]) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            logger.error("Failed to serialize frame payload")
            return false
        }

        return sendPacket(opcode: .frame, data: data)
    }

    private func sendPacket(opcode: Opcode, data: Data) -> Bool {
        guard let fd = socketFD else { return false }

        // Header: opcode (UInt32 LE) + length (UInt32 LE)
        var header = Data(count: 8)
        var op = opcode.rawValue.littleEndian
        var len = UInt32(data.count).littleEndian
        header.replaceSubrange(0..<4, with: Data(bytes: &op, count: 4))
        header.replaceSubrange(4..<8, with: Data(bytes: &len, count: 4))

        let packet = header + data
        let written = packet.withUnsafeBytes { bufferPtr in
            Darwin.write(fd, bufferPtr.baseAddress!, packet.count)
        }

        if written != packet.count {
            logger.error("Failed to write packet: wrote \(written) of \(packet.count)")
            return false
        }

        return true
    }

    private func readResponse() -> Bool {
        guard let fd = socketFD else { return false }

        // Read header (8 bytes)
        var headerBuf = [UInt8](repeating: 0, count: 8)
        let headerRead = Darwin.read(fd, &headerBuf, 8)
        guard headerRead == 8 else {
            logger.error("Failed to read response header")
            return false
        }

        // Parse length from header bytes 4-7 (little-endian)
        let length = headerBuf.withUnsafeBufferPointer { buf in
            UInt32(buf[4]) | (UInt32(buf[5]) << 8) | (UInt32(buf[6]) << 16) | (UInt32(buf[7]) << 24)
        }

        guard length > 0, length < 65536 else {
            logger.error("Invalid response length: \(length)")
            return false
        }

        // Read payload
        var payloadBuf = [UInt8](repeating: 0, count: Int(length))
        let payloadRead = Darwin.read(fd, &payloadBuf, Int(length))
        guard payloadRead == Int(length) else {
            logger.error("Failed to read response payload")
            return false
        }

        logger.debug("Discord handshake response received")
        return true
    }

    private func closeSocket() {
        if let fd = socketFD {
            Darwin.close(fd)
            socketFD = nil
        }
        isConnected = false
    }

    private func handleDisconnect() {
        logger.info("Discord disconnected")
        closeSocket()
        if shouldReconnect {
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard shouldReconnect else { return }
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            await self?.connect()
        }
    }
}
#endif
