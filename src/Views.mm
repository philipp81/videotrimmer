#import "Views.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#pragma mark - PlayerView

@implementation PlayerView

- (instancetype)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawNever;
    }
    return self;
}

- (CALayer *)makeBackingLayer
{
    AVPlayerLayer *layer = [AVPlayerLayer layer];
    layer.backgroundColor = CGColorGetConstantColor(kCGColorBlack);
    layer.videoGravity = AVLayerVideoGravityResizeAspect;
    return layer;
}

- (AVPlayerLayer *)playerLayer
{
    return (AVPlayerLayer *)self.layer;
}

@end

#pragma mark - DropView

@implementation DropView

static NSDictionary *DropReadOptions(void)
{
    return @{
        NSPasteboardURLReadingFileURLsOnlyKey: @YES,
        NSPasteboardURLReadingContentsConformToTypesKey: @[
            UTTypeMovie.identifier, UTTypeVideo.identifier, UTTypeAudiovisualContent.identifier
        ],
    };
}

- (instancetype)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    }
    return self;
}

- (NSURL *)videoURLFromPasteboard:(NSPasteboard *)pb
{
    NSArray<NSURL *> *urls = [pb readObjectsForClasses:@[NSURL.class] options:DropReadOptions()];
    return urls.firstObject;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
    return [self videoURLFromPasteboard:sender.draggingPasteboard] ? NSDragOperationCopy : NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender
{
    return [self draggingEntered:sender];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
    NSURL *url = [self videoURLFromPasteboard:sender.draggingPasteboard];
    if (!url) return NO;
    if (self.onDropURL) self.onDropURL(url);
    return YES;
}

@end
