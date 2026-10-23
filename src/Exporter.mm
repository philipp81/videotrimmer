#import "Exporter.h"

@implementation Exporter {
    AVAssetExportSession *_session;
    AVFileType _fileType;
}

- (instancetype)initWithAsset:(AVAsset *)asset reencode:(BOOL)reencode
{
    if (!(self = [super init])) return nil;

    NSString *preset = reencode ? AVAssetExportPresetHighestQuality : AVAssetExportPresetPassthrough;
    _session = [[AVAssetExportSession alloc] initWithAsset:asset presetName:preset];
    if (!_session) return nil;

    NSArray<AVFileType> *types = _session.supportedFileTypes;
    if ([types containsObject:AVFileTypeMPEG4]) {
        _fileType = AVFileTypeMPEG4;
        _preferredExtension = @"mp4";
        _outputType = UTTypeMPEG4Movie;
    } else if ([types containsObject:AVFileTypeQuickTimeMovie]) {
        // z. B. bei Audiospuren, die MP4 nicht aufnehmen kann (PCM) → .mov
        _fileType = AVFileTypeQuickTimeMovie;
        _preferredExtension = @"mov";
        _outputType = UTTypeQuickTimeMovie;
    } else {
        return nil;
    }
    return self;
}

- (float)progress
{
    return _session.progress;
}

- (void)exportToURL:(NSURL *)url start:(double)start end:(double)end completion:(VTExportCompletion)completion
{
    [[NSFileManager defaultManager] removeItemAtURL:url error:nil];

    _session.outputURL = url;
    _session.outputFileType = _fileType;
    _session.shouldOptimizeForNetworkUse = YES;
    CMTime s = CMTimeMakeWithSeconds(start, 60000);
    CMTime e = CMTimeMakeWithSeconds(end, 60000);
    _session.timeRange = CMTimeRangeFromTimeToTime(s, e);

    AVAssetExportSession *session = _session;
    [session exportAsynchronouslyWithCompletionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            switch (session.status) {
                case AVAssetExportSessionStatusCompleted:
                    completion(nil, NO);
                    break;
                case AVAssetExportSessionStatusCancelled:
                    completion(nil, YES);
                    break;
                default: {
                    NSError *err = session.error ?: [NSError errorWithDomain:@"VideoTrimmer" code:1 userInfo:@{
                        NSLocalizedDescriptionKey: @"Der Export ist aus unbekanntem Grund fehlgeschlagen." }];
                    completion(err, NO);
                }
            }
        });
    }];
}

- (void)cancel
{
    [_session cancelExport];
}

@end
