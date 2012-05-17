//
//  QSUnreadMailSource.m
//  AppleMailElement
//
//  Created by Rob McBroom on 2012/05/17.
//

#import "QSUnreadMailSource.h"
#import "Mail.h"

@implementation QSUnreadMailSource

- (BOOL)indexIsValidFromDate:(NSDate *)indexDate forEntry:(NSDictionary *)theEntry
{
	// rescan only if the indexDate is prior to the last launch
	NSDate *launched = [[NSRunningApplication currentApplication] launchDate];
	if (launched) {
		return ([launched compare:indexDate] == NSOrderedAscending);
	} else {
		// Quicksilver wasn't launched by LaunchServices - date unknown - rescan to be safe
		return NO;
	}
}

- (NSArray *)objectsForEntry:(NSDictionary *)theEntry
{
	MailApplication *Mail = [SBApplication applicationWithBundleIdentifier:@"com.apple.mail"];
	if ([Mail isRunning]) {
		QSObject *unreadMailParent = [QSObject objectWithName:@"Unread Messages"];
		return [NSArray arrayWithObject:unreadMailParent];
	}
	return nil;
}

- (BOOL)objectHasChildren:(QSObject *)object
{
	return YES;
}

- (BOOL)loadChildrenForObject:(QSObject *)object
{
	return NO;
}

@end
