//
//  QSUnreadMailSource.m
//  AppleMailElement
//
//  Created by Rob McBroom on 2012/05/17.
//

#import "QSUnreadMailSource.h"
#import "Mail.h"

@implementation QSUnreadMailSource

- (id)init
{
	self = [super init];
	if (self) {
		Mail = [[SBApplication applicationWithBundleIdentifier:@"com.apple.mail"] retain];
	}
	return self;
}

- (void)dealloc
{
	[Mail release];
	[super dealloc];
}

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
	if ([Mail isRunning]) {
		QSObject *unreadMailParent = [QSObject objectWithName:@"Unread Messages"];
		[unreadMailParent setIdentifier:@"QSUnreadMailParent"];
		[unreadMailParent setPrimaryType:@"QSUnreadMailParent"];
		return [NSArray arrayWithObject:unreadMailParent];
	}
	return nil;
}

- (BOOL)objectHasChildren:(QSObject *)object
{
	if ([Mail isRunning]) {
		return ([[Mail inbox] unreadCount] > 0);
	}
	return NO;
}

- (BOOL)loadChildrenForObject:(QSObject *)object
{
	MailMailbox *inbox = [Mail inbox];
	if ([inbox unreadCount] == 0) {
		return NO;
	}
	QSObject *child;
	NSMutableArray *qsmessages = [NSMutableArray arrayWithCapacity:[inbox unreadCount]];
	NSPredicate *unread = [NSPredicate predicateWithFormat:@"readStatus == 0"];
	NSArray *messages = [[[inbox messages] get] filteredArrayUsingPredicate:unread];
	NSString *accountPath, *searchFilter;
	NSMetadataQuery *query = [[NSMetadataQuery alloc] init];
	NSArray *messagePaths;
	for (MailMessage *msg in messages) {
		child = [QSObject objectWithName:[msg subject]];
		[child setIdentifier:[msg messageId]];
		[child setDetails:[msg sender]];
		[child setParentID:[object identifier]];
		[child setObject:msg forType:@"qs.mail.message"];
		[child setPrimaryType:@"qs.mail.message"];
		[child setObject:[[msg mailbox] name] forMeta:@"mailboxName"];
		accountPath = [[[[msg mailbox] account] accountDirectory] path];
		searchFilter = [NSString stringWithFormat:@"kMDItemSubject == '%@'", [msg subject]];
		messagePaths = [query resultsForSearchString:searchFilter inFolders:[NSSet setWithObject:accountPath]];
		if ([messagePaths count]) {
			[child setObject:[[messagePaths objectAtIndex:0] valueForAttribute:@"kMDItemPath"] forType:QSFilePathType];
		}
		[qsmessages addObject:child];
	}
	[query release];
	[object setChildren:qsmessages];
	return YES;
}

- (void)setQuickIconForObject:(QSObject *)object
{
	if ([[object primaryType] isEqualToString:@"QSUnreadMailParent"]) {
		[object setIcon:[QSResourceManager imageNamed:@"com.apple.mail"]];
	}
}

@end
