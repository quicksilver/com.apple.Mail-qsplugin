//
//  QSAppleMailPlugIn_Source.m
//  QSAppleMailPlugIn
//
//  Created by Nicholas Jitkoff on 9/28/04.
//  Copyright __MyCompanyName__ 2004. All rights reserved.
//

#import "QSAppleMailPlugIn_Source.h"
#import "QSAppleMailMediator.h"
#import "Mail.h"

#define kAllowLoadChildren @"allowLoadChildren"

@interface QSAppleMailPlugIn_Source (hidden)
- (QSObject *)makeMailboxObject:(NSString *)mailbox withAccountName:(NSString *)accountName withAccountId:(NSString *)accountId withFile:(NSString *)file withChildren:(BOOL)allowLoadChildren;
- (NSArray *)mailsForMailbox:(QSObject *)object;
- (NSArray *)mailContent:(QSObject *)object;
@end

@implementation QSAppleMailPlugIn_Source
{
	MailApplication *_cachedMailApp;
	NSMutableDictionary *_accountNameCache;
}

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

- (BOOL)objectHasChildren:(QSObject *)object{
	// when mailbox appears in third pane, you can't arrow into it
	if ([object objectForMeta:kAllowLoadChildren] != nil) {
		return [[object objectForMeta:kAllowLoadChildren] boolValue];
	}
	return NO;
}

- (BOOL)loadChildrenForObject:(QSObject *)object{
	// when mailbox appears in third pane, you can't arrow into it
	if ([object objectForMeta:kAllowLoadChildren] != nil && ![[object objectForMeta:kAllowLoadChildren] boolValue]) {
		return NO;
	}

	if ([[object primaryType]isEqualToString:QSFilePathType]){
		[object setChildren:[self objectsForEntry:nil]];
		return YES;
	}
	if ([[object primaryType] isEqualToString:kQSAppleMailMailboxType]){
		// Check if we have a cached mailbox reference for loading sub-mailboxes
		MailMailbox *mailboxRef = [object objectForMeta:@"mailboxReference"];
		if (mailboxRef) {
			NSArray *mailboxes = [mailboxRef mailboxes];
			NSMutableArray *children = [NSMutableArray array];
			if ([mailboxes count]) {
				NSString *accountName = [object details];
				NSString *accountId = [object objectForMeta:@"accountId"];
				NSString *mailboxName = [object objectForMeta:@"mailboxName"];
				NSString *parentPath = [NSString stringWithFormat:@"%@/%@", accountName, mailboxName];
				
				@try {
					// Load sub-mailboxes on demand using scripting bridge
					NSString *mailboxPath = [self buildMailboxPathForMailbox:mailboxRef];
					[self addMailboxesFromArray:[mailboxRef mailboxes]
															toArray:children
													accountName:accountName
														accountId:accountId
												 allowLoadChildren:YES
													 parentPath:parentPath
													mailboxPath:mailboxPath
					                recursive:NO];
				} @catch (NSException *e) {
					NSLog(@"AppleMailPlugin loadChildrenForObject: Error loading sub-mailboxes: %@", e);
				}
			}
			
			// Load messages via filesystem/Spotlight (much faster for many messages)
			[children addObjectsFromArray:[self mailsForMailbox:object]];
			[object setChildren:children];
		} else {
			// Fallback to loading messages only via filesystem
			[object setChildren:[self mailsForMailbox:object]];
		}
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
	return [self allMailboxes:YES recursive:NO];
}

- (NSArray *)allMailboxes:(BOOL)allowLoadChildren recursive:(BOOL)recursive {
	NSMutableArray *objects=[NSMutableArray arrayWithCapacity:1];

	// Get Mail app instance
	MailApplication *mailApp = [SBApplication applicationWithBundleIdentifier:@"com.apple.mail"];
	if (!mailApp) {
		return objects;
	}

	// Batch fetch all accounts at once to minimize inter-process calls
	NSArray *accounts = [mailApp accounts];
	
	
	for (MailAccount *account in accounts) {
		// Cache these properties - they're expensive IPC calls
		NSString *accountName = [account name];
		NSString *accountId = [account id];
		
		if (!accountName || !accountId) {
			continue;
		}
		
		// Process mailboxes for this account
		[self addMailboxesFromArray:[account mailboxes] 
						toArray:objects 
						accountName:accountName 
						accountId:accountId 
						allowLoadChildren:allowLoadChildren
						parentPath:nil
						mailboxPath:nil
						recursive:recursive];
	}
	
	return objects;
}

- (NSString *)buildMailboxPathForMailbox:(MailMailbox *)mailbox {
	// Walk up the container hierarchy and build the complete filesystem path
	NSMutableArray *pathComponents = [NSMutableArray array];
	MailMailbox *currentMailbox = mailbox;
	
	while (currentMailbox) {
		NSString *name = [currentMailbox name];
		if (name) {
			[pathComponents insertObject:[NSString stringWithFormat:@"%@.mbox", name] atIndex:0];
		} else {
			break;
		}
		currentMailbox = [currentMailbox container];
	}
	
	return [pathComponents componentsJoinedByString:@"/"];
}

- (void)addMailboxesFromArray:(NSArray *)mailboxes toArray:(NSMutableArray *)objects accountName:(NSString *)accountName accountId:(NSString *)accountId allowLoadChildren:(BOOL)allowLoadChildren parentPath:(NSString *)parentPath mailboxPath:(NSString *)mailboxPath recursive:(BOOL)recursive {
	// Get the base Mail path with version detection
	NSString *mailPath = [self getMailPath];
	
	for (MailMailbox *mailbox in mailboxes) {
		NSString *mailboxName = [mailbox name];
		if (!mailboxName) {
			continue;
		}
		
		// Build display path (for UI)
		NSString *currentPath = parentPath ? [NSString stringWithFormat:@"%@/%@", parentPath, mailboxName] : mailboxName;
		
		// Build filesystem path (includes .mbox extensions)
		NSString *currentMailboxPath = mailboxPath ? [NSString stringWithFormat:@"%@/%@.mbox", mailboxPath, mailboxName] : [NSString stringWithFormat:@"%@.mbox", mailboxName];
		
		QSObject *newObject = [QSObject objectWithName:[NSString stringWithFormat:@"%@ %@", accountName, currentPath]];
		[newObject setObject:mailboxName forType:kQSAppleMailMailboxType];
		[newObject setLabel:mailboxName];
		[newObject setDetails:accountName];
		[newObject setObject:accountId forMeta:@"accountId"];
		[newObject setObject:mailboxName forMeta:@"mailboxName"];
		[newObject setObject:mailbox forMeta:@"mailboxReference"];
		[newObject setObject:currentMailboxPath forMeta:@"mailbox"];
		[newObject setIdentifier:[NSString stringWithFormat:@"mailbox:%@//%@", accountName, currentPath]];
		[newObject setObject:[NSNumber numberWithBool:allowLoadChildren] forMeta:kAllowLoadChildren];
		[newObject setPrimaryType:kQSAppleMailMailboxType];
		
		// Set the account path for file system access
		[newObject setObject:[mailPath stringByAppendingPathComponent:accountId] forMeta:@"accountPath"];
		
		[objects addObject:newObject];
		
		if (recursive) {
			// Recursively load sub-mailboxes
			NSArray *submailboxes = [mailbox mailboxes];
			if ([submailboxes count] > 0) {
				[self addMailboxesFromArray:submailboxes
														toArray:objects
												accountName:accountName
													accountId:accountId
									allowLoadChildren:NO
												 parentPath:currentPath
												mailboxPath:currentMailboxPath
													recursive:recursive];
			}
		}
	}
}

- (NSString *)getMailPath {
	NSString *basePath = [MAILPATH stringByStandardizingPath];
	NSFileManager *fm = [NSFileManager defaultManager];
	
	// Try to access folders in reverse increment from V11 down to V1
	NSArray *versionedPaths = @[@"V11", @"V10", @"V9", @"V8", @"V7", @"V6", @"V5", @"V4", @"V3", @"V2", @"V1"];
	for (NSString *versionedPath in versionedPaths) {
		NSString *testPath = [basePath stringByAppendingPathComponent:versionedPath];
		BOOL isDir;
		if ([fm fileExistsAtPath:testPath isDirectory:&isDir] && isDir) {
			return testPath;
		}
	}
	
	// Fallback to base path if no versioned folder found
	return basePath;
}

- (QSObject *)makeMailboxObject:(NSString *)mailbox withAccountName:(NSString *)accountName withAccountId:(NSString *)accountId withFile:(NSString *)file withChildren:(BOOL)allowLoadChildren {
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
	[newObject setObject:[NSNumber numberWithBool:allowLoadChildren] forMeta:kAllowLoadChildren];
	[newObject setPrimaryType:kQSAppleMailMailboxType];
	return newObject;
}

- (NSString *)decodeRFC2047Subject:(NSString *)subject {
	// Handle RFC 2047 encoded-word format: =?charset?encoding?encoded-text?=
	NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"=\\?([^?]+)\\?([BQ])\\?([^?]+)\\?=" options:0 error:NULL];
	NSMutableString *decoded = [subject mutableCopy];
	
	NSArray *matches = [regex matchesInString:subject options:0 range:NSMakeRange(0, [subject length])];
	
	// Process matches in reverse order to maintain string positions
	for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
		NSString *charset = [subject substringWithRange:[match rangeAtIndex:1]];
		NSString *encoding = [subject substringWithRange:[match rangeAtIndex:2]];
		NSString *encodedText = [subject substringWithRange:[match rangeAtIndex:3]];
		
		NSString *decodedPart = nil;
		
		if ([encoding isEqualToString:@"Q"]) {
			// Quoted-printable decoding
			// Replace _ with space and decode =XX sequences
			NSMutableString *qDecoded = [[encodedText stringByReplacingOccurrencesOfString:@"_" withString:@" "] mutableCopy];
			
			// Decode =XX hex sequences
			NSRegularExpression *hexRegex = [NSRegularExpression regularExpressionWithPattern:@"=([0-9A-F]{2})" options:NSRegularExpressionCaseInsensitive error:NULL];
			NSMutableData *decodedData = [NSMutableData data];
			
			NSRange searchRange = NSMakeRange(0, [qDecoded length]);
			NSArray *hexMatches = [hexRegex matchesInString:qDecoded options:0 range:searchRange];
			
			// Build the decoded bytes
			NSUInteger lastEnd = 0;
			for (NSTextCheckingResult *hexMatch in hexMatches) {
				// Add the literal characters before this hex code
				if (hexMatch.range.location > lastEnd) {
					NSString *literal = [qDecoded substringWithRange:NSMakeRange(lastEnd, hexMatch.range.location - lastEnd)];
					[decodedData appendData:[literal dataUsingEncoding:NSUTF8StringEncoding]];
				}
				
				// Decode the hex value
				NSString *hexStr = [qDecoded substringWithRange:[hexMatch rangeAtIndex:1]];
				unsigned int hexValue;
				[[NSScanner scannerWithString:hexStr] scanHexInt:&hexValue];
				unsigned char byte = (unsigned char)hexValue;
				[decodedData appendBytes:&byte length:1];
				lastEnd = hexMatch.range.location + hexMatch.range.length;
			}
			
			// Add remaining literal characters
			if (lastEnd < [qDecoded length]) {
				NSString *literal = [qDecoded substringFromIndex:lastEnd];
				[decodedData appendData:[literal dataUsingEncoding:NSUTF8StringEncoding]];
			}
			
			decodedPart = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
		} else if ([encoding isEqualToString:@"B"]) {
			// Base64 decoding
			NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:encodedText options:0];
			decodedPart = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
		}
		
		if (decodedPart) {
			[decoded replaceCharactersInRange:match.range withString:decodedPart];
		}
	}
	
	return decoded;
}

- (NSString *)messageIDFromEmlxFile:(NSString *)filePath {
	NSData *data = [NSData dataWithContentsOfFile:filePath];
	if (!data || [data length] == 0) {
		return nil;
	}
	
	// EMLX format: [byte_count]\n[message][plist]
	const char *bytes = (const char *)[data bytes];
	NSUInteger dataLen = [data length];
	
	// Find the newline that terminates the length
	NSUInteger newlinePos = 0;
	for (NSUInteger i = 0; i < dataLen && i < 20; i++) {
		if (bytes[i] == '\n') {
			newlinePos = i;
			break;
		}
	}
	
	if (newlinePos == 0) {
		return nil;
	}
	
	// Extract and parse the length number
	NSString *lengthStr = [[NSString alloc] initWithBytes:bytes length:newlinePos encoding:NSUTF8StringEncoding];
	lengthStr = [lengthStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	NSUInteger messageLength = [lengthStr integerValue];
	
	if (messageLength == 0 || (newlinePos + 1 + messageLength > dataLen)) {
		return nil;
	}
	
	// Extract just the message portion
	NSUInteger messageStart = newlinePos + 1;
	NSData *messageData = [data subdataWithRange:NSMakeRange(messageStart, messageLength)];
	NSString *messageContent = [[NSString alloc] initWithData:messageData encoding:NSUTF8StringEncoding];
	if (!messageContent) {
		return nil;
	}
	
	// Parse headers to find Message-ID
	NSArray *lines = [messageContent componentsSeparatedByString:@"\n"];
	for (NSString *line in lines) {
		if ([line hasPrefix:@"Message-Id:"]) {
			NSString *messageId = [[line substringFromIndex:11] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			if ([messageId hasPrefix:@"<"] && [messageId hasSuffix:@">"]) {
				messageId = [messageId substringWithRange:NSMakeRange(1, [messageId length] - 2)];
			}
			return messageId;
		}
		// Stop at first blank line (end of headers)
		if ([line length] == 0) {
			break;
		}
	}
	
	return nil;
}

- (NSDictionary *)emailMetadataFromFile:(NSString *)filePath {
	NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
	NSData *data = [NSData dataWithContentsOfFile:filePath];
	if (!data || [data length] == 0) {
		return metadata;
	}
	
	// EMLX format: [byte_count]\n[message][plist]
	// First, parse the length header
	const char *bytes = (const char *)[data bytes];
	NSUInteger dataLen = [data length];
	
	// Find the newline that terminates the length
	NSUInteger newlinePos = 0;
	for (NSUInteger i = 0; i < dataLen && i < 20; i++) {
		if (bytes[i] == '\n') {
			newlinePos = i;
			break;
		}
	}
	
	if (newlinePos == 0) {
		return metadata;
	}
	
	// Extract and parse the length number
	NSString *lengthStr = [[NSString alloc] initWithBytes:bytes length:newlinePos encoding:NSUTF8StringEncoding];
	lengthStr = [lengthStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	NSUInteger messageLength = [lengthStr integerValue];
	
	if (messageLength == 0 || (newlinePos + 1 + messageLength > dataLen)) {
		return metadata;
	}
	
	// Extract just the message portion
	NSUInteger messageStart = newlinePos + 1;
	NSData *messageData = [data subdataWithRange:NSMakeRange(messageStart, messageLength)];
	NSString *messageContent = [[NSString alloc] initWithData:messageData encoding:NSUTF8StringEncoding];
	if (!messageContent) {
		return metadata;
	}
	
	// Parse headers to find Subject and From
	NSArray *lines = [messageContent componentsSeparatedByString:@"\n"];
	for (NSString *line in lines) {
		if ([line hasPrefix:@"Subject:"]) {
			NSString *subject = [[line substringFromIndex:8] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			if (subject && [subject length] > 0) {
				// Decode RFC 2047 encoded-word format
				subject = [self decodeRFC2047Subject:subject];
				[metadata setObject:subject forKey:@"subject"];
			}
		}
		if ([line hasPrefix:@"From:"]) {
			NSString *from = [[line substringFromIndex:5] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			if (from && [from length] > 0) {
				[metadata setObject:from forKey:@"from"];
			}
		}
		// Stop at first blank line (end of headers)
		if ([line length] == 0) {
			break;
		}
	}
	
	return metadata;
}

- (NSArray *)mailsForMailbox:(QSObject *)object {
	NSString *mailboxName = [object objectForType:kQSAppleMailMailboxType];
	NSString *accountID = [object objectForMeta:@"accountId"];
	NSString *accountPath = [object objectForMeta:@"accountPath"];
	MailMailbox *mailboxRef = [object objectForMeta:@"mailboxReference"];
	NSMutableArray *objects = [NSMutableArray arrayWithCapacity:0];
	
	if (!accountPath || !mailboxRef) {
		return objects;
	}
	
	// Build the complete mailbox path by walking up containers if we have the reference
	NSString *mailboxPath;
	mailboxPath = [accountPath stringByAppendingPathComponent:[self buildMailboxPathForMailbox:mailboxRef]];
	NSFileManager *fm = [NSFileManager defaultManager];
	
	// Check if mailbox path exists
	BOOL isDir;
	if (![fm fileExistsAtPath:mailboxPath isDirectory:&isDir] || !isDir) {
		return objects;
	}
	
	@autoreleasepool {
		// Recursively find all .emlx files in the mailbox
		NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:mailboxPath];
		NSMutableArray *emlxFiles = [NSMutableArray array];
		
		for (NSString *file in enumerator) {
			if ([[file pathExtension] isEqualToString:@"emlx"]) {
				[emlxFiles addObject:[mailboxPath stringByAppendingPathComponent:file]];
			}
		}
		
		// If mailbox folder is empty, just return empty array
		if ([emlxFiles count] == 0) {
			return objects;
		}
		
		// Normal case: process files found in the mailbox folder
		NSLock *arrayLock = [[NSLock alloc] init];
		[emlxFiles enumerateObjectsWithOptions:NSEnumerationConcurrent usingBlock:^(NSString *filePath, NSUInteger idx, BOOL *stop) {
			NSDictionary *metadata = [self emailMetadataFromFile:filePath];
			NSString *subject = metadata[@"subject"];
			NSString *from = metadata[@"from"];
			
			if (!subject) {
				return;
			}
			
			if ([subject length] > 255) {
				subject = [subject substringToIndex:255];
			}
			NSString *fsName = [filePath lastPathComponent];
			
			QSObject *messageObjectNew = [[QSObject alloc] init];
			[messageObjectNew setPrimaryType:kQSAppleMailMessageType];
			[messageObjectNew setObject:accountPath forMeta:@"accountPath"];
			[messageObjectNew setObject:mailboxName forMeta:@"mailboxName"];
			[messageObjectNew setObject:accountID forMeta:@"accountId"];
			[messageObjectNew setObject:[object details] forMeta:@"accountName"];
			[messageObjectNew setParentID:[object identifier]];
			[messageObjectNew setObject:subject forMeta:kQSObjectPrimaryName];
			[messageObjectNew setDetails:from];
			[messageObjectNew setIdentifier:[NSString stringWithFormat:@"message:%@", fsName]];
			[messageObjectNew setObject:fsName forMeta:@"message_id"];
			if (subject) {
				[[messageObjectNew dataDictionary] setObject:subject forKey:kQSAppleMailMessageType];
			}
			[messageObjectNew setObject:filePath forMeta:QSFilePathType];
			
			// Lock only for the array addition (fast operation)
			[arrayLock lock];
			[objects addObject:messageObjectNew];
			[arrayLock unlock];
		}];
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
