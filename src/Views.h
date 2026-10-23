// Views.h — kleine Hilfs-Views: Videofläche (AVPlayerLayer) und Drop-Ziel für Dateien.
#pragma once
#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>

// Layer-gestützte View, deren Backing-Layer ein AVPlayerLayer ist.
@interface PlayerView : NSView
@property (nonatomic, readonly) AVPlayerLayer *playerLayer;
@end

// Content-View des Fensters: nimmt per Drag & Drop Videodateien an.
@interface DropView : NSView
@property (nonatomic, copy) void (^onDropURL)(NSURL *url);
@end
