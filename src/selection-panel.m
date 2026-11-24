// Selection Count — a floating panel that counts the text selected in any app.
//
// Reads the current selection through the Accessibility API, so it needs
// Accessibility permission (System Settings › Privacy & Security › Accessibility).
// Nothing is logged, stored, or sent anywhere.
//
// Build:  bash tools/build-selection-panel.sh
// Check:  SelectionCount --count-stdin    JSON counts for piped text
//         SelectionCount --selftest       counting rules
//         SelectionCount --check-access   is Accessibility granted?

#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>

// MARK: - counting (same rules as src/count-core.cjs)

typedef struct {
    NSUInteger cjk;
    NSUInteger words;
    NSUInteger chars;
    NSUInteger charsNoSpace;
} Counts;

static NSRegularExpression *TokenRegex(void) {
    static NSRegularExpression *regex = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *pattern = @"\\p{Script=Han}|\\p{Script=Hiragana}|\\p{Script=Katakana}|\\p{Script=Hangul}|"
                            @"\\p{Script=Bopomofo}|\\p{Nd}+(?:[.,]\\p{Nd}+)*|"
                            @"[\\p{L}\\p{N}\\p{M}]+(?:['\u2019\\-\u2010\u2011_][\\p{L}\\p{N}\\p{M}]+)*";
        regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
    });
    return regex;
}

static NSRegularExpression *CjkRegex(void) {
    static NSRegularExpression *regex = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *pattern = @"[\\p{Script=Han}\\p{Script=Hiragana}\\p{Script=Katakana}\\p{Script=Hangul}\\p{Script=Bopomofo}]";
        regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
    });
    return regex;
}

static Counts CountText(NSString *text) {
    __block Counts counts = {0, 0, 0, 0};
    NSUInteger length = text.length;

    [TokenRegex() enumerateMatchesInString:text options:0 range:NSMakeRange(0, length)
                                    usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
        NSString *token = [text substringWithRange:match.range];
        if (token.length == 1 && [CjkRegex() firstMatchInString:token options:0 range:NSMakeRange(0, 1)]) {
            counts.cjk++;
        } else {
            counts.words++;
        }
    }];

    for (NSUInteger index = 0; index < length; index++) {
        unichar unit = [text characterAtIndex:index];
        if (unit != 10 && unit != 13) counts.chars++;
        switch (unit) {
            case 32: case 9: case 10: case 13: case 0xA0: case 0x3000:
                break;
            default:
                counts.charsNoSpace++;
                break;
        }
    }
    return counts;
}

// MARK: - Accessibility

static BOOL AccessibilityGranted(BOOL prompt) {
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @(prompt)};
    return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}

static NSString *SelectedText(void) {
    AXUIElementRef system = AXUIElementCreateSystemWide();
    if (!system) return nil;

    CFTypeRef focused = NULL;
    if (AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute, &focused) != kAXErrorSuccess || !focused) {
        CFRelease(system);
        return nil;
    }

    CFTypeRef value = NULL;
    AXError error = AXUIElementCopyAttributeValue((AXUIElementRef)focused, kAXSelectedTextAttribute, &value);
    CFRelease(focused);
    CFRelease(system);

    if (error != kAXErrorSuccess || !value) return nil;
    if (CFGetTypeID(value) != CFStringGetTypeID()) {
        CFRelease(value);
        return nil;
    }
    NSString *text = [(__bridge NSString *)value copy];
    CFRelease(value);
    return text.length > 0 ? text : nil;
}

static void WriteStatus(NSString *state) {
    static NSString *lastState = nil;
    if (lastState && [lastState isEqualToString:state]) return;
    NSString *base = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [base stringByAppendingPathComponent:@"DocxWordCount"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *path = [dir stringByAppendingPathComponent:@"panel-status.txt"];
    [state writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    lastState = state;
}

// MARK: - panel

@interface FloatingPanel : NSPanel
@end

@implementation FloatingPanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@interface CounterPanel : NSObject
- (void)showHeadline:(NSString *)headline detail:(NSString *)detail warning:(BOOL)warning;
- (void)hide;
@end

@implementation CounterPanel {
    FloatingPanel *_panel;
    NSTextField *_headlineLabel;
    NSTextField *_detailLabel;
}

static const CGFloat PanelWidth = 360;
static const CGFloat PanelHeight = 56;

- (instancetype)init {
    if ((self = [super init])) {
        _panel = [[FloatingPanel alloc] initWithContentRect:NSMakeRect(0, 0, PanelWidth, PanelHeight)
                                                  styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
        _panel.level = NSFloatingWindowLevel;
        _panel.opaque = NO;
        _panel.backgroundColor = [NSColor colorWithCalibratedWhite:0 alpha:0.78];
        _panel.hasShadow = YES;
        _panel.ignoresMouseEvents = YES;
        _panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                    NSWindowCollectionBehaviorFullScreenAuxiliary |
                                    NSWindowCollectionBehaviorStationary;

        _headlineLabel = [CounterPanel labelWithSize:13 color:[NSColor whiteColor]];
        _detailLabel = [CounterPanel labelWithSize:11
                                            color:[NSColor colorWithCalibratedRed:1 green:0.85 blue:0.3 alpha:1]];
        [_panel.contentView addSubview:_headlineLabel];
        [_panel.contentView addSubview:_detailLabel];
        [self positionBottomRight];
    }
    return self;
}

+ (NSTextField *)labelWithSize:(CGFloat)size color:(NSColor *)color {
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
    label.editable = NO;
    label.selectable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.textColor = color;
    label.font = [NSFont systemFontOfSize:size];
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.usesSingleLineMode = YES;
    label.cell.wraps = NO;
    return label;
}

- (void)positionBottomRight {
    NSScreen *screen = [NSScreen mainScreen];
    if (!screen) return;
    NSRect visible = screen.visibleFrame;
    NSRect frame = NSMakeRect(visible.origin.x + visible.size.width - PanelWidth - 16,
                              visible.origin.y + 72,
                              PanelWidth,
                              PanelHeight);
    [_panel setFrame:frame display:NO];
}

- (void)showHeadline:(NSString *)headline detail:(NSString *)detail warning:(BOOL)warning {
    _headlineLabel.stringValue = headline;
    _headlineLabel.textColor = warning ? [NSColor colorWithCalibratedRed:1 green:0.45 blue:0.45 alpha:1]
                                       : [NSColor whiteColor];
    _headlineLabel.frame = NSMakeRect(12, PanelHeight - 30, PanelWidth - 24, 20);
    _detailLabel.stringValue = detail;
    _detailLabel.frame = NSMakeRect(12, 10, PanelWidth - 24, 18);
    if (!_panel.isVisible) [self positionBottomRight];
    [_panel orderFrontRegardless];
}

- (void)hide {
    [_panel orderOut:nil];
}

@end

// MARK: - app

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation AppDelegate {
    CounterPanel *_counter;
    NSTimer *_timer;
    NSString *_lastSelection;
    NSUInteger _emptyTicks;
    BOOL _warned;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    _counter = [[CounterPanel alloc] init];
    _lastSelection = @"";
    AccessibilityGranted(YES);

    [self tick];
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.35 repeats:YES block:^(NSTimer *timer) {
        [self tick];
    }];
    [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (void)tick {
    if (!AccessibilityGranted(NO)) {
        WriteStatus(@"no-accessibility");
        if (!_warned) {
            _warned = YES;
            [_counter showHeadline:@"需要在「辅助功能」里勾选 SelectionCount"
                            detail:@"系统设置 › 隐私与安全性 › 辅助功能"
                           warning:YES];
        }
        return;
    }
    WriteStatus(@"ok");
    if (_warned) {
        _warned = NO;
        [_counter hide];
    }

    NSString *text = SelectedText();
    if (!text) {
        _emptyTicks++;
        if (_emptyTicks >= 3) {
            [_counter hide];
            _lastSelection = @"";
        }
        return;
    }
    _emptyTicks = 0;
    if ([text isEqualToString:_lastSelection]) return;
    _lastSelection = text;

    Counts counts = CountText(text);
    [_counter showHeadline:[NSString stringWithFormat:@"选中: 中 %lu字 英 %lu词 | 共 %lu",
                                                       (unsigned long)counts.cjk,
                                                       (unsigned long)counts.words,
                                                       (unsigned long)(counts.cjk + counts.words)]
                    detail:[NSString stringWithFormat:@"字符数 %lu（不计空格）／%lu（含空格）",
                                                       (unsigned long)counts.charsNoSpace,
                                                       (unsigned long)counts.chars]
                   warning:NO];
}

@end

// MARK: - command line helpers

static NSString *ReadStandardInput(void) {
    NSFileHandle *input = [NSFileHandle fileHandleWithStandardInput];
    NSData *data = [input readDataToEndOfFile];
    if (!data) return @"";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

static int RunSelfTest(void) {
    NSArray<NSArray *> *cases = @[
        @[@"", @0, @0],
        @[@"你好 world 42", @2, @2],
        @[@"state-of-the-art", @0, @1],
        @[@"1,000 apples", @0, @2],
        @[@"café naïve", @0, @2],
        @[@"你好world", @2, @1],
        @[@"don't stop", @0, @2],
        @[@"今天天气不错，我去跑步了。", @11, @0]
    ];
    NSUInteger failures = 0;
    for (NSArray *testCase in cases) {
        NSString *text = testCase[0];
        NSUInteger wantCjk = [testCase[1] unsignedIntegerValue];
        NSUInteger wantWords = [testCase[2] unsignedIntegerValue];
        Counts counts = CountText(text);
        BOOL ok = counts.cjk == wantCjk && counts.words == wantWords;
        if (!ok) failures++;
        printf("%s  \"%s\" cjk=%lu words=%lu\n",
               ok ? "PASS" : "FAIL",
               text.UTF8String,
               (unsigned long)counts.cjk,
               (unsigned long)counts.words);
    }
    printf("%s\n", failures == 0
        ? [[NSString stringWithFormat:@"selftest: all %lu cases passed", (unsigned long)cases.count] UTF8String]
        : [[NSString stringWithFormat:@"selftest: %lu failed", (unsigned long)failures] UTF8String]);
    return failures == 0 ? 0 : 1;
}

int main(int argc, const char *argv[]) {
    for (int index = 1; index < argc; index++) {
        NSString *argument = @(argv[index]);
        if ([argument isEqualToString:@"--selftest"]) {
            return RunSelfTest();
        }
        if ([argument isEqualToString:@"--count-stdin"]) {
            Counts counts = CountText(ReadStandardInput());
            printf("{\"cjk\": %lu, \"words\": %lu, \"total\": %lu, \"chars\": %lu, \"charsNoSpace\": %lu}\n",
                   (unsigned long)counts.cjk,
                   (unsigned long)counts.words,
                   (unsigned long)(counts.cjk + counts.words),
                   (unsigned long)counts.chars,
                   (unsigned long)counts.charsNoSpace);
            return 0;
        }
        if ([argument isEqualToString:@"--check-access"]) {
            printf("%s\n", AccessibilityGranted(NO) ? "accessibility: granted" : "accessibility: not granted");
            return 0;
        }
    }

    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
