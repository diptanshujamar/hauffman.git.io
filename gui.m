#import <Cocoa/Cocoa.h>
#include "compression.h"
#include <math.h>

@interface FlippedView : NSView @end
@implementation FlippedView
- (BOOL)isFlipped { return YES; }
@end

/* ---------- Compact Tree View ---------- */
@interface TreeCanvasView : NSView
@property (nonatomic, assign) TreeNode *root;
@property (nonatomic, assign) double gap, startX;
@end

@implementation TreeCanvasView
- (BOOL)isFlipped { return YES; }

- (void)drawTree:(TreeNode *)n x:(double)x y:(double)y g:(double)gap {
    if (!n) return;
    double r = 18.0, ny = y + 65.0;

    if (n->left) {
        double lx = x - gap;
        [[NSColor colorWithCalibratedRed:0.35 green:0.48 blue:0.60 alpha:1] setStroke];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(x, y + r) toPoint:NSMakePoint(lx, ny - r)];
        [@"0" drawAtPoint:NSMakePoint((x + lx)/2.0 - 6, y + 28) withAttributes:@{
            NSFontAttributeName: [NSFont boldSystemFontOfSize:9],
            NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.18 green:0.35 blue:0.54 alpha:1]
        }];
        [self drawTree:n->left x:lx y:ny g:gap/2.0];
    }
    if (n->right) {
        double rx = x + gap;
        [[NSColor colorWithCalibratedRed:0.35 green:0.48 blue:0.60 alpha:1] setStroke];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(x, y + r) toPoint:NSMakePoint(rx, ny - r)];
        [@"1" drawAtPoint:NSMakePoint((x + rx)/2.0 + 6, y + 28) withAttributes:@{
            NSFontAttributeName: [NSFont boldSystemFontOfSize:9],
            NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.18 green:0.35 blue:0.54 alpha:1]
        }];
        [self drawTree:n->right x:rx y:ny g:gap/2.0];
    }

    NSRect cr = NSMakeRect(x - r, y - r, 2*r, 2*r);
    NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:cr];
    [circle setLineWidth:2.0];

    if (n->is_leaf) {
        [[NSColor colorWithCalibratedRed:1.0 green:0.90 blue:0.40 alpha:1] setFill];
        [[NSColor colorWithCalibratedRed:0.79 green:0.63 blue:0.0 alpha:1] setStroke];
        [circle fill]; [circle stroke];
        NSString *s = strcmp(n->sym, " ") == 0 ? @"sp" : [NSString stringWithUTF8String:n->sym];
        NSDictionary *a = @{NSFontAttributeName: [NSFont boldSystemFontOfSize:11]};
        NSSize sz = [s sizeWithAttributes:a];
        [s drawAtPoint:NSMakePoint(x - sz.width/2.0, y - sz.height/2.0) withAttributes:a];
    } else {
        [[NSColor colorWithCalibratedRed:0.84 green:0.92 blue:0.97 alpha:1] setFill];
        [[NSColor colorWithCalibratedRed:0.16 green:0.50 blue:0.73 alpha:1] setStroke];
        [circle fill]; [circle stroke];
        [@"*" drawAtPoint:NSMakePoint(x - 4, y - 7) withAttributes:@{
            NSFontAttributeName: [NSFont boldSystemFontOfSize:11],
            NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.10 green:0.32 blue:0.46 alpha:1]
        }];
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor colorWithCalibratedRed:0.98 green:0.99 blue:1.0 alpha:1] setFill];
    NSRectFill(dirtyRect);
    if (self.root) [self drawTree:self.root x:self.startX y:30.0 g:self.gap];
}
@end

/* ---------- Application Controller ---------- */
@interface DMApp : NSObject <NSApplicationDelegate>
@property (strong) NSWindow *mainWin, *treeWin;
@property (strong) NSTextField *inputField;
@property (strong) NSTextView *outputView;
@property (strong) TreeCanvasView *huffCanvas, *sfCanvas;
@property (nonatomic, assign) TreeNode *huffRoot, *sfRoot;
@end

static CodeTable last_huff_tbl, last_sf_tbl;

@implementation DMApp

- (void)measure:(TreeNode *)n x:(double)x y:(double)y g:(double)g mx:(double *)mx my:(double *)my {
    if (!n) return;
    if (x > *mx) *mx = x;
    if (y > *my) *my = y;
    if (n->left)  [self measure:n->left x:x - g y:y + 65.0 g:g/2.0 mx:mx my:my];
    if (n->right) [self measure:n->right x:x + g y:y + 65.0 g:g/2.0 mx:mx my:my];
}

- (void)setupCanvas:(TreeCanvasView *)cv withTree:(TreeNode *)r {
    cv.root = r;
    if (!r) { [cv setFrameSize:NSMakeSize(964, 280)]; return; }
    int d = get_tree_depth(r);
    double gap = d > 1 ? 30.0 * pow(2.0, d - 2) : 40.0;
    if (gap < 80.0) gap = 80.0; if (gap > 260.0) gap = 260.0;
    double sx = gap * 2.0, mx = sx, my = 30.0;
    [self measure:r x:sx y:30.0 g:gap mx:&mx my:&my];
    cv.gap = gap; cv.startX = sx;
    [cv setFrameSize:NSMakeSize(MAX(mx + gap * 2.0, 964.0), MAX(my + 60.0, 280.0))];
    [cv setNeedsDisplay:YES];
}

- (void)runCompress:(id)sender {
    (void)sender;
    NSString *inStr = [self.inputField stringValue];
    const char *txt = [inStr UTF8String];
    if (!txt || !txt[0]) { txt = "discrete mathematics"; [self.inputField setStringValue:@"discrete mathematics"]; }

    int n = get_frequencies(txt, &last_huff_tbl);
    get_frequencies(txt, &last_sf_tbl);

    char hbin[8192] = {0}, sfbin[8192] = {0}, hdec[2048] = {0}, sfdec[2048] = {0};
    huffman_encode(txt, &last_huff_tbl, hbin, sizeof(hbin));
    shannon_fano_encode(txt, &last_sf_tbl, sfbin, sizeof(sfbin));
    decode_bitstream(hbin, &last_huff_tbl, hdec, sizeof(hdec));
    decode_bitstream(sfbin, &last_sf_tbl, sfdec, sizeof(sfdec));

    double H = get_entropy(&last_huff_tbl, n);
    double Lh = get_average_length(&last_huff_tbl, n);
    double Lsf = get_average_length(&last_sf_tbl, n);
    int hb = (int)strlen(hbin), sb = (int)strlen(sfbin);

    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"Original: %s (%d chars)\n\n", txt, n];
    [out appendString:@"--- Generated Codes & Bit Lengths ---\n"];
    [out appendString:@"Char     | Count | Prob  | Huff Code  | Bits | Huff p*L | SF Code    | Bits | SF p*L\n"];
    [out appendString:@"--------------------------------------------------------------------------------\n"];

    for (int i = 0; i < last_huff_tbl.count; i++) {
        double p = (double)last_huff_tbl.items[i].count / n;
        int hl = (int)strlen(last_huff_tbl.items[i].code), sl = (int)strlen(last_sf_tbl.items[i].code);
        const char *sym = strcmp(last_huff_tbl.items[i].sym, " ") == 0 ? "space" : last_huff_tbl.items[i].sym;
        [out appendFormat:@"%-8s | %-5d | %-5.3f | %-10s | %-4d | %-8.3f | %-10s | %-4d | %-8.3f\n",
         sym, last_huff_tbl.items[i].count, p, last_huff_tbl.items[i].code, hl, p*hl, last_sf_tbl.items[i].code, sl, p*sl];
    }

    [out appendFormat:@"\nHuffman Binary:      %s\n", hbin];
    [out appendFormat:@"Shannon-Fano Binary: %s\n", sfbin];
    [out appendFormat:@"Huffman Decoded:      %s\n", hdec];
    [out appendFormat:@"Shannon-Fano Decoded: %s\n\n", sfdec];

    [out appendFormat:@"--- Discrete Mathematics Summary ---\n"];
    [out appendFormat:@"Original Size: %d bits | Huffman: %d bits | Shannon-Fano: %d bits\n", n * 8, hb, sb];
    [out appendFormat:@"Entropy H(X):    %.3f bits/symbol (Theoretical lower bound)\n", H];
    [out appendFormat:@"Huffman Avg L:   %.3f bits/symbol (Efficiency: %.2f%%)\n", Lh, (H/Lh)*100];
    [out appendFormat:@"Shannon-Fano L:  %.3f bits/symbol (Efficiency: %.2f%%)\n", Lsf, (H/Lsf)*100];

    char d[256];
    check_prefix_free(&last_huff_tbl, d, sizeof(d));
    [out appendFormat:@"\nHuffman Prefix-Free: %s\n", d];
    check_prefix_free(&last_sf_tbl, d, sizeof(d));
    [out appendFormat:@"Shannon-Fano Prefix-Free: %s\n", d];

    [out appendString:@"\n--- Formulas & Data Structures Used ---\n"];
    [out appendString:@"* Huffman:      Min-Heap Priority Queue + Binary Prefix Tree (Optimal)\n"];
    [out appendString:@"* Shannon-Fano: Descending Sorted Array + Divide-and-Conquer Recursion\n"];
    [out appendString:@"* Entropy:      H(X) = -SUM [ p(x) * log2(p(x)) ]\n"];
    [out appendString:@"* Avg Length:   L    = SUM [ p(x) * length(code(x)) ]\n"];
    [out appendString:@"* Efficiency:   eta  = (H(X) / L) * 100%\n"];
    [out appendString:@"* Kraft Sum:    K    = SUM [ 2^(-l(x)) ] <= 1.0 (Satisfied)\n"];

    [self.outputView setString:out];
}

- (void)showTrees:(id)sender {
    (void)sender;
    if (last_huff_tbl.count == 0) { [self.outputView setString:@"Please click Compress Text first.\n"]; return; }
    if (self.huffRoot) free_tree(self.huffRoot);
    if (self.sfRoot) free_tree(self.sfRoot);
    self.huffRoot = build_tree_from_codes(&last_huff_tbl);
    self.sfRoot = build_tree_from_codes(&last_sf_tbl);
    [self setupCanvas:self.huffCanvas withTree:self.huffRoot];
    [self setupCanvas:self.sfCanvas withTree:self.sfRoot];
    [self.treeWin makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)checkCustom:(id)sender {
    (void)sender;
    NSAlert *a = [[NSAlert alloc] init];
    [a setMessageText:@"Test Custom Codes for Prefix-Free & Ambiguity"];
    [a setInformativeText:@"Enter pairs (e.g. 'A-10, B-00, C-01' or 'A=0, B=01, C=10'):"];
    [a addButtonWithTitle:@"Analyze"]; [a addButtonWithTitle:@"Cancel"];

    NSTextField *tf = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 420, 24)];
    [tf setStringValue:@"A-10, B-00, C-01"];
    [a setAccessoryView:tf];

    if ([a runModal] == NSAlertFirstButtonReturn) {
        CodeTable tbl;
        char err[128], d1[256], d2[256];
        if (!parse_custom_codes([[tf stringValue] UTF8String], &tbl, err, sizeof(err))) {
            NSAlert *ea = [[NSAlert alloc] init];
            [ea setMessageText:@"Syntax Error"]; [ea setInformativeText:[NSString stringWithUTF8String:err]];
            [ea runModal]; return;
        }

        int pf = check_prefix_free(&tbl, d1, sizeof(d1));
        int amb = check_ambiguity(&tbl, d2, sizeof(d2));
        double k = get_kraft_sum(&tbl);

        NSMutableString *rep = [NSMutableString stringWithFormat:@"=== CUSTOM CODE ANALYSIS ===\nInput: %@\n\n", [tf stringValue]];
        for (int i = 0; i < tbl.count; i++)
            [rep appendFormat:@"%-6s | %-12s | %d bits\n", tbl.items[i].sym, tbl.items[i].code, (int)strlen(tbl.items[i].code)];
        [rep appendFormat:@"\n[1] Prefix-Free Test: %s\n    Detail: %s\n", pf ? "PASSED" : "FAILED", d1];
        [rep appendFormat:@"[2] Ambiguity Test:   %s\n    Detail: %s\n", amb ? "AMBIGUOUS" : "UNAMBIGUOUS (Unique)", d2];
        [rep appendFormat:@"[3] Kraft Sum:        K = %.4f %s\n", k, k <= 1.000001 ? "(<= 1.0 Satisfied)" : "(> 1.0 Violated)"];

        [self.outputView setString:rep];

        NSAlert *ra = [[NSAlert alloc] init];
        [ra setMessageText:pf ? @"Prefix-Free & Unambiguous" : (amb ? @"Ambiguous Code Detected!" : @"Uniquely Decodable (Non-Prefix)")];
        [ra setInformativeText:[NSString stringWithFormat:@"Prefix-Free: %@\nAmbiguity: %@\nKraft Sum: %.4f\n\nReport copied to Output.",
                                pf ? @"YES" : @"NO", amb ? @"AMBIGUOUS" : @"UNAMBIGUOUS", k]];
        [ra runModal];
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)n {
    (void)n;
    NSColor *bg = [NSColor colorWithCalibratedRed:0.92 green:0.94 blue:0.97 alpha:1];

    self.mainWin = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 720, 620)
                                               styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable)
                                                 backing:NSBackingStoreBuffered defer:NO];
    [self.mainWin setTitle:@"Huffman vs Shannon-Fano & Code Analyzer"];
    [self.mainWin setBackgroundColor:bg];
    [self.mainWin center];

    FlippedView *cv = [[FlippedView alloc] initWithFrame:NSMakeRect(0, 0, 720, 620)];
    [self.mainWin setContentView:cv];

    NSTextField *t = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 12, 720, 24)];
    [t setStringValue:@"Huffman vs Shannon-Fano Coding & Prefix Analyzer"];
    [t setFont:[NSFont boldSystemFontOfSize:16]];
    [t setAlignment:NSTextAlignmentCenter]; [t setBezeled:NO]; [t setDrawsBackground:NO]; [t setEditable:NO];
    [t setTextColor:[NSColor blackColor]];
    [cv addSubview:t];

    NSTextField *sub = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 36, 720, 18)];
    [sub setStringValue:@"Discrete Mathematics Project  |  Compression & Ambiguity Suite"];
    [sub setFont:[NSFont systemFontOfSize:10]]; [sub setAlignment:NSTextAlignmentCenter];
    [sub setTextColor:[NSColor blackColor]]; [sub setBezeled:NO]; [sub setDrawsBackground:NO]; [sub setEditable:NO];
    [cv addSubview:sub];

    NSTextField *lbl = [[NSTextField alloc] initWithFrame:NSMakeRect(60, 66, 75, 20)];
    [lbl setStringValue:@"Enter text:"]; [lbl setBezeled:NO]; [lbl setDrawsBackground:NO]; [lbl setEditable:NO];
    [lbl setFont:[NSFont boldSystemFontOfSize:12]];
    [lbl setTextColor:[NSColor blackColor]];
    [cv addSubview:lbl];

    self.inputField = [[NSTextField alloc] initWithFrame:NSMakeRect(135, 64, 515, 24)];
    [self.inputField setStringValue:@"discrete mathematics"];
    [self.inputField setFont:[NSFont systemFontOfSize:12]];
    [self.inputField setTextColor:[NSColor blackColor]];
    [self.inputField setBackgroundColor:[NSColor whiteColor]];
    [cv addSubview:self.inputField];

    NSButton *b1 = [[NSButton alloc] initWithFrame:NSMakeRect(115, 96, 140, 32)];
    [b1 setTitle:@"Compress Text"]; [b1 setBezelStyle:NSBezelStyleRounded];
    [b1 setTarget:self]; [b1 setAction:@selector(runCompress:)]; [cv addSubview:b1];

    NSButton *b2 = [[NSButton alloc] initWithFrame:NSMakeRect(270, 96, 140, 32)];
    [b2 setTitle:@"Show Trees"]; [b2 setBezelStyle:NSBezelStyleRounded];
    [b2 setTarget:self]; [b2 setAction:@selector(showTrees:)]; [cv addSubview:b2];

    NSButton *b3 = [[NSButton alloc] initWithFrame:NSMakeRect(425, 96, 175, 32)];
    [b3 setTitle:@"Check Custom Code..."]; [b3 setBezelStyle:NSBezelStyleRounded];
    [b3 setTarget:self]; [b3 setAction:@selector(checkCustom:)]; [cv addSubview:b3];

    NSBox *box = [[NSBox alloc] initWithFrame:NSMakeRect(14, 134, 692, 472)];
    [box setTitle:@" Output & Analysis "];

    NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(6, 6, 678, 444)];
    [sv setHasVerticalScroller:YES]; [sv setHasHorizontalScroller:YES];
    self.outputView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 678, 444)];
    [self.outputView setFont:[NSFont fontWithName:@"Menlo" size:10] ?: [NSFont userFixedPitchFontOfSize:10]];
    [self.outputView setTextColor:[NSColor blackColor]];
    [self.outputView setBackgroundColor:[NSColor whiteColor]];
    [self.outputView setEditable:NO];
    [sv setDocumentView:self.outputView];
    [box setContentView:sv];
    [cv addSubview:box];

    // Tree Window
    self.treeWin = [[NSWindow alloc] initWithContentRect:NSMakeRect(150, 80, 980, 680)
                                               styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable)
                                                 backing:NSBackingStoreBuffered defer:NO];
    [self.treeWin setTitle:@"Decoding Trees"];
    FlippedView *tcv = [[FlippedView alloc] initWithFrame:NSMakeRect(0, 0, 980, 680)];
    [self.treeWin setContentView:tcv];

    NSTextField *nt = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 8, 980, 20)];
    [nt setStringValue:@"Yellow = Leaf Character  |  Blue = Internal Node (*)  |  0 = Left  |  1 = Right"];
    [nt setAlignment:NSTextAlignmentCenter]; [nt setBezeled:NO]; [nt setDrawsBackground:NO]; [nt setEditable:NO];
    [nt setTextColor:[NSColor blackColor]];
    [tcv addSubview:nt];

    NSTextField *tl1 = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 32, 980, 20)];
    [tl1 setStringValue:@"Huffman Tree"]; [tl1 setFont:[NSFont boldSystemFontOfSize:11]];
    [tl1 setAlignment:NSTextAlignmentCenter]; [tl1 setBezeled:NO]; [tl1 setDrawsBackground:NO]; [tl1 setEditable:NO];
    [tl1 setTextColor:[NSColor blackColor]];
    [tcv addSubview:tl1];

    NSScrollView *s1 = [[NSScrollView alloc] initWithFrame:NSMakeRect(8, 54, 964, 275)];
    [s1 setHasVerticalScroller:YES]; [s1 setHasHorizontalScroller:YES];
    self.huffCanvas = [[TreeCanvasView alloc] initWithFrame:NSMakeRect(0, 0, 964, 275)];
    [s1 setDocumentView:self.huffCanvas]; [tcv addSubview:s1];

    NSTextField *tl2 = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 340, 980, 20)];
    [tl2 setStringValue:@"Shannon-Fano Tree"]; [tl2 setFont:[NSFont boldSystemFontOfSize:11]];
    [tl2 setAlignment:NSTextAlignmentCenter]; [tl2 setBezeled:NO]; [tl2 setDrawsBackground:NO]; [tl2 setEditable:NO];
    [tl2 setTextColor:[NSColor blackColor]];
    [tcv addSubview:tl2];

    NSScrollView *s2 = [[NSScrollView alloc] initWithFrame:NSMakeRect(8, 362, 964, 275)];
    [s2 setHasVerticalScroller:YES]; [s2 setHasHorizontalScroller:YES];
    self.sfCanvas = [[TreeCanvasView alloc] initWithFrame:NSMakeRect(0, 0, 964, 275)];
    [s2 setDocumentView:self.sfCanvas]; [tcv addSubview:s2];

    [self.mainWin makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)s { return YES; }

- (void)dealloc {
    if (self.huffRoot) free_tree(self.huffRoot);
    if (self.sfRoot) free_tree(self.sfRoot);
    [super dealloc];
}
@end

int main(int argc, const char *argv[]) {
    (void)argc; (void)argv;
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        DMApp *delegate = [[DMApp alloc] init];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}
