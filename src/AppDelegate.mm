#import "AppDelegate.h"
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "Exporter.h"
#import "TrimView.h"
#import "Views.h"
#include "TimeUtil.hpp"
#include <algorithm>
#include <cmath>

static void *kItemStatusCtx  = &kItemStatusCtx;
static void *kTimeControlCtx = &kTimeControlCtx;
static NSString *const kReencodeKey = @"VTExportReencode";
static const double kMinSelection = 0.05;   // Sekunden

static NSString *NSStr(const std::string &s) { return [NSString stringWithUTF8String:s.c_str()]; }
static NSImage *Symbol(NSString *name) { return [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil]; }

static NSStackView *HStack(NSArray<NSView *> *views)
{
    NSStackView *s = [NSStackView stackViewWithViews:views];
    s.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    s.alignment = NSLayoutAttributeCenterY;
    s.spacing = 8;
    s.translatesAutoresizingMaskIntoConstraints = NO;
    return s;
}

static NSMenuItem *StdItem(NSString *title, SEL action, NSString *key, NSEventModifierFlags mask)
{
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
    item.keyEquivalentModifierMask = mask;      // target nil → Responder-Kette
    return item;
}

@interface AppDelegate () <TrimViewDelegate, NSWindowDelegate, NSTextFieldDelegate, NSMenuItemValidation>

// UI
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) PlayerView *playerView;
@property (nonatomic, strong) NSTextField *emptyLabel;
@property (nonatomic, strong) TrimView *trimView;
@property (nonatomic, strong) NSButton *playButton;
@property (nonatomic, strong) NSTextField *timeLabel;
@property (nonatomic, strong) NSTextField *startField;
@property (nonatomic, strong) NSTextField *endField;
@property (nonatomic, strong) NSTextField *selectionLabel;
@property (nonatomic, strong) NSPopUpButton *modePopup;
@property (nonatomic, strong) NSArray<NSControl *> *videoControls;

// Fortschritts-Sheet
@property (nonatomic, strong) NSWindow *progressSheet;
@property (nonatomic, strong) NSProgressIndicator *progressBar;
@property (nonatomic, strong) NSTextField *progressLabel;
@property (nonatomic, strong) NSTimer *progressTimer;

// Medien
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerItem *playerItem;
@property (nonatomic, strong) AVURLAsset *asset;
@property (nonatomic, strong) NSURL *currentURL;
@property (nonatomic, strong) id periodicObserver;
@property (nonatomic, strong) id boundaryObserver;
@property (nonatomic, strong) AVAssetImageGenerator *imageGenerator;
@property (nonatomic, strong) Exporter *exporter;
@property (nonatomic, strong) NSURL *pendingURL;
@property (nonatomic) CGFloat videoAspect;
@property (nonatomic) NSUInteger thumbCount;
@property (nonatomic) double duration;
@property (nonatomic) BOOL videoLoaded;

@end

@implementation AppDelegate

#pragma mark - App-Lebenszyklus

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    [self buildMenus];
    [self buildWindow];
    [self buildProgressSheet];

    self.player = [[AVPlayer alloc] init];
    self.player.actionAtItemEnd = AVPlayerActionAtItemEndPause;
    self.playerView.playerLayer.player = self.player;
    [self.player addObserver:self forKeyPath:@"timeControlStatus"
                     options:NSKeyValueObservingOptionNew context:kTimeControlCtx];

    __weak __typeof__(self) weakSelf = self;
    self.periodicObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 60)
                                                                      queue:dispatch_get_main_queue()
                                                                 usingBlock:^(CMTime time) {
        [weakSelf playbackTimeChanged:time];
    }];

    [self setVideoControlsEnabled:NO];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    NSURL *url = self.pendingURL;
    self.pendingURL = nil;
    if (!url) {
        NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
        if (args.count > 1 && ![args[1] hasPrefix:@"-"]) url = [NSURL fileURLWithPath:args[1]];
    }
    if (url) [self loadURL:url];
    [self scheduleSnapshotIfRequested];
}

- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls
{
    NSURL *url = urls.firstObject;
    if (!url) return;
    if (self.window) [self loadURL:url];
    else self.pendingURL = url;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }
- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app { return YES; }

- (void)windowWillClose:(NSNotification *)notification
{
    [self.player pause];
    [self.exporter cancel];
}

#pragma mark - Menüs

- (NSMenuItem *)item:(NSString *)title action:(SEL)action key:(NSString *)key mask:(NSEventModifierFlags)mask
{
    NSMenuItem *item = StdItem(title, action, key, mask);
    item.target = self;
    return item;
}

- (void)buildMenus
{
    NSString *appName = @"VideoTrimmer";
    NSString *left  = [NSString stringWithFormat:@"%C", (unichar)NSLeftArrowFunctionKey];
    NSString *right = [NSString stringWithFormat:@"%C", (unichar)NSRightArrowFunctionKey];
    const NSEventModifierFlags cmd = NSEventModifierFlagCommand;
    const NSEventModifierFlags shift = NSEventModifierFlagShift;

    NSMenu *bar = [[NSMenu alloc] init];

    NSMenu *app = [[NSMenu alloc] initWithTitle:appName];
    [app addItem:StdItem([@"Über " stringByAppendingString:appName], @selector(orderFrontStandardAboutPanel:), @"", 0)];
    [app addItem:NSMenuItem.separatorItem];
    [app addItem:StdItem([appName stringByAppendingString:@" ausblenden"], @selector(hide:), @"h", cmd)];
    [app addItem:StdItem(@"Andere ausblenden", @selector(hideOtherApplications:), @"h", cmd | NSEventModifierFlagOption)];
    [app addItem:StdItem(@"Alle einblenden", @selector(unhideAllApplications:), @"", 0)];
    [app addItem:NSMenuItem.separatorItem];
    [app addItem:StdItem([appName stringByAppendingString:@" beenden"], @selector(terminate:), @"q", cmd)];
    [bar addItemWithTitle:appName action:nil keyEquivalent:@""].submenu = app;

    NSMenu *file = [[NSMenu alloc] initWithTitle:@"Ablage"];
    [file addItem:[self item:@"Öffnen…" action:@selector(openDocument:) key:@"o" mask:cmd]];
    [file addItem:NSMenuItem.separatorItem];
    [file addItem:[self item:@"Auswahl sichern unter…" action:@selector(exportSelection:) key:@"s" mask:cmd]];
    [file addItem:[self item:@"Anfang bis Abspielposition sichern…" action:@selector(exportToHere:) key:@"a" mask:cmd | shift]];
    [file addItem:[self item:@"Abspielposition bis Ende sichern…" action:@selector(exportFromHere:) key:@"e" mask:cmd | shift]];
    [file addItem:NSMenuItem.separatorItem];
    [file addItem:StdItem(@"Schließen", @selector(performClose:), @"w", cmd)];
    [bar addItemWithTitle:@"Ablage" action:nil keyEquivalent:@""].submenu = file;

    NSMenu *edit = [[NSMenu alloc] initWithTitle:@"Bearbeiten"];
    [edit addItem:[self item:@"Start hier setzen" action:@selector(setStartHere:) key:@"i" mask:0]];
    [edit addItem:[self item:@"Ende hier setzen" action:@selector(setEndHere:) key:@"o" mask:0]];
    [edit addItem:[self item:@"Auswahl zurücksetzen" action:@selector(resetSelection:) key:@"r" mask:cmd]];
    [edit addItem:NSMenuItem.separatorItem];
    [edit addItem:StdItem(@"Ausschneiden", @selector(cut:), @"x", cmd)];
    [edit addItem:StdItem(@"Kopieren", @selector(copy:), @"c", cmd)];
    [edit addItem:StdItem(@"Einsetzen", @selector(paste:), @"v", cmd)];
    [edit addItem:StdItem(@"Alles auswählen", @selector(selectAll:), @"a", cmd)];
    [bar addItemWithTitle:@"Bearbeiten" action:nil keyEquivalent:@""].submenu = edit;

    NSMenu *play = [[NSMenu alloc] initWithTitle:@"Wiedergabe"];
    [play addItem:[self item:@"Wiedergabe/Pause" action:@selector(togglePlay:) key:@" " mask:0]];
    [play addItem:NSMenuItem.separatorItem];
    [play addItem:[self item:@"Ein Bild zurück" action:@selector(stepBackward:) key:left mask:0]];
    [play addItem:[self item:@"Ein Bild vor" action:@selector(stepForward:) key:right mask:0]];
    [play addItem:[self item:@"1 Sekunde zurück" action:@selector(jumpBack:) key:left mask:shift]];
    [play addItem:[self item:@"1 Sekunde vor" action:@selector(jumpForward:) key:right mask:shift]];
    [play addItem:NSMenuItem.separatorItem];
    [play addItem:[self item:@"Zum Auswahlanfang" action:@selector(gotoStart:) key:left mask:cmd]];
    [play addItem:[self item:@"Zum Auswahlende" action:@selector(gotoEnd:) key:right mask:cmd]];
    [bar addItemWithTitle:@"Wiedergabe" action:nil keyEquivalent:@""].submenu = play;

    NSMenu *win = [[NSMenu alloc] initWithTitle:@"Fenster"];
    [win addItem:StdItem(@"Im Dock ablegen", @selector(performMiniaturize:), @"m", cmd)];
    [win addItem:StdItem(@"Zoomen", @selector(performZoom:), @"", 0)];
    [bar addItemWithTitle:@"Fenster" action:nil keyEquivalent:@""].submenu = win;
    NSApp.windowsMenu = win;

    NSApp.mainMenu = bar;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    // Während in ein Textfeld getippt wird oder ein Dialog/Sheet offen ist, dürfen
    // Einzeltasten-Kürzel (Leertaste, I, O, Pfeile) nicht greifen.
    BOOL unmodified = item.keyEquivalent.length > 0 && item.keyEquivalentModifierMask == 0;
    NSWindow *key = NSApp.keyWindow;
    if (unmodified && (key != self.window || [key.firstResponder isKindOfClass:NSText.class])) return NO;

    SEL a = item.action;
    if (a == @selector(openDocument:)) return self.exporter == nil;
    if (a == @selector(exportSelection:) || a == @selector(exportToHere:) || a == @selector(exportFromHere:))
        return self.videoLoaded && self.exporter == nil;
    return self.videoLoaded;
}

#pragma mark - Fensteraufbau

- (NSTextField *)makeTimeField
{
    NSTextField *f = [[NSTextField alloc] initWithFrame:NSZeroRect];
    f.font = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightRegular];
    f.alignment = NSTextAlignmentCenter;
    f.placeholderString = @"0:00.00";
    f.delegate = self;
    f.toolTip = @"Zeit eingeben, z. B. 1:23.5 oder 0:01:23 – mit Return übernehmen";
    [[f.widthAnchor constraintEqualToConstant:96] setActive:YES];
    return f;
}

- (void)buildWindow
{
    NSRect frame = NSMakeRect(0, 0, 1000, 700);
    NSWindowStyleMask mask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    NSWindow *w = [[NSWindow alloc] initWithContentRect:frame styleMask:mask backing:NSBackingStoreBuffered defer:NO];
    w.title = @"VideoTrimmer";
    w.minSize = NSMakeSize(880, 560);
    w.delegate = self;
    w.releasedWhenClosed = NO;
    [w center];
    [w setFrameAutosaveName:@"VTMainWindow"];
    self.window = w;

    DropView *content = [[DropView alloc] initWithFrame:frame];
    __weak __typeof__(self) weakSelf = self;
    content.onDropURL = ^(NSURL *url) { [weakSelf loadURL:url]; };
    w.contentView = content;

    // Videofläche mit Hinweistext
    self.playerView = [[PlayerView alloc] initWithFrame:NSZeroRect];
    self.playerView.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:self.playerView];

    self.emptyLabel = [NSTextField labelWithString:@"Video hierher ziehen oder mit ⌘O öffnen"];
    self.emptyLabel.font = [NSFont systemFontOfSize:16];
    self.emptyLabel.textColor = [NSColor colorWithWhite:0.72 alpha:1];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.playerView addSubview:self.emptyLabel];

    // Zeitleiste
    self.trimView = [[TrimView alloc] initWithFrame:NSZeroRect];
    self.trimView.translatesAutoresizingMaskIntoConstraints = NO;
    self.trimView.delegate = self;
    [content addSubview:self.trimView];

    // Zeile 1: Transport
    NSButton *back = [NSButton buttonWithImage:Symbol(@"backward.frame") target:self action:@selector(stepBackward:)];
    back.toolTip = @"Ein Bild zurück (←)";
    self.playButton = [NSButton buttonWithImage:Symbol(@"play.fill") target:self action:@selector(togglePlay:)];
    self.playButton.toolTip = @"Wiedergabe/Pause (Leertaste)";
    NSButton *fwd = [NSButton buttonWithImage:Symbol(@"forward.frame") target:self action:@selector(stepForward:)];
    fwd.toolTip = @"Ein Bild vor (→)";
    self.timeLabel = [NSTextField labelWithString:@"0:00.00 / 0:00.00"];
    self.timeLabel.font = [NSFont monospacedDigitSystemFontOfSize:14 weight:NSFontWeightMedium];
    NSStackView *row1 = HStack(@[back, self.playButton, fwd, self.timeLabel]);
    NSTextField *hint = [NSTextField labelWithString:@"Gelbe Griffe ziehen = Anfang/Ende · Klick in die Leiste = Position · I/O = Start/Ende hier"];
    hint.font = [NSFont systemFontOfSize:11];
    hint.textColor = NSColor.secondaryLabelColor;
    hint.lineBreakMode = NSLineBreakByTruncatingTail;
    [hint setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [row1 addView:hint inGravity:NSStackViewGravityTrailing];

    // Zeile 2: Auswahl
    NSButton *setStart = [NSButton buttonWithTitle:@"Start setzen" target:self action:@selector(setStartHere:)];
    setStart.toolTip = @"Auswahlanfang auf die Abspielposition setzen (I)";
    self.startField = [self makeTimeField];
    NSTextField *dash = [NSTextField labelWithString:@"–"];
    self.endField = [self makeTimeField];
    NSButton *setEnd = [NSButton buttonWithTitle:@"Ende setzen" target:self action:@selector(setEndHere:)];
    setEnd.toolTip = @"Auswahlende auf die Abspielposition setzen (O)";
    self.selectionLabel = [NSTextField labelWithString:@"Dauer 0:00.00"];
    self.selectionLabel.font = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightRegular];
    self.selectionLabel.textColor = NSColor.secondaryLabelColor;
    NSButton *reset = [NSButton buttonWithTitle:@"Auswahl zurücksetzen" target:self action:@selector(resetSelection:)];
    reset.toolTip = @"Gesamtes Video auswählen (⌘R)";
    NSStackView *row2 = HStack(@[setStart, self.startField, dash, self.endField, setEnd, self.selectionLabel]);
    [row2 addView:reset inGravity:NSStackViewGravityTrailing];

    // Zeile 3: Export
    NSTextField *modeLabel = [NSTextField labelWithString:@"Export:"];
    self.modePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.modePopup addItemsWithTitles:@[@"Schnell (verlustfrei)", @"Bildgenau (neu kodieren)"]];
    self.modePopup.toolTip = @"Schnell: Bild- und Tondaten werden 1:1 kopiert; der Schnitt liegt exakt, manche Player "
                             @"zeigen am Anfang jedoch bis zum vorigen Schlüsselbild etwas mehr.\n"
                             @"Bildgenau: Video wird neu kodiert (H.264), Schnitt in jedem Player exakt.";
    [self.modePopup selectItemAtIndex:[NSUserDefaults.standardUserDefaults boolForKey:kReencodeKey] ? 1 : 0];
    self.modePopup.target = self;
    self.modePopup.action = @selector(modeChanged:);
    NSButton *toHere = [NSButton buttonWithTitle:@"Anfang → hier sichern…" target:self action:@selector(exportToHere:)];
    toHere.toolTip = @"Alles vom Videoanfang bis zur Abspielposition sichern (⇧⌘A)";
    NSButton *fromHere = [NSButton buttonWithTitle:@"Hier → Ende sichern…" target:self action:@selector(exportFromHere:)];
    fromHere.toolTip = @"Alles von der Abspielposition bis zum Videoende sichern (⇧⌘E)";
    NSButton *sel = [NSButton buttonWithTitle:@"Auswahl sichern…" target:self action:@selector(exportSelection:)];
    sel.toolTip = @"Den gelb markierten Bereich sichern (⌘S)";
    NSStackView *row3 = HStack(@[modeLabel, self.modePopup]);
    [row3 addView:toHere inGravity:NSStackViewGravityTrailing];
    [row3 addView:fromHere inGravity:NSStackViewGravityTrailing];
    [row3 addView:sel inGravity:NSStackViewGravityTrailing];

    for (NSStackView *row in @[row1, row2, row3]) [content addSubview:row];

    self.videoControls = @[back, self.playButton, fwd, setStart, setEnd, self.startField, self.endField,
                           reset, toHere, fromHere, sel];

    const CGFloat m = 16;
    [NSLayoutConstraint activateConstraints:@[
        [self.playerView.topAnchor constraintEqualToAnchor:content.topAnchor],
        [self.playerView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [self.playerView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [self.playerView.bottomAnchor constraintEqualToAnchor:self.trimView.topAnchor constant:-10],
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.playerView.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.playerView.centerYAnchor],

        [self.trimView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:8],
        [self.trimView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-8],
        [self.trimView.heightAnchor constraintEqualToConstant:64],
        [self.trimView.bottomAnchor constraintEqualToAnchor:row1.topAnchor constant:-10],

        [row1.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:m],
        [row1.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-m],
        [row1.bottomAnchor constraintEqualToAnchor:row2.topAnchor constant:-8],
        [row2.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:m],
        [row2.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-m],
        [row2.bottomAnchor constraintEqualToAnchor:row3.topAnchor constant:-8],
        [row3.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:m],
        [row3.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-m],
        [row3.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-14],
    ]];
}

- (void)buildProgressSheet
{
    NSWindow *s = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 460, 120)
                                              styleMask:NSWindowStyleMaskTitled
                                                backing:NSBackingStoreBuffered defer:NO];
    s.releasedWhenClosed = NO;
    NSView *c = s.contentView;

    self.progressLabel = [NSTextField labelWithString:@"Exportiere …"];
    self.progressLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.progressBar = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    self.progressBar.style = NSProgressIndicatorStyleBar;
    self.progressBar.indeterminate = NO;
    self.progressBar.minValue = 0;
    self.progressBar.maxValue = 100;
    NSButton *cancel = [NSButton buttonWithTitle:@"Abbrechen" target:self action:@selector(cancelExport:)];
    cancel.keyEquivalent = @"\033";

    for (NSView *v in @[self.progressLabel, self.progressBar, cancel]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [c addSubview:v];
    }
    [NSLayoutConstraint activateConstraints:@[
        [self.progressLabel.topAnchor constraintEqualToAnchor:c.topAnchor constant:20],
        [self.progressLabel.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:20],
        [self.progressLabel.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-20],
        [self.progressBar.topAnchor constraintEqualToAnchor:self.progressLabel.bottomAnchor constant:10],
        [self.progressBar.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:20],
        [self.progressBar.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-20],
        [cancel.topAnchor constraintEqualToAnchor:self.progressBar.bottomAnchor constant:12],
        [cancel.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-20],
        [cancel.bottomAnchor constraintEqualToAnchor:c.bottomAnchor constant:-16],
    ]];
    self.progressSheet = s;
}

- (void)setVideoControlsEnabled:(BOOL)enabled
{
    for (NSControl *c in self.videoControls) c.enabled = enabled;
}

#pragma mark - Laden

- (void)openDocument:(id)sender
{
    NSOpenPanel *p = [NSOpenPanel openPanel];
    p.allowedContentTypes = @[UTTypeMovie, UTTypeVideo, UTTypeMPEG4Movie, UTTypeQuickTimeMovie];
    p.allowsMultipleSelection = NO;
    p.message = @"Video zum Schneiden auswählen";
    [p beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSModalResponseOK && p.URL) [self loadURL:p.URL];
    }];
}

- (void)loadURL:(NSURL *)url
{
    if (self.exporter) { NSBeep(); return; }
    [self.player pause];
    [self cancelThumbnails];
    [self teardownItem];

    self.currentURL = url;
    self.videoLoaded = NO;
    self.duration = 0;
    [self.trimView clear];
    [self setVideoControlsEnabled:NO];
    self.emptyLabel.stringValue = @"Lade …";
    self.emptyLabel.hidden = NO;
    self.window.title = url.lastPathComponent;
    self.window.representedURL = url;
    [self updateTimeUI];

    self.asset = [AVURLAsset URLAssetWithURL:url options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
    self.playerItem = [AVPlayerItem playerItemWithAsset:self.asset];
    [self.playerItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:kItemStatusCtx];
    [self.player replaceCurrentItemWithPlayerItem:self.playerItem];
}

- (void)teardownItem
{
    if (self.playerItem) {
        [self.playerItem removeObserver:self forKeyPath:@"status" context:kItemStatusCtx];
        self.playerItem = nil;
    }
    [self removeBoundaryObserver];
    [self.player replaceCurrentItemWithPlayerItem:nil];
    self.asset = nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context
{
    if (context == kItemStatusCtx) {
        AVPlayerItem *item = object;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (item != self.playerItem) return;
            if (item.status == AVPlayerItemStatusReadyToPlay) [self itemBecameReady];
            else if (item.status == AVPlayerItemStatusFailed) [self loadFailedWithError:item.error];
        });
    } else if (context == kTimeControlCtx) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self updatePlayButton]; });
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)itemBecameReady
{
    if (self.videoLoaded) return;
    double d = CMTimeGetSeconds(self.playerItem.duration);
    if (!(d > 0) || std::isinf(d)) d = CMTimeGetSeconds(self.asset.duration);
    if (!(d > 0) || std::isinf(d)) { [self loadFailedWithError:nil]; return; }

    self.videoLoaded = YES;
    self.duration = d;
    self.trimView.duration = d;
    self.trimView.startTime = 0;
    self.trimView.endTime = d;
    self.trimView.playhead = 0;
    self.emptyLabel.hidden = YES;
    [self setVideoControlsEnabled:YES];
    [self installBoundaryObserver];
    [self updateTimeUI];

    __weak __typeof__(self) weakSelf = self;
    AVURLAsset *asset = self.asset;
    [asset loadTracksWithMediaType:AVMediaTypeVideo completionHandler:^(NSArray<AVAssetTrack *> *tracks, NSError *error) {
        CGFloat aspect = 16.0 / 9.0;
        AVAssetTrack *track = tracks.firstObject;
        if (track) {
            CGSize shown = CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform);
            shown.width = std::fabs(shown.width);
            shown.height = std::fabs(shown.height);
            if (shown.width > 0 && shown.height > 0) aspect = shown.width / shown.height;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __typeof__(self) strongSelf = weakSelf;
            if (!strongSelf || strongSelf.asset != asset) return;
            strongSelf.videoAspect = aspect;
            [strongSelf generateThumbnails];
        });
    }];
}

- (void)loadFailedWithError:(NSError *)error
{
    self.emptyLabel.stringValue = @"Video konnte nicht geladen werden";
    self.emptyLabel.hidden = NO;
    NSString *detail = error.localizedDescription ?: @"Unbekannter Fehler.";
    NSString *msg = [NSString stringWithFormat:
        @"%@\n\nmacOS kann dieses Format nicht dekodieren (z. B. VP9/AV1 in MP4). "
        @"Mit ffmpeg lässt es sich vorher umwandeln:\n\nffmpeg -i \"%@\" -c:v libx264 -c:a aac konvertiert.mp4",
        detail, self.currentURL.lastPathComponent];
    [self showErrorTitle:@"Video kann nicht geöffnet werden" message:msg];
}

#pragma mark - Vorschaubilder

- (void)cancelThumbnails
{
    [self.imageGenerator cancelAllCGImageGeneration];
    self.imageGenerator = nil;
}

- (void)generateThumbnails
{
    [self cancelThumbnails];
    if (!self.videoLoaded || !self.asset || self.videoAspect <= 0) return;

    NSUInteger count = [self.trimView thumbnailCountForAspect:self.videoAspect];
    if (count == 0) count = 40;
    self.thumbCount = count;
    [self.trimView prepareThumbnailSlots:count];

    CGFloat scale = self.window.backingScaleFactor > 0 ? self.window.backingScaleFactor : 2.0;
    CGFloat h = std::max<CGFloat>(16, self.trimView.stripHeight) * scale;
    AVAssetImageGenerator *gen = [[AVAssetImageGenerator alloc] initWithAsset:self.asset];
    gen.appliesPreferredTrackTransform = YES;
    gen.maximumSize = CGSizeMake(std::ceil(h * self.videoAspect) + 2, h);
    const double step = self.duration / count;
    CMTime tolerance = CMTimeMakeWithSeconds(std::max(0.05, step / 2), 600);
    gen.requestedTimeToleranceBefore = tolerance;
    gen.requestedTimeToleranceAfter = tolerance;

    NSMutableArray<NSValue *> *times = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; ++i)
        [times addObject:[NSValue valueWithCMTime:CMTimeMakeWithSeconds((i + 0.5) * step, 600)]];

    __weak __typeof__(self) weakSelf = self;
    const double duration = self.duration;
    [gen generateCGImagesAsynchronouslyForTimes:times
                              completionHandler:^(CMTime requestedTime, CGImageRef image, CMTime actualTime,
                                                  AVAssetImageGeneratorResult result, NSError *error) {
        if (result != AVAssetImageGeneratorSucceeded || !image) return;
        NSImage *img = [[NSImage alloc] initWithCGImage:image size:NSZeroSize];
        double t = CMTimeGetSeconds(requestedTime);
        NSUInteger idx = (NSUInteger)std::clamp(std::floor(t / duration * count), 0.0, (double)count - 1);
        dispatch_async(dispatch_get_main_queue(), ^{
            __typeof__(self) strongSelf = weakSelf;
            if (!strongSelf || strongSelf.imageGenerator != gen) return;
            [strongSelf.trimView setThumbnail:img atIndex:idx];
        });
    }];
    self.imageGenerator = gen;
}

#pragma mark - Wiedergabe

- (double)currentTime { return CMTimeGetSeconds(self.player.currentTime); }
- (BOOL)isPlaying { return self.player.timeControlStatus != AVPlayerTimeControlStatusPaused; }

- (void)playbackTimeChanged:(CMTime)time
{
    if (!self.videoLoaded || self.trimView.isDragging) return;
    self.trimView.playhead = CMTimeGetSeconds(time);
    [self updateTimeUI];
}

- (void)updatePlayButton
{
    self.playButton.image = Symbol([self isPlaying] ? @"pause.fill" : @"play.fill");
}

- (void)seekTo:(double)seconds completion:(void (^)(void))completion
{
    if (!self.videoLoaded) return;
    seconds = std::clamp(seconds, 0.0, self.duration);
    self.trimView.playhead = seconds;
    [self updateTimeUI];
    CMTime t = CMTimeMakeWithSeconds(seconds, 60000);
    [self.player seekToTime:t toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero
          completionHandler:^(BOOL finished) {
        if (finished && completion) dispatch_async(dispatch_get_main_queue(), completion);
    }];
}

- (void)seekTo:(double)seconds { [self seekTo:seconds completion:nil]; }

- (void)syncPlayheadFromPlayer
{
    self.trimView.playhead = [self currentTime];
    [self updateTimeUI];
}

- (void)togglePlay:(id)sender
{
    if (!self.videoLoaded) return;
    if ([self isPlaying]) { [self.player pause]; return; }

    double t = [self currentTime];
    double s = self.trimView.startTime, e = self.trimView.endTime;
    if (t < s - 0.001 || t >= e - 0.02) {
        // Außerhalb (oder am Ende) der Auswahl: vom Auswahlanfang abspielen
        __weak __typeof__(self) weakSelf = self;
        [self seekTo:s completion:^{ [weakSelf.player play]; }];
    } else {
        [self.player play];
    }
}

- (void)stepByFrames:(NSInteger)count
{
    if (!self.videoLoaded) return;
    [self.player pause];
    BOOL canStep = count > 0 ? self.playerItem.canStepForward : self.playerItem.canStepBackward;
    if (canStep) {
        [self.playerItem stepByCount:count];
        [self syncPlayheadFromPlayer];
    } else {
        [self seekTo:[self currentTime] + count / 30.0];
    }
}

- (void)stepBackward:(id)sender { [self stepByFrames:-1]; }
- (void)stepForward:(id)sender  { [self stepByFrames:1]; }
- (void)jumpBack:(id)sender     { [self.player pause]; [self seekTo:[self currentTime] - 1.0]; }
- (void)jumpForward:(id)sender  { [self.player pause]; [self seekTo:[self currentTime] + 1.0]; }
- (void)gotoStart:(id)sender    { [self.player pause]; [self seekTo:self.trimView.startTime]; }
- (void)gotoEnd:(id)sender      { [self.player pause]; [self seekTo:self.trimView.endTime]; }

- (void)removeBoundaryObserver
{
    if (self.boundaryObserver) {
        [self.player removeTimeObserver:self.boundaryObserver];
        self.boundaryObserver = nil;
    }
}

// Hält die Wiedergabe exakt am Auswahlende an.
- (void)installBoundaryObserver
{
    [self removeBoundaryObserver];
    if (!self.videoLoaded) return;
    CMTime end = CMTimeMakeWithSeconds(self.trimView.endTime, 60000);
    __weak __typeof__(self) weakSelf = self;
    self.boundaryObserver = [self.player addBoundaryTimeObserverForTimes:@[[NSValue valueWithCMTime:end]]
                                                                   queue:dispatch_get_main_queue()
                                                              usingBlock:^{ [weakSelf reachedSelectionEnd]; }];
}

- (void)reachedSelectionEnd
{
    if (![self isPlaying] || self.trimView.isDragging) return;
    [self.player pause];
    [self seekTo:self.trimView.endTime];
}

#pragma mark - Auswahl

- (void)applySelectionStart:(double)s end:(double)e
{
    if (!self.videoLoaded) return;
    s = std::clamp(s, 0.0, self.duration);
    e = std::clamp(e, 0.0, self.duration);
    if (e - s < kMinSelection) {
        if (s + kMinSelection <= self.duration) e = s + kMinSelection;
        else s = std::max(0.0, e - kMinSelection);
    }
    self.trimView.startTime = s;
    self.trimView.endTime = e;
    [self installBoundaryObserver];
    [self updateTimeUI];
}

- (void)setStartHere:(id)sender
{
    double t = self.trimView.playhead, e = self.trimView.endTime;
    if (t >= e - kMinSelection) e = self.duration;     // Start hinter dem Ende → Ende ans Videoende
    [self applySelectionStart:t end:e];
}

- (void)setEndHere:(id)sender
{
    double t = self.trimView.playhead, s = self.trimView.startTime;
    if (t <= s + kMinSelection) s = 0;                 // Ende vor dem Start → Start an den Videoanfang
    [self applySelectionStart:s end:t];
}

- (void)resetSelection:(id)sender
{
    [self applySelectionStart:0 end:self.duration];
}

- (void)updateTimeUI
{
    double cur = self.trimView.playhead, s = self.trimView.startTime, e = self.trimView.endTime;
    self.timeLabel.stringValue = NSStr(vt::formatTime(cur) + " / " + vt::formatTime(self.duration));
    // Felder nicht überschreiben, während darin getippt wird
    if (!self.startField.currentEditor) self.startField.stringValue = NSStr(vt::formatTime(s));
    if (!self.endField.currentEditor)   self.endField.stringValue   = NSStr(vt::formatTime(e));
    self.selectionLabel.stringValue = NSStr("Dauer " + vt::formatTime(std::max(0.0, e - s)));
}

// Eingabe in den Zeitfeldern übernehmen
- (void)controlTextDidEndEditing:(NSNotification *)notification
{
    NSTextField *field = notification.object;
    if (field != self.startField && field != self.endField) return;

    auto parsed = vt::parseTime(field.stringValue.UTF8String);
    if (parsed && self.videoLoaded) {
        double t = std::clamp(*parsed, 0.0, self.duration);
        if (field == self.startField) {
            double e = self.trimView.endTime;
            if (t >= e - kMinSelection) e = self.duration;
            [self applySelectionStart:t end:e];
        } else {
            double s = self.trimView.startTime;
            if (t <= s + kMinSelection) s = 0;
            [self applySelectionStart:s end:t];
        }
        [self.player pause];
        [self seekTo:t];
    } else if (!parsed) {
        NSBeep();
    }
    [self updateTimeUI];

    NSInteger movement = [notification.userInfo[NSTextMovementUserInfoKey] integerValue];
    __weak __typeof__(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        // Nach Return den Fokus abgeben (damit Leertaste/Pfeile wieder die Wiedergabe steuern)
        if (movement == NSTextMovementReturn) [weakSelf.window makeFirstResponder:nil];
        [weakSelf updateTimeUI];   // Feld auf das normierte Format bringen, sobald der Editor weg ist
    });
}

#pragma mark - TrimViewDelegate

- (void)trimViewDidBeginInteraction:(TrimView *)view { [self.player pause]; }
- (void)trimView:(TrimView *)view didScrubToTime:(double)time { [self seekTo:time]; }
- (void)trimView:(TrimView *)view didChangeStart:(double)start end:(double)end { [self updateTimeUI]; }

- (void)trimViewDidEndInteraction:(TrimView *)view
{
    [self installBoundaryObserver];
    [self updateTimeUI];
}

- (void)trimViewDidResize:(TrimView *)view
{
    if (!self.videoLoaded) return;
    NSUInteger n = [view thumbnailCountForAspect:self.videoAspect];
    if (n > 0 && n != self.thumbCount) [self generateThumbnails];
}

#pragma mark - Export

- (void)modeChanged:(id)sender
{
    [NSUserDefaults.standardUserDefaults setBool:(self.modePopup.indexOfSelectedItem == 1) forKey:kReencodeKey];
}

- (void)exportSelection:(id)sender
{
    [self exportRangeStart:self.trimView.startTime end:self.trimView.endTime];
}

- (void)exportFromHere:(id)sender
{
    if (!self.videoLoaded) return;
    [self applySelectionStart:self.trimView.playhead end:self.duration];
    [self exportRangeStart:self.trimView.startTime end:self.trimView.endTime];
}

- (void)exportToHere:(id)sender
{
    if (!self.videoLoaded) return;
    [self applySelectionStart:0 end:self.trimView.playhead];
    [self exportRangeStart:self.trimView.startTime end:self.trimView.endTime];
}

- (void)exportRangeStart:(double)start end:(double)end
{
    if (!self.videoLoaded || self.exporter) return;
    if (end - start < kMinSelection) { NSBeep(); return; }
    [self.player pause];

    BOOL reencode = self.modePopup.indexOfSelectedItem == 1;
    Exporter *exporter = [[Exporter alloc] initWithAsset:self.asset reencode:reencode];
    if (!exporter) {
        [self showErrorTitle:@"Export nicht möglich"
                     message:@"AVFoundation kann dieses Video in diesem Modus nicht exportieren. "
                             @"Bitte den anderen Export-Modus versuchen."];
        return;
    }

    NSString *base = self.currentURL.lastPathComponent.stringByDeletingPathExtension;
    NSString *name = [NSString stringWithFormat:@"%@_%s-%s.%@", base,
                      vt::formatTimeForFilename(start).c_str(), vt::formatTimeForFilename(end).c_str(),
                      exporter.preferredExtension];

    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.title = @"Geschnittenes Video sichern";
    panel.nameFieldStringValue = name;
    panel.directoryURL = self.currentURL.URLByDeletingLastPathComponent;
    panel.allowedContentTypes = @[exporter.outputType];
    panel.canCreateDirectories = YES;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK || !panel.URL) return;
        NSURL *url = panel.URL;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self runExporter:exporter toURL:url start:start end:end];
        });
    }];
}

- (void)runExporter:(Exporter *)exporter toURL:(NSURL *)url start:(double)start end:(double)end
{
    self.exporter = exporter;
    [self setVideoControlsEnabled:NO];
    self.progressLabel.stringValue = [NSString stringWithFormat:@"Exportiere %@  (%s – %s) …",
                                      url.lastPathComponent, vt::formatTime(start).c_str(), vt::formatTime(end).c_str()];
    self.progressBar.doubleValue = 0;
    [self.window beginSheet:self.progressSheet completionHandler:nil];

    __weak __typeof__(self) weakSelf = self;
    self.progressTimer = [NSTimer scheduledTimerWithTimeInterval:0.15 repeats:YES block:^(NSTimer *timer) {
        weakSelf.progressBar.doubleValue = exporter.progress * 100.0;
    }];
    [exporter exportToURL:url start:start end:end completion:^(NSError *error, BOOL cancelled) {
        [weakSelf exportFinishedToURL:url error:error cancelled:cancelled];
    }];
}

- (void)cancelExport:(id)sender
{
    [self.exporter cancel];
}

- (void)exportFinishedToURL:(NSURL *)url error:(NSError *)error cancelled:(BOOL)cancelled
{
    [self.progressTimer invalidate];
    self.progressTimer = nil;
    self.exporter = nil;
    [self.window endSheet:self.progressSheet];
    [self setVideoControlsEnabled:self.videoLoaded];

    if (cancelled) {
        [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
        return;
    }
    if (error) {
        [self showErrorTitle:@"Export fehlgeschlagen" message:error.localizedDescription];
        return;
    }
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText = @"Export abgeschlossen";
    a.informativeText = url.path;
    [a addButtonWithTitle:@"OK"];
    [a addButtonWithTitle:@"Im Finder zeigen"];
    [a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
        if (r == NSAlertSecondButtonReturn) [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[url]];
    }];
}

- (void)showErrorTitle:(NSString *)title message:(NSString *)message
{
    NSAlert *a = [[NSAlert alloc] init];
    a.alertStyle = NSAlertStyleWarning;
    a.messageText = title;
    a.informativeText = message ?: @"";
    [a beginSheetModalForWindow:self.window completionHandler:nil];
}

#pragma mark - Debug: Fensterinhalt als PNG sichern (VT_SNAPSHOT=/pfad.png)

- (void)scheduleSnapshotIfRequested
{
    NSDictionary *env = NSProcessInfo.processInfo.environment;
    NSString *path = env[@"VT_SNAPSHOT"];
    if (path.length == 0) return;
    NSString *delayStr = env[@"VT_SNAPSHOT_DELAY"];
    double delay = delayStr.length ? delayStr.doubleValue : 2.0;
    NSString *size = env[@"VT_WINDOW_SIZE"];   // z. B. "880x560"
    NSArray<NSString *> *parts = [size componentsSeparatedByString:@"x"];
    if (parts.count == 2) [self.window setContentSize:NSMakeSize(parts[0].doubleValue, parts[1].doubleValue)];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSView *v = self.window.contentView;
        NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
        [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        [png writeToFile:path atomically:YES];
        [NSApp terminate:nil];
    });
}

@end
