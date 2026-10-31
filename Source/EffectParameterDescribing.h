// (c) 2024 Ricci Adams
// MIT License (or) 1-clause BSD License

#import <Cocoa/Cocoa.h>
#import <AudioToolbox/AudioToolbox.h>

// Optional descriptions shared by an audio unit and its custom editor.
@protocol ParameterDescribing <NSObject>
@optional
- (AUValue) embrace_defaultValueForParameterAddress:(AUParameterAddress)address;
- (NSString *) embrace_helpTextForParameterAddress:(AUParameterAddress)address;
@end
