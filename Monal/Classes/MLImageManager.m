//
//  MLImageManager.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/16/13.
//
//

#import "MLImageManager.h"
#import "HelperTools.h"
#import "DataLayer.h"
#import "AESGcm.h"
#import "UIColor+Extension.h"


@interface MLImageManager()
@property (nonatomic, strong) NSCache* iconCache;
@property (nonatomic, strong) NSString* documentsDirectory;
@end

@implementation MLImageManager

#pragma mark initilization

+(MLImageManager*) sharedInstance
{
    static dispatch_once_t once;
    static MLImageManager* sharedInstance;
    dispatch_once(&once, ^{
        DDLogVerbose(@"Creating shared image manager instance...");
        sharedInstance = [[MLImageManager alloc] init];
    });
    return sharedInstance;
}

+(UIImage*) circularImage:(UIImage*) image
{
    UIImage* composedImage;
    UIGraphicsBeginImageContextWithOptions(image.size, NO, 0);
    
    UIBezierPath* clipPath = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, image.size.width, image.size.height)];
    [clipPath addClip];
    
    // Flip coordinates before drawing image as UIKit and CoreGraphics have inverted coordinate system
    CGContextTranslateCTM(UIGraphicsGetCurrentContext(), 0, image.size.height);
    CGContextScaleCTM(UIGraphicsGetCurrentContext(), 1, -1);
    
    CGContextDrawImage(UIGraphicsGetCurrentContext(), CGRectMake(0, 0, image.size.width, image.size.height), image.CGImage);
    composedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return composedImage;
}

-(id) init
{
    self = [super init];
    self.iconCache = [[NSCache alloc] init];
    
    NSFileManager* fileManager = [NSFileManager defaultManager];
    
    self.documentsDirectory = [[fileManager containerURLForSecurityApplicationGroupIdentifier:kAppGroup] path];
    
    NSString* writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"imagecache"];
    [fileManager createDirectoryAtPath:writablePath withIntermediateDirectories:YES attributes:nil error:nil];
    [HelperTools configureFileProtectionFor:writablePath];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleMemoryPressureNotification) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    
    return self;
}

-(void) deinit
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void) handleMemoryPressureNotification
{
    DDLogVerbose(@"Removing all objects in avatar cache due to memory pressure...");
    [self purgeCache];
}

#pragma mark cache

-(void) purgeCache
{
    [self.iconCache removeAllObjects];
}

-(void) purgeCacheForContact:(NSString*) contact andAccount:(NSString*) accountNo
{
    [self.iconCache removeObjectForKey:[NSString stringWithFormat:@"%@_%@",accountNo,contact]];
}

-(void) cleanupHashes
{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSArray<MLContact*>* contactList = [[DataLayer sharedInstance] contactList];
    
    for(MLContact* contact in contactList)
    {
        NSString* writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"buddyicons"];
        writablePath = [writablePath stringByAppendingPathComponent:contact.accountId];
        writablePath = [writablePath stringByAppendingPathComponent:[self fileNameforContact:contact.contactJid]];
        BOOL hasHash = [@"" isEqualToString:[[DataLayer sharedInstance] getAvatarHashForContact:contact.contactJid andAccount:contact.accountId]];
        
        if(hasHash && ![fileManager isReadableFileAtPath:writablePath])
        {
            DDLogDebug(@"Deleting orphan hash of contact: %@", contact);
            //delete avatar hash from db if the file containing our image data vanished
            [[DataLayer sharedInstance] setAvatarHash:@"" forContact:contact.contactJid andAccount:contact.accountId];
        }
        
        if(!hasHash && [fileManager isReadableFileAtPath:writablePath])
        {
            DDLogDebug(@"Deleting orphan avatar file of contact: %@", contact);
            NSError* error;
            [fileManager removeItemAtPath:writablePath error:&error];
            if(error)
                DDLogError(@"Error deleting orphan avatar file: %@", error);
        }
    }
}

-(void) removeAllIcons
{
    NSError* error;
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSString* writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"buddyicons"];
    [fileManager removeItemAtPath:writablePath error:&error];
    if(error)
        DDLogError(@"Got error when removing buddyicons: %@", error);
}

#pragma mark chat bubbles

-(UIImage*) inboundImage
{
    if(_inboundImage)
        return _inboundImage;
    _inboundImage = [[UIImage imageNamed:@"incoming"] resizableImageWithCapInsets:UIEdgeInsetsMake(6, 6, 6, 6)];
    return _inboundImage;
    
}

-(UIImage*) outboundImage
{
    if (_outboundImage)
        return _outboundImage;
    _outboundImage = [[UIImage imageNamed:@"outgoing"] resizableImageWithCapInsets:UIEdgeInsetsMake(6, 6, 6, 6)];
    return _outboundImage;
}

#pragma mark user icons

-(UIImage*) generateDummyIconForContact:(MLContact*) contact
{
    UIColor* background = [HelperTools generateColorFromJid:contact.contactJid];
    UIColor* foreground = [UIColor blackColor];
    if(![background isLightColor])
        foreground = [UIColor whiteColor];
    
    UIGraphicsImageRenderer* renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(200, 200)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        [background setFill];
        [context fillRect:renderer.format.bounds];
        
        NSString* contactLetter = [[[contact contactDisplayName] substringToIndex:1] uppercaseString];
        
        NSMutableParagraphStyle* paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
        paragraphStyle.alignment = NSTextAlignmentCenter;
        NSDictionary* attributes = @{
            NSFontAttributeName: [[UIFont preferredFontForTextStyle:UIFontTextStyleLargeTitle] fontWithSize:120],
            NSForegroundColorAttributeName: foreground,
            NSParagraphStyleAttributeName: paragraphStyle
        };
        CGSize textSize = [contactLetter sizeWithAttributes:attributes];
        CGRect textRect = CGRectMake(floorf((renderer.format.bounds.size.width - textSize.width) / 2),
                                    floorf((renderer.format.bounds.size.height - textSize.height) / 2),
                                    textSize.width,
                                    textSize.height);
        [contactLetter drawInRect:textRect withAttributes:attributes];
    }];
}

-(NSString*) fileNameforContact:(NSString*) contact
{
    return [NSString stringWithFormat:@"%@.png", [contact lowercaseString]];;
}

-(void) setIconForContact:(NSString*) contact andAccount:(NSString*) accountNo WithData:(NSData* _Nullable) data
{
    //documents directory/buddyicons/account no/contact
    
    NSString* filename = [self fileNameforContact:contact];
    
    NSFileManager* fileManager = [NSFileManager defaultManager];
    
    NSString *writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"buddyicons"];
    writablePath = [writablePath stringByAppendingPathComponent:accountNo];
    NSError* error;
    [fileManager createDirectoryAtPath:writablePath withIntermediateDirectories:YES attributes:nil error:&error];
    [HelperTools configureFileProtectionFor:writablePath];
    writablePath = [writablePath stringByAppendingPathComponent:filename];
    
    if([fileManager fileExistsAtPath:writablePath])
        [fileManager removeItemAtPath:writablePath error:nil];

    if(data)
    {
        if([data writeToFile:writablePath atomically:NO])
        {
            [HelperTools configureFileProtectionFor:writablePath];
            DDLogVerbose(@"wrote image to file: %@", writablePath);
        }
        else
            DDLogError(@"failed to write image to file: %@", writablePath);
    }
    
    //remove from cache if its there
    [self.iconCache removeObjectForKey:[NSString stringWithFormat:@"%@_%@", accountNo, contact]];
    
}

-(UIImage*) getIconForContact:(MLContact*) contact
{
    return [self getIconForContact:contact withCompletion:nil];
}

-(UIImage*) getIconForContact:(MLContact*) contact withCompletion:(void (^)(UIImage *))completion
{
    DDLogVerbose(@"getIconForContact: %@", contact);
    NSString* filename = [self fileNameforContact:contact.contactJid];
    DDLogVerbose(@"filename: %@", filename);
    
    __block UIImage* toreturn = nil;
    //get filname from DB
    NSString* cacheKey = [NSString stringWithFormat:@"%@_%@", contact.accountId, contact.contactJid];
    DDLogVerbose(@"cache key: %@", cacheKey);
    
    //check cache
    toreturn = [self.iconCache objectForKey:cacheKey];
    DDLogVerbose(@"after cache try: %@", toreturn);
    if(!toreturn)
    {
        if(contact.isGroup)
            toreturn = [@"channel" isEqualToString:contact.mucType] ? [UIImage imageNamed:@"noicon_channel"] : [UIImage imageNamed:@"noicon_muc"];
        else
        {
            NSString* writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"buddyicons"];
            writablePath = [writablePath stringByAppendingPathComponent:contact.accountId];
            writablePath = [writablePath stringByAppendingPathComponent:filename];

            DDLogVerbose(@"loading avatar image at %@", writablePath);
            NSFileManager* fileManager = [NSFileManager defaultManager];
            NSError* error;
            NSDictionary* fileAttributes = [fileManager attributesOfItemAtPath:writablePath error:&error];
            if(error)
                DDLogError(@"Error while getting file attributes: %@", error);
            else
                DDLogVerbose(@"image file size: %@", fileAttributes[NSFileSize]);
            [DDLog flushLog];
            UIImage* savedImage = [UIImage imageWithContentsOfFile:writablePath];
            if(savedImage)
                toreturn = savedImage;
            DDLogVerbose(@"after file load: %@", toreturn);

            if(toreturn == nil)
            {
                DDLogVerbose(@"Generating dummy icon...");
                toreturn = [self generateDummyIconForContact:contact];
            }
        }
        
        //uiimage image named is cached if avaialable, but onlyif not in appex due to memory limits therein
        if(toreturn && ![HelperTools isAppExtension])
        {
            DDLogVerbose(@"Caching image under key %@", cacheKey);
            [DDLog flushLog];
            [self.iconCache setObject:toreturn forKey:cacheKey];
        }
        if(completion)
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(toreturn);
            });
    }
    else if(completion)
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(toreturn);
        });
    DDLogVerbose(@"returning %@", toreturn);
    [DDLog flushLog];
    return toreturn;
}


-(BOOL) saveBackgroundImageData:(NSData *) data {
    NSFileManager* fileManager = [NSFileManager defaultManager];

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *writablePath = [documentsDirectory stringByAppendingPathComponent:@"background.jpg"];

    if([fileManager fileExistsAtPath:writablePath])
    {
        [fileManager removeItemAtPath:writablePath error:nil];
    }

    return [data writeToFile:writablePath atomically:YES];
}

-(UIImage*) getBackground:(BOOL) forceReload
{
    // use cached image
    if(self.chatBackground && forceReload == NO)
        return self.chatBackground;
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* documentsDirectory = [paths objectAtIndex:0];
    NSString* writablePath = [documentsDirectory stringByAppendingPathComponent:@"background.jpg"];

    self.chatBackground = [UIImage imageWithContentsOfFile:writablePath];

    return self.chatBackground;
}

-(void) resetBackgroundImage
{
    self.chatBackground = nil;
}

/*
- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite{
    
}
*/
@end
