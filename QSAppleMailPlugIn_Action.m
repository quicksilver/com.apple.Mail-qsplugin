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
		return [[QSReg getClassInstance:@"QSAppleMailPlugIn_Source"] allMailboxes:NO];
	}
	return nil;
}

- (QSObject *)revealMailbox:(QSObject *)dObject{
	NSString *mailbox=[dObject objectForType:kQSAppleMailMailboxType];
	NSArray *arguments=[NSArray arrayWithObjects:mailbox,[self makeAccountPath:dObject],nil];

	NSAppleScript *script=[(QSAppleMailMediator *)[QSReg getClassInstance:@"QSAppleMailMediator"] mailScript];
	NSDictionary *err = nil;
	[script executeSubroutine:@"open_mailbox" arguments:arguments error:&err];
	if (err) {
		NSLog(@"AppleMailPlugin revealMailbox: Applescirpt error %@", err);
		return nil;
	}
	return nil;
}

- (QSObject *)revealMessage:(QSObject *)dObject{
	NSAppleEventDescriptor *arguments = [NSAppleEventDescriptor listDescriptor];
	[arguments insertDescriptor:[NSAppleEventDescriptor descriptorWithInt32:[[dObject objectForMeta:@"message_id"] integerValue]] atIndex:0];
	[arguments insertDescriptor:[NSAppleEventDescriptor descriptorWithString:[dObject objectForMeta:@"mailboxName"]] atIndex:0];
	[arguments insertDescriptor:[NSAppleEventDescriptor descriptorWithString:[self makeAccountPath:dObject]] atIndex:0];

	NSAppleScript *script=[(QSAppleMailMediator *)[QSReg getClassInstance:@"QSAppleMailMediator"] mailScript];
	NSDictionary *err = nil;
	[script executeSubroutine:@"open_message" arguments:arguments error:&err];
	if (err) {
		NSLog(@"AppleMailPlugin revealMessage: Applescirpt error %@", err);
		return nil;
	}
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
    // read the entire message file in as a string
	NSError *e;
	NSString *messagePath = [object objectForType:QSFilePathType];
	NSString *rawMessage = [NSString stringWithContentsOfFile:messagePath encoding:NSUTF8StringEncoding error:&e];
	[[rawMessage lines] enumerateObjectsWithOptions:NSEnumerationConcurrent usingBlock:^(NSString *line, NSUInteger i, BOOL *stop){
		// look for "Message-Id: <ABC123>" (ignore case)
		NSArray *parts = [line componentsSeparatedByString:@":"];
		if ([parts count] == 2) {
			if ([[[parts objectAtIndex:0] lowercaseString] isEqualToString:@"message-id"]) {
				// Message ID found
				*stop = YES;
				// get the value
				NSString *idContainer = [parts objectAtIndex:1];
				// turn ' <some-id>' into 'some-id'
				NSRange idRange = NSMakeRange(2, [idContainer length] - 3);
				NSString *messageID = [idContainer substringWithRange:idRange];
				//NSLog(@"Message ID: %@", messageID);
				NSPredicate *messageByID = [NSPredicate predicateWithFormat:@"messageId == %@", messageID];
				NSString *mailbox = [object objectForMeta:@"mailboxName"];
				MailAccount *account = [[Mail accounts] objectWithName:[object objectForMeta:@"accountName"]];
				if (account) {
					MailMailbox *box = [[account mailboxes] objectWithName:mailbox];
					NSArray *matches = [[box messages] filteredArrayUsingPredicate:messageByID];
					if ([matches count]) {
						message = [matches objectAtIndex:0];
						//NSLog(@"Message: %@", [message subject]);
					}
				}
			}
		}
	}];
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
