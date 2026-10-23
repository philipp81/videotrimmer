#import "TrimView.h"
#include <algorithm>
#include <cmath>

static const CGFloat kHandleW = 14.0;   // Breite der gelben Griffe
static const CGFloat kBarH    = 3.0;    // Dicke der gelben Ober-/Unterkante
static const CGFloat kVPad    = 2.0;    // Abstand Filmstreifen ↔ View-Rand
static const CGFloat kRadius  = 6.0;
static const double  kMinSelection = 0.05; // kleinste zulässige Auswahl in Sekunden

typedef NS_ENUM(NSInteger, VTDragMode) { VTDragNone, VTDragStart, VTDragEnd, VTDragPlayhead };

@implementation TrimView {
    NSMutableArray<id> *_thumbs;   // NSImage oder NSNull je Platz
    NSUInteger _thumbCount;
    VTDragMode _drag;
}

#pragma mark - Geometrie

- (NSRect)trackRect
{
    NSRect b = self.bounds;
    return NSMakeRect(NSMinX(b) + kHandleW, NSMinY(b) + kVPad,
                      std::max<CGFloat>(0, NSWidth(b) - 2 * kHandleW),
                      std::max<CGFloat>(0, NSHeight(b) - 2 * kVPad));
}

- (CGFloat)xForTime:(double)t
{
    NSRect r = [self trackRect];
    if (_duration <= 0) return NSMinX(r);
    double f = std::clamp(t / _duration, 0.0, 1.0);
    return NSMinX(r) + (CGFloat)f * NSWidth(r);
}

- (double)timeForX:(CGFloat)x
{
    NSRect r = [self trackRect];
    if (_duration <= 0 || NSWidth(r) <= 0) return 0;
    double f = (x - NSMinX(r)) / NSWidth(r);
    return std::clamp(f, 0.0, 1.0) * _duration;
}

- (CGFloat)stripHeight
{
    return NSHeight([self trackRect]);
}

- (NSUInteger)thumbnailCountForAspect:(CGFloat)aspect
{
    NSRect r = [self trackRect];
    if (NSWidth(r) <= 0 || NSHeight(r) <= 0 || aspect <= 0) return 0;
    double n = std::ceil(NSWidth(r) / (NSHeight(r) * aspect));
    return (NSUInteger)std::clamp(n, 1.0, 200.0);
}

#pragma mark - Zustand

- (void)clear
{
    _duration = _startTime = _endTime = _playhead = 0;
    _thumbs = nil;
    _thumbCount = 0;
    _drag = VTDragNone;
    [self.window invalidateCursorRectsForView:self];
    self.needsDisplay = YES;
}

- (void)prepareThumbnailSlots:(NSUInteger)count
{
    _thumbCount = count;
    _thumbs = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; ++i) [_thumbs addObject:NSNull.null];
    self.needsDisplay = YES;
}

- (void)setThumbnail:(NSImage *)image atIndex:(NSUInteger)index
{
    if (!image || index >= _thumbCount) return;
    _thumbs[index] = image;
    self.needsDisplay = YES;
}

- (void)setDuration:(double)duration   { _duration = std::max(0.0, duration); self.needsDisplay = YES; }
- (void)setPlayhead:(double)playhead   { _playhead = playhead; self.needsDisplay = YES; }
- (void)setStartTime:(double)startTime
{
    _startTime = startTime;
    [self.window invalidateCursorRectsForView:self];
    self.needsDisplay = YES;
}
- (void)setEndTime:(double)endTime
{
    _endTime = endTime;
    [self.window invalidateCursorRectsForView:self];
    self.needsDisplay = YES;
}
- (BOOL)isDragging { return _drag != VTDragNone; }

- (void)viewDidEndLiveResize
{
    [super viewDidEndLiveResize];
    [self.delegate trimViewDidResize:self];
}

#pragma mark - Zeichnen

static void DrawImageAspectFill(NSImage *img, NSRect slot)
{
    NSSize sz = img.size;
    if (sz.width <= 0 || sz.height <= 0) return;
    CGFloat imgAspect = sz.width / sz.height;
    CGFloat slotAspect = NSWidth(slot) / NSHeight(slot);
    NSRect src;
    if (imgAspect > slotAspect) {               // Bild breiter → links/rechts beschneiden
        CGFloat w = sz.height * slotAspect;
        src = NSMakeRect((sz.width - w) / 2, 0, w, sz.height);
    } else {                                    // Bild höher → oben/unten beschneiden
        CGFloat h = sz.width / slotAspect;
        src = NSMakeRect(0, (sz.height - h) / 2, sz.width, h);
    }
    [img drawInRect:slot fromRect:src operation:NSCompositingOperationSourceOver fraction:1.0
     respectFlipped:YES hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSRect bounds = self.bounds;
    NSRect track = [self trackRect];
    NSBezierPath *trackPath = [NSBezierPath bezierPathWithRoundedRect:track xRadius:kRadius yRadius:kRadius];

    [[NSColor colorWithWhite:0.13 alpha:1.0] setFill];
    [trackPath fill];

    if (_duration <= 0) {
        NSDictionary *attrs = @{ NSFontAttributeName: [NSFont systemFontOfSize:12],
                                 NSForegroundColorAttributeName: [NSColor colorWithWhite:0.55 alpha:1] };
        NSString *msg = @"Kein Video geladen";
        NSSize s = [msg sizeWithAttributes:attrs];
        [msg drawAtPoint:NSMakePoint(NSMidX(track) - s.width / 2, NSMidY(track) - s.height / 2) withAttributes:attrs];
        return;
    }

    // Filmstreifen
    [NSGraphicsContext saveGraphicsState];
    [trackPath addClip];
    if (_thumbCount > 0) {
        CGFloat slotW = NSWidth(track) / _thumbCount;
        for (NSUInteger i = 0; i < _thumbCount; ++i) {
            NSRect slot = NSMakeRect(NSMinX(track) + i * slotW, NSMinY(track), slotW + 0.5, NSHeight(track));
            id thumb = _thumbs[i];
            if ([thumb isKindOfClass:NSImage.class]) {
                DrawImageAspectFill((NSImage *)thumb, slot);
            } else {
                [[NSColor colorWithWhite:(i % 2 ? 0.20 : 0.17) alpha:1] setFill];
                NSRectFill(slot);
            }
        }
    }

    // Bereiche außerhalb der Auswahl abdunkeln
    CGFloat xs = [self xForTime:_startTime];
    CGFloat xe = [self xForTime:_endTime];
    [[NSColor colorWithWhite:0 alpha:0.6] setFill];
    NSRectFillUsingOperation(NSMakeRect(NSMinX(track), NSMinY(track), xs - NSMinX(track), NSHeight(track)),
                             NSCompositingOperationSourceOver);
    NSRectFillUsingOperation(NSMakeRect(xe, NSMinY(track), NSMaxX(track) - xe, NSHeight(track)),
                             NSCompositingOperationSourceOver);
    [NSGraphicsContext restoreGraphicsState];

    // Gelber Rahmen: äußeres abgerundetes Rechteck minus inneres Fenster (Even-Odd)
    NSRect outer = NSMakeRect(xs - kHandleW, NSMinY(bounds), (xe - xs) + 2 * kHandleW, NSHeight(bounds));
    NSRect inner = NSMakeRect(xs, NSMinY(bounds) + kBarH, xe - xs, NSHeight(bounds) - 2 * kBarH);
    NSBezierPath *frame = [NSBezierPath bezierPathWithRoundedRect:outer xRadius:kRadius yRadius:kRadius];
    [frame appendBezierPathWithRect:inner];
    frame.windingRule = NSWindingRuleEvenOdd;
    [[NSColor colorWithSRGBRed:1.0 green:0.82 blue:0.0 alpha:1.0] setFill];
    [frame fill];

    // Griff-Symbole ‹ ›
    NSBezierPath *chev = [NSBezierPath bezierPath];
    chev.lineWidth = 1.8;
    chev.lineCapStyle = NSLineCapStyleRound;
    chev.lineJoinStyle = NSLineJoinStyleRound;
    CGFloat midY = NSMidY(bounds);
    CGFloat lc = xs - kHandleW / 2, rc = xe + kHandleW / 2;
    [chev moveToPoint:NSMakePoint(lc + 2, midY - 5)];
    [chev lineToPoint:NSMakePoint(lc - 2, midY)];
    [chev lineToPoint:NSMakePoint(lc + 2, midY + 5)];
    [chev moveToPoint:NSMakePoint(rc - 2, midY - 5)];
    [chev lineToPoint:NSMakePoint(rc + 2, midY)];
    [chev lineToPoint:NSMakePoint(rc - 2, midY + 5)];
    [[NSColor colorWithWhite:0.1 alpha:0.8] setStroke];
    [chev stroke];

    // Abspielmarke
    CGFloat xp = [self xForTime:_playhead];
    CGFloat w = (_drag == VTDragPlayhead) ? 3.0 : 2.0;
    NSRect shadow = NSMakeRect(xp - w / 2 - 1.5, NSMinY(bounds), w + 3, NSHeight(bounds));
    [[NSColor colorWithWhite:0 alpha:0.45] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:shadow xRadius:2 yRadius:2] fill];
    NSRect line = NSMakeRect(xp - w / 2, NSMinY(bounds), w, NSHeight(bounds));
    [[NSColor whiteColor] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:line xRadius:1 yRadius:1] fill];
}

#pragma mark - Maus

- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

- (void)resetCursorRects
{
    if (_duration <= 0) return;
    CGFloat xs = [self xForTime:_startTime], xe = [self xForTime:_endTime];
    NSRect b = self.bounds;
    [self addCursorRect:NSMakeRect(xs - kHandleW - 4, NSMinY(b), kHandleW + 8, NSHeight(b))
                 cursor:NSCursor.resizeLeftRightCursor];
    [self addCursorRect:NSMakeRect(xe - 4, NSMinY(b), kHandleW + 8, NSHeight(b))
                 cursor:NSCursor.resizeLeftRightCursor];
}

- (void)mouseDown:(NSEvent *)event
{
    if (_duration <= 0) return;
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat xs = [self xForTime:_startTime], xe = [self xForTime:_endTime];
    CGFloat ds = std::fabs(p.x - (xs - kHandleW / 2));
    CGFloat de = std::fabs(p.x - (xe + kHandleW / 2));
    const CGFloat grab = kHandleW / 2 + 6;

    if (ds <= grab && ds <= de)      _drag = VTDragStart;
    else if (de <= grab)             _drag = VTDragEnd;
    else                             _drag = VTDragPlayhead;

    [self.delegate trimViewDidBeginInteraction:self];
    [self applyDragAtX:p.x];
}

- (void)mouseDragged:(NSEvent *)event
{
    if (_drag == VTDragNone) return;
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    [self applyDragAtX:p.x];
}

- (void)mouseUp:(NSEvent *)event
{
    if (_drag == VTDragNone) return;
    _drag = VTDragNone;
    [self.window invalidateCursorRectsForView:self];
    self.needsDisplay = YES;
    [self.delegate trimViewDidEndInteraction:self];
}

- (void)applyDragAtX:(CGFloat)x
{
    double t = [self timeForX:x];
    switch (_drag) {
        case VTDragStart:
            t = std::clamp(t, 0.0, std::max(0.0, _endTime - kMinSelection));
            _startTime = t;
            _playhead = t;
            [self.delegate trimView:self didChangeStart:_startTime end:_endTime];
            [self.delegate trimView:self didScrubToTime:t];
            break;
        case VTDragEnd:
            t = std::clamp(t, std::min(_duration, _startTime + kMinSelection), _duration);
            _endTime = t;
            _playhead = t;
            [self.delegate trimView:self didChangeStart:_startTime end:_endTime];
            [self.delegate trimView:self didScrubToTime:t];
            break;
        case VTDragPlayhead:
            _playhead = t;
            [self.delegate trimView:self didScrubToTime:t];
            break;
        case VTDragNone:
            break;
    }
    self.needsDisplay = YES;
}

@end
