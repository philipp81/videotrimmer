// TrimView.h — Zeitleiste mit Filmstreifen, gelbem Auswahlrahmen (Start/Ende) und Abspielmarke.
#pragma once
#import <Cocoa/Cocoa.h>

@class TrimView;

@protocol TrimViewDelegate <NSObject>
- (void)trimViewDidBeginInteraction:(TrimView *)view;            // Maus gedrückt → Wiedergabe pausieren
- (void)trimView:(TrimView *)view didScrubToTime:(double)time;    // Abspielmarke bewegt (Sekunden)
- (void)trimView:(TrimView *)view didChangeStart:(double)start end:(double)end; // Griffe bewegt
- (void)trimViewDidEndInteraction:(TrimView *)view;
- (void)trimViewDidResize:(TrimView *)view;                       // Gelegenheit, Vorschaubilder neu zu erzeugen
@end

@interface TrimView : NSView

@property (nonatomic) double duration;   // Gesamtlänge in Sekunden (0 = kein Video)
@property (nonatomic) double startTime;  // Auswahlanfang
@property (nonatomic) double endTime;    // Auswahlende
@property (nonatomic) double playhead;   // aktuelle Abspielposition
@property (nonatomic, weak) id<TrimViewDelegate> delegate;
@property (nonatomic, readonly) BOOL isDragging;

- (void)clear;
- (CGFloat)stripHeight;                                       // Höhe des Filmstreifens in Punkten
- (NSUInteger)thumbnailCountForAspect:(CGFloat)aspect;        // wie viele Bilder den Streifen füllen
- (void)prepareThumbnailSlots:(NSUInteger)count;              // leert den Streifen und reserviert Plätze
- (void)setThumbnail:(NSImage *)image atIndex:(NSUInteger)index;

@end
