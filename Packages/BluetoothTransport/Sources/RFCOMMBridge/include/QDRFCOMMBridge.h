#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One RFCOMM channel to one device. Every method must be called on the main thread,
/// and every callback arrives there, because IOBluetooth delivers on the run loop that
/// opened the channel.
@interface QDRFCOMMChannel : NSObject

- (instancetype)initWithAddress:(NSString *)address channelID:(uint8_t)channelID NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, copy, nullable) void (^onData)(NSData *data);
@property (nonatomic, copy, nullable) void (^onClosed)(void);

/// Opens asynchronously. The completion receives an IOReturn, 0 on success, exactly once.
- (void)openWithCompletion:(void (^)(int32_t status))completion;

/// Queues bytes for sending and returns an IOReturn, 0 on success.
- (int32_t)writeData:(NSData *)data;

/// Closes the RFCOMM channel only. The baseband link stays up, because audio uses it.
- (void)close;

@end

/// A device paired with this Mac. `isConnected` is informational and can be stale.
@interface QDPairedDevice : NSObject

@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *address;
@property (nonatomic, readonly) BOOL isConnected;

@end

/// Reports Bluetooth connections, so a session can come back after a power cycle.
@interface QDConnectionMonitor : NSObject

- (instancetype)initWithHandler:(void (^)(NSString *address))handler NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)stop;

@end

/// Whether the Bluetooth controller is switched on.
BOOL QDBluetoothIsPoweredOn(void);

/// This Mac's Bluetooth address, or nil. Like the power state, call it off the main thread.
NSString *_Nullable QDBluetoothHostAddress(void);

/// Returns the devices paired with this Mac.
NSArray<QDPairedDevice *> *QDPairedDevices(void);

NS_ASSUME_NONNULL_END
