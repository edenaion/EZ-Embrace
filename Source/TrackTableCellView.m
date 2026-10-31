// (c) 2014-2024 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "TrackTableCellView.h"

#import "Track.h"
#import "TrackGenre.h"
#import "TrackErrorButton.h"
#import "AppDelegate.h"
#import "NoDropImageView.h"
#import "Preferences.h"
#import "TrackLabelView.h"
#import "TrackTableView.h"
#import "TrackTableRowView.h"
#import "TrackStripeView.h"
#import "MaskView.h"
#import "InterfaceAppearance.h"
#import "TrackCueController.h"


@interface TrackTableCellView () <ApplicationEventListener>

@property (nonatomic, weak) IBOutlet NSLayoutConstraint *titleDurationConstraint;

@property (nonatomic, weak) IBOutlet TrackStripeView *stripeView;

@property (nonatomic, weak) IBOutlet NSTextField *titleField;
@property (nonatomic, weak) IBOutlet NSTextField *durationField;

@property (nonatomic, weak) IBOutlet NSTextField *lineTwoLeftField;
@property (nonatomic, weak) IBOutlet NSTextField *lineTwoRightField;

@property (nonatomic, weak) IBOutlet NSTextField *lineThreeLeftField;
@property (nonatomic, weak) IBOutlet NSTextField *lineThreeRightField;

@property (nonatomic, weak) IBOutlet NoDropImageView *speakerImageView;
@property (nonatomic, weak) IBOutlet TrackErrorButton *errorButton;

@property (nonatomic, weak) IBOutlet NSLayoutConstraint *speakerLeftConstraint;

@property (nonatomic, weak) IBOutlet NSLayoutConstraint *firstLineTopConstraint;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint *secondLineTopConstraint;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint *thirdLineTopConstraint;

@property (nonatomic, strong)          TrackLabelView *dotLabelView;
@property (nonatomic, weak)   IBOutlet TrackLabelView *edgeLabelView;
@property (nonatomic, strong)          TrackLabelView *statusShapeLabelView;

@end


@interface TrackTableView (Private)
- (void) _trackTableViewCell:(TrackTableCellView *)cellView mouseInside:(BOOL)mouseInside;
@end


@implementation TrackTableCellView {
    NSArray        *_observedKeyPaths;
    id              _observedObject;

    NSTextField    *_timeField;
    MaskView       *_timeMaskView;
    BOOL            _showsTime;
    
    NSArray        *_errorButtonConstraints;
    NSArray        *_endTimeConstraints;

    NoDropImageView    *_duplicateImageView;
    NSArray            *_duplicateConstraints;
    NSLayoutConstraint *_duplicateRightConstraint;
    
    NSArray            *_dotConstraints;
    NSLayoutConstraint *_dotRightConstraint;

    NSTrackingArea *_trackingArea;
    BOOL            _mouseInside;
    BOOL            _timeRequested;
    BOOL            _animatesTime;
    BOOL            _animatesSpeakerImage;
    TrackCueButton *_cueButton;
    NSPopover *_cuePopover;
}


- (id) initWithFrame:(NSRect)frameRect
{
    if ((self = [super initWithFrame:frameRect])) {
        [self _commonTrackTableCellViewInit];
    }
    
    return self;
}


- (id) initWithCoder:(NSCoder *)aDecoder
{
    if ((self = [super initWithCoder:aDecoder])) {
        [self _commonTrackTableCellViewInit];
    }
    
    return self;
}


- (void) application:(Application *)application flagsChanged:(NSEvent *)event
{
    [self _updateTimeVisibilityAnimated:NO];
}


- (void) dealloc
{
    [_cuePopover close];
    [self _removeObservers];

    [_errorButton setTarget:nil];
    [_errorButton setAction:NULL];
}


- (void) viewDidMoveToSuperview
{
    [super viewDidMoveToSuperview];
    if (!self.superview) [_cuePopover close];
    _mouseInside = NO;
    [self updateColors];
}


- (void) viewDidChangeEffectiveAppearance
{
    PerformWithAppearance([self effectiveAppearance], ^{
        [self _updateView];
    });
}


- (TrackTableView *) _tableView
{
    NSView *view = [self superview];
    
    while (view) {
        if ([view isKindOfClass:[TrackTableView class]]) {
            return (TrackTableView *)view;
        }

        view = [view superview];
    }
    
    return nil;
}


- (void) _commonTrackTableCellViewInit
{
    [(Application *)NSApp registerEventListener:self];

   
    NSTrackingAreaOptions options = NSTrackingInVisibleRect | NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways;
    _trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect options:options owner:self userInfo:nil];
    [self addTrackingArea:_trackingArea];
}


- (void) awakeFromNib
{
    NSView *container = _durationField.superview;
    _cueButton = [[TrackCueButton alloc] initWithFrame:NSZeroRect];
    _cueButton.translatesAutoresizingMaskIntoConstraints = NO;
    _cueButton.bordered = NO;
    _cueButton.title = @"";
    _cueButton.target = self;
    _cueButton.action = @selector(_cueButtonClicked:);
    [container addSubview:_cueButton];
    for (NSLayoutConstraint *constraint in container.constraints) {
        if (constraint.firstItem == container && constraint.firstAttribute == NSLayoutAttributeRight &&
            constraint.secondItem == _durationField && constraint.secondAttribute == NSLayoutAttributeRight) {
            constraint.constant += 28;
        }
    }
    [NSLayoutConstraint activateConstraints:@[
        [_cueButton.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-5],
        [_cueButton.centerYAnchor constraintEqualToAnchor:_durationField.centerYAnchor],
        [_cueButton.widthAnchor constraintEqualToConstant:22],
        [_cueButton.heightAnchor constraintEqualToConstant:18]
    ]];
    [_errorButton setAutoresizingMask:NSViewMinXMargin];
    [_errorButton setTarget:self];
    [_errorButton setAction:@selector(_errorButtonClicked:)];

    _timeField = [[NSTextField alloc] initWithFrame:NSZeroRect];

    [_timeField setBezeled:NO];
    [_timeField setSelectable:NO];
    [_timeField setEditable:NO];
    [_timeField setDrawsBackground:NO];
    [_timeField setAlignment:NSTextAlignmentRight];
    [_timeField setAlphaValue:0];
    [_timeField setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_timeField setContentCompressionResistancePriority:(NSLayoutPriorityDefaultHigh + 1) forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_timeField setTranslatesAutoresizingMaskIntoConstraints:NO];

    _timeMaskView = [[MaskView alloc] initWithFrame:NSZeroRect];
    [_timeMaskView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [_timeMaskView setGradientLength:32];
    [_timeMaskView setGradientLayoutAttribute:NSLayoutAttributeLeft];

#if 0
    [_titleField setBackgroundColor:[NSColor yellowColor]];
    [_titleField setDrawsBackground:YES];
    [_lineThreeLeftField setBackgroundColor:[NSColor yellowColor]];
    [_lineThreeLeftField setDrawsBackground:YES];
    [_lineTwoLeftField setBackgroundColor:[NSColor yellowColor]];
    [_lineTwoLeftField setDrawsBackground:YES];
    [_lineThreeRightField setBackgroundColor:[NSColor yellowColor]];
    [_lineThreeRightField setDrawsBackground:YES];
    [_lineTwoRightField setBackgroundColor:[NSColor yellowColor]];
    [_lineTwoRightField setDrawsBackground:YES];
#endif

    _errorButtonConstraints = @[
        [NSLayoutConstraint constraintWithItem:_titleField         attribute:NSLayoutAttributeRight relatedBy:NSLayoutRelationEqual toItem:_errorButton attribute:NSLayoutAttributeLeft multiplier:1.0 constant:-8.0],
        [NSLayoutConstraint constraintWithItem:_lineTwoLeftField   attribute:NSLayoutAttributeRight relatedBy:NSLayoutRelationEqual toItem:_errorButton attribute:NSLayoutAttributeLeft multiplier:1.0 constant:-8.0],
        [NSLayoutConstraint constraintWithItem:_lineThreeLeftField attribute:NSLayoutAttributeRight relatedBy:NSLayoutRelationEqual toItem:_errorButton attribute:NSLayoutAttributeLeft multiplier:1.0 constant:-8.0]
    ];
    
    [NSLayoutConstraint activateConstraints:_errorButtonConstraints];

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        [context setDuration:0];
        [self _updateView];
    } completionHandler:^{
        _animatesSpeakerImage = YES;
    }];
}


- (void) _adjustConstraintsForLineLayout
{
    if (_endTimeConstraints) {
        [NSLayoutConstraint deactivateConstraints:_endTimeConstraints];
        _endTimeConstraints = nil;
    }
    
    NSInteger numberOfLines = [[Preferences sharedInstance] numberOfLayoutLines];

    NSTextField *targetField = nil;

    if (numberOfLines == 1) {
        targetField = [self durationField];
    } else if (numberOfLines == 2) {
        targetField = [self lineTwoRightField];
    } else if (numberOfLines == 3) {
        targetField = [self lineThreeRightField];
    }

    NSTextField *oldTargetField = [[_endTimeConstraints lastObject] secondItem];

    if (targetField && (targetField != oldTargetField)) {
        CGFloat length = [_timeMaskView gradientLength] + 8;
        
        _endTimeConstraints = @[
            [NSLayoutConstraint constraintWithItem:_timeField attribute:NSLayoutAttributeRight    relatedBy:NSLayoutRelationEqual              toItem:targetField attribute:NSLayoutAttributeRight    multiplier:1.0 constant:0.0],
            [NSLayoutConstraint constraintWithItem:_timeField attribute:NSLayoutAttributeBaseline relatedBy:NSLayoutRelationEqual              toItem:targetField attribute:NSLayoutAttributeBaseline multiplier:1.0 constant:0.0],
            [NSLayoutConstraint constraintWithItem:_timeField attribute:NSLayoutAttributeWidth    relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:targetField attribute:NSLayoutAttributeWidth    multiplier:1.0 constant:0.0],

            [NSLayoutConstraint constraintWithItem:_timeMaskView attribute:NSLayoutAttributeTop      relatedBy:NSLayoutRelationEqual toItem:_timeField attribute:NSLayoutAttributeTop       multiplier:1.0 constant:0.0],
            [NSLayoutConstraint constraintWithItem:_timeMaskView attribute:NSLayoutAttributeBottom   relatedBy:NSLayoutRelationEqual toItem:_timeField attribute:NSLayoutAttributeBottom    multiplier:1.0 constant:0.0],
            [NSLayoutConstraint constraintWithItem:_timeMaskView attribute:NSLayoutAttributeRight    relatedBy:NSLayoutRelationEqual toItem:_timeField attribute:NSLayoutAttributeRight     multiplier:1.0 constant:0.0],
            [NSLayoutConstraint constraintWithItem:_timeMaskView attribute:NSLayoutAttributeLeft     relatedBy:NSLayoutRelationEqual toItem:_timeField attribute:NSLayoutAttributeLeft      multiplier:1.0 constant:-length]
        ];
        
        [[targetField superview] addSubview:_timeField    positioned:NSWindowAbove relativeTo:targetField];
        [[targetField superview] addSubview:_timeMaskView positioned:NSWindowAbove relativeTo:targetField];

        [NSLayoutConstraint activateConstraints:_endTimeConstraints];
    }
}


- (void) mouseEntered:(NSEvent *)theEvent
{
    [super mouseEntered:theEvent];
    _mouseInside = YES;

    [self _updateTimeVisibilityAnimated:NO];
    
    [[self _tableView] _trackTableViewCell:self mouseInside:YES];
}


- (void) mouseExited:(NSEvent *)theEvent
{
    [super mouseExited:theEvent];
    _mouseInside = NO;

    [self _updateTimeVisibilityAnimated:NO];

    [[self _tableView] _trackTableViewCell:self mouseInside:NO];
}


- (void) mouseDown:(NSEvent *)theEvent
{
    NSUInteger mask = (NSEventModifierFlagControl | NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption);
    
    if (([theEvent modifierFlags] & mask) == NSEventModifierFlagControl) {
        if ([self _tryToPresentContextMenuWithEvent:theEvent]) {
            return;
        }
    }

    [super mouseDown:theEvent];
}


- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (object == _observedObject) {
    
        if ([keyPath isEqualToString:@"trackStatus"]) {
            [self _updateStatusShape];
            [self updateColors];
            
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ac) {
                [ac setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionDefault]];
                [ac setDuration:0.25];
                [self _updateSpeakerIconAnimated:YES];
            } completionHandler:nil];

        } else if ([keyPath isEqualToString:@"estimatedEndTime"]) {
            [self _updateFieldStrings];

        } else if ([_observedKeyPaths containsObject:keyPath]) {
            [self _updateView];
        }
    }
}


- (void) setObjectValue:(id)objectValue
{
    if (objectValue != self.objectValue) { [_cuePopover close]; _cuePopover = nil; }
    [self _removeObservers];

    [super setObjectValue:objectValue];
    
    _observedKeyPaths = @[
        @"title",
        @"artist",
        @"playDuration",
        @"queuedPlayDuration",
        @"cueStartTime",
        @"error",
        @"estimatedEndTime",
        @"pausesAfterPlaying",
        @"ignoresAutoGap",
        @"artist",
        @"tonality",
        @"comments",
        @"grouping",
        @"genre",
        @"beatsPerMinute",
        @"trackStatus",
        @"trackLabel",
        @"duplicate"
    ];
    
    _observedObject = objectValue;

    for (NSString *keyPath in _observedKeyPaths) {
        [_observedObject addObserver:self forKeyPath:keyPath options:0 context:NULL];
    }

    [self _updateView];
}


#pragma mark - Private Methods

- (void) _removeObservers
{
    for (NSString *keyPath in _observedKeyPaths) {
        [_observedObject removeObserver:self forKeyPath:keyPath context:NULL];
    }

    _observedKeyPaths = nil;
    _observedObject   = nil;
}


- (BOOL) _tryToPresentContextMenuWithEvent:(NSEvent *)event
{
    NSView *superview = [self superview];
    NSMenu *menu = nil;

    while (superview) {
        if ([superview isKindOfClass:[NSTableView class]]) {
            menu = [superview menuForEvent:event];
            if (menu) break;
        }
        
        superview = [superview superview];
    }
    
    if (menu) {
        [NSMenu popUpContextMenu:menu withEvent:event forView:self];
        return YES;
    }
    
    return NO;
}


- (void) _errorButtonClicked:(id)sender
{
    [GetAppDelegate() displayErrorForTrack:[self track]];
}

- (void) _cueButtonClicked:(id)sender
{
    if (!self.track) return;
    if (_cuePopover.shown) { [_cuePopover close]; return; }
    _cuePopover = [TrackCueController showForTrack:self.track relativeToView:_cueButton];
}

- (void) _updateCueButton
{
    Track *track = self.track;
    NSTimeInterval cue = track.cueStartTime;
    _cueButton.hidden = !track;
    _cueButton.cueActive = cue > 0;
    NSString *state = cue > 0 ? [NSString stringWithFormat:NSLocalizedString(@"Starts at %@ once. Clears after playback.", nil), GetStringForTime(cue)] : NSLocalizedString(@"Off. Starts at 0:00.", nil);
    NSString *label = [NSString stringWithFormat:NSLocalizedString(@"Start marker for %@. %@", nil), track.title ?: @"", state];
    _cueButton.accessibilityLabel = label;
    _cueButton.toolTip = label;
}


- (void) _unrequestTime
{
    _timeRequested = NO;
    [self _updateTimeVisibilityAnimated:YES];
}


- (void) _updateTimeVisibilityAnimated:(BOOL)animated
{
    NSUInteger modifierFlags = [NSEvent modifierFlags];
    
    modifierFlags &= (
        NSEventModifierFlagOption  |
        NSEventModifierFlagCommand |
        NSEventModifierFlagControl |
        NSEventModifierFlagShift
    );
    
    BOOL isCommandKeyDown = (modifierFlags == NSEventModifierFlagOption);
    
    BOOL showsTime = ((isCommandKeyDown && _mouseInside) || _timeRequested);

    if (_showsTime != showsTime) {
        _showsTime = showsTime;
        _animatesTime = animated;
        [self _updateView];
    }
}


- (CGFloat) _statusShapeLength
{
    NSInteger numberOfLayoutLines = [[Preferences sharedInstance] numberOfLayoutLines];
    
    if (numberOfLayoutLines == 1) {
        return 20;
    } else {
        return 25;
    }
}


#pragma mark - Update

- (void) _updateView
{
    Track *track = [self track];

    [[NSAnimationContext currentContext] setDuration:0];
    
    [self _updateLabelEdgeAndStripe];
    [self updateColors];
    [self _updateCueButton];

    if ([self track]) {
        [self _updateStatusShape];
        [self _updateRightIcons];
        [self _updateFieldStrings];
        [self _updateFieldHidden];
        [self _updateFieldAlphas];
    }

    [self _updateSpeakerIconAnimated:NO];
    
    [self _adjustConstraintsForLineLayout];
    
    [self _updateFieldFonts];

    // Update constraints
    if ([track error]) {
        [NSLayoutConstraint activateConstraints:_errorButtonConstraints];
    } else {
        [NSLayoutConstraint deactivateConstraints:_errorButtonConstraints];
    }
}


- (void) _updateSpeakerIconAnimated:(BOOL)animated
{
    TrackStatus trackStatus = [[self track] trackStatus];

    BOOL        isPlaying   = (trackStatus == TrackStatusPlaying);
    
    if (![[Preferences sharedInstance] showsPlayingStatus]) {
        isPlaying = NO;
    }
    [_speakerImageView setHidden:!isPlaying];
    [_speakerImageView setAccessibilityElement:isPlaying];
    
    CGFloat constant = isPlaying ? 8.0 : -13.0;
    CGFloat alpha    = isPlaying ? 1.0 :  0.0;

    if ([[Preferences sharedInstance] showsStatusShape]) {
        constant += 8 + [self _statusShapeLength];
    }

    if (animated) {
        [[_speakerLeftConstraint animator] setConstant:constant];
        [[_speakerImageView animator] setAlphaValue:alpha];
    } else {
        [_speakerLeftConstraint setConstant:constant];
        [_speakerImageView setAlphaValue:alpha];
    }
}

- (void) _updateStatusShape
{
    BOOL showsStatusShape   = [[Preferences sharedInstance] showsStatusShape];

    if (showsStatusShape && !_statusShapeLabelView) {
        _statusShapeLabelView = [[TrackLabelView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
        [_statusShapeLabelView setStyle:TrackLabelViewStatusShape];
        [_statusShapeLabelView setTranslatesAutoresizingMaskIntoConstraints:NO];

        [[_durationField superview] addSubview:_statusShapeLabelView positioned:NSWindowAbove relativeTo:nil];

    } else if (!showsStatusShape && _statusShapeLabelView) {
        [_statusShapeLabelView removeFromSuperview];
        _statusShapeLabelView = nil;
    }
    

    CGRect bounds = [self bounds];

    CGFloat length = [self _statusShapeLength];
    
    
    CGRect frame = CGRectMake(
        8,
        round((bounds.size.height - length) / 2.0),
        length,
        length
    );

    [_statusShapeLabelView setFrame:frame];
    
    [_statusShapeLabelView setTrackStatus:[[self track] trackStatus]];
    [_statusShapeLabelView setLabel:[[self track] trackLabel]];
}

- (void) _updateRightIcons
{
    TrackLabel trackLabel = [[self track] trackLabel];

    BOOL showsDuplicateIcon = [[Preferences sharedInstance] showsDuplicateStatus] && [[self track] isDuplicate];
    BOOL showsDot           = [[Preferences sharedInstance] showsLabelDots] && (trackLabel != TrackLabelNone);

    if (showsDuplicateIcon && !_duplicateImageView) {
        NSImage *image = [NSImage imageNamed:@"DuplicateTemplate"];
        [image setTemplate:YES];
        
        _duplicateImageView = [[NoDropImageView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
        [_duplicateImageView setTranslatesAutoresizingMaskIntoConstraints:NO];
        [_duplicateImageView setImage:image];
        [[_durationField superview] addSubview:_duplicateImageView positioned:NSWindowBelow relativeTo:nil];

        _duplicateRightConstraint = [NSLayoutConstraint constraintWithItem:_duplicateImageView attribute:NSLayoutAttributeRight relatedBy:NSLayoutRelationEqual toItem:_durationField attribute:NSLayoutAttributeLeft multiplier:1.0 constant:-4.0];
        
        _duplicateConstraints = @[
            _duplicateRightConstraint,
            [NSLayoutConstraint constraintWithItem:_duplicateImageView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:_durationField attribute:NSLayoutAttributeTop     multiplier:1.0 constant:4.0]
        ];

        [NSLayoutConstraint activateConstraints:_duplicateConstraints];

    } else if (!showsDuplicateIcon && _duplicateImageView) {
        [_duplicateImageView removeFromSuperview];
        _duplicateImageView = nil;
        
        [NSLayoutConstraint deactivateConstraints:_duplicateConstraints];
        _duplicateConstraints = nil;
        _duplicateRightConstraint = nil;
    }


    if (showsDot && !_dotLabelView) {
        _dotLabelView = [[TrackLabelView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
        [_dotLabelView setStyle:TrackLabelViewDot];
        [_dotLabelView setTranslatesAutoresizingMaskIntoConstraints:NO];

        [[_durationField superview] addSubview:_dotLabelView positioned:NSWindowBelow relativeTo:nil];

        _dotRightConstraint = [NSLayoutConstraint constraintWithItem:_dotLabelView attribute:NSLayoutAttributeRight relatedBy:NSLayoutRelationEqual toItem:_durationField attribute:NSLayoutAttributeLeft multiplier:1.0 constant:-4.0];

        _dotConstraints = @[
            _dotRightConstraint,
            [NSLayoutConstraint constraintWithItem:_dotLabelView attribute:NSLayoutAttributeTop      relatedBy:NSLayoutRelationEqual toItem:_durationField attribute:NSLayoutAttributeTop     multiplier:1.0 constant:4.0],
            [NSLayoutConstraint constraintWithItem:_dotLabelView attribute:NSLayoutAttributeWidth    relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute     multiplier:1.0 constant:10.0],
            [NSLayoutConstraint constraintWithItem:_dotLabelView attribute:NSLayoutAttributeHeight   relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute     multiplier:1.0 constant:10.0]
        ];

        [NSLayoutConstraint activateConstraints:_dotConstraints];

        
    } else if (!showsDot && _dotLabelView) {
        [_dotLabelView removeFromSuperview];
        _dotLabelView = nil;
        
        [NSLayoutConstraint deactivateConstraints:_dotConstraints];
        _dotConstraints = nil;
        _dotRightConstraint = nil;
    }


    NSInteger constant = 8;
    
    if (showsDuplicateIcon && showsDot) {
        constant = 28 + 4;
        [_duplicateRightConstraint setConstant:-18];
        [_dotRightConstraint setConstant:-4];

    } else if (showsDuplicateIcon) {
        constant = 18;
        [_duplicateRightConstraint setConstant:-4];

    } else if (showsDot) {
        constant = 8;
        [_dotRightConstraint setConstant:-4];
    }

    if (showsDot) {
        [_dotLabelView setLabel:trackLabel];
    }

    [_titleDurationConstraint setConstant:constant];
}

- (NSTableRowView *) _rowView
{
    NSView *superview = [self superview];
    
    if ([superview isKindOfClass:[NSTableRowView class]]) {
        return (NSTableRowView *)superview;
    } else {
        return nil;
    }
}



- (void) updateColors
{
    NSTableRowView *rowView = [self _rowView];

    BOOL rowIsSelected   = [rowView isSelected];
    BOOL rowIsEmphasized = [rowView isEmphasized];

    NSColor *primaryColor   = nil;
    NSColor *secondaryColor = nil;

    TrackStatus trackStatus = [[self track] trackStatus];

    if ([rowView isKindOfClass:[TrackTableRowView class]]) {
        TrackTableRowView *trackRow = (TrackTableRowView *)rowView;
        [trackRow setPlaying:trackStatus == TrackStatusPlaying && [[Preferences sharedInstance] showsPlayingStatus]];
        trackRow.highlightsUpcomingOtherGenre = trackStatus == TrackStatusQueued &&
            TrackGenreUsesUpcomingHighlight(self.track.genre);
    }
    BOOL drawsOtherGenreHighlight = [rowView isKindOfClass:TrackTableRowView.class] &&
        [(TrackTableRowView *)rowView drawsUpcomingOtherGenreHighlight];
    NSString *status = trackStatus == TrackStatusPlayed ? NSLocalizedString(@"Played", nil) :
        trackStatus == TrackStatusPlaying ? NSLocalizedString(@"Now playing", nil) :
        trackStatus == TrackStatusPreparing ? NSLocalizedString(@"Preparing playback", nil) : NSLocalizedString(@"Up Next", nil);
    [self setToolTip:status];
    [_speakerImageView setAccessibilityLabel:NSLocalizedString(@"Now playing", nil)];
    [_speakerImageView setAccessibilityRole:NSAccessibilityImageRole];

    if (trackStatus == TrackStatusPlayed) {
        primaryColor   = [NSColor colorNamed:@"SetlistPrimaryPlayed"] ?: [NSColor colorWithWhite:0 alpha:0.50];
        secondaryColor = [NSColor colorNamed:@"SetlistSecondaryPlayed"] ?: [NSColor colorWithWhite:0 alpha:0.40];
    
    } else {
        primaryColor   = [NSColor colorNamed:@"SetlistPrimary"];
        secondaryColor = [NSColor colorNamed:@"SetlistSecondary"];
    }
    
    if (rowIsSelected && rowIsEmphasized) {
        primaryColor   = [NSColor colorNamed:@"SetlistPrimaryEmphasized"];
        secondaryColor = [NSColor colorNamed:@"SetlistSecondaryEmphasized"];

    } else if ((trackStatus == TrackStatusPreparing) || (trackStatus == TrackStatusPlaying)) {
        primaryColor   = TrackTableViewGetPlayingTextColor();
        secondaryColor = primaryColor;

    } else if (drawsOtherGenreHighlight) {
        NSColor *rgb = [[[Preferences sharedInstance] upcomingOtherGenreColor]
            colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        CGFloat luminance = rgb ? 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent +
            0.0722 * rgb.blueComponent : 1;
        primaryColor = luminance > 0.52 ? NSColor.blackColor : NSColor.whiteColor;
        secondaryColor = primaryColor;
    }
   
    BOOL appliesContrast = !drawsOtherGenreHighlight &&
        (trackStatus != TrackStatusPlayed || (rowIsSelected && rowIsEmphasized));
    [InterfaceAppearance setTextColor:primaryColor forField:[self titleField] appliesContrast:appliesContrast];
    [InterfaceAppearance setTextColor:primaryColor forField:[self durationField] appliesContrast:appliesContrast];
    [InterfaceAppearance setTextColor:secondaryColor forField:[self lineTwoLeftField] appliesContrast:appliesContrast];
    [InterfaceAppearance setTextColor:secondaryColor forField:[self lineTwoRightField] appliesContrast:appliesContrast];
    [InterfaceAppearance setTextColor:secondaryColor forField:[self lineThreeLeftField] appliesContrast:appliesContrast];
    [InterfaceAppearance setTextColor:secondaryColor forField:[self lineThreeRightField] appliesContrast:appliesContrast];
    [InterfaceAppearance setTextColor:secondaryColor forField:_timeField appliesContrast:appliesContrast];

    [_duplicateImageView setTintColor:primaryColor];
    [_speakerImageView   setTintColor:primaryColor];
    
    if (rowIsSelected && rowIsEmphasized) {
        [_errorButton setNormalColor:primaryColor];
        [_errorButton setPressedColor:primaryColor];

        [_dotLabelView setNeedsWhiteBorder:YES];
        [_statusShapeLabelView setNeedsWhiteBorder:YES];

    } else {
        [_errorButton setNormalColor: [NSColor colorNamed:@"ButtonAlert"]];
        [_errorButton setPressedColor:[NSColor colorNamed:@"ButtonAlertPressed"]];

        [_dotLabelView setNeedsWhiteBorder:NO];
        [_statusShapeLabelView setNeedsWhiteBorder:NO];
    }
  
    
    NSVisualEffectMaterial material = 0;
    NSColor *color = nil;

    if (rowIsSelected) {
        color = TrackTableViewGetRowHighlightColor(rowIsEmphasized);
    } else if (drawsOtherGenreHighlight) {
        color = [[Preferences sharedInstance] upcomingOtherGenreColor];
    } else {
        if (@available(macOS 10.14, *)) {
            material = NSVisualEffectMaterialContentBackground;
        } else {
            color = [NSColor controlBackgroundColor];
        }
    }

    [_timeMaskView setColor:color];
    [_timeMaskView setMaterial:material];
    [_timeMaskView setEmphasized:rowIsEmphasized];
}


- (void) _updateLabelEdgeAndStripe
{
    Track *track = [self track];
    if (!track) return;

    TrackStripeView *stripeView = [self stripeView];

    NSColor *stripeSolidColor = nil;
    NSColor *stripeDashColor  = nil;

    if ([track trackStatus] != TrackStatusPlayed) {
        if ([track stopsAfterPlaying]) {
            stripeSolidColor = [NSColor colorNamed:@"SetlistStopAfterPlayingStripe2"];
            stripeDashColor  = [NSColor colorNamed:@"SetlistStopAfterPlayingStripe1"];

        } else if ([track ignoresAutoGap]) {
            stripeSolidColor = [NSColor colorNamed:@"SetlistIgnoreAutoGapStripe"];
        }
    }

    if (stripeSolidColor || stripeDashColor) {
        [stripeView setSolidColor:stripeSolidColor];
        [stripeView setDashColor:stripeDashColor];
        [stripeView setHidden:NO];
    } else {
        [stripeView setHidden:YES];
    }

    TrackLabel trackLabel = [track trackLabel];
    [[self edgeLabelView] setLabel:trackLabel];
    [[self edgeLabelView] setHidden:![[Preferences sharedInstance] showsLabelStripes]];
}


- (void) _updateFieldStrings
{
    Preferences *preferences = [Preferences sharedInstance];

    Track *track = [self track];
    if (!track) return;

    NSInteger numberOfLines = [preferences numberOfLayoutLines];

    NSMutableArray *a_2L = [NSMutableArray array];
    NSMutableArray *a_2R = [NSMutableArray array];
    NSMutableArray *a_3L = [NSMutableArray array];
    NSMutableArray *a_3R = [NSMutableArray array];

    NSMutableArray *(^sparsest)(NSArray<NSMutableArray *> *) = ^(NSArray<NSMutableArray *> *arrays) {
        NSMutableArray *result = nil;
        NSInteger minCount = NSIntegerMax;
        
        for (NSMutableArray *array in arrays) {
            NSInteger arrayCount = [array count];

            if (arrayCount < minCount) {
                result = array;
                minCount = arrayCount;
            }
        }

        return result;
    };

    NSString *(^collectAttributes)(NSArray *) = ^(NSArray *attributes) {
        NSMutableArray *strings = [NSMutableArray array];

        for (NSNumber *attributeNumber in attributes) {
            TrackViewAttribute attribute = [attributeNumber integerValue];
            NSString *string = nil;

            if (attribute == TrackViewAttributeAlbumArtist) {
                string = [track albumArtist];

            } else if (attribute == TrackViewAttributeArtist) {
                string = [track artist];

            } else if (attribute == TrackViewAttributeBeatsPerMinute) {
                NSInteger bpm = [track beatsPerMinute];
                if (bpm) string = [NSNumberFormatter localizedStringFromNumber:@(bpm) numberStyle:NSNumberFormatterDecimalStyle];

            } else if (attribute == TrackViewAttributeComments) {
                string = [track comments];

            } else if (attribute == TrackViewAttributeEnergyLevel) {
                NSInteger energyLevel = [track energyLevel];
                if (energyLevel) string = [NSNumberFormatter localizedStringFromNumber:@(energyLevel) numberStyle:NSNumberFormatterDecimalStyle];
        
            } else if (attribute == TrackViewAttributeGenre) {
                string = [track genre];

            } else if (attribute == TrackViewAttributeGrouping) {
                string = [track grouping];

            } else if (attribute == TrackViewAttributeKeySignature) {
                KeySignatureDisplayMode displayMode = [preferences keySignatureDisplayMode];
        
                if (displayMode == KeySignatureDisplayModeRaw) {
                    string = [track initialKey];

                } else if (displayMode == KeySignatureDisplayModeTraditional) {
                    string = GetTraditionalStringForTonality([track tonality]);

                } else if (displayMode == KeySignatureDisplayModeOpenKeyNotation) {
                    string = GetOpenKeyNotationStringForTonality([track tonality]);
                }

            } else if (attribute == TrackViewAttributeYear) {
                NSInteger year = [track year];
                if (year) string = [NSString stringWithFormat:@"%ld", (long)year];
            }
            
            if (string) [strings addObject:string];
        }

        NSString *joiner = NSLocalizedString(@" \\U2013 ", nil);
        return [strings componentsJoinedByString:joiner];
    };

    if ([preferences showsArtist]) {
        [a_2L addObject:@(TrackViewAttributeArtist)];
    }

    if ([preferences showsAlbumArtist]) {
        [a_2L addObject:@(TrackViewAttributeAlbumArtist)];
    }

    if ([preferences showsYear]) {
        [a_2L addObject:@(TrackViewAttributeYear)];
    }

    if ([preferences showsBPM]) {
        [a_2R addObject:@(TrackViewAttributeBeatsPerMinute)];
    }
    
    if ([preferences showsEnergyLevel]) {
        [a_2R addObject:@(TrackViewAttributeEnergyLevel)];
    }

    if ([preferences showsKeySignature]) {
        [a_2R addObject:@(TrackViewAttributeKeySignature)];
    }

    if ([preferences showsComments]) {
        [(numberOfLines == 3 ? a_3L : a_2R) addObject:@(TrackViewAttributeComments)];
    }

    if ([preferences showsGrouping]) {
        NSMutableArray *array;

        if (numberOfLines == 2) {
            array = sparsest(@[ a_2R, a_2L ]);
        } else {
            array = sparsest(@[ a_3R, a_3L, a_2R, a_2L ]);
        }

        [array addObject:@(TrackViewAttributeGrouping)];
    }

    if ([preferences showsGenre]) {
        NSMutableArray *array;

        if (numberOfLines == 2) {
            array = sparsest(@[ a_2R, a_2L ]);
        } else {
            array = sparsest(@[ a_3L, a_3R, a_2R, a_2L ]);
        }

        [array addObject:@(TrackViewAttributeGenre)];
    }

  
    [[self lineTwoLeftField]    setStringValue:collectAttributes(a_2L)];
    [[self lineTwoRightField]   setStringValue:collectAttributes(a_2R)];
    [[self lineThreeLeftField]  setStringValue:collectAttributes(a_3L)];
    [[self lineThreeRightField] setStringValue:collectAttributes(a_3R)];

    NSString *timeString = @"";
    NSString *timeStringFormat;
    NSDate   *date;
    
    if ([track trackStatus] == TrackStatusPlayed) {
        date = [track playedTimeDate];
        timeStringFormat = NSLocalizedString(@"Played at %@", nil);
    } else {
        date = [track estimatedEndTimeDate];
        timeStringFormat = NSLocalizedString(@"Ends at %@", nil);
    }

    if (date) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateStyle:NSDateFormatterNoStyle];
        [formatter setTimeStyle:NSDateFormatterMediumStyle];

        timeString = [NSString stringWithFormat:timeStringFormat, [formatter stringFromDate:date]];
    }
       
    [_timeField setStringValue:timeString];
    
    NSString *titleString = [track title];
    if (!titleString) titleString = @"";
    [[self titleField] setStringValue:titleString];
    
    NSString *durationString = GetStringForTime(round([track queuedPlayDuration]));
    if (!durationString) durationString = @"";
    [[self durationField] setStringValue:durationString];
}


- (void) _updateFieldHidden
{
    NSInteger numberOfLines = [[Preferences sharedInstance] numberOfLayoutLines];

    NSTextField *line1Right  = [self durationField];
    NSTextField *line2Left   = [self lineTwoLeftField];
    NSTextField *line2Right  = [self lineTwoRightField];
    NSTextField *line3Left   = [self lineThreeLeftField];
    NSTextField *line3Right  = [self lineThreeRightField];
    NSView      *errorButton = [self errorButton];

    BOOL showError = [[self track] error] != nil;
    
    [line1Right  setHidden:showError];
    [line2Left   setHidden:(numberOfLines < 2)];
    [line2Right  setHidden:showError || (numberOfLines < 2)];
    [line3Left   setHidden:(numberOfLines < 3)];
    [line3Right  setHidden:showError || (numberOfLines < 3)];
    [errorButton setHidden:!showError];
}


- (void) _updateFieldAlphas
{
    BOOL shortensPlayedTracks = [[Preferences sharedInstance] shortensPlayedTracks];
    BOOL isPlayedTrack        = [[self track] trackStatus] == TrackStatusPlayed;
    
    if (shortensPlayedTracks && isPlayedTrack) {
        [[[self lineTwoLeftField]    animator] setAlphaValue:_expandedPlayedTrack ? 1.0 : 0.0];
        [[[self lineThreeLeftField]  animator] setAlphaValue:_expandedPlayedTrack ? 1.0 : 0.0];
        [[[self lineTwoRightField]   animator] setAlphaValue:_expandedPlayedTrack ? 1.0 : 0.0];
        [[[self lineThreeRightField] animator] setAlphaValue:_expandedPlayedTrack ? 1.0 : 0.0];
    } else {
        [[self lineTwoLeftField]    setAlphaValue:1.0];
        [[self lineThreeLeftField]  setAlphaValue:1.0];
        [[self lineTwoRightField]   setAlphaValue:1.0];
        [[self lineThreeRightField] setAlphaValue:1.0];
    }

    CGFloat endTimeAlpha = _showsTime ? 1.0 : 0.0;
    
    if (_animatesTime) {
        [[_timeField    animator] setAlphaValue:endTimeAlpha];
        [[_timeMaskView animator] setAlphaValue:endTimeAlpha];

    } else {
        [_timeField    setAlphaValue:endTimeAlpha];
        [_timeMaskView setAlphaValue:endTimeAlpha];
    }

    [_timeField setContentCompressionResistancePriority:(_showsTime ? (NSLayoutPriorityDefaultHigh + 1) : 1) forOrientation:NSLayoutConstraintOrientationHorizontal];
}


- (void) _updateFieldFonts
{
    CGFloat primaryFontSize   = 13.0;
    CGFloat secondaryFontSize = 11.0;

    NSFont *titleFont     = [NSFont systemFontOfSize:primaryFontSize                  weight:NSFontWeightRegular];
    NSFont *secondaryFont = [NSFont systemFontOfSize:secondaryFontSize                weight:NSFontWeightRegular];
    NSFont *durationFont  = [NSFont monospacedDigitSystemFontOfSize:primaryFontSize   weight:NSFontWeightRegular];
    NSFont *timeFont      = [NSFont monospacedDigitSystemFontOfSize:secondaryFontSize weight:NSFontWeightRegular];

    [InterfaceAppearance setFont:titleFont forControl:[self titleField]];
    [InterfaceAppearance setFont:durationFont forControl:[self durationField]];

    [InterfaceAppearance setFont:secondaryFont forControl:[self lineTwoLeftField]];
    [InterfaceAppearance setFont:secondaryFont forControl:[self lineTwoRightField]];
    [InterfaceAppearance setFont:secondaryFont forControl:[self lineThreeLeftField]];
    [InterfaceAppearance setFont:secondaryFont forControl:[self lineThreeRightField]];
    
    [[self firstLineTopConstraint]  setConstant:2];
    [[self secondLineTopConstraint] setConstant:2];
    [[self thirdLineTopConstraint]  setConstant:2];
        
    [InterfaceAppearance setFont:timeFont forControl:_timeField];
}


#pragma mark - Public Methods

- (void) revealTime
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_unrequestTime) object:nil];
    [self performSelector:@selector(_unrequestTime) withObject:nil afterDelay:2];

    _timeRequested = YES;
    [self _updateTimeVisibilityAnimated:YES];
}


#pragma mark - Accessors

- (void) setBackgroundStyle:(NSBackgroundStyle)backgroundStyle
{
    [super setBackgroundStyle:backgroundStyle];
    [self updateColors];
}


- (void) setExpandedPlayedTrack:(BOOL)expandedPlayedTrack
{
    if (_expandedPlayedTrack != expandedPlayedTrack) {
        _expandedPlayedTrack = expandedPlayedTrack;
        [self _updateView];
    }
}


- (Track *) track
{
    return (Track *)[self objectValue];
}


@end
