// (c) 2014-2024 Ricci Adams
// MIT License (or) 1-clause BSD License

#import <Foundation/Foundation.h>

@class Effect;

@interface EditEffectController : NSWindowController

- (void) moveToolbarControlsIntoContentView;
- (void) reloadData;

- (id) initWithEffect:(Effect *)effect index:(NSInteger)index;

@property (nonatomic, weak) Effect *effect;

- (IBAction) loadPreset:(id)sender;
- (IBAction) savePreset:(id)sender;
- (IBAction) restoreDefaultValues:(id)sender;
- (IBAction) toggleBypass:(id)sender;
- (IBAction) recallEQPreset:(id)sender;
- (IBAction) saveEQPreset:(id)sender;

@end
