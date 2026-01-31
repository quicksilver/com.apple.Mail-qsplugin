//
//  QSAppleMailPlugIn_Action.m
//  QSAppleMailPlugIn
//
//  Created by Nicholas Jitkoff on 9/28/04.
//  Copyright __MyCompanyName__ 2004. All rights reserved.
//

#import "QSAppleMailPlugIn_Action.h"
#import "QSAppleMailPlugIn_Source.h"
#import "Mail.h"
@interface QSAppleMailPlugIn_Action (hidden)
- (NSString *)makeAccountPath:(QSObject *)object;
@end

@implementation QSAppleMailPlugIn_Action

- (id)init
{
    self = [super init];
    if (self) {
        Mail = [SBApplication applicationWithBundleIdentifier:@"com.apple.mail"];
    }
    return self;
}


- (NSArray *)validIndirectObjectsForAction:(NSString *)action directObject:(QSObject *)dObject
{
	if ([action isEqualToString:@"QSAppleMailMessageMoveAction"]) {
		// override loading the children for indirect object
		return [[QSReg getClassInstance:@"QSAppleMailPlugIn_Source"] allMailboxes:NO recursive:YES];
	}
	return nil;
}

- (QSObject *)revealMailbox:(QSObject *)dObject{
	// Get the mailbox name and account name from the QSObject metadata
	NSString *mailboxName = [dObject objectForType:kQSAppleMailMailboxType];
	NSString *accountName = [dObject details];
	
	if (!mailboxName || !accountName) {
		return nil;
	}
	
	@try {
		// Get or create a message viewer using scripting bridge
		NSArray *viewers = [Mail messageViewers];
		MailMessageViewer *viewer = nil;
		
		if ([viewers count] > 0) {
			viewer = [viewers objectAtIndex:0];
		}
		
		if (viewer) {
			// Activate Mail and bring window to front
			[Mail activate];
			MailWindow *window = [viewer window];
			if (window) {
				[window setIndex:0];
			}
			
			// Try to find the mailbox by iterating through accounts (serial, for thread safety)
			for (MailAccount *account in [Mail accounts]) {
				if ([[account name] isEqualToString:accountName]) {
					// Recursively search for the mailbox through nested structure
					MailMailbox *foundMailbox = [self findMailboxNamed:mailboxName inMailboxArray:[account mailboxes]];
					if (foundMailbox) {
						[viewer setSelectedMailboxes:@[foundMailbox]];
					}
					break;
				}
			}
		}
	} @catch (NSException *e) {
		NSLog(@"AppleMailPlugin revealMailbox: Error %@", e);
		return nil;
	}
	
	return nil;
}

- (MailMailbox *)findMailboxNamed:(NSString *)targetName inMailboxArray:(NSArray *)mailboxes {
	for (MailMailbox *mbox in mailboxes) {
		if ([[mbox name] isEqualToString:targetName]) {
			return mbox;
		}
		
		// Recursively search sub-mailboxes
		MailMailbox *subMailbox = [self findMailboxNamed:targetName inMailboxArray:[mbox mailboxes]];
		if (subMailbox) {
			return subMailbox;
		}
	}
	
	return nil;
}

- (QSObject *)revealMessage:(QSObject *)dObject{
	NSString *messageFilePath = [dObject objectForMeta:QSFilePathType];
	
	if (!messageFilePath) {
		return nil;
	}
	
	// Open the .emlx file directly with Mail.app
	[[NSWorkspace sharedWorkspace] openFile:messageFilePath withApplication:@"Mail"];
	
	return nil;
}

- (QSBasicObject *)deleteMessage:(QSObject *)dObject
{
	MailMessage *message = [self messageObjectFromQSObject:dObject];
	[message delete];
	return [QSObject nullObject];
}

- (QSObject *)moveMessage:(QSObject *)dObject toMailbox:(QSObject *)iObject
{
	MailMessage *message = [self messageObjectFromQSObject:dObject];
	MailMailbox *mailbox = [self mailboxObjectFromQSObject:iObject];
	[message moveTo:mailbox];
	return nil;
}

- (NSString *)makeAccountPath:(QSObject *)object {
	if ([[object objectForMeta:@"accountId"] isEqualToString:@"Local Mailbox"]) {
		return @"local";
	} else {
		return [object objectForMeta:@"accountPath"];
	}
}

- (MailMessage *)messageObjectFromQSObject:(QSObject *)object
{
	// open message file, parse for message ID, look up message ID with Scripting Bridge
	MailMessage __block *message = nil;
	NSError *fileError = nil;
	NSString *messageFilePath = [object objectForType:QSFilePathType];
	NSString *rawMessage = [NSString stringWithContentsOfFile:messageFilePath encoding:NSUTF8StringEncoding error:&fileError];
	
	NSString __block *messageID = nil;
	[[rawMessage componentsSeparatedByString:@"\n"] enumerateObjectsUsingBlock:^(NSString *line, NSUInteger idx, BOOL *stop) {
		NSArray *parts = [line componentsSeparatedByString:@":"];
		if ([parts count] >= 2) {
			NSString *key = [[parts objectAtIndex:0] lowercaseString];
			if ([key isEqualToString:@"message-id"]) {
				messageID = [[parts objectAtIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
				// Remove angle brackets if present
				if ([messageID hasPrefix:@"<"] && [messageID hasSuffix:@">"]) {
					messageID = [messageID substringWithRange:NSMakeRange(1, [messageID length] - 2)];
				}
				*stop = YES;
			}
		}
	}];
	
	if (messageID) {
		NSString *mailbox = [object objectForMeta:@"mailboxName"];
		MailAccount *account = [[Mail accounts] objectWithName:[object objectForMeta:@"accountName"]];
		if (account) {
			MailMailbox *box = [[account mailboxes] objectWithName:mailbox];
			for (MailMessage *msg in [box messages]) {
				if ([[msg messageId] isEqualToString:messageID]) {
					message = msg;
					break;
				}
			}
		}
	}
	
	return message;
}

- (MailMailbox *)mailboxObjectFromQSObject:(QSObject *)object
{
	MailAccount *account = [[Mail accounts] objectWithName:[object details]];
	if (account) {
		NSString *mailboxName = [object objectForType:kQSAppleMailMailboxType];
		MailMailbox *mailbox = [[account mailboxes] objectWithName:mailboxName];
		return mailbox;
	}
	return nil;
}

@end
