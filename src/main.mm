// main.mm — Startpunkt. Ohne Argumente (oder mit Videodatei) startet die GUI.
// Zusätzlich gibt es einen Kommandozeilen-Modus zum Schneiden ohne Fenster:
//   VideoTrimmer --cut <eingabe> <ausgabe> <start> <ende> [--reencode]
#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import "AppDelegate.h"
#import "Exporter.h"
#include "TimeUtil.hpp"
#include <cstdio>
#include <cstring>

static int Usage(void)
{
    std::fprintf(stderr,
        "VideoTrimmer\n"
        "  VideoTrimmer [video.mp4]                             GUI starten\n"
        "  VideoTrimmer --cut EIN AUS START ENDE [--reencode]   ohne GUI schneiden\n"
        "     Zeiten als Sekunden oder m:ss(.cc) bzw. h:mm:ss(.cc)\n");
    return 2;
}

static int RunCut(int argc, const char *argv[])
{
    if (argc < 6) return Usage();
    NSURL *in  = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]];
    NSURL *out = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[3]]];
    auto start = vt::parseTime(argv[4]);
    auto end   = vt::parseTime(argv[5]);
    bool reencode = argc > 6 && std::strcmp(argv[6], "--reencode") == 0;
    if (!start || !end || *end <= *start) {
        std::fprintf(stderr, "Ungültiger Zeitbereich.\n");
        return 2;
    }

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:in options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
    Exporter *exporter = [[Exporter alloc] initWithAsset:asset reencode:reencode];
    if (!exporter) {
        std::fprintf(stderr, "Export nicht möglich (Format nicht unterstützt?).\n");
        return 1;
    }
    if (![out.pathExtension.lowercaseString isEqualToString:exporter.preferredExtension])
        std::fprintf(stderr, "Hinweis: Für diese Quelle wird die Endung .%s empfohlen.\n", exporter.preferredExtension.UTF8String);

    __block int rc = 0;
    [exporter exportToURL:out start:*start end:*end completion:^(NSError *error, BOOL cancelled) {
        if (error) {
            std::fprintf(stderr, "Fehler: %s\n", error.localizedDescription.UTF8String);
            rc = 1;
        } else if (cancelled) {
            rc = 1;
        } else {
            AVURLAsset *result = [AVURLAsset URLAssetWithURL:out options:nil];
            std::printf("OK: %s (Dauer %s)\n", out.path.UTF8String,
                        vt::formatTime(CMTimeGetSeconds(result.duration)).c_str());
        }
        CFRunLoopStop(CFRunLoopGetMain());
    }];
    CFRunLoopRun();
    return rc;
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc > 1 && std::strcmp(argv[1], "--cut") == 0) return RunCut(argc, argv);
        if (argc > 1 && (std::strcmp(argv[1], "--help") == 0 || std::strcmp(argv[1], "-h") == 0)) return Usage();

        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
