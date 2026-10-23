// mkicon.mm — zeichnet das App-Icon vektoriell und schreibt ein .iconset (plus Vorschau-PNG).
//   mkicon <iconset-ordner> [vorschau.png]
#import <Cocoa/Cocoa.h>
#include <cmath>
#include <cstdio>

static const CGFloat CANVAS = 1024;

static NSColor *Hex(unsigned rgb, CGFloat a = 1.0)
{
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0
                                blue:(rgb & 0xFF) / 255.0 alpha:a];
}

static NSBezierPath *Star4(NSPoint c, CGFloat r)
{
    // Vierzackiger „Funkel“-Stern
    NSBezierPath *p = [NSBezierPath bezierPath];
    const CGFloat k = 0.22;
    NSPoint pts[8] = {
        {c.x, c.y + r}, {c.x + r * k, c.y + r * k}, {c.x + r, c.y}, {c.x + r * k, c.y - r * k},
        {c.x, c.y - r}, {c.x - r * k, c.y - r * k}, {c.x - r, c.y}, {c.x - r * k, c.y + r * k},
    };
    [p moveToPoint:pts[0]];
    for (int i = 1; i < 8; ++i) [p lineToPoint:pts[i]];
    [p closePath];
    return p;
}

static NSFont *HeavyFont(CGFloat size)
{
    for (NSString *name in @[@"AvenirNextCondensed-Heavy", @"AvenirNext-Heavy", @"HelveticaNeue-CondensedBlack", @"Helvetica-Bold"]) {
        NSFont *f = [NSFont fontWithName:name size:size];
        if (f) return f;
    }
    return [NSFont boldSystemFontOfSize:size];
}

// Zeichnet das Icon in ein 1024×1024-Koordinatensystem. `px` steuert nur Detailreduktion bei kleinen Größen.
static void DrawIcon(CGFloat px)
{
    const BOOL small = px < 64;
    const CGFloat inset = 100;                                   // Apple-Rastermaß: 824 px Inhalt auf 1024
    NSRect iconRect = NSMakeRect(inset, inset, CANVAS - 2 * inset, CANVAS - 2 * inset);
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:iconRect xRadius:185 yRadius:185];

    // Weicher Schatten unter dem Icon (wie bei Systemsymbolen)
    [NSGraphicsContext saveGraphicsState];
    NSShadow *drop = [[NSShadow alloc] init];
    drop.shadowColor = [NSColor colorWithWhite:0 alpha:0.35];
    drop.shadowBlurRadius = 24;
    drop.shadowOffset = NSMakeSize(0, -12);
    [drop set];
    [Hex(0x1A1038) setFill];
    [shape fill];
    [NSGraphicsContext restoreGraphicsState];

    [NSGraphicsContext saveGraphicsState];
    [shape addClip];

    // Hintergrund: tiefes Indigo → Violett → Magenta, diagonal
    NSGradient *bg = [[NSGradient alloc] initWithColorsAndLocations:
                      Hex(0x120B2E), 0.0, Hex(0x3A1C8F), 0.55, Hex(0xB22C8A), 1.0, nil];
    [bg drawInRect:iconRect angle:-35];

    // Leuchtender Schein unten links
    NSGradient *glow = [[NSGradient alloc] initWithStartingColor:Hex(0x8B5CF6, 0.55) endingColor:Hex(0x8B5CF6, 0.0)];
    [glow drawFromCenter:NSMakePoint(330, 330) radius:0 toCenter:NSMakePoint(330, 330) radius:520 options:0];

    // Filmstreifen, leicht gekippt
    NSAffineTransform *tilt = [NSAffineTransform transform];
    [tilt translateXBy:CANVAS / 2 yBy:CANVAS / 2];
    [tilt rotateByDegrees:-12];
    [tilt translateXBy:-CANVAS / 2 yBy:-CANVAS / 2];
    [tilt concat];

    const CGFloat cy = CANVAS / 2;
    const CGFloat stripH = 420;
    NSRect strip = NSMakeRect(-300, cy - stripH / 2, CANVAS + 600, stripH);

    // Streifen mit ausgestanzten Perforationslöchern (Even-Odd)
    NSBezierPath *film = [NSBezierPath bezierPathWithRect:strip];
    const CGFloat holeW = 46, holeH = 34, pitch = 96, holeInset = 22;
    for (CGFloat x = -280; x < CANVAS + 300; x += pitch) {
        [film appendBezierPathWithRoundedRect:NSMakeRect(x, NSMaxY(strip) - holeInset - holeH, holeW, holeH) xRadius:7 yRadius:7];
        [film appendBezierPathWithRoundedRect:NSMakeRect(x, NSMinY(strip) + holeInset, holeW, holeH) xRadius:7 yRadius:7];
    }
    film.windingRule = NSWindingRuleEvenOdd;
    [NSGraphicsContext saveGraphicsState];
    NSShadow *filmShadow = [[NSShadow alloc] init];
    filmShadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.5];
    filmShadow.shadowBlurRadius = 30;
    filmShadow.shadowOffset = NSMakeSize(0, -10);
    [filmShadow set];
    [Hex(0x14101F) setFill];
    [film fill];
    [NSGraphicsContext restoreGraphicsState];

    // Bildfenster
    const CGFloat frameH = 232, frameW = 236, gap = 20;
    const NSRect sel = NSMakeRect(cy - 352, cy - frameH / 2, 704, frameH);   // Auswahlbereich (mittig)
    NSGradient *dim = [[NSGradient alloc] initWithStartingColor:Hex(0x2B2347) endingColor:Hex(0x1C1733)];
    NSGradient *vivid = [[NSGradient alloc] initWithColorsAndLocations:
                         Hex(0xFF9F43), 0.0, Hex(0xFF3D81), 0.5, Hex(0x7C3AED), 1.0, nil];
    const CGFloat startX = cy - 352 - (frameW + gap) * 3;      // so dass Auswahl genau 3 Bilder fasst? nein: Auswahl ist eigener Rahmen
    for (CGFloat x = startX; x < CANVAS + 300; x += frameW + gap) {
        NSRect fr = NSMakeRect(x, cy - frameH / 2, frameW, frameH);
        NSBezierPath *fp = [NSBezierPath bezierPathWithRoundedRect:fr xRadius:10 yRadius:10];
        BOOL inside = NSMidX(fr) > NSMinX(sel) && NSMidX(fr) < NSMaxX(sel);
        [(inside ? vivid : dim) drawInBezierPath:fp angle:-30];
    }
    // Auswahlbereich als durchgehendes, leuchtendes Bild überlagern
    NSBezierPath *selPath = [NSBezierPath bezierPathWithRoundedRect:sel xRadius:12 yRadius:12];
    [vivid drawInBezierPath:selPath angle:-30];
    NSGradient *gloss = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithWhite:1 alpha:0.22]
                                                      endingColor:[NSColor colorWithWhite:1 alpha:0.0]];
    [gloss drawInBezierPath:selPath angle:-90];

    // Schriftzug im ausgewählten Clip
    if (!small) {
        NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
        ps.alignment = NSTextAlignmentCenter;
        NSShadow *ts = [[NSShadow alloc] init];
        ts.shadowColor = [NSColor colorWithWhite:0 alpha:0.45];
        ts.shadowBlurRadius = 14;
        ts.shadowOffset = NSMakeSize(0, -6);
        NSDictionary *attrs = @{ NSFontAttributeName: HeavyFont(196),
                                 NSForegroundColorAttributeName: NSColor.whiteColor,
                                 NSKernAttributeName: @(-2),
                                 NSParagraphStyleAttributeName: ps,
                                 NSShadowAttributeName: ts };
        NSAttributedString *word = [[NSAttributedString alloc] initWithString:@"argvis" attributes:attrs];
        NSSize ws = word.size;
        [word drawInRect:NSMakeRect(NSMinX(sel), NSMidY(sel) - ws.height / 2 + 6, NSWidth(sel), ws.height)];
    }

    // Gelber Trim-Rahmen mit Griffen (Even-Odd: außen abgerundet, innen ausgespart)
    const CGFloat bar = 18, handleW = 64;
    NSRect outer = NSInsetRect(sel, -handleW, -bar);
    NSBezierPath *frame = [NSBezierPath bezierPathWithRoundedRect:outer xRadius:34 yRadius:34];
    [frame appendBezierPathWithRoundedRect:sel xRadius:10 yRadius:10];
    frame.windingRule = NSWindingRuleEvenOdd;
    [NSGraphicsContext saveGraphicsState];
    NSShadow *yglow = [[NSShadow alloc] init];
    yglow.shadowColor = Hex(0xFFD60A, 0.85);
    yglow.shadowBlurRadius = small ? 10 : 44;
    yglow.shadowOffset = NSZeroSize;
    [yglow set];
    [Hex(0xFFD60A) setFill];
    [frame fill];
    [NSGraphicsContext restoreGraphicsState];
    [Hex(0xFFD60A) setFill];
    [frame fill];
    NSGradient *ygloss = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithWhite:1 alpha:0.35]
                                                       endingColor:[NSColor colorWithWhite:1 alpha:0.0]];
    [ygloss drawInBezierPath:frame angle:-90];

    // Griff-Symbole ‹ ›
    NSBezierPath *chev = [NSBezierPath bezierPath];
    chev.lineWidth = 12;
    chev.lineCapStyle = NSLineCapStyleRound;
    chev.lineJoinStyle = NSLineJoinStyleRound;
    CGFloat lc = NSMinX(outer) + handleW / 2, rc = NSMaxX(outer) - handleW / 2, my = NSMidY(sel);
    [chev moveToPoint:NSMakePoint(lc + 12, my - 30)];
    [chev lineToPoint:NSMakePoint(lc - 12, my)];
    [chev lineToPoint:NSMakePoint(lc + 12, my + 30)];
    [chev moveToPoint:NSMakePoint(rc - 12, my - 30)];
    [chev lineToPoint:NSMakePoint(rc + 12, my)];
    [chev lineToPoint:NSMakePoint(rc - 12, my + 30)];
    [Hex(0x3B2A00, 0.85) setStroke];
    [chev stroke];

    // Abspielmarke im Clip
    NSRect ph = NSMakeRect(NSMinX(sel) + NSWidth(sel) * 0.905 - 5, NSMinY(sel) + 10, 10, NSHeight(sel) - 20);
    [NSGraphicsContext saveGraphicsState];
    NSShadow *wglow = [[NSShadow alloc] init];
    wglow.shadowColor = [NSColor colorWithWhite:1 alpha:0.9];
    wglow.shadowBlurRadius = 18;
    wglow.shadowOffset = NSZeroSize;
    [wglow set];
    [NSColor.whiteColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:ph xRadius:5 yRadius:5] fill];
    [NSGraphicsContext restoreGraphicsState];

    // Funkeln
    if (!small) {
        [NSGraphicsContext saveGraphicsState];
        NSShadow *sglow = [[NSShadow alloc] init];
        sglow.shadowColor = [NSColor colorWithWhite:1 alpha:0.9];
        sglow.shadowBlurRadius = 22;
        sglow.shadowOffset = NSZeroSize;
        [sglow set];
        [NSColor.whiteColor setFill];
        [Star4(NSMakePoint(NSMaxX(outer) + 10, NSMaxY(outer) + 150), 46) fill];
        [Star4(NSMakePoint(NSMaxX(outer) - 110, NSMaxY(outer) + 205), 20) fill];
        [Hex(0xFFD60A) setFill];
        [Star4(NSMakePoint(NSMinX(outer) + 30, NSMinY(outer) - 150), 30) fill];
        [NSGraphicsContext restoreGraphicsState];
    }

    [NSGraphicsContext restoreGraphicsState];   // Kippung + Clip zurück

    // Feiner heller Rand und oberer Glanz
    [NSGraphicsContext saveGraphicsState];
    [shape addClip];
    NSGradient *top = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithWhite:1 alpha:0.14]
                                                    endingColor:[NSColor colorWithWhite:1 alpha:0.0]];
    [top drawInRect:NSMakeRect(NSMinX(iconRect), NSMaxY(iconRect) - 300, NSWidth(iconRect), 300) angle:90];
    [NSGraphicsContext restoreGraphicsState];
    [[NSColor colorWithWhite:1 alpha:0.10] setStroke];
    shape.lineWidth = 3;
    [shape stroke];
}

static BOOL RenderPNG(CGFloat px, NSString *path)
{
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)px pixelsHigh:(NSInteger)px
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    rep.size = NSMakeSize(px, px);
    NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = ctx;
    ctx.imageInterpolation = NSImageInterpolationHigh;
    NSAffineTransform *scale = [NSAffineTransform transform];
    [scale scaleBy:px / CANVAS];
    [scale concat];
    DrawIcon(px);
    [ctx flushGraphics];
    [NSGraphicsContext restoreGraphicsState];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return [png writeToFile:path atomically:YES];
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc < 2) { std::fprintf(stderr, "mkicon <iconset-ordner> [vorschau.png]\n"); return 2; }
        NSString *dir = [NSString stringWithUTF8String:argv[1]];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        struct { int base; int scale; } entries[] = {
            {16, 1}, {16, 2}, {32, 1}, {32, 2}, {128, 1}, {128, 2}, {256, 1}, {256, 2}, {512, 1}, {512, 2},
        };
        for (auto &e : entries) {
            NSString *name = e.scale == 1 ? [NSString stringWithFormat:@"icon_%dx%d.png", e.base, e.base]
                                          : [NSString stringWithFormat:@"icon_%dx%d@2x.png", e.base, e.base];
            if (!RenderPNG(e.base * e.scale, [dir stringByAppendingPathComponent:name])) {
                std::fprintf(stderr, "Konnte %s nicht schreiben\n", name.UTF8String);
                return 1;
            }
        }
        if (argc > 2) RenderPNG(1024, [NSString stringWithUTF8String:argv[2]]);
        std::printf("Iconset geschrieben: %s\n", dir.UTF8String);
    }
    return 0;
}
