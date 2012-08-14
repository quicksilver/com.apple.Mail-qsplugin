#import "QSAppleMailMediator.h"
#import "QSMailMediator.h"
@class QSCountBadgeImage;

@implementation QSAppleMailMediator

- (void) sendEmailTo:(NSArray *)addresses from:(NSString *)sender subject:(NSString *)subject body:(NSString *)body attachments:(NSArray *)pathArray sendNow:(BOOL)sendNow{
    if (!sender){
        NSArray *accounts=[[[self mailScript] executeSubroutine:@"account_list"
													  arguments:[NSArray arrayWithObjects:subject,body,addresses,pathArray,nil]
														  error:nil]objectValue];
		//NSLog(@"accounts %@",accounts);
        NSInteger accountIndex = 0;
        for (NSUInteger i=0; i<[accounts count]; i++) {
            if (emailsShareDomain([addresses lastObject],[[accounts objectAtIndex:i]objectAtIndex:0])){
                accountIndex = i;
                break;
            }
        }
        NSArray *account=[accounts objectAtIndex:accountIndex];
        NSString *accountFormatted=[(NSString *)[account lastObject]length]?[NSString stringWithFormat:@"%@ <%@>",[account lastObject],[account objectAtIndex:0]]:[account objectAtIndex:0];
        sender=accountFormatted;
        //NSLog(@"accounts %@",accountFormatted);
        
    }
	[[QSReg getClassInstance:@"QSMailMediator"] sendEmailWithScript:[self mailScript] to:(NSArray *)addresses from:(NSString *)sender subject:(NSString *)subject body:(NSString *)body attachments:(NSArray *)pathArray sendNow:(BOOL)sendNow];

 //   [self superSendEmailTo:(NSArray *)addresses from:(NSString *)sender subject:(NSString *)subject body:(NSString *)body attachments:(NSArray *)pathArray sendNow:(BOOL)sendNow];
}

- (NSString *)scriptPath{
    return [[NSBundle bundleForClass:[QSAppleMailMediator class]]pathForResource:@"Mail" ofType:@"scpt"];
}

//-------------------------

- (void) superSendEmailTo:(NSArray *)addresses from:(NSString *)sender subject:(NSString *)subject body:(NSString *)body attachments:(NSArray *)pathArray sendNow:(BOOL)sendNow{
    
    if (!sender)sender=@""; 
    if (!addresses){ 
        NSRunAlertPanel(@"Invalid address",@"Missing email address", nil,nil,nil);
        
        // [self sendDirectEmailTo:address subject:subject body:body attachments:pathArray];
        return;
    }
    
//    if (VERBOSE)NSLog(@"Sending Email:\r     To: %@\rSubject: %@\r   Body: %@\rAttachments: %@\r",[addresses componentsJoinedByString:@", "],subject,body,[pathArray componentsJoinedByString:@"\r"]);
    
    NSDictionary *errorDict=nil;
    
    //id message=
	[[self mailScript] executeSubroutine:(sendNow?@"send_mail":@"compose_mail")
							   arguments:[NSArray arrayWithObjects:subject,body,sender,addresses,(pathArray?pathArray:[NSArray array]),nil]
								   error:&errorDict];
    //  NSLog(@"%@",message);
    if (errorDict) 
        NSRunAlertPanel(@"An error occured while sending mail", [errorDict objectForKey:@"NSAppleScriptErrorMessage"], nil,nil,nil);
}



- (NSAppleScript *)mailScript {
    if (!mailScript){
        NSString *path=[self scriptPath];
        if (path) mailScript=[[NSAppleScript alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:nil];
    }
    return mailScript;
}

- (void)setMailScript:(NSAppleScript *)newMailScript {
    [mailScript release];
    mailScript = [newMailScript retain];
}

+ (NSDictionary *)mailPreferences
{
	// locate and read Mail.app's preferences
	NSString *prefs = [@"~/Library/Preferences/" stringByStandardizingPath];
	NSArray *paths = [[NSFileManager defaultManager] subpathsAtPath:prefs];
	NSDictionary *mailPrefs = nil;
	NSPredicate *mailPrefix = [NSPredicate predicateWithFormat:@"SELF BEGINSWITH[c] 'com.apple.mail' AND NOT SELF ENDSWITH[c] '.lockfile'"];
	NSString *prefFile = [[paths filteredArrayUsingPredicate:mailPrefix] objectAtIndex:0];
	NSString *prefPath = [prefs stringByAppendingPathComponent:prefFile];
	mailPrefs = [NSDictionary dictionaryWithContentsOfFile:prefPath];
	return mailPrefs;
}

- (NSDictionary *)smtpServerDetails
{
	NSArray *smtpList = [[QSAppleMailMediator mailPreferences] objectForKey:@"DeliveryAccounts"];
	if ([smtpList count]) {
		NSMutableDictionary *details = [[smtpList objectAtIndex:0] mutableCopy];
		[details setObject:[details objectForKey:@"SSLEnabled"] forKey:QSMailMediatorTLS];
		if ([[details objectForKey:QSMailMediatorAuthenticate] isEqualToString:@"YES"]) {
			NSString *server = [details objectForKey:QSMailMediatorServer];
			NSString *user = [details objectForKey:QSMailMediatorUsername];
			UInt32 passLen = 0;
			void *password = nil;
			OSStatus status = SecKeychainFindInternetPassword(NULL, (UInt32)[server length], [server UTF8String], 0, NULL, (UInt32)[user length], [user UTF8String], 0, NULL, 0, kSecProtocolTypeSMTP, kSecAuthenticationTypeDefault, &passLen, &password, NULL);
			if (status == noErr) {
				NSString *smtpPassword = [NSString stringWithCString:password encoding:[NSString defaultCStringEncoding]];
				SecKeychainItemFreeContent(NULL, password);
				[details setObject:smtpPassword forKey:QSMailMediatorPassword];
			}
		}
		return details;
	}
	return nil;
}

- (NSImage *)iconForAction:(NSString *)actionID
{
	if ([actionID isEqualToString:@"QSEmailItemAction"] || [actionID isEqualToString:@"QSEmailItemReverseAction"]) {
		// actions that send immediately
		return [QSResourceManager imageNamed:@"MailMailbox-Sent"];
	}
	return [QSResourceManager imageNamed:@"com.apple.Mail"];
}



@end
