#import "QSAppleMailMediator.h"
#import "QSMailMediator.h"
#import "Mail.h"
#import <AddressBook/AddressBook.h>

@class QSCountBadgeImage;

@implementation QSAppleMailMediator

- (id)init
{
	self = [super init];
	if (self) {
		mailScript = nil;
	}
	return self;
}

- (void) sendEmailTo:(NSArray *)addresses from:(NSString *)sender subject:(NSString *)subject body:(NSString *)body attachments:(NSArray *)pathArray sendNow:(BOOL)sendNow{
	NSArray *accounts = [[[self mailScript] executeSubroutine:@"account_list" arguments:[NSArray arrayWithObjects:subject, body, addresses, pathArray, nil] error:nil] objectValue];
	if (!sender && ![accounts count]) {
		return;
	}
	//NSLog(@"accounts %@",accounts);
	NSInteger accountIndex = -1;
	for (NSUInteger i = 0; i < [accounts count]; i++) {
		NSString *accountAddress = [[accounts objectAtIndex:i] objectAtIndex:0];
		for (NSString *address in addresses) {
			if (emailsShareDomain(address, accountAddress)){
				accountIndex = i;
				i = [accounts count]; // stop the outer loop
				break;                // stop the inner loop
			}
		}
	}
	if (accountIndex >= 0 || !sender) {
		// better sender found, or default is missing
		NSArray *account = [accounts objectAtIndex:(accountIndex >= 0) ? accountIndex : 0];
		NSString *accountFormatted = [(NSString *)[account lastObject]length]?[NSString stringWithFormat:@"%@ <%@>", [account lastObject], [account objectAtIndex:0]]:[account objectAtIndex:0];
		sender = accountFormatted;
	}
	//NSLog(@"accounts %@",accountFormatted);
	
	[[QSReg getClassInstance:@"QSMailMediator"] sendEmailWithScript:[self mailScript] to:(NSArray *)addresses from:(NSString *)sender subject:(NSString *)subject body:(NSString *)body attachments:(NSArray *)pathArray sendNow:(BOOL)sendNow];
	
}

- (NSString *)scriptPath {
	return [[NSBundle bundleForClass:[QSAppleMailMediator class]]pathForResource:@"Mail" ofType:@"scpt"];
}


- (NSAppleScript *)mailScript {
	if (!mailScript){
		NSString *path=[self scriptPath];
		if (path) mailScript=[[NSAppleScript alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:nil];
	}
	return mailScript;
}

- (void)setMailScript:(NSAppleScript *)newMailScript {
	mailScript = newMailScript;
}

+ (NSDictionary *)mailPreferences
{
	// locate and read Mail.app's preferences
	NSArray *candidates = [NSArray arrayWithObjects:@"~/Library/Mail/V2/MailData/Accounts.plist", @"~/Library/Containers/com.apple.mail/Data/Library/Preferences/com.apple.mail.plist", @"~/Library/Preferences/com.apple.mail.plist", nil];
	for (NSString *prefs in candidates) {
		NSDictionary *mailPrefs = [NSDictionary dictionaryWithContentsOfFile:[prefs stringByStandardizingPath]];
		if (mailPrefs) {
			return mailPrefs;
		}
	}
	return nil;
}

- (NSImage *)iconForAction:(NSString *)actionID
{
	if ([actionID isEqualToString:@"QSEmailItemAction"] || [actionID isEqualToString:@"QSEmailItemReverseAction"]) {
		// actions that send immediately
		return [QSResourceManager imageNamed:@"MailMailbox-Sent"];
	}
	return [QSResourceManager imageNamed:@"com.apple.Mail"];
}

- (NSDictionary *)smtpServerDetails {
	// unused for apple mail - use the direct method instead
	return nil;
}


@end
