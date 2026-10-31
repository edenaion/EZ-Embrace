// (c) 2014-2024 Ricci Adams
// MIT License (or) 1-clause BSD License

#import <Cocoa/Cocoa.h>

@class HugMeterData;

@interface SetlistMeterView : NSView <EmbraceWindowListener>

+ (NSColor *) colorForPeakLevel:(float)peak limiterActive:(BOOL)limiterActive;

@property (nonatomic, getter=isMetering) BOOL metering;

- (void) setLeftMeterData:(HugMeterData *)leftMeterData
           rightMeterData:(HugMeterData *)rightMeterData;

@property (nonatomic, readonly) HugMeterData *leftMeterData;
@property (nonatomic, readonly) HugMeterData *rightMeterData;

@end
