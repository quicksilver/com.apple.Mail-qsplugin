//
//  QSAppleMailPlugIn_Source.h
//  QSAppleMailPlugIn
//
//  Created by Nicholas Jitkoff on 9/28/04.
//  Copyright __MyCompanyName__ 2004. All rights reserved.
//

#define kQSAppleMailMailboxType @"qs.mail.mailbox"
#define kQSAppleMailMessageType @"qs.mail.message"
#define MAIL_BID @"com.apple.mail"
#define MAILPATH @"~/Library/Mail"

@interface QSAppleMailPlugIn_Source : NSObject
{
}
- (NSArray *)allMailboxes;
- (NSArray *)allMailboxes:(BOOL)loadChildren;
@end

