#import "QSMailMediator.h"

@interface QSAppleMailMediator : QSMailMediator

- (NSAppleScript *)mailScript;
+ (NSDictionary *)mailPreferences;
@end
