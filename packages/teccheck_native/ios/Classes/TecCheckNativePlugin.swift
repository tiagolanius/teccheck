import CoreLocation
import Darwin
import Flutter
import UIKit

/// Recursos nativos do TecCheck no iOS:
///  - ICMP echo com TTL configurável (ping e traceroute) via socket ICMP não privilegiado
///  - pedido de permissão de localização (necessária para ler o SSID)
///  - abrir o app Speedtest (Ookla)
public class TecCheckNativePlugin: NSObject, FlutterPlugin, CLLocationManagerDelegate {

    private var locationManager: CLLocationManager?
    private var pendingLocation: FlutterResult?
    private let queue = DispatchQueue(label: "teccheck.icmp", attributes: .concurrent)

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "teccheck_native", binaryMessenger: registrar.messenger())
        let instance = TecCheckNativePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "requestPermissions":
            requestLocation(result)
        case "icmpEcho":
            let host = args["host"] as? String ?? ""
            let ttl = args["ttl"] as? Int ?? 64
            let timeout = args["timeoutMs"] as? Int ?? 2000
            let size = args["size"] as? Int ?? 56
            let df = args["df"] as? Bool ?? false
            queue.async {
                let r = Self.icmpEcho(ip: host, ttl: ttl, timeoutMs: timeout, size: size, df: df)
                DispatchQueue.main.async { result(r) }
            }
        case "reachable":
            let ip = args["ip"] as? String ?? ""
            let timeout = args["timeoutMs"] as? Int ?? 400
            queue.async {
                let r = Self.icmpEcho(ip: ip, ttl: 64, timeoutMs: timeout, size: 16, df: false)
                DispatchQueue.main.async { result((r["status"] as? String) == "reply") }
            }
        case "openOokla":
            guard let url = URL(string: "speedtest://") else { result(false); return }
            UIApplication.shared.open(url, options: [:]) { ok in result(ok) }
        case "netInfo", "wifiScan":
            result(nil) // no iOS estes dados vêm do lado Dart / não são permitidos
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Localização

    private func requestLocation(_ result: @escaping FlutterResult) {
        let mgr = CLLocationManager()
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) { status = mgr.authorizationStatus } else { status = CLLocationManager.authorizationStatus() }
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            result(true)
        case .denied, .restricted:
            result(false)
        default:
            locationManager = mgr
            pendingLocation = result
            mgr.delegate = self
            mgr.requestWhenInUseAuthorization()
        }
    }

    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        guard status != .notDetermined, let r = pendingLocation else { return }
        r(status == .authorizedWhenInUse || status == .authorizedAlways)
        pendingLocation = nil
        locationManager = nil
    }

    // MARK: - ICMP

    private static func checksum(_ data: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i + 1 < data.count {
            sum += (UInt32(data[i]) << 8) | UInt32(data[i + 1])
            i += 2
        }
        if i < data.count { sum += UInt32(data[i]) << 8 }
        while (sum >> 16) != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
        return ~UInt16(truncatingIfNeeded: sum)
    }

    private static func resolve(_ host: String) -> in_addr? {
        var addr = in_addr()
        if inet_pton(AF_INET, host, &addr) == 1 { return addr }
        var hints = addrinfo()
        hints.ai_family = AF_INET
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let first = res else { return nil }
        defer { freeaddrinfo(res) }
        guard let sa = first.pointee.ai_addr else { return nil }
        return sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
    }

    private static func ipString(_ a: in_addr) -> String {
        var a = a
        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &a, &buf, socklen_t(INET_ADDRSTRLEN))
        return String(cString: buf)
    }

    static func icmpEcho(ip: String, ttl: Int, timeoutMs: Int, size: Int, df: Bool) -> [String: Any] {
        guard let target = resolve(ip) else { return ["status": "error", "message": "Host desconhecido"] }

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        if fd < 0 { return ["status": "error", "message": "socket ICMP indisponível"] }
        defer { close(fd) }

        var t = Int32(ttl)
        setsockopt(fd, IPPROTO_IP, IP_TTL, &t, socklen_t(MemoryLayout<Int32>.size))
        if df {
            var one: Int32 = 1
            setsockopt(fd, IPPROTO_IP, 28 /* IP_DONTFRAG */, &one, socklen_t(MemoryLayout<Int32>.size))
        }
        var tv = timeval(tv_sec: 0, tv_usec: 100_000) // lê em fatias de 100 ms até o prazo
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let ident = UInt16.random(in: 1...0xFFFF)
        let seq = UInt16.random(in: 1...0xFFFF)
        var pkt = [UInt8](repeating: 0, count: 8 + max(0, size))
        pkt[0] = 8 // echo request
        pkt[4] = UInt8(ident >> 8); pkt[5] = UInt8(ident & 0xFF)
        pkt[6] = UInt8(seq >> 8); pkt[7] = UInt8(seq & 0xFF)
        for i in 8..<pkt.count { pkt[i] = UInt8(truncatingIfNeeded: i) }
        let cs = checksum(pkt)
        pkt[2] = UInt8(cs >> 8); pkt[3] = UInt8(cs & 0xFF)

        var dest = sockaddr_in()
        dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_addr = target

        let start = DispatchTime.now().uptimeNanoseconds
        let sent = withUnsafePointer(to: &dest) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(fd, pkt, pkt.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if sent < 0 {
            if errno == EMSGSIZE { return ["status": "fragneeded"] }
            return ["status": "error", "message": String(cString: strerror(errno))]
        }

        let deadline = start + UInt64(timeoutMs) * 1_000_000
        var buf = [UInt8](repeating: 0, count: 2048)
        while DispatchTime.now().uptimeNanoseconds < deadline {
            var from = sockaddr_in()
            var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(fd, &buf, buf.count, 0, $0, &fromLen)
                }
            }
            if n <= 0 { continue }
            let len = Int(n)
            // No Darwin o datagrama recebido inclui o cabeçalho IP.
            var off = 0
            if (buf[0] >> 4) == 4 { off = Int(buf[0] & 0x0F) * 4 }
            guard len >= off + 8 else { continue }
            let type = buf[off]
            let fromIp = ipString(from.sin_addr)
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000

            if type == 0 { // echo reply
                let rseq = (UInt16(buf[off + 6]) << 8) | UInt16(buf[off + 7])
                if rseq == seq {
                    return ["status": "reply", "from": fromIp, "rttMs": elapsed]
                }
                continue
            }
            if type == 11 || type == 3 { // TTL excedido / destino inalcançável
                let inner = off + 8
                guard len >= inner + 20 else { continue }
                let innerIhl = Int(buf[inner] & 0x0F) * 4
                let icmp = inner + innerIhl
                guard len >= icmp + 8 else { continue }
                let iseq = (UInt16(buf[icmp + 6]) << 8) | UInt16(buf[icmp + 7])
                guard iseq == seq else { continue }
                if type == 11 { return ["status": "ttl", "from": fromIp, "rttMs": elapsed] }
                let code = buf[off + 1]
                return ["status": code == 4 ? "fragneeded" : "unreachable", "from": fromIp, "rttMs": elapsed]
            }
        }
        return ["status": "timeout"]
    }
}
