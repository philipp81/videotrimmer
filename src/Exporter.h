// Exporter.h — schneidet einen Zeitbereich per AVAssetExportSession heraus.
#pragma once
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

typedef void (^VTExportCompletion)(NSError * _Nullable error, BOOL cancelled);

@interface Exporter : NSObject

// reencode = NO: Passthrough (verlustfrei, schnell). reencode = YES: Neukodierung (bildgenau).
// Liefert nil, wenn das Asset mit dem gewählten Preset nicht exportiert werden kann.
- (nullable instancetype)initWithAsset:(nonnull AVAsset *)asset reencode:(BOOL)reencode;

@property (nonatomic, readonly, nonnull) NSString *preferredExtension;  // "mp4" oder "mov"
@property (nonatomic, readonly, nonnull) UTType *outputType;
@property (nonatomic, readonly) float progress;                          // 0…1

- (void)exportToURL:(nonnull NSURL *)url start:(double)start end:(double)end
         completion:(nonnull VTExportCompletion)completion;
- (void)cancel;

@end
