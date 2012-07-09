#import "QSMailMediator.h"

@interface QSAppleMailMediator : NSObject<QSMailMediator> {
    NSAppleScript *mailScript;
}
- (NSAppleScript *)mailScript;
@end
