//
//  PingFoundation.swift
//  RealReachability2
//
//  Based on Apple's SimplePing sample code.
//  A low-level ICMP ping implementation for Swift.
//
//  Copyright © 2016 Apple Inc. All rights reserved.
//  Copyright © 2016 Dustturtle. All rights reserved.
//

import Foundation

// MARK: - ICMP Header Structure

/// ICMP header structure for IPv4 and IPv6
public struct ICMPHeader {
    var type: UInt8
    var code: UInt8
    var checksum: UInt16
    var identifier: UInt16
    var sequenceNumber: UInt16
}

/// ICMP type values for IPv4
public enum ICMPv4Type: UInt8 {
    case echoRequest = 8
    case echoReply = 0
}

/// ICMP type values for IPv6
public enum ICMPv6Type: UInt8 {
    case echoRequest = 128
    case echoReply = 129
}

// MARK: - Address Style

/// The IP address version to use for ping
public enum PingAddressStyle {
    /// Use the first IPv4 or IPv6 address found (default)
    case any
    /// Use only IPv4
    case icmpv4
    /// Use only IPv6
    case icmpv6
}

// MARK: - Ping Foundation Delegate

/// Delegate protocol for PingFoundation events
@available(iOS 13.0, macOS 10.15, *)
public protocol PingFoundationDelegate: AnyObject {
    /// Called once the object has started up.
    func pingFoundation(_ pinger: PingFoundation, didStartWithAddress address: Data)
    
    /// Called if the object fails to start up.
    func pingFoundation(_ pinger: PingFoundation, didFailWithError error: Error)
    
    /// Called when the object has successfully sent a ping packet.
    func pingFoundation(_ pinger: PingFoundation, didSendPacket packet: Data, sequenceNumber: UInt16)
    
    /// Called when the object fails to send a ping packet.
    func pingFoundation(_ pinger: PingFoundation, didFailToSendPacket packet: Data, sequenceNumber: UInt16, error: Error)
    
    /// Called when the object receives a ping response.
    func pingFoundation(_ pinger: PingFoundation, didReceivePingResponsePacket packet: Data, sequenceNumber: UInt16)
    
    /// Called when the object receives an unmatched packet.
    func pingFoundation(_ pinger: PingFoundation, didReceiveUnexpectedPacket packet: Data)
}

// MARK: - Default Protocol Extension

@available(iOS 13.0, macOS 10.15, *)
public extension PingFoundationDelegate {
    func pingFoundation(_ pinger: PingFoundation, didSendPacket packet: Data, sequenceNumber: UInt16) {}
    func pingFoundation(_ pinger: PingFoundation, didFailToSendPacket packet: Data, sequenceNumber: UInt16, error: Error) {}
    func pingFoundation(_ pinger: PingFoundation, didReceiveUnexpectedPacket packet: Data) {}
}

// MARK: - Ping Foundation

/// Low-level ICMP ping implementation using BSD sockets
@available(iOS 13.0, macOS 10.15, *)
public final class PingFoundation: NSObject {
    
    // MARK: - Public Properties
    
    /// The host name to ping
    public let hostName: String
    
    /// The delegate for callbacks
    public weak var delegate: PingFoundationDelegate?
    
    /// Controls the IP address version used by the object
    public var addressStyle: PingAddressStyle = .any
    
    /// The address being pinged (nil until started)
    public private(set) var hostAddress: Data?
    
    /// The address family for hostAddress
    public var hostAddressFamily: sa_family_t {
        guard let hostAddress = hostAddress, hostAddress.count >= MemoryLayout<sockaddr>.size else {
            return sa_family_t(AF_UNSPEC)
        }
        return hostAddress.withUnsafeBytes { $0.load(as: sockaddr.self).sa_family }
    }
    
    /// The identifier used by pings (random, set at init)
    public let identifier: UInt16
    
    /// The next sequence number to be used
    public private(set) var nextSequenceNumber: UInt16 = 0
    
    // MARK: - Private Properties
    
    private var host: CFHost?
    private var socket: CFSocket?
    private var nextSequenceNumberHasWrapped = false
    
    // MARK: - Initialization
    
    /// Initializes the ping foundation with a host name
    /// - Parameter hostName: The DNS name of the host to ping (or IP address string)
    public init(hostName: String) {
        self.hostName = hostName
        self.identifier = UInt16.random(in: 0...UInt16.max)
        super.init()
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Public Methods
    
    /// Starts the pinger
    public func start() {
        guard host == nil else { return } // Already started
        
        var context = CFHostClientContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        host = CFHostCreateWithName(nil, hostName as CFString).takeRetainedValue()
        guard let host = host else {
            didFail(with: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOMEM), userInfo: nil))
            return
        }
        
        CFHostSetClient(host, hostResolveCallback, &context)
        CFHostScheduleWithRunLoop(host, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        
        var streamError = CFStreamError()
        let success = CFHostStartInfoResolution(host, .addresses, &streamError)
        if !success {
            didFail(withHostStreamError: streamError)
        }
    }
    
    /// Sends an ICMP ping packet
    /// - Parameter data: Optional payload data
    public func sendPing(with data: Data? = nil) {
        let payload: Data
        if let data = data {
            payload = data
        } else {
            let message = String(format: "%28zd bottles of beer on the wall", 99 - Int(nextSequenceNumber % 100))
            payload = message.data(using: .ascii) ?? Data()
        }
        
        let packet: Data
        switch hostAddressFamily {
        case sa_family_t(AF_INET):
            packet = pingPacket(type: ICMPv4Type.echoRequest.rawValue, payload: payload, requiresChecksum: true)
        case sa_family_t(AF_INET6):
            packet = pingPacket(type: ICMPv6Type.echoRequest.rawValue, payload: payload, requiresChecksum: false)
        default:
            assertionFailure("Invalid address family")
            return
        }
        
        var bytesSent: Int = -1
        var err: Int32 = 0
        
        if let socket = socket {
            let fd = CFSocketGetNative(socket)
            bytesSent = hostAddress!.withUnsafeBytes { addrPtr in
                packet.withUnsafeBytes { packetPtr in
                    sendto(fd, packetPtr.baseAddress, packet.count, SO_NOSIGPIPE,
                           addrPtr.baseAddress?.assumingMemoryBound(to: sockaddr.self),
                           socklen_t(hostAddress!.count))
                }
            }
            if bytesSent < 0 {
                err = errno
            }
        } else {
            err = EBADF
        }
        
        if bytesSent > 0 && bytesSent == packet.count {
            delegate?.pingFoundation(self, didSendPacket: packet, sequenceNumber: nextSequenceNumber)
        } else {
            if err == 0 { err = ENOBUFS }
            let error = NSError(domain: NSPOSIXErrorDomain, code: Int(err), userInfo: nil)
            delegate?.pingFoundation(self, didFailToSendPacket: packet, sequenceNumber: nextSequenceNumber, error: error)
        }
        
        nextSequenceNumber &+= 1
        if nextSequenceNumber == 0 {
            nextSequenceNumberHasWrapped = true
        }
    }
    
    /// Stops the pinger
    public func stop() {
        if let socket = socket {
            CFSocketInvalidate(socket)
            self.socket = nil
        }
        
        if let host = host {
            CFHostSetClient(host, nil, nil)
            CFHostUnscheduleFromRunLoop(host, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            self.host = nil
        }
        
        hostAddress = nil
    }
    
    // MARK: - Private Methods
    
    private func pingPacket(type: UInt8, payload: Data, requiresChecksum: Bool) -> Data {
        var header = ICMPHeader(
            type: type,
            code: 0,
            checksum: 0,
            identifier: identifier.bigEndian,
            sequenceNumber: nextSequenceNumber.bigEndian
        )
        
        var packet = Data(bytes: &header, count: MemoryLayout<ICMPHeader>.size)
        packet.append(payload)
        
        if requiresChecksum {
            let checksum = computeChecksum(data: packet)
            packet.replaceSubrange(2..<4, with: withUnsafeBytes(of: checksum) { Data($0) })
        }
        
        return packet
    }
    
    private func computeChecksum(data: Data) -> UInt16 {
        var sum: UInt32 = 0
        var bytesLeft = data.count
        var cursor = 0
        
        while bytesLeft > 1 {
            let word = UInt16(data[cursor]) | (UInt16(data[cursor + 1]) << 8)
            sum += UInt32(word)
            cursor += 2
            bytesLeft -= 2
        }
        
        if bytesLeft == 1 {
            sum += UInt32(data[cursor])
        }
        
        sum = (sum >> 16) + (sum & 0xffff)
        sum += (sum >> 16)
        
        return ~UInt16(truncatingIfNeeded: sum)
    }
    
    private func didFail(with error: Error) {
        stop()
        delegate?.pingFoundation(self, didFailWithError: error)
    }
    
    private func didFail(withHostStreamError streamError: CFStreamError) {
        var userInfo: [String: Any]?
        if streamError.domain == CFStreamErrorDomain.netDB.rawValue {
            userInfo = [kCFGetAddrInfoFailureKey as String: streamError.error]
        }
        let error = NSError(domain: kCFErrorDomainCFNetwork as String, code: Int(CFNetworkErrors.cfHostErrorUnknown.rawValue), userInfo: userInfo)
        didFail(with: error)
    }
    
    fileprivate func hostResolutionDone() {
        guard let host = host else { return }
        
        var resolved = DarwinBoolean(false)
        guard let addresses = CFHostGetAddressing(host, &resolved)?.takeUnretainedValue() as? [Data], resolved.boolValue else {
            didFail(with: NSError(domain: kCFErrorDomainCFNetwork as String, code: Int(CFNetworkErrors.cfHostErrorHostNotFound.rawValue), userInfo: nil))
            return
        }
        
        var foundAddress: Data?
        for address in addresses {
            guard address.count >= MemoryLayout<sockaddr>.size else { continue }
            let family = address.withUnsafeBytes { $0.load(as: sockaddr.self).sa_family }
            
            switch family {
            case sa_family_t(AF_INET):
                if addressStyle != .icmpv6 {
                    foundAddress = address
                }
            case sa_family_t(AF_INET6):
                if addressStyle != .icmpv4 {
                    foundAddress = address
                }
            default:
                continue
            }
            
            if foundAddress != nil { break }
        }
        
        if let address = foundAddress {
            hostAddress = address
            startWithHostAddress()
        } else {
            didFail(with: NSError(domain: kCFErrorDomainCFNetwork as String, code: Int(CFNetworkErrors.cfHostErrorHostNotFound.rawValue), userInfo: nil))
        }
    }
    
    private func startWithHostAddress() {
        guard let hostAddress = hostAddress else { return }
        
        let family = hostAddress.withUnsafeBytes { $0.load(as: sockaddr.self).sa_family }
        var fd: Int32 = -1
        var err: Int32 = 0
        
        switch family {
        case sa_family_t(AF_INET):
            fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
            if fd < 0 { err = errno }
        case sa_family_t(AF_INET6):
            fd = Darwin.socket(AF_INET6, SOCK_DGRAM, IPPROTO_ICMPV6)
            if fd < 0 { err = errno }
        default:
            err = EPROTONOSUPPORT
        }
        
        if err != 0 {
            didFail(with: NSError(domain: NSPOSIXErrorDomain, code: Int(err), userInfo: nil))
            return
        }
        
        var context = CFSocketContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        socket = CFSocketCreateWithNative(nil, fd, CFSocketCallBackType.readCallBack.rawValue, socketReadCallback, &context)
        
        guard let socket = socket else {
            close(fd)
            didFail(with: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOMEM), userInfo: nil))
            return
        }
        
        // Don't close socket on invalidate (we manage it)
        let flags = CFSocketGetSocketFlags(socket)
        CFSocketSetSocketFlags(socket, flags & ~CFOptionFlags(kCFSocketCloseOnInvalidate))
        
        guard let rls = CFSocketCreateRunLoopSource(nil, socket, 0) else {
            stop()
            didFail(with: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOMEM), userInfo: nil))
            return
        }
        
        CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, .defaultMode)
        
        delegate?.pingFoundation(self, didStartWithAddress: hostAddress)
    }
    
    fileprivate func readData() {
        var buffer = [UInt8](repeating: 0, count: 65535)
        var addr = sockaddr_storage()
        var addrLen = socklen_t(MemoryLayout<sockaddr_storage>.size)
        
        let bytesRead = withUnsafeMutablePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                recvfrom(CFSocketGetNative(socket!), &buffer, buffer.count, 0, sockaddrPtr, &addrLen)
            }
        }
        
        if bytesRead > 0 {
            var packet = Data(bytes: buffer, count: bytesRead)
            var sequenceNumber: UInt16 = 0
            
            if validatePingResponsePacket(&packet, sequenceNumber: &sequenceNumber) {
                delegate?.pingFoundation(self, didReceivePingResponsePacket: packet, sequenceNumber: sequenceNumber)
            } else {
                delegate?.pingFoundation(self, didReceiveUnexpectedPacket: packet)
            }
        } else if bytesRead < 0 {
            didFail(with: NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil))
        }
    }
    
    private func validatePingResponsePacket(_ packet: inout Data, sequenceNumber: inout UInt16) -> Bool {
        switch hostAddressFamily {
        case sa_family_t(AF_INET):
            return validatePing4ResponsePacket(&packet, sequenceNumber: &sequenceNumber)
        case sa_family_t(AF_INET6):
            return validatePing6ResponsePacket(&packet, sequenceNumber: &sequenceNumber)
        default:
            return false
        }
    }
    
    private func validatePing4ResponsePacket(_ packet: inout Data, sequenceNumber: inout UInt16) -> Bool {
        // IPv4 header is 20+ bytes, ICMP header is 8 bytes
        guard packet.count >= 28 else { return false }
        
        // Get IP header length
        let versionAndHeaderLength = packet[0]
        guard (versionAndHeaderLength & 0xF0) == 0x40 else { return false } // IPv4
        guard packet[9] == IPPROTO_ICMP else { return false }
        
        let ipHeaderLength = Int(versionAndHeaderLength & 0x0F) * 4
        guard packet.count >= ipHeaderLength + 8 else { return false }
        
        // Extract ICMP header
        let icmpData = packet.subdata(in: ipHeaderLength..<packet.count)
        guard icmpData.count >= 8 else { return false }
        
        let type = icmpData[0]
        let code = icmpData[1]
        let receivedIdentifier = UInt16(icmpData[4]) << 8 | UInt16(icmpData[5])
        let receivedSequence = UInt16(icmpData[6]) << 8 | UInt16(icmpData[7])
        
        guard type == ICMPv4Type.echoReply.rawValue else { return false }
        guard code == 0 else { return false }
        guard receivedIdentifier == identifier else { return false }
        guard validateSequenceNumber(receivedSequence) else { return false }
        
        // Remove IP header from packet
        packet = icmpData
        sequenceNumber = receivedSequence
        return true
    }
    
    private func validatePing6ResponsePacket(_ packet: inout Data, sequenceNumber: inout UInt16) -> Bool {
        guard packet.count >= 8 else { return false }
        
        let type = packet[0]
        let code = packet[1]
        let receivedIdentifier = UInt16(packet[4]) << 8 | UInt16(packet[5])
        let receivedSequence = UInt16(packet[6]) << 8 | UInt16(packet[7])
        
        guard type == ICMPv6Type.echoReply.rawValue else { return false }
        guard code == 0 else { return false }
        guard receivedIdentifier == identifier else { return false }
        guard validateSequenceNumber(receivedSequence) else { return false }
        
        sequenceNumber = receivedSequence
        return true
    }
    
    private func validateSequenceNumber(_ sequenceNumber: UInt16) -> Bool {
        if nextSequenceNumberHasWrapped {
            return (nextSequenceNumber &- sequenceNumber) < 120
        } else {
            return sequenceNumber < nextSequenceNumber
        }
    }
}

// MARK: - CFHost Callback

@available(iOS 13.0, macOS 10.15, *)
private func hostResolveCallback(host: CFHost, typeInfo: CFHostInfoType, error: UnsafePointer<CFStreamError>?, info: UnsafeMutableRawPointer?) {
    guard let info = info else { return }
    let pinger = Unmanaged<PingFoundation>.fromOpaque(info).takeUnretainedValue()
    
    if let error = error, error.pointee.domain != 0 {
        pinger.didFail(withHostStreamError: error.pointee)
    } else {
        pinger.hostResolutionDone()
    }
}

// MARK: - CFSocket Callback

@available(iOS 13.0, macOS 10.15, *)
private func socketReadCallback(socket: CFSocket?, callbackType: CFSocketCallBackType, address: CFData?, data: UnsafeRawPointer?, info: UnsafeMutableRawPointer?) {
    guard let info = info, callbackType == .readCallBack else { return }
    let pinger = Unmanaged<PingFoundation>.fromOpaque(info).takeUnretainedValue()
    pinger.readData()
}
