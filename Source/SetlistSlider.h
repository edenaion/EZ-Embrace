// (c) 2014-2024 Ricci Adams
// MIT License (or) 1-clause BSD License

#import <Foundation/Foundation.h>

@protocol SetlistSliderDragDelegate;


@interface SetlistSlider : NSSlider <EmbraceWindowListener>

@property (nonatomic, weak) id<SetlistSliderDragDelegate> dragDelegate;
@property (readonly) NSRect knobRect;
@property (nonatomic, strong) NSColor *levelColor;

@end


@interface SetlistSliderCell : NSSliderCell

@end


@protocol SetlistSliderDragDelegate <NSObject>
- (void) sliderDidStartDrag:(SetlistSlider *)slider;
- (void) sliderDidEndDrag:(SetlistSlider *)slider;
@end
