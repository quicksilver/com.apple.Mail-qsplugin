//
//  QSAppleMailPlugIn_Action.h
//  QSAppleMailPlugIn
//
//  Created by Nicholas Jitkoff on 9/28/04.
//  Copyright __MyCompanyName__ 2004. All rights reserved.
//

#import "QSAppleMailMediator.h"
#define QSAppleMailPlugIn_Type @"QSAppleMailPlugIn_Type"

@class MailApplication;

@interface QSAppleMailPlugIn_Action : QSActionProvider
{
	MailApplication *Mail;
}
@end

