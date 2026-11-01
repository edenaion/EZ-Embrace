#import <Foundation/Foundation.h>
#import "HugAudioEngine.h"

volatile mach_port_t _HugCrashPadIgnoredThread;
volatile BOOL _HugCrashPadEnabled;

static NSUInteger checks;
static void Check(BOOL condition, NSString *message)
{
    checks++;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}

// Isolate the real chain-update method from graph construction. Output is never configured or started.
@interface TestEngine : HugAudioEngine
@property (nonatomic) NSUInteger rebuildCount;
@end
@implementation TestEngine
- (void)_reconnectGraph { self.rebuildCount++; }
@end

@interface ObservedEffect : NSObject
@property (nonatomic) NSUInteger resetCount;
@property (nonatomic) NSUInteger rebuildCountAtReset;
@property (nonatomic, weak) TestEngine *engine;
- (void)reset;
@end
@implementation ObservedEffect
- (void)reset
{
    self.resetCount++;
    self.rebuildCountAtReset = self.engine.rebuildCount;
}
@end

int main(void)
{
    @autoreleasepool {
        TestEngine *engine = [[TestEngine alloc] init];
        ObservedEffect *first = [[ObservedEffect alloc] init];
        ObservedEffect *second = [[ObservedEffect alloc] init];
        first.engine = second.engine = engine;
        NSArray *one = @[first];
        [engine updateEffectAudioUnits:one];
        Check(engine.rebuildCount == 1, @"Adding an effect rebuilds the graph");
        Check(first.resetCount == 0, @"Newly active effect is never reset after graph rebuild");
        [engine updateEffectAudioUnits:(id)@[first, second]];
        Check(first.resetCount == 0 && second.resetCount == 0, @"Adding a second effect preserves both active effects");
        [engine updateEffectAudioUnits:(id)@[second]];
        Check(first.resetCount == 1 && second.resetCount == 0, @"Removing an effect resets only the removed effect");
        Check(first.rebuildCountAtReset == engine.rebuildCount, @"Removed effect resets after graph replacement");
        [engine updateEffectAudioUnits:@[]];
        Check(first.resetCount == 1 && second.resetCount == 1, @"Clearing the chain resets the remaining effect once");
        printf("PASS: %lu effect-lifecycle assertions\n", (unsigned long)checks);
    }
    return 0;
}
