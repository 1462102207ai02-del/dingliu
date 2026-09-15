#import "WDDiag.h"
#import <stdarg.h>
#import <fcntl.h>
#import <unistd.h>
#import <stdio.h>

#define WD_DIAG_MAX 500

static NSMutableArray *gDiagLines = nil;
static NSLock *gDiagLock = nil;
static NSMutableSet *gDiagKeys = nil;

static char gDiagHome[512];
static char gDiagTmp[512];

static void WDDiagInit(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gDiagLines = [NSMutableArray array];
        gDiagLock = [[NSLock alloc] init];
        gDiagKeys = [NSMutableSet set];
        const char *tmp = getenv("TMPDIR");
        if (!tmp || !tmp[0]) tmp = "/tmp";
        snprintf(gDiagTmp, sizeof(gDiagTmp), "%s/WechatDuo.log", tmp);
        const char *home = getenv("HOME");
        if (home && home[0]) snprintf(gDiagHome, sizeof(gDiagHome), "%s/Documents/WechatDuo.log", home);
    });
}

static void WDDiagWriteFile(const char *line) {
    const char *paths[2] = { gDiagTmp[0] ? gDiagTmp : NULL, gDiagHome[0] ? gDiagHome : NULL };
    for (int i = 0; i < 2; i++) {
        if (!paths[i]) continue;
        int fd = open(paths[i], O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (fd < 0) continue;
        write(fd, line, strlen(line));
        close(fd);
    }
}

void WDDiagLog(NSString *fmt, ...) {
    if (!fmt) return;
    WDDiagInit();
    va_list ap;
    va_start(ap, fmt);
    NSString *body = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    static NSDateFormatter *fmt2 = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt2 = [[NSDateFormatter alloc] init];
        fmt2.dateFormat = "HH:mm:ss.SSS";
    });
    NSString *line = [NSString stringWithFormat:@"%@ %@", [fmt2 stringFromDate:[NSDate date]], body];
    [gDiagLock lock];
    if (gDiagLines.count >= WD_DIAG_MAX) [gDiagLines removeObjectAtIndex:0];
    [gDiagLines addObject:line];
    [gDiagLock unlock];
    WDDiagWriteFile([line cStringUsingEncoding:NSUTF8StringEncoding]);
}

void WDDiagLogOnce(NSString *key, NSString *fmt, ...) {
    if (!key || !fmt) return;
    WDDiagInit();
    [gDiagLock lock];
    if ([gDiagKeys containsObject:key]) { [gDiagLock unlock]; return; }
    [gDiagKeys addObject:key];
    [gDiagLock unlock];
    va_list ap;
    va_start(ap, fmt);
    NSString *body = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    WDDiagLog(@"%@", body);
}

NSString *WDDiagDump(void) {
    WDDiagInit();
    [gDiagLock lock];
    NSString *s = [gDiagLines componentsJoinedByString:@"\n"];
    [gDiagLock unlock];
    if (!s.length) s = @"（暂无记录）\n打开微信 → 首页/通讯录/朋友圈/我 各转一圈，再回来看。";
    return s;
}

void WDDiagClear(void) {
    WDDiagInit();
    [gDiagLock lock];
    [gDiagLines removeAllObjects];
    [gDiagKeys removeAllObjects];
    [gDiagLock unlock];
}
