//
//  RRPingFoundation.m
//  RealReachability2ObjC
//
//  Based on Apple's SimplePing sample code.
//  Modified for RealReachability2.
//
//  Copyright © 2016 Apple Inc. All rights reserved.
//  Copyright © 2016 Dustturtle. All rights reserved.
//

#import "RRPingFoundation.h"

#include <sys/socket.h>
#include <netinet/in.h>
#include <errno.h>

#pragma mark - IPv4 Header Structure

/// Describes the on-the-wire header format for an IPv4 packet.
struct RRIPv4Header {
    uint8_t     versionAndHeaderLength;
    uint8_t     differentiatedServices;
    uint16_t    totalLength;
    uint16_t    identification;
    uint16_t    flagsAndFragmentOffset;
    uint8_t     timeToLive;
    uint8_t     protocol;
    uint16_t    headerChecksum;
    uint8_t     sourceAddress[4];
    uint8_t     destinationAddress[4];
    // options...
    // data...
};
typedef struct RRIPv4Header RRIPv4Header;

#pragma mark - Checksum Calculation

/// Calculates an IP checksum.
/// This is the standard BSD checksum code, modified to use modern types.
/// @param buffer A pointer to the data to checksum.
/// @param bufferLen The length of that data.
/// @returns The checksum value, in network byte order.
static uint16_t rr_in_cksum(const void *buffer, size_t bufferLen) {
    size_t              bytesLeft;
    int32_t             sum;
    const uint16_t *    cursor;
    union {
        uint16_t        us;
        uint8_t         uc[2];
    } last;
    uint16_t            answer;
    
    bytesLeft = bufferLen;
    sum = 0;
    cursor = buffer;
    
    // Our algorithm is simple, using a 32 bit accumulator (sum), we add
    // sequential 16 bit words to it, and at the end, fold back all the
    // carry bits from the top 16 bits into the lower 16 bits.
    while (bytesLeft > 1) {
        sum += *cursor;
        cursor += 1;
        bytesLeft -= 2;
    }
    
    // Mop up an odd byte, if necessary
    if (bytesLeft == 1) {
        last.uc[0] = * (const uint8_t *) cursor;
        last.uc[1] = 0;
        sum += last.us;
    }
    
    // Add back carry outs from top 16 bits to low 16 bits
    sum = (sum >> 16) + (sum & 0xffff);  // add hi 16 to low 16
    sum += (sum >> 16);                   // add carry
    answer = (uint16_t) ~sum;             // truncate to 16 bits
    
    return answer;
}

#pragma mark - RRPingFoundation Implementation

@interface RRPingFoundation ()

// Read/write versions of public properties
@property (nonatomic, copy, readwrite, nullable) NSData *hostAddress;
@property (nonatomic, assign, readwrite) uint16_t nextSequenceNumber;

// Private properties
@property (nonatomic, assign, readwrite) BOOL nextSequenceNumberHasWrapped;
@property (nonatomic, strong, readwrite, nullable) CFHostRef host __attribute__ ((NSObject));
@property (nonatomic, strong, readwrite, nullable) CFSocketRef socket __attribute__ ((NSObject));

@end

@implementation RRPingFoundation

- (instancetype)initWithHostName:(NSString *)hostName {
    if ([hostName length] <= 0) {
        return nil;
    }
    
    self = [super init];
    if (self != nil) {
        self->_hostName = [hostName copy];
        self->_identifier = (uint16_t) arc4random();
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (sa_family_t)hostAddressFamily {
    sa_family_t result = AF_UNSPEC;
    if ((self.hostAddress != nil) && (self.hostAddress.length >= sizeof(struct sockaddr))) {
        result = ((const struct sockaddr *) self.hostAddress.bytes)->sa_family;
    }
    return result;
}

#pragma mark - Error Handling

/// Shuts down the pinger object and tells the delegate about the error.
- (void)didFailWithError:(NSError *)error {
    id<RRPingFoundationDelegate> strongDelegate;
    
    // We retain ourselves temporarily because it's common for the delegate method
    // to release its last reference to us.
    CFAutorelease(CFBridgingRetain(self));
    
    [self stop];
    
    strongDelegate = self.delegate;
    if ((strongDelegate != nil) && [strongDelegate respondsToSelector:@selector(pingFoundation:didFailWithError:)]) {
        [strongDelegate pingFoundation:self didFailWithError:error];
    }
}

/// Shuts down the pinger object and tells the delegate about the error.
- (void)didFailWithHostStreamError:(CFStreamError)streamError {
    NSDictionary *userInfo;
    NSError *error;
    
    if (streamError.domain == kCFStreamErrorDomainNetDB) {
        userInfo = @{(id) kCFGetAddrInfoFailureKey: @(streamError.error)};
    } else {
        userInfo = nil;
    }
    error = [NSError errorWithDomain:(NSString *) kCFErrorDomainCFNetwork code:kCFHostErrorUnknown userInfo:userInfo];
    
    [self didFailWithError:error];
}

#pragma mark - Ping Packet Building

/// Builds a ping packet from the supplied parameters.
- (NSData *)pingPacketWithType:(uint8_t)type payload:(NSData *)payload requiresChecksum:(BOOL)requiresChecksum {
    NSMutableData *packet;
    RRICMPHeader *icmpPtr;
    
    packet = [NSMutableData dataWithLength:sizeof(*icmpPtr) + payload.length];
    
    icmpPtr = packet.mutableBytes;
    icmpPtr->type = type;
    icmpPtr->code = 0;
    icmpPtr->checksum = 0;
    icmpPtr->identifier     = OSSwapHostToBigInt16(self.identifier);
    icmpPtr->sequenceNumber = OSSwapHostToBigInt16(self.nextSequenceNumber);
    memcpy(&icmpPtr[1], [payload bytes], [payload length]);
    
    if (requiresChecksum) {
        // The IP checksum routine returns a 16-bit number that's already in correct byte order
        icmpPtr->checksum = rr_in_cksum(packet.bytes, packet.length);
    }
    
    return packet;
}

- (void)sendPingWithData:(NSData *)data {
    int err;
    NSData *payload;
    NSData *packet;
    ssize_t bytesSent;
    id<RRPingFoundationDelegate> strongDelegate;
    
    // Construct the ping packet
    payload = data;
    if (payload == nil) {
        payload = [[NSString stringWithFormat:@"%28zd bottles of beer on the wall", (ssize_t) 99 - (size_t) (self.nextSequenceNumber % 100)] dataUsingEncoding:NSASCIIStringEncoding];
    }
    
    switch (self.hostAddressFamily) {
        case AF_INET: {
            packet = [self pingPacketWithType:RRICMPv4TypeEchoRequest payload:payload requiresChecksum:YES];
        } break;
        case AF_INET6: {
            packet = [self pingPacketWithType:RRICMPv6TypeEchoRequest payload:payload requiresChecksum:NO];
        } break;
        default: {
            NSAssert(NO, @"Invalid address family");
            return;
        }
    }
    
    // Send the packet
    if (self.socket == NULL) {
        bytesSent = -1;
        err = EBADF;
    } else {
        bytesSent = sendto(
            CFSocketGetNative(self.socket),
            packet.bytes,
            packet.length,
            SO_NOSIGPIPE,
            self.hostAddress.bytes,
            (socklen_t) self.hostAddress.length
        );
        err = 0;
        if (bytesSent < 0) {
            err = errno;
        }
    }
    
    // Handle the results of the send
    strongDelegate = self.delegate;
    if ((bytesSent > 0) && (((NSUInteger) bytesSent) == packet.length)) {
        // Complete success. Tell the client.
        if ((strongDelegate != nil) && [strongDelegate respondsToSelector:@selector(pingFoundation:didSendPacket:sequenceNumber:)]) {
            [strongDelegate pingFoundation:self didSendPacket:packet sequenceNumber:self.nextSequenceNumber];
        }
    } else {
        NSError *error;
        
        // Some sort of failure. Tell the client.
        if (err == 0) {
            err = ENOBUFS;
        }
        error = [NSError errorWithDomain:NSPOSIXErrorDomain code:err userInfo:nil];
        if ((strongDelegate != nil) && [strongDelegate respondsToSelector:@selector(pingFoundation:didFailToSendPacket:sequenceNumber:error:)]) {
            [strongDelegate pingFoundation:self didFailToSendPacket:packet sequenceNumber:self.nextSequenceNumber error:error];
        }
    }
    
    self.nextSequenceNumber += 1;
    if (self.nextSequenceNumber == 0) {
        self.nextSequenceNumberHasWrapped = YES;
    }
}

#pragma mark - Packet Validation

/// Calculates the offset of the ICMP header within an IPv4 packet.
+ (NSUInteger)icmpHeaderOffsetInIPv4Packet:(NSData *)packet {
    NSUInteger result;
    const struct RRIPv4Header *ipPtr;
    size_t ipHeaderLength;
    
    result = NSNotFound;
    if (packet.length >= (sizeof(RRIPv4Header) + sizeof(RRICMPHeader))) {
        ipPtr = (const RRIPv4Header *) packet.bytes;
        if (((ipPtr->versionAndHeaderLength & 0xF0) == 0x40) &&  // IPv4
            (ipPtr->protocol == IPPROTO_ICMP)) {
            ipHeaderLength = (ipPtr->versionAndHeaderLength & 0x0F) * sizeof(uint32_t);
            if (packet.length >= (ipHeaderLength + sizeof(RRICMPHeader))) {
                result = ipHeaderLength;
            }
        }
    }
    return result;
}

/// Checks whether the specified sequence number is one we sent.
- (BOOL)validateSequenceNumber:(uint16_t)sequenceNumber {
    if (self.nextSequenceNumberHasWrapped) {
        return ((uint16_t) (self.nextSequenceNumber - sequenceNumber)) < (uint16_t) 120;
    } else {
        return sequenceNumber < self.nextSequenceNumber;
    }
}

/// Checks whether an incoming IPv4 packet looks like a ping response.
- (BOOL)validatePing4ResponsePacket:(NSMutableData *)packet sequenceNumber:(uint16_t *)sequenceNumberPtr {
    BOOL result;
    NSUInteger icmpHeaderOffset;
    RRICMPHeader *icmpPtr;
    uint16_t receivedChecksum;
    uint16_t calculatedChecksum;
    
    result = NO;
    
    icmpHeaderOffset = [[self class] icmpHeaderOffsetInIPv4Packet:packet];
    if (icmpHeaderOffset != NSNotFound) {
        icmpPtr = (struct RRICMPHeader *) (((uint8_t *) packet.mutableBytes) + icmpHeaderOffset);
        
        receivedChecksum = icmpPtr->checksum;
        icmpPtr->checksum = 0;
        calculatedChecksum = rr_in_cksum(icmpPtr, packet.length - icmpHeaderOffset);
        icmpPtr->checksum = receivedChecksum;
        
        if (receivedChecksum == calculatedChecksum) {
            if ((icmpPtr->type == RRICMPv4TypeEchoReply) && (icmpPtr->code == 0)) {
                if (OSSwapBigToHostInt16(icmpPtr->identifier) == self.identifier) {
                    uint16_t sequenceNumber;
                    
                    sequenceNumber = OSSwapBigToHostInt16(icmpPtr->sequenceNumber);
                    if ([self validateSequenceNumber:sequenceNumber]) {
                        // Remove the IPv4 header off the front of the data
                        [packet replaceBytesInRange:NSMakeRange(0, icmpHeaderOffset) withBytes:NULL length:0];
                        
                        *sequenceNumberPtr = sequenceNumber;
                        result = YES;
                    }
                }
            }
        }
    }
    
    return result;
}

/// Checks whether an incoming IPv6 packet looks like a ping response.
- (BOOL)validatePing6ResponsePacket:(NSMutableData *)packet sequenceNumber:(uint16_t *)sequenceNumberPtr {
    BOOL result;
    const RRICMPHeader *icmpPtr;
    
    result = NO;
    
    if (packet.length >= sizeof(*icmpPtr)) {
        icmpPtr = packet.bytes;
        
        // In the IPv6 case we don't check the checksum because the kernel has already done this
        if ((icmpPtr->type == RRICMPv6TypeEchoReply) && (icmpPtr->code == 0)) {
            if (OSSwapBigToHostInt16(icmpPtr->identifier) == self.identifier) {
                uint16_t sequenceNumber;
                
                sequenceNumber = OSSwapBigToHostInt16(icmpPtr->sequenceNumber);
                if ([self validateSequenceNumber:sequenceNumber]) {
                    *sequenceNumberPtr = sequenceNumber;
                    result = YES;
                }
            }
        }
    }
    return result;
}

/// Checks whether an incoming packet looks like a ping response.
- (BOOL)validatePingResponsePacket:(NSMutableData *)packet sequenceNumber:(uint16_t *)sequenceNumberPtr {
    BOOL result;
    
    switch (self.hostAddressFamily) {
        case AF_INET: {
            result = [self validatePing4ResponsePacket:packet sequenceNumber:sequenceNumberPtr];
        } break;
        case AF_INET6: {
            result = [self validatePing6ResponsePacket:packet sequenceNumber:sequenceNumberPtr];
        } break;
        default: {
            NSAssert(NO, @"Invalid address family");
            result = NO;
        } break;
    }
    return result;
}

#pragma mark - Socket Reading

/// Reads data from the ICMP socket.
- (void)readData {
    int err;
    struct sockaddr_storage addr;
    socklen_t addrLen;
    ssize_t bytesRead;
    void *buffer;
    enum { kBufferSize = 65535 };
    
    buffer = malloc(kBufferSize);
    if (buffer == NULL) {
        return;
    }
    
    // Actually read the data
    addrLen = sizeof(addr);
    bytesRead = recvfrom(CFSocketGetNative(self.socket), buffer, kBufferSize, 0, (struct sockaddr *) &addr, &addrLen);
    err = 0;
    if (bytesRead < 0) {
        err = errno;
    }
    
    // Process the data
    if (bytesRead > 0) {
        NSMutableData *packet;
        id<RRPingFoundationDelegate> strongDelegate;
        uint16_t sequenceNumber;
        
        packet = [NSMutableData dataWithBytes:buffer length:(NSUInteger) bytesRead];
        
        // Try to validate the packet
        if ([self validatePingResponsePacket:packet sequenceNumber:&sequenceNumber]) {
            strongDelegate = self.delegate;
            if ((strongDelegate != nil) && [strongDelegate respondsToSelector:@selector(pingFoundation:didReceivePingResponsePacket:sequenceNumber:)]) {
                [strongDelegate pingFoundation:self didReceivePingResponsePacket:packet sequenceNumber:sequenceNumber];
            }
        } else {
            strongDelegate = self.delegate;
            if ((strongDelegate != nil) && [strongDelegate respondsToSelector:@selector(pingFoundation:didReceiveUnexpectedPacket:)]) {
                [strongDelegate pingFoundation:self didReceiveUnexpectedPacket:packet];
            }
        }
    } else {
        // Error occurred
        if (err != 0) {
            [self didFailWithError:[NSError errorWithDomain:NSPOSIXErrorDomain code:err userInfo:nil]];
        }
    }
    
    free(buffer);
}

/// CFSocket callback for receiving data
static void SocketReadCallback(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info) {
    RRPingFoundation *obj = (__bridge RRPingFoundation *) info;
    
    if (type == kCFSocketReadCallBack) {
        [obj readData];
    }
}

#pragma mark - Host Resolution

/// Called by the CFHost API when the host name resolution completes.
static void HostResolveCallback(CFHostRef theHost, CFHostInfoType typeInfo, const CFStreamError *error, void *info) {
    RRPingFoundation *obj = (__bridge RRPingFoundation *) info;
    
    if ((error != NULL) && (error->domain != 0)) {
        [obj didFailWithHostStreamError:*error];
    } else {
        [obj hostResolutionDone];
    }
}

/// Called when host resolution is complete.
- (void)hostResolutionDone {
    Boolean resolved;
    NSArray *addresses;
    
    // Get the addresses
    addresses = (__bridge NSArray *) CFHostGetAddressing(self.host, &resolved);
    if (resolved && (addresses != nil)) {
        // Find a suitable address
        resolved = false;
        for (NSData *address in addresses) {
            const struct sockaddr *addrPtr = (const struct sockaddr *) address.bytes;
            
            if (address.length >= sizeof(struct sockaddr)) {
                switch (addrPtr->sa_family) {
                    case AF_INET: {
                        if (self.addressStyle != RRPingFoundationAddressStyleICMPv6) {
                            self.hostAddress = address;
                            resolved = true;
                        }
                    } break;
                    case AF_INET6: {
                        if (self.addressStyle != RRPingFoundationAddressStyleICMPv4) {
                            self.hostAddress = address;
                            resolved = true;
                        }
                    } break;
                }
            }
            if (resolved) {
                break;
            }
        }
    }
    
    if (resolved) {
        [self startWithHostAddress];
    } else {
        [self didFailWithError:[NSError errorWithDomain:(NSString *)kCFErrorDomainCFNetwork code:kCFHostErrorHostNotFound userInfo:nil]];
    }
}

/// Starts the send and receive infrastructure after we have a valid host address.
- (void)startWithHostAddress {
    int err;
    int fd;
    const struct sockaddr *addrPtr;
    
    addrPtr = (const struct sockaddr *) self.hostAddress.bytes;
    
    // Create the socket
    fd = -1;
    err = 0;
    switch (addrPtr->sa_family) {
        case AF_INET: {
            fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
            if (fd < 0) {
                err = errno;
            }
        } break;
        case AF_INET6: {
            fd = socket(AF_INET6, SOCK_DGRAM, IPPROTO_ICMPV6);
            if (fd < 0) {
                err = errno;
            }
        } break;
        default: {
            err = EPROTONOSUPPORT;
        } break;
    }
    
    if (err != 0) {
        [self didFailWithError:[NSError errorWithDomain:NSPOSIXErrorDomain code:err userInfo:nil]];
    } else {
        CFSocketContext context = {0, (__bridge void *)(self), NULL, NULL, NULL};
        CFRunLoopSourceRef rls;
        
        // Create the CFSocket wrapper
        self.socket = CFSocketCreateWithNative(NULL, fd, kCFSocketReadCallBack, SocketReadCallback, &context);
        if (self.socket == NULL) {
            close(fd);
            [self didFailWithError:[NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil]];
        } else {
            // CFSocket will now close the socket
            CFSocketSetSocketFlags(self.socket, CFSocketGetSocketFlags(self.socket) & ~(CFOptionFlags)kCFSocketCloseOnInvalidate);
            
            // Connect to the run loop
            rls = CFSocketCreateRunLoopSource(NULL, self.socket, 0);
            if (rls == NULL) {
                [self stop];
                [self didFailWithError:[NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil]];
            } else {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kCFRunLoopDefaultMode);
                CFRelease(rls);
                
                // Tell the delegate we started
                id<RRPingFoundationDelegate> strongDelegate = self.delegate;
                if ((strongDelegate != nil) && [strongDelegate respondsToSelector:@selector(pingFoundation:didStartWithAddress:)]) {
                    [strongDelegate pingFoundation:self didStartWithAddress:self.hostAddress];
                }
            }
        }
    }
}

#pragma mark - Start/Stop

- (void)start {
    Boolean success;
    CFHostClientContext context = {0, (__bridge void *)(self), NULL, NULL, NULL};
    CFStreamError streamError;
    
    if (self.host != nil) {
        return;  // Already started
    }
    
    // Create the CFHost object
    self.host = CFHostCreateWithName(NULL, (__bridge CFStringRef) self.hostName);
    if (self.host == NULL) {
        [self didFailWithError:[NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil]];
        return;
    }
    
    CFHostSetClient(self.host, HostResolveCallback, &context);
    CFHostScheduleWithRunLoop(self.host, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    
    // Start the resolution
    success = CFHostStartInfoResolution(self.host, kCFHostAddresses, &streamError);
    if (!success) {
        [self didFailWithHostStreamError:streamError];
    }
}

- (void)stop {
    // Clean up socket
    if (self.socket != NULL) {
        CFSocketInvalidate(self.socket);
        self.socket = NULL;
    }
    
    // Clean up host
    if (self.host != NULL) {
        CFHostSetClient(self.host, NULL, NULL);
        CFHostUnscheduleFromRunLoop(self.host, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        self.host = NULL;
    }
    
    self.hostAddress = nil;
}

@end
