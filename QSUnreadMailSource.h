//
//  QSUnreadMailSource.h
//  AppleMailElement
//
//  Created by Rob McBroom on 2012/05/17.
//

#import <QSCore/QSCore.h>
@class MailApplication;

@interface QSUnreadMailSource : QSObjectSource
{
	MailApplication *Mail;
}
@end
