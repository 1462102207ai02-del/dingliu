#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// 诊断日志：环形缓冲（内存）+ 同步写入文件日志。
// 设置页「查看诊断日志」可以直接看 / 复制，用来排查"识别到了哪个类、
// 选了哪层胶囊、钩子有没有触发"这类问题。
void WDDiagLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
// 同一个 key 只记一次（避免滚动/布局刷屏）
void WDDiagLogOnce(NSString *key, NSString *fmt, ...) NS_FORMAT_FUNCTION(2, 3);
NSString *WDDiagDump(void);
void WDDiagClear(void);
