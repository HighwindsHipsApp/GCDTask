//
//  GCDTask.h
//
//  Author: Darvell Long
//  Copyright (c) 2014 Reliablehosting.com. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface GCDTask : NSObject

- (id)initWithLaunchPath:(NSString *)launchPath andArguments:(NSArray *)arguments;

- (void)launchWithOutputBlock:(void (^)(NSData *))outputHandler
               andErrorBlock:(void (^)(NSData *))errorHandler
                    onLaunch:(void (^)())launchHandler
                      onExit:(void (^)())exitHandler;

- (BOOL)writeStringToStandardInput:(NSString *)input;
- (BOOL)writeDataToStandardInput:(NSData *)input;

- (void)requestTermination;
- (void)waitUntilExit;

@end