//
//  QSAppleMailPlugIn_Source.m
//  QSAppleMailPlugIn
//
//  Created by Nicholas Jitkoff on 9/28/04.
//  Copyright __MyCompanyName__ 2004. All rights reserved.
//

#import "QSAppleMailPlugIn_Source.h"

@interface QSAppleMailPlugIn_Source (hidden)
- (QSObject *)makeMailboxObject:(NSString *)mailbox withAccountName:(NSString *)accountName withAccountId:(NSString *)accountId withFile:(NSString *)file withChildren:(BOOL)loadChildren;
- (NSArray *)mailsForMailbox:(QSObject *)object;
- (NSArray *)mailContent:(QSObject *)object;
@end

@implementation QSAppleMailPlugIn_Source
- (BOOL)indexIsValidFromDate:(NSDate *)indexDate forEntry:(NSDictionary *)theEntry{
    return YES;
}

- (NSImage *) iconForEntry:(NSDictionary *)dict{
    return nil;
}

- (NSString *)identifierForObject:(id <QSObject>)object{
    return nil;
}

- (void)setQuickIconForObject:(QSObject *)object{
	if ([[object primaryType]isEqualToString:kQSAppleMailMailboxType]){
		NSString *mailboxName = [object objectForType:kQSAppleMailMailboxType];
		if ([mailboxName rangeOfString:@"Junk" options:NSCaseInsensitiveSearch].location != NSNotFound ||
			[mailboxName rangeOfString:@"Spam" options:NSCaseInsensitiveSearch].location != NSNotFound) {
			[object setIcon:[QSResourceManager imageNamed:@"MailMailbox-Junk"]];
		} else if ([mailboxName rangeOfString:@"Drafts" options:NSCaseInsensitiveSearch].location != NSNotFound){
			[object setIcon:[QSResourceManager imageNamed:@"MailMailbox-Drafts"]];
		} else if ([mailboxName rangeOfString:@"Sent" options:NSCaseInsensitiveSearch].location != NSNotFound){
			[object setIcon:[QSResourceManager imageNamed:@"MailMailbox-Sent"]];
		} else if ([mailboxName rangeOfString:@"Trash" options:NSCaseInsensitiveSearch].location != NSNotFound ||
				   [mailboxName rangeOfString:@"Deleted" options:NSCaseInsensitiveSearch].location != NSNotFound){
			[object setIcon:[QSResourceManager imageNamed:@"TrashIcon"]];
		} else if ([mailboxName rangeOfString:@"Inbox" options:NSCaseInsensitiveSearch].location != NSNotFound){
			[object setIcon:[QSResourceManager imageNamed:@"MailMailbox-Inbox"]];
		} else {
			[object setIcon:[QSResourceManager imageNamed:@"MailMailbox"]];
		}
		return;
	}
	if ([[object primaryType]isEqualToString:kQSAppleMailMessageType]){
		[object setIcon:[QSResourceManager imageNamed:@"MailMessage"]];
		return;
	}
}


- (BOOL)loadIconForObject:(QSObject *)object{
	return NO;
}


- (id)initFileObject:(QSObject *)object ofType:(NSString *)type{
	NSString *filePath=[object singleFilePath];
	NSString *iden=[[filePath lastPathComponent]stringByDeletingPathExtension];
	NSString *mailbox=[[[filePath stringByDeletingLastPathComponent]stringByDeletingLastPathComponent]lastPathComponent];
	NSString *messagePath=[NSString stringWithFormat:@"%@//%@",mailbox,iden];
	
	NSMetadataItem *mditem=[NSMetadataItem itemWithPath:filePath];
	[object setName:[mditem valueForAttribute:(NSString *)kMDItemDisplayName]];
	[object setObject:messagePath forType:kQSAppleMailMessageType];
	[object setDetails:[[mditem valueForAttribute:(NSString *)kMDItemAuthors]lastObject]];
	return object;
	
}

- (NSString *)detailsOfObject:(QSObject *)object{
	if ([[object primaryType]isEqualToString:kQSAppleMailMailboxType]){
		
		NSString *mailbox=[object objectForType:kQSAppleMailMailboxType];
		return [mailbox stringByDeletingLastPathComponent]; 
	}
	return nil;
}

- (BOOL)objectHasChildren:(QSObject *)object{
	// when mailbox appears in third pane, you can't arrow into it
	if ([object objectForMeta:@"loadChildren"] != nil && ![[object objectForMeta:@"loadChildren"] boolValue]) {
		return NO;
	}
	
	// check, if mailbox has children
	if([[object primaryType] isEqualToString:kQSAppleMailMailboxType])
	{
		NSFileManager *fm = [NSFileManager defaultManager];
		NSArray *files = [fm subpathsAtPath:[NSString stringWithFormat:@"%@/%@.%@/Messages",
												[object objectForMeta:@"accountPath"],
												[object objectForMeta:@"mailboxName"],
												[object objectForMeta:@"mailboxType"]]];
		// mailbox doesn't have a "Messages" folder or there are no files in it, it can't have messages
		if ([files count] <= 0) {
			return NO;
		}
		
		// if there are no .emlx files in it, there are also no messages
		NSUInteger index = [files indexOfObjectPassingTest:^(id obj, NSUInteger idx, BOOL *stop) {
			return [obj hasSuffix:@".emlx"];
		}];
		if(index == NSNotFound) {
			return NO;
		}
		
		// seems like there are .emlx files, so there are messages, so set the right-arrow indicator
		return YES;
	}
	
	// messages always have children: body text and from-address
	if([[object primaryType] isEqualToString:kQSAppleMailMessageType]) {
		return YES;
	}
	return NO;
}

- (BOOL)loadChildrenForObject:(QSObject *)object{
	// when mailbox appears in third pane, you can't arrow into it
	if ([object objectForMeta:@"loadChildren"] != nil && ![[object objectForMeta:@"loadChildren"] boolValue]) {
		return NO;
	}

	if ([[object primaryType]isEqualToString:QSFilePathType]){
		[object setChildren:[self objectsForEntry:nil]];
		return YES;
	}
	if ([[object primaryType]isEqualToString:kQSAppleMailMailboxType]){
		[object setChildren:[self mailsForMailbox:object]];
		return YES; 
	}
	if ([[object primaryType]isEqualToString:kQSAppleMailMessageType]){
		[object setChildren:[self mailContent:object]];
		return YES;
	}
	return NO;
}

- (NSArray *) objectsForEntry:(NSDictionary *)theEntry{
	return [self allMailboxes];
}

- (NSArray *)allMailboxes {
	return [self allMailboxes:YES];
}

- (NSArray *)allMailboxes:(BOOL)loadChildren{
	NSMutableArray *objects=[NSMutableArray arrayWithCapacity:1];
	QSObject *newObject;

	NSString *path = [MAILPATH stringByStandardizingPath];
	NSFileManager *fm = [NSFileManager defaultManager];
	if ([NSApplication isLion]) {
		path = [path stringByAppendingPathComponent:@"V2"];
	}
	NSDirectoryEnumerator *accountEnum = [fm enumeratorAtPath:path];
	NSDirectoryEnumerator *mailboxEnum;

	// find real names for accounts
	NSUserDefaults *mailPrefs = [[NSUserDefaults alloc] init];
	NSArray *pl = [[mailPrefs persistentDomainForName:@"com.apple.mail"] objectForKey:@"MailAccounts"];
	[mailPrefs release];
	NSMutableDictionary *realAccountNames = [NSMutableDictionary dictionaryWithCapacity:[pl count]];
	for(NSDictionary *dict in pl) {
		if ([dict objectForKey:@"AccountPath"] != nil && [dict objectForKey:@"AccountName"] != nil) {
			[realAccountNames setObject:[dict objectForKey:@"AccountName"] forKey:[dict objectForKey:@"AccountPath"]];
		}
	}

	NSString *file, *accountName, *accountId, *mb;
	while (file = [accountEnum nextObject]) {
		// skip everything that's not a mailbox directory
		if ([[accountEnum fileAttributes] fileType] != NSFileTypeDirectory ||
			!([file hasPrefix:@"IMAP-"] || [file hasPrefix:@"Mac-"] || [file hasPrefix:@"POP-"] || [file isEqualToString:@"Mailboxes"])) {
			[accountEnum skipDescendants];
			continue;
		}

		if ([file isEqualToString:@"Mailboxes"]) {
			accountName = @"Local Mailbox";
			accountId = accountName;
		} else {
			accountName = [realAccountNames objectForKey:[NSString stringWithFormat:@"%@/%@", MAILPATH, file]];
			accountId = [file substringFromIndex:[file rangeOfString:@"-"].location + 1];
		}

		// scan account folder
		mailboxEnum = [fm enumeratorAtPath:[path stringByAppendingPathComponent:file]];
		while (mb = [mailboxEnum nextObject]) {
			if ([[mailboxEnum fileAttributes] fileType] != NSFileTypeDirectory) {
				continue;
			}

			// IMAP- & MoblieMe-Accounts
			if ([[mb pathExtension] isEqualToString:@"imapmbox"]) {
				newObject = [self makeMailboxObject:mb
									withAccountName:accountName
									  withAccountId:accountId
										   withFile:file
									   withChildren:loadChildren];

				[objects addObject:newObject];
				[mailboxEnum skipDescendants];
			}

			// POP-accounts & local mailboxes
			if ([[mb pathExtension] isEqualToString:@"mbox"]) {
				newObject = [self makeMailboxObject:mb
									withAccountName:accountName
									  withAccountId:accountId
										   withFile:file
									   withChildren:loadChildren];

				[objects addObject:newObject];
				[mailboxEnum skipDescendants];
			}
		}
		[accountEnum skipDescendents];
	}
	return objects;
}

- (QSObject *)makeMailboxObject:(NSString *)mailbox withAccountName:(NSString *)accountName withAccountId:(NSString *)accountId withFile:(NSString *)file withChildren:(BOOL)loadChildren {
	NSString *mailboxType = [mailbox pathExtension];
	NSString *mailboxName = [mailbox stringByDeletingPathExtension];

	QSObject *newObject = [QSObject objectWithName:[NSString stringWithFormat:@"%@ %@", accountName, mailboxName]];
	[newObject setObject:mailboxName forType:kQSAppleMailMailboxType];
	[newObject setLabel:mailboxName];
	[newObject setDetails:accountName];
	[newObject setObject:accountId forMeta:@"accountId"];
	[newObject setObject:mailboxType forMeta:@"mailboxType"];
	[newObject setObject:mailbox forMeta:@"mailbox"];
	[newObject setIdentifier:[NSString stringWithFormat:@"mailbox:%@//%@", accountName, mailboxName]];
	NSString *accountPath = [NSApplication isLion] ? [MAILPATH stringByAppendingPathComponent:@"V2"] : MAILPATH;
	[newObject setObject:[[accountPath stringByAppendingPathComponent:file] stringByStandardizingPath] forMeta:@"accountPath"];
	[newObject setObject:mailboxName forMeta:@"mailboxName"];
	[newObject setObject:[NSNumber numberWithBool:loadChildren] forMeta:@"loadChildren"];
	[newObject setPrimaryType:kQSAppleMailMailboxType];
	return newObject;
}

- (NSArray *)mailsForMailbox:(QSObject *)object {
	NSString *mailboxName = [object objectForType:kQSAppleMailMailboxType];
	NSString *accountID = [object objectForMeta:@"accountId"];
	NSString *accountPath = [object objectForMeta:@"accountPath"];
	NSString *mailbox = [object objectForMeta:@"mailbox"];
	NSString *subject, *sender, *mailPath, *subPath, *childPath;
	NSMutableArray *objects = [NSMutableArray arrayWithCapacity:0];
	QSObject *newObject;
	NSFileManager *manager = [NSFileManager defaultManager];
	// predicate to find sub-mailboxes
	NSPredicate *mbox = [NSPredicate predicateWithFormat:@"SELF ENDSWITH[cd] '.mbox'"];
	// predicate to find messages
	NSPredicate *messages = [NSPredicate predicateWithFormat:@"NOT SELF ENDSWITH[cd] '.mbox'"];
	BOOL isDir;
	NSString *mailboxPath = [accountPath stringByAppendingPathComponent:mailbox];
	NSArray *subs = [manager contentsOfDirectoryAtPath:mailboxPath error:nil];
	NSArray *subMailboxes = [subs filteredArrayUsingPredicate:mbox];
	NSArray *messageStore = [subs filteredArrayUsingPredicate:messages];
	for (NSString *subMailbox in subMailboxes) {
		// create QSObject for sub-folder
		subPath = [[[accountPath pathComponents] lastObject] stringByAppendingPathComponent:mailbox];
		newObject = [self makeMailboxObject:subMailbox withAccountName:[object details] withAccountId:accountID withFile:subPath withChildren:YES];
		[objects addObject:newObject];
	}
	for (NSString *mailboxChild in messageStore) {
		childPath = [mailboxPath stringByAppendingPathComponent:mailboxChild];
		[manager fileExistsAtPath:childPath isDirectory:&isDir];
		if (!isDir) {
			// skip over plists and other metadata
			continue;
		}
		NSMetadataQuery *messageQuery = [[NSMetadataQuery alloc] init];
		NSSet *messageContainer = [NSSet setWithObject:childPath];
		[messageQuery resultsForSearchString:@"kMDItemKind == 'Mail Message'" inFolders:messageContainer];
		for (NSMetadataItem *message in [messageQuery results]) {
			subject = [message valueForAttribute:(NSString *)kMDItemSubject];
			sender = [[message valueForAttribute:(NSString *)kMDItemAuthors] lastObject];
			mailPath = [message valueForAttribute:@"kMDItemPath"];
			newObject=[QSObject objectWithName:subject];
			[newObject setDetails:sender];
			[newObject setParentID:[object identifier]];
			[newObject setIdentifier:[NSString stringWithFormat:@"message:%d", [message valueForAttribute:(NSString *)kMDItemFSName]]];
			[newObject setObject:accountID forMeta:@"accountId"];
			[newObject setObject:[message valueForAttribute:(NSString *)kMDItemFSName] forMeta:@"message_id"];
			[newObject setObject:mailboxName forMeta:@"mailboxName"];
			[newObject setObject:accountPath forMeta:@"accountPath"];
			[newObject setObject:subject forType:kQSAppleMailMessageType];
			[newObject setObject:mailPath forType:QSFilePathType];
			[newObject setPrimaryType:kQSAppleMailMessageType];
			[objects addObject:newObject];
		}
		[messageQuery release];
	}
	return objects;
}

- (NSArray *)mailContent:(QSObject *)object {
	NSMutableArray *objects=[NSMutableArray arrayWithCapacity:1];
	QSObject *newObject;

	// read mail file
	NSError *err = nil;
	NSString *fileContents = [NSString stringWithContentsOfFile:[object objectForType:QSFilePathType] encoding:NSASCIIStringEncoding error:&err];
	if (!fileContents || err) {
		NSLog(@"Couldn't read mail. Error: %@ (%ld - %@)", [err localizedDescription], [err code], [object objectForType:QSFilePathType]);
		return nil;
	}

	// remove non-MIME-stuff
	NSCharacterSet *cs = [NSCharacterSet newlineCharacterSet];
	NSRange r = [fileContents rangeOfCharacterFromSet:cs];
	fileContents = [fileContents substringFromIndex:(r.location+r.length)];
	fileContents = [fileContents substringToIndex:[fileContents rangeOfString:@"<?xml"].location];

	// make sure, it an ASCII string
	if (![fileContents canBeConvertedToEncoding:NSASCIIStringEncoding]) {
		NSData *d = [fileContents dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
		fileContents = [[[NSString alloc] initWithData:d encoding:NSASCIIStringEncoding] autorelease];
	}

	// parse message
	CTCoreMessage *message =  [[CTCoreMessage alloc] initWithString:fileContents];
	[message fetchBody];

	// create QSObjects
	newObject=[QSObject objectWithString:[[message body] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
	[newObject setParentID:[object identifier]];
	[objects addObject:newObject];

	CTCoreAddress * from = [[message from] anyObject];
	[message release];

	newObject=[QSObject objectWithName:[from email]];
	[newObject setObject:[from email] forType:QSEmailAddressType];
	[newObject setDetails:[from name]];
	[newObject setParentID:[object identifier]];
	[newObject setPrimaryType:QSEmailAddressType];
	[objects addObject:newObject];

	return objects;
}

@end
