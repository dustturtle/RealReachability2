//
//  RRPingFoundation.h
//  RealReachability2ObjC
//
//  Based on Apple's SimplePing sample code.
//  Modified for RealReachability2.
//
//  Copyright © 2016 Apple Inc. All rights reserved.
//  Copyright © 2016 Dustturtle. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <sys/socket.h>

#if TARGET_OS_EMBEDDED || TARGET_IPHONE_SIMULATOR
#import <CFNetwork/CFNetwork.h>
#else
#if __has_include(<CoreServices/CoreServices.h>)
#import <CoreServices/CoreServices.h>
#endif
#endif

#include <AssertMacros.h>

NS_ASSUME_NONNULL_BEGIN

@protocol RRPingFoundationDelegate;

/// Address style for ping operations
typedef NS_ENUM(NSInteger, RRPingFoundationAddressStyle) {
    /// Use the first IPv4 or IPv6 address found; the default.
    RRPingFoundationAddressStyleAny,
    /// Use the first IPv4 address found.
    RRPingFoundationAddressStyleICMPv4,
    /// Use the first IPv6 address found.
    RRPingFoundationAddressStyleICMPv6
};

/// ICMP header structure
struct RRICMPHeader {
    uint8_t     type;
    uint8_t     code;
    uint16_t    checksum;
    uint16_t    identifier;
    uint16_t    sequenceNumber;
    // data...
};
typedef struct RRICMPHeader RRICMPHeader;

/// ICMP type values for IPv4
enum {
    RRICMPv4TypeEchoRequest = 8,
    RRICMPv4TypeEchoReply   = 0
};

/// ICMP type values for IPv6
enum {
    RRICMPv6TypeEchoRequest = 128,
    RRICMPv6TypeEchoReply   = 129
};

/// Low-level ICMP ping foundation class
/// An object wrapper around the low-level BSD Sockets ping function.
API_AVAILABLE(ios(12.0), macos(10.14))
@interface RRPingFoundation : NSObject

- (instancetype)init NS_UNAVAILABLE;

/// Initialise the object to ping the specified host.
/// @param hostName The DNS name of the host to ping; an IPv4 or IPv6 address in string form will work here.
/// @returns The initialised object.
- (instancetype)initWithHostName:(NSString *)hostName NS_DESIGNATED_INITIALIZER;

/// A copy of the value passed to `-initWithHostName:`.
@property (nonatomic, copy, readonly) NSString *hostName;

/// The delegate for this object.
/// Delegate callbacks are scheduled in the default run loop mode of the run loop of the
/// thread that calls `-start`.
@property (nonatomic, weak, readwrite, nullable) id<RRPingFoundationDelegate> delegate;

/// Controls the IP address version used by the object.
/// You should set this value before starting the object.
@property (nonatomic, assign, readwrite) RRPingFoundationAddressStyle addressStyle;

/// The address being pinged.
/// The contents of the NSData is a (struct sockaddr) of some form. The
/// value is nil while the object is stopped and remains nil on start until
/// `-pingFoundation:didStartWithAddress:` is called.
@property (nonatomic, copy, readonly, nullable) NSData *hostAddress;

/// The address family for `hostAddress`, or `AF_UNSPEC` if that's nil.
@property (nonatomic, assign, readonly) sa_family_t hostAddressFamily;

/// The identifier used by pings by this object.
/// When you create an instance of this object it generates a random identifier
/// that it uses to identify its own pings.
@property (nonatomic, assign, readonly) uint16_t identifier;

/// The next sequence number to be used by this object.
/// This value starts at zero and increments each time you send a ping (safely
/// wrapping back to zero if necessary). The sequence number is included in the ping,
/// allowing you to match up requests and responses, and thus calculate ping times and so on.
@property (nonatomic, assign, readonly) uint16_t nextSequenceNumber;

/// Starts the pinger object pinging.
/// You should call this after you've setup the delegate and any ping parameters.
- (void)start;

/// Sends an actual ping.
/// Pass nil for data to use a standard 56 byte payload (resulting in a standard 64 byte ping).
/// Otherwise pass a non-nil value and it will be appended to the ICMP header.
/// Do not try to send a ping before you receive the `-pingFoundation:didStartWithAddress:` delegate callback.
/// @param data Optional payload data to send with the ping.
- (void)sendPingWithData:(nullable NSData *)data;

/// Stops the pinger object.
/// You should call this when you're done pinging.
- (void)stop;

@end

/// Delegate protocol for RRPingFoundation
@protocol RRPingFoundationDelegate <NSObject>

@optional

/// Called once the object has started up.
/// This is called shortly after you start the object to tell you that the
/// object has successfully started. On receiving this callback, you can call
/// `-sendPingWithData:` to send pings.
/// If the object didn't start, `-pingFoundation:didFailWithError:` is called instead.
/// @param pinger The object issuing the callback.
/// @param address The address that's being pinged; at the time this delegate callback
///     is made, this will have the same value as the `hostAddress` property.
- (void)pingFoundation:(RRPingFoundation *)pinger didStartWithAddress:(NSData *)address;

/// Called if the object fails to start up.
/// This is called shortly after you start the object to tell you that the
/// object has failed to start. The most likely cause of failure is a problem
/// resolving `hostName`.
/// By the time this callback is called, the object has stopped (that is, you don't
/// need to call `-stop` yourself).
/// @param pinger The object issuing the callback.
/// @param error Describes the failure.
- (void)pingFoundation:(RRPingFoundation *)pinger didFailWithError:(NSError *)error;

/// Called when the object has successfully sent a ping packet.
/// Each call to `-sendPingWithData:` will result in either a
/// `-pingFoundation:didSendPacket:sequenceNumber:` delegate callback or a
/// `-pingFoundation:didFailToSendPacket:sequenceNumber:error:` delegate callback.
/// @param pinger The object issuing the callback.
/// @param packet The packet that was sent; this includes the ICMP header and the
///     data you passed to `-sendPingWithData:` but does not include any IP-level headers.
/// @param sequenceNumber The ICMP sequence number of that packet.
- (void)pingFoundation:(RRPingFoundation *)pinger didSendPacket:(NSData *)packet sequenceNumber:(uint16_t)sequenceNumber;

/// Called when the object fails to send a ping packet.
/// @param pinger The object issuing the callback.
/// @param packet The packet that was not sent.
/// @param sequenceNumber The ICMP sequence number of that packet.
/// @param error Describes the failure.
- (void)pingFoundation:(RRPingFoundation *)pinger didFailToSendPacket:(NSData *)packet sequenceNumber:(uint16_t)sequenceNumber error:(NSError *)error;

/// Called when the object receives a ping response.
/// If the object receives a ping response that matches a ping request that it
/// sent, it informs the delegate via this callback. Matching is primarily done based on
/// the ICMP identifier, although other criteria are used as well.
/// @param pinger The object issuing the callback.
/// @param packet The packet received; this includes the ICMP header and any data that
///     follows that in the ICMP message but does not include any IP-level headers.
/// @param sequenceNumber The ICMP sequence number of that packet.
- (void)pingFoundation:(RRPingFoundation *)pinger didReceivePingResponsePacket:(NSData *)packet sequenceNumber:(uint16_t)sequenceNumber;

/// Called when the object receives an unmatched packet.
/// @param pinger The object issuing the callback.
/// @param packet The unexpected packet that was received.
- (void)pingFoundation:(RRPingFoundation *)pinger didReceiveUnexpectedPacket:(NSData *)packet;

@end

NS_ASSUME_NONNULL_END
