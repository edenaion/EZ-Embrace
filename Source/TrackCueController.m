#import "TrackCueController.h"
#import "Track.h"
#import "WaveformView.h"
#import "Preferences.h"
#import "InterfaceAppearance.h"
#import "AuditionPlayer.h"
#import "AuditionRoute.h"
#import "HugAudioDevice.h"

@implementation TrackCueButton
- (BOOL) acceptsFirstMouse:(NSEvent *)event { return YES; }
- (BOOL) mouseDownCanMoveWindow { return NO; }
- (void) setCueActive:(BOOL)cueActive { _cueActive = cueActive; self.needsDisplay = YES; }
- (void) viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay = YES; }
- (void) drawRect:(NSRect)dirtyRect
{
    NSColor *color = _cueActive ? NSColor.systemBlueColor : NSColor.secondaryLabelColor;
    if (self.highlighted) {
        [[NSColor.labelColor colorWithAlphaComponent:0.1] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1, 1) xRadius:4 yRadius:4] fill];
    }
    NSImage *symbol = [NSImage imageWithSystemSymbolName:@"flag" accessibilityDescription:nil];
    NSImage *tinted = [NSImage imageWithSize:NSMakeSize(13, 13) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [symbol drawInRect:rect];
        [color setFill];
        NSRectFillUsingOperation(rect, NSCompositingOperationSourceAtop);
        return YES;
    }];
    NSRect icon = NSMakeRect(round(NSMidX(self.bounds) - 6.5), round(NSMidY(self.bounds) - 6.5), 13, 13);
    [tinted drawInRect:icon];
    if (_cueActive) {
        [color setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMaxX(icon) - 1, NSMaxY(icon) - 2, 4, 4)] fill];
    }
}
@end

// Reuses the decoded overview while keeping all cue interaction local to the draft.
@interface TrackCueWaveform : WaveformView
@property (nonatomic, weak) id target;
@property (nonatomic) SEL action;
@end

@implementation TrackCueWaveform
- (Track *) seekTrack { return self.track.playDuration > 0 ? self.track : nil; }
- (void) _applyPercentage:(double)percentage
{
    self.percentage = MIN(1, MAX(0, percentage));
    [NSApp sendAction:self.action to:self.target from:self];
}
- (void) _applyEvent:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    [self _applyPercentage:self.bounds.size.width > 0 ? point.x / self.bounds.size.width : 0];
}
- (void) mouseDown:(NSEvent *)event
{
    if (![self seekTrack]) return;
    [self.window makeFirstResponder:self];
    double original = self.percentage;
    [self _applyEvent:event];
    while (YES) {
        NSEvent *next = [self.window nextEventMatchingMask:NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp | NSEventMaskKeyDown
            untilDate:NSDate.distantFuture inMode:NSEventTrackingRunLoopMode dequeue:YES];
        if (!next || (next.type == NSEventTypeKeyDown && next.keyCode == 53)) { [self _applyPercentage:original]; break; }
        if (next.type == NSEventTypeKeyDown) continue;
        [self _applyEvent:next];
        if (next.type == NSEventTypeLeftMouseUp) break;
    }
}
- (void) keyDown:(NSEvent *)event
{
    if (event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption)) { [super keyDown:event]; return; }
    double step = (event.modifierFlags & NSEventModifierFlagShift ? 15 : 5) / MAX(1, self.track.playDuration);
    switch (event.keyCode) {
        case 123: [self _applyPercentage:self.percentage - step]; break;
        case 124: [self _applyPercentage:self.percentage + step]; break;
        case 115: [self _applyPercentage:0]; break;
        case 119: [self _applyPercentage:1]; break;
        default: [super keyDown:event]; break;
    }
}
- (NSString *) accessibilityLabel { return NSLocalizedString(@"Cue start position", nil); }
- (NSString *) accessibilityHelp { return NSLocalizedString(@"Choose a start point for this track. Save start applies it. Playback is unchanged while editing.", nil); }
- (BOOL) isAccessibilityEnabled { return [self seekTrack] != nil; }
- (BOOL) isAccessibilitySelectorAllowed:(SEL)selector
{
    if (selector == @selector(setAccessibilityValue:)) return [self seekTrack] != nil;
    return [super isAccessibilitySelectorAllowed:selector];
}
- (void) setAccessibilityValue:(id)value { if ([value respondsToSelector:@selector(doubleValue)]) [self _applyPercentage:[value doubleValue] / 100]; }
- (BOOL) accessibilityPerformIncrement { [self _applyPercentage:self.percentage + 5 / MAX(1, self.track.playDuration)]; return YES; }
- (BOOL) accessibilityPerformDecrement { [self _applyPercentage:self.percentage - 5 / MAX(1, self.track.playDuration)]; return YES; }
@end

@interface TrackCueController () <NSPopoverDelegate, NSTextFieldDelegate>
@property (nonatomic, strong) Track *track;
@property (nonatomic, weak) NSPopover *popover;
@end

@implementation TrackCueController {
    NSTextField *_timeField;
    NSTextField *_durationField;
    NSTextField *_errorField;
    NSTextField *_trackField;
    NSTextField *_previewStatusField;
    TrackCueWaveform *_waveform;
    NSSlider *_slider;
    NSButton *_previewButton;
    NSButton *_pausePreviewButton;
    NSButton *_stopPreviewButton;
    NSStackView *_stack;
    NSView *_documentView;
    CGFloat _scale;
    CGFloat _contentWidth;
    NSTimeInterval _draft;
    AuditionPlayer *_audition;
    NSUUID *_auditionRequestIdentifier;
    NSString *_auditionOutputName;
}

static __weak NSPopover *sVisibleCuePopover;

+ (NSPopover *) showForTrack:(Track *)track relativeToView:(NSView *)anchor
{
    [sVisibleCuePopover close];
    TrackCueController *controller = [self new];
    controller.track = track;
    controller->_draft = track.cueStartTime;
    CGFloat anchorScale = [anchor convertRect:anchor.bounds toView:nil].size.width / MAX(1, anchor.bounds.size.width);
    controller->_scale = MAX([[Preferences sharedInstance] textSizePercent] / 100.0, anchorScale);
    NSRect screen = anchor.window.screen.visibleFrame;
    if (screen.size.width > 0) controller->_scale = MIN(controller->_scale, MIN((screen.size.width - 50) / 420, (screen.size.height - 70) / 500));
    controller->_scale = MAX(0.75, controller->_scale);
    controller->_contentWidth = MIN(420 * controller->_scale, MAX(300 * controller->_scale, anchor.window.contentView.frame.size.width - 24));
    NSPopover *popover = [NSPopover new];
    popover.behavior = NSPopoverBehaviorTransient;
    popover.animates = NO;
    popover.contentViewController = controller;
    popover.delegate = controller;
    controller.popover = popover;
    [controller view];
    [controller _updateDraft];
    popover.contentSize = controller.view.frame.size;
    [popover showRelativeToRect:anchor.bounds ofView:anchor preferredEdge:NSRectEdgeMinY];
    sVisibleCuePopover = popover;
    [track startPriorityAnalysis];
    return popover;
}

- (void) dealloc
{
    [_audition stopPreviewWithIdentifier:_auditionRequestIdentifier];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSTextField *) _label:(NSString *)text size:(CGFloat)size
{
    NSTextField *field = [NSTextField wrappingLabelWithString:text];
    field.selectable = NO;
    field.maximumNumberOfLines = 2;
    [InterfaceAppearance setFont:[NSFont systemFontOfSize:size] forControl:field];
    return field;
}

- (NSButton *) _button:(NSString *)title action:(SEL)action
{
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    [InterfaceAppearance setFont:[NSFont systemFontOfSize:13] forControl:button];
    return button;
}

- (void) loadView
{
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, _contentWidth, 400 * _scale)];
    [root setBoundsSize:NSMakeSize(_contentWidth / _scale, 400)];
    _documentView = [[NSView alloc] initWithFrame:root.bounds];
    [root addSubview:_documentView];
    self.view = root;
    NSTextField *heading = [self _label:NSLocalizedString(@"Start point", nil) size:17];
    _trackField = [self _label:self.track.title ?: @"" size:13];
    _trackField.preferredMaxLayoutWidth = _contentWidth / _scale - 36;
    _waveform = [[TrackCueWaveform alloc] initWithFrame:NSZeroRect];
    _waveform.track = self.track;
    _waveform.activeWaveformColor = NSColor.tertiaryLabelColor;
    _waveform.inactiveWaveformColor = NSColor.systemBlueColor;
    _waveform.target = self;
    _waveform.action = @selector(_waveformChanged:);
    _slider = [NSSlider sliderWithValue:0 minValue:0 maxValue:1 target:self action:@selector(_sliderChanged:)];
    _slider.continuous = YES;
    _slider.accessibilityLabel = NSLocalizedString(@"Cue start position", nil);
    NSTextField *timeLabel = [self _label:NSLocalizedString(@"Start from (minutes:seconds)", nil) size:12];
    _timeField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _timeField.delegate = self;
    _timeField.accessibilityLabel = NSLocalizedString(@"Start from, minutes and seconds", nil);
    [InterfaceAppearance setFont:[NSFont monospacedDigitSystemFontOfSize:17 weight:NSFontWeightRegular] forControl:_timeField];
    _durationField = [self _label:@"" size:12];
    NSStackView *timeRow = [NSStackView stackViewWithViews:@[_timeField, _durationField]];
    timeRow.spacing = 12;
    timeRow.alignment = NSLayoutAttributeCenterY;
    _audition = [AuditionPlayer sharedInstance];
    _previewButton = [self _button:NSLocalizedString(@"Preview in headphones", nil) action:@selector(_preview:)];
    _previewButton.toolTip = NSLocalizedString(@"Preview this draft start through Audition Output. Master playback and the queue stay unchanged.", nil);
    _previewButton.accessibilityLabel = NSLocalizedString(@"Preview draft start in headphones", nil);
    _pausePreviewButton = [self _button:NSLocalizedString(@"Pause", nil) action:@selector(_pausePreview:)];
    _pausePreviewButton.accessibilityLabel = NSLocalizedString(@"Pause or resume start point preview", nil);
    _stopPreviewButton = [self _button:NSLocalizedString(@"Stop", nil) action:@selector(_stopPreview:)];
    _stopPreviewButton.accessibilityLabel = NSLocalizedString(@"Stop start point preview", nil);
    NSStackView *previewActions = [NSStackView stackViewWithViews:@[_previewButton, _pausePreviewButton, _stopPreviewButton]];
    previewActions.spacing = 8;
    previewActions.alignment = NSLayoutAttributeCenterY;
    _previewStatusField = [self _label:@"" size:11];
    _previewStatusField.lineBreakMode = NSLineBreakByTruncatingTail;
    _previewStatusField.accessibilityLabel = NSLocalizedString(@"Start point preview status", nil);
    NSTextField *scope = [self _label:NSLocalizedString(@"Applies on next playback; clears after that play finishes", nil) size:11];
    _errorField = [self _label:@"" size:12];
    _errorField.textColor = NSColor.systemRedColor;
    _errorField.hidden = YES;
    NSButton *reset = [self _button:NSLocalizedString(@"From beginning", nil) action:@selector(_reset:)];
    NSButton *cancel = [self _button:NSLocalizedString(@"Cancel", nil) action:@selector(_cancel:)];
    NSButton *save = [self _button:NSLocalizedString(@"Save start", nil) action:@selector(_save:)];
    save.keyEquivalent = @"\r";
    cancel.keyEquivalent = @"\e";
    NSStackView *actions = [NSStackView stackViewWithViews:@[reset, cancel, save]];
    actions.spacing = 8;
    _stack = [NSStackView stackViewWithViews:@[heading, _trackField, _waveform, _slider, timeLabel, timeRow, previewActions, _previewStatusField, scope, _errorField, actions]];
    _stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _stack.alignment = NSLayoutAttributeLeading;
    _stack.spacing = 10;
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_documentView addSubview:_stack];
    [NSLayoutConstraint activateConstraints:@[
        [_stack.leadingAnchor constraintEqualToAnchor:_documentView.leadingAnchor constant:18],
        [_stack.trailingAnchor constraintEqualToAnchor:_documentView.trailingAnchor constant:-18],
        [_stack.topAnchor constraintEqualToAnchor:_documentView.topAnchor constant:18],
        [_waveform.widthAnchor constraintEqualToAnchor:_stack.widthAnchor],
        [_waveform.heightAnchor constraintEqualToConstant:80],
        [_slider.widthAnchor constraintEqualToAnchor:_stack.widthAnchor],
        [_timeField.widthAnchor constraintEqualToConstant:85],
        [_trackField.widthAnchor constraintEqualToAnchor:_stack.widthAnchor],
        [_previewStatusField.widthAnchor constraintEqualToAnchor:_stack.widthAnchor],
        [_errorField.widthAnchor constraintEqualToAnchor:_stack.widthAnchor]
    ]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_trackChanged:) name:TrackDidModifyDurationNotificationName object:self.track];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_auditionChanged:) name:AuditionPlayerDidChangeNotification object:_audition];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_auditionOutputChanged:) name:AuditionPreferencesDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_auditionOutputChanged:) name:HugAudioDevicesDidRefreshNotification object:nil];
    [self _refreshAuditionOutput];
    [self _updateDraft];
    [self _updateAudition];
}

- (void) _resize
{
    [self.view layoutSubtreeIfNeeded];
    NSSize logical = NSMakeSize(_contentWidth / _scale, ceil(_stack.fittingSize.height + 36));
    NSSize size = NSMakeSize(_contentWidth, logical.height * _scale);
    [self.view setFrameSize:size];
    [self.view setBoundsSize:logical];
    [_documentView setFrame:self.view.bounds];
    self.popover.contentSize = size;
}

- (void) viewDidAppear { [super viewDidAppear]; [self _resize]; }

- (void) _updateDraft
{
    _timeField.stringValue = GetStringForTime(_draft);
    double offset = MAX(0, _draft - self.track.startTime);
    double duration = MAX(0, self.track.playDuration);
    _durationField.stringValue = [NSString stringWithFormat:NSLocalizedString(@"Plays %@ of %@", nil), GetStringForTime(MAX(0, duration - offset)), GetStringForTime(duration)];
    _slider.doubleValue = duration > 0 ? offset / duration : 0;
    _slider.enabled = duration > 0;
    _waveform.percentage = _slider.doubleValue;
    NSTimeInterval previewTime = _draft > 0 ? _draft : self.track.startTime;
    _previewButton.title = [NSString stringWithFormat:NSLocalizedString(@"Preview from %@", nil), GetStringForTime(previewTime)];
    _errorField.hidden = YES;
    [self _resize];
}

- (void) _setDraftPercentage:(double)percentage
{
    NSTimeInterval end = self.track.startTime + self.track.playDuration;
    _draft = percentage <= 0 ? 0 : MAX(ceil(self.track.startTime), MIN(floor(end - 0.01), round(self.track.startTime + percentage * self.track.playDuration)));
    [self _updateDraft];
}
- (void) _sliderChanged:(id)sender { [self _setDraftPercentage:_slider.doubleValue]; }
- (void) _waveformChanged:(id)sender { [self _setDraftPercentage:_waveform.percentage]; }
- (void) _reset:(id)sender { _draft = 0; [self _updateDraft]; }
- (void) _cancel:(id)sender { [self.popover close]; }
- (void) _trackChanged:(NSNotification *)note { [self _updateDraft]; }

- (void) _refreshAuditionOutput
{
    Preferences *preferences = [Preferences sharedInstance];
    NSString *uid = preferences.auditionOutputDeviceUID;
    _auditionOutputName = uid.length ? NSLocalizedString(@"Audition Output unavailable", nil) : NSLocalizedString(@"Audition Output disabled", nil);
    for (NSDictionary *device in AuditionOutputDevices()) {
        if ([device[@"uid"] isEqual:uid]) { _auditionOutputName = device[@"name"]; break; }
    }
}

- (void) _updateAudition
{
    BOOL ownsPreview = _auditionRequestIdentifier && [_audition.requestIdentifier isEqual:_auditionRequestIdentifier];
    BOOL active = ownsPreview && (_audition.state == AuditionStatePlaying || _audition.state == AuditionStatePaused);
    _pausePreviewButton.enabled = active;
    _pausePreviewButton.title = _audition.state == AuditionStatePaused && ownsPreview ? NSLocalizedString(@"Resume", nil) : NSLocalizedString(@"Pause", nil);
    _stopPreviewButton.enabled = ownsPreview && _audition.state != AuditionStateStopped;
    NSString *message = ownsPreview ? _audition.message : NSLocalizedString(@"Ready", nil);
    _previewStatusField.stringValue = [NSString stringWithFormat:@"%@ · %@", message, _auditionOutputName ?: @""];
    _previewStatusField.toolTip = _previewStatusField.stringValue;
}

- (void) _preview:(id)sender
{
    if (![self _readTime] || (self.track.playDuration <= 0 && _draft > 0)) {
        _errorField.stringValue = NSLocalizedString(@"Choose a valid start point before previewing.", nil);
        _errorField.hidden = NO;
        [self _resize];
        return;
    }
    NSURL *url = self.track.internalURL;
    if (!url) {
        _errorField.stringValue = NSLocalizedString(@"This track is not ready for preview.", nil);
        _errorField.hidden = NO;
        [self _resize];
        return;
    }
    NSTimeInterval startTime = _draft > 0 ? _draft : self.track.startTime;
    NSTimeInterval endTime = self.track.startTime + self.track.playDuration;
    _auditionRequestIdentifier = [_audition previewURL:url title:self.track.title artist:self.track.artist
        startTime:startTime endTime:endTime];
    [self _updateAudition];
}

- (void) _pausePreview:(id)sender
{
    if (![_audition.requestIdentifier isEqual:_auditionRequestIdentifier]) return;
    if (_audition.state == AuditionStatePaused) [_audition resume];
    else [_audition pause];
}

- (void) _stopPreview:(id)sender
{
    [_audition stopPreviewWithIdentifier:_auditionRequestIdentifier];
}

- (void) _auditionChanged:(NSNotification *)note { [self _updateAudition]; }
- (void) _auditionOutputChanged:(NSNotification *)note { [self _refreshAuditionOutput]; [self _updateAudition]; }

- (void) popoverWillClose:(NSNotification *)notification
{
    [_audition stopPreviewWithIdentifier:_auditionRequestIdentifier];
    _auditionRequestIdentifier = nil;
}

- (BOOL) _readTime
{
    NSString *text = [_timeField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([text rangeOfString:@"^[0-9]{1,3}:[0-5][0-9]$" options:NSRegularExpressionSearch].location == NSNotFound) return NO;
    NSArray *parts = [text componentsSeparatedByString:@":"];
    NSTimeInterval value = [parts[0] integerValue] * 60 + [parts[1] integerValue];
    NSTimeInterval end = self.track.startTime + self.track.playDuration;
    if (value > 0 && (value < self.track.startTime || value >= end)) return NO;
    _draft = value;
    return YES;
}

- (void) controlTextDidChange:(NSNotification *)note
{
    if ([self _readTime]) {
        NSString *typed = _timeField.stringValue;
        [self _updateDraft];
        _timeField.stringValue = typed;
    }
}

- (void) _save:(id)sender
{
    if (![self _readTime] || (self.track.playDuration <= 0 && _draft > 0)) {
        _errorField.stringValue = [NSString stringWithFormat:NSLocalizedString(@"Enter minutes:seconds before %@. Use 0:00 to clear.", nil), GetStringForTime(self.track.startTime + self.track.playDuration)];
        _errorField.hidden = NO;
        [self _resize];
        return;
    }
    self.track.cueStartTime = _draft;
    [self.popover close];
}
@end
