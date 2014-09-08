//
//  QSAppleMailPlugIn_Source.m
//  QSAppleMailPlugIn
//
//  Created by Nicholas Jitkoff on 9/28/04.
//  Copyright __MyCompanyName__ 2004. All rights reserved.
//

#import "QSAppleMailPlugIn_Source.h"
#import "QSAppleMailMediator.h"

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


- (QSObject *)initFileObject:(QSObject *)object ofType:(NSString *)type{
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

- (BOOL)objectHasChildren:(QSObject *)object{
	// when mailbox appears in third pane, you can't arrow into it
	if ([object objectForMeta:@"loadChildren"] != nil && ![[object objectForMeta:@"loadChildren"] boolValue]) {
		return NO;
	}
	
	// check, if mailbox has children
	if([[object primaryType] isEqualToString:kQSAppleMailMailboxType])
	{
		NSFileManager *fm = [NSFileManager defaultManager];
        BOOL hasFiles = NO;
        NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:[NSString stringWithFormat:@"%@/%@.%@",
                                                         [object objectForMeta:@"accountPath"],
                                                         [object objectForMeta:@"mailboxName"],
                                                         [object objectForMeta:@"mailboxType"]]];
        NSString *file;
        while ((file = [enumerator nextObject])) {
            hasFiles = YES;
            break;
        }
        
        // If the directory has any files, we can (perhaps incorrectly) assume that there are at least some .emlx (message) files
        return hasFiles;
		

	}
	
	// messages always have children: body text and from-address
//	if([[object primaryType] isEqualToString:kQSAppleMailMessageType]) {
//		return YES;
//	}
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
//	if ([[object primaryType]isEqualToString:kQSAppleMailMessageType]){
//		[object setChildren:[self mailContent:object]];
//		return YES;
//	}
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
	NSDictionary *mailPrefs = [QSAppleMailMediator mailPreferences];
	NSArray *pl = [mailPrefs objectForKey:@"MailAccounts"];
	NSMutableDictionary *realAccountNames = [NSMutableDictionary dictionaryWithCapacity:[pl count]];
	for(NSDictionary *dict in pl) {
		if ([dict objectForKey:@"AccountPath"] != nil && [dict objectForKey:@"AccountName"] != nil) {
			[realAccountNames setObject:[dict objectForKey:@"AccountName"] forKey:[[dict objectForKey:@"AccountPath"] lastPathComponent]];
		}
	}

	NSString *file, *accountName, *accountId, *mb;
    // folders for accounts look like TYPE-username@server
    NSString *accountRegEx = @"^.+-.+@.+$";
    NSPredicate *regextest = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", accountRegEx];
	while (file = [accountEnum nextObject]) {
		// skip everything that's not a mailbox directory
		if ([[accountEnum fileAttributes] fileType] != NSFileTypeDirectory ||
			!([regextest evaluateWithObject:file] || [file isEqualToString:@"Mailboxes"])) {
			[accountEnum skipDescendants];
			continue;
		}

		if ([file isEqualToString:@"Mailboxes"]) {
			accountName = @"Local Mailbox";
			accountId = accountName;
		} else {
			accountName = [realAccountNames objectForKey:file];
			accountId = [file substringFromIndex:[file rangeOfString:@"-"].location + 1];
		}

		// scan account folder
		mailboxEnum = [fm enumeratorAtPath:[path stringByAppendingPathComponent:file]];
		while (mb = [mailboxEnum nextObject]) {
			if ([[mailboxEnum fileAttributes] fileType] != NSFileTypeDirectory) {
				continue;
			}

			// IMAP, POP, iCloud, Exchange, and Local Accounts
			if ([[mb pathExtension] hasSuffix:@"mbox"]) {
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
	NSMutableArray *objects = [NSMutableArray arrayWithCapacity:0];
	QSObject *newObject;
	NSFileManager *manager = [NSFileManager defaultManager];
	NSString *mailboxPath = [accountPath stringByAppendingPathComponent:mailbox];
	NSArray *subs = [manager contentsOfDirectoryAtURL:[NSURL fileURLWithPath:mailboxPath] includingPropertiesForKeys:@[NSURLIsDirectoryKey] options:0 error:0];
	NSArray *subMailboxes = [subs filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSURL *evaluatedObject, NSDictionary *bindings) {
        // predicate to find sub-mailboxes
        return [[evaluatedObject pathExtension] isEqualToString:@"mbox"];
    }]];
	NSArray *messageStore = [subs filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSURL* evaluatedObject, NSDictionary *bindings) {
        // predicate to find messages
        return ![[evaluatedObject pathExtension] isEqualToString:@"mbox"];
    }]];
    NSString *subpath = [[accountPath lastPathComponent] stringByAppendingPathComponent:mailbox];

	for (NSURL *subMailbox in subMailboxes) {
		// create QSObject for sub-folder
		newObject = [self makeMailboxObject:[subMailbox lastPathComponent] withAccountName:[object details] withAccountId:accountID withFile:subpath withChildren:YES];
		[objects addObject:newObject];
	}
    @autoreleasepool {
        for (NSURL *mailboxChild in messageStore) {
            NSNumber *isDir;
            [mailboxChild getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
            if (![isDir boolValue]) {
                // skip over plists and other metadata
                continue;
            }
            NSMetadataQuery *messageQuery = [[NSMetadataQuery alloc] init];
            NSSet *messageContainer = [NSSet setWithObject:[mailboxChild path]];

            [messageQuery resultsForSearchString:@"kMDItemContentType == 'com.apple.mail.emlx'" inFolders:messageContainer];
            QSObject *messageObject = [[QSObject alloc] init];
            [messageObject setPrimaryType:kQSAppleMailMessageType];
            [messageObject setObject:accountPath forMeta:@"accountPath"];
            [messageObject setObject:mailboxName forMeta:@"mailboxName"];
            [messageObject setObject:accountID forMeta:@"accountId"];
            [messageObject setObject:[object details] forMeta:@"accountName"];
            [messageObject setParentID:[object identifier]];
            
            [[messageQuery results] enumerateObjectsWithOptions:NSEnumerationConcurrent usingBlock:^(NSMetadataItem *message, NSUInteger i, BOOL *stop) {
                /* Various optimisations in this routine
                 
                 * Get all MDMetadataItem attributes at once (50%)
                 * Create a QSObject with the placeholder info outside of this loop (2%)
                 * Bypass -[QSObject setName:]. This is a new object so there is no needt to check against the label etc. (0.5%)
                 * Set the kQSAppleMailMessageType and filetype in data directly - (avoids calls to @synchronized and QSUTIForAnyType()) (7%)
                 
                 */
                
                NSDictionary *attrs = [message valuesForAttributes:@[(NSString *)kMDItemPath, (NSString *)kMDItemSubject, (NSString *)kMDItemAuthors, (NSString *)kMDItemFSName]];
                NSString *subject = attrs[(NSString *)kMDItemSubject];
                if ([subject length] > 255) subject = [subject substringToIndex:255];
                
                NSString *fsName = attrs[(NSString *)kMDItemFSName];
                
                QSObject *messageObjectNew = [messageObject copy];
                [messageObjectNew setObject:subject forMeta:kQSObjectPrimaryName];
                [messageObjectNew setDetails:[attrs[(NSString *)kMDItemAuthors] lastObject]];
                [messageObjectNew setIdentifier:[NSString stringWithFormat:@"message:%@", fsName]];
                [messageObjectNew setObject:fsName forMeta:@"message_id"];
                [[messageObjectNew dataDictionary] setObject:subject forKey:kQSAppleMailMessageType];
                [[messageObjectNew dataDictionary] setObject:attrs[(NSString *)kMDItemPath] forKey:QSFilePathType];
                [objects addObject:messageObjectNew];
                [messageObjectNew release];
            }];
            [messageObject release];
            [messageQuery release];
        };
    }
	return objects;
}

//- (NSArray *)mailContent:(QSObject *)object
//{
//	NSMutableArray *objects = [NSMutableArray arrayWithCapacity:1];
//	QSObject *newObject;
//
//	// read mail file and parse message
//	CTCoreMessage *message = [[CTCoreMessage alloc] initWithFileAtPath:@"/Users/rob/example.msg"];
//	if (message) {
//		// create QSObjects
//		newObject = [QSObject objectWithString:[[message body] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
//		[newObject setParentID:[object identifier]];
//		[objects addObject:newObject];
//		
//		CTCoreAddress *from = [[message from] anyObject];
//		[message release];
//		
//		newObject = [QSObject objectWithName:[from email]];
//		[newObject setObject:[from email] forType:QSEmailAddressType];
//		[newObject setDetails:[from name]];
//		[newObject setParentID:[object identifier]];
//		[newObject setPrimaryType:QSEmailAddressType];
//		[objects addObject:newObject];
//		
//		return objects;
//	}
//	return nil;
//}

@end
