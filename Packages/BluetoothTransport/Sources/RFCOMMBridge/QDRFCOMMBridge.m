#import "QDRFCOMMBridge.h"

#import <IOBluetooth/IOBluetooth.h>

@interface QDRFCOMMChannel () <IOBluetoothRFCOMMChannelDelegate>
@end

@implementation QDRFCOMMChannel {
    NSString *_address;
    uint8_t _channelID;
    IOBluetoothDevice *_device;
    IOBluetoothRFCOMMChannel *_channel;
    void (^_openCompletion)(int32_t);
    BOOL _closed;
}

- (instancetype)initWithAddress:(NSString *)address channelID:(uint8_t)channelID {
    self = [super init];
    if (self) {
        _address = [address copy];
        _channelID = channelID;
    }
    return self;
}

- (void)openWithCompletion:(void (^)(int32_t))completion {
    NSAssert(NSThread.isMainThread, @"QDRFCOMMChannel must be used on the main thread");
    _openCompletion = [completion copy];
    _device = [IOBluetoothDevice deviceWithAddressString:_address];
    if (_device == nil) {
        [self finishOpen:kIOReturnNoDevice];
        return;
    }

    // isConnected can be stale, even while audio plays, so it only decides whether a
    // best-effort wake-up is worth trying. RFCOMM is attempted either way.
    if (!_device.isConnected && [_device openConnection:self] == kIOReturnSuccess) {
        return; // Continues in connectionComplete:status:.
    }
    [self openChannel];
}

- (void)connectionComplete:(IOBluetoothDevice *)device status:(IOReturn)status {
    // A failure here often means "already connected", so RFCOMM is attempted regardless.
    [self openChannel];
}

- (void)openChannel {
    if (_closed) {
        return;
    }
    IOBluetoothRFCOMMChannel *channel = nil;
    // The synchronous variant can fail immediately on recent macOS versions.
    IOReturn status = [_device openRFCOMMChannelAsync:&channel withChannelID:_channelID delegate:self];
    if (status != kIOReturnSuccess) {
        [self finishOpen:status];
        return;
    }
    _channel = channel;
}

- (void)finishOpen:(int32_t)status {
    void (^completion)(int32_t) = _openCompletion;
    _openCompletion = nil;
    if (completion != nil) {
        completion(status);
    }
}

- (int32_t)writeData:(NSData *)data {
    NSAssert(NSThread.isMainThread, @"QDRFCOMMChannel must be used on the main thread");
    if (_channel == nil) {
        return kIOReturnNotOpen;
    }

    NSUInteger mtu = MAX((NSUInteger)[_channel getMTU], (NSUInteger)1);
    NSUInteger offset = 0;
    while (offset < data.length) {
        NSUInteger length = MIN(mtu, data.length - offset);
        NSData *chunk = [data subdataWithRange:NSMakeRange(offset, length)];
        // The chunk must outlive the write, so it is released in the completion callback.
        void *refcon = (void *)CFBridgingRetain(chunk);
        IOReturn status = [_channel writeAsync:(void *)chunk.bytes length:(UInt16)length refcon:refcon];
        if (status != kIOReturnSuccess) {
            CFBridgingRelease(refcon);
            return status;
        }
        offset += length;
    }
    return kIOReturnSuccess;
}

- (void)close {
    NSAssert(NSThread.isMainThread, @"QDRFCOMMChannel must be used on the main thread");
    _closed = YES;
    [_channel closeChannel];
    _channel = nil;
    _device = nil;
    [self finishOpen:kIOReturnAborted];
}

#pragma mark - IOBluetoothRFCOMMChannelDelegate

- (void)rfcommChannelOpenComplete:(IOBluetoothRFCOMMChannel *)rfcommChannel status:(IOReturn)error {
    [self finishOpen:error];
}

- (void)rfcommChannelData:(IOBluetoothRFCOMMChannel *)rfcommChannel data:(void *)dataPointer length:(size_t)dataLength {
    if (self.onData != nil) {
        self.onData([NSData dataWithBytes:dataPointer length:dataLength]);
    }
}

- (void)rfcommChannelClosed:(IOBluetoothRFCOMMChannel *)rfcommChannel {
    _channel = nil;
    if (self.onClosed != nil) {
        self.onClosed();
    }
}

- (void)rfcommChannelWriteComplete:(IOBluetoothRFCOMMChannel *)rfcommChannel
                            refcon:(void *)refcon
                            status:(IOReturn)error
                      bytesWritten:(size_t)length {
    CFBridgingRelease(refcon);
}

@end

@implementation QDPairedDevice

- (instancetype)initWithDevice:(IOBluetoothDevice *)device {
    self = [super init];
    if (self) {
        _name = [device.name copy] ?: @"";
        _address = [device.addressString copy] ?: @"";
        _isConnected = device.isConnected;
    }
    return self;
}

@end

@implementation QDConnectionMonitor {
    void (^_handler)(NSString *);
    IOBluetoothUserNotification *_notification;
}

- (instancetype)initWithHandler:(void (^)(NSString *))handler {
    self = [super init];
    if (self) {
        _handler = [handler copy];
        _notification = [IOBluetoothDevice registerForConnectNotifications:self
                                                                  selector:@selector(deviceConnected:device:)];
    }
    return self;
}

- (void)deviceConnected:(IOBluetoothUserNotification *)notification device:(IOBluetoothDevice *)device {
    NSString *address = device.addressString;
    if (address != nil) {
        _handler(address);
    }
}

- (void)stop {
    [_notification unregister];
    _notification = nil;
}

@end

BOOL QDBluetoothIsPoweredOn(void) {
    return IOBluetoothHostController.defaultController.powerState == kBluetoothHCIPowerStateON;
}

NSString *QDBluetoothHostAddress(void) {
    return IOBluetoothHostController.defaultController.addressAsString;
}

NSArray<QDPairedDevice *> *QDPairedDevices(void) {
    NSMutableArray<QDPairedDevice *> *result = [NSMutableArray array];
    for (IOBluetoothDevice *device in [IOBluetoothDevice pairedDevices]) {
        [result addObject:[[QDPairedDevice alloc] initWithDevice:device]];
    }
    return result;
}
