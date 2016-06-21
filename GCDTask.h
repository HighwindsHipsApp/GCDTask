//
//  GCDTask.h
//
//  Author: Darvell Long
//  Copyright (c) 2014 Reliablehosting.com. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface GCDTask : NSObject

@property (nonatomic, copy) void (^outputHandler)(NSData *);
@property (nonatomic, copy) void (^errorHandler)(NSData *);
@property (nonatomic, copy) void (^launchHandler)();
@property (nonatomic, copy) void (^exitHandler)();

/**
 * Initialize the GCDTask with the specified launch path and arguments.
 *
 * @param NSString *launchPath The task to launch
 * @param NSArray  *arguments  The arguments to launch the task.
 */
- (id)initWithLaunchPath:(NSString *)launchPath andArguments:(NSArray *)arguments;

/**
 * Launch the task
 */
- (void)launch;

/**
 * Writes the input string to the stdin. Converts the string to data using UTF8 encoding.
 *
 * @param NSString *input The string to send to stdin
 */
- (BOOL)writeStringToStandardInput:(NSString *)input;

/**
 * Writes the data to the stdin
 *
 * @param NSData *input The data to send to stdin
 */
- (BOOL)writeDataToStandardInput:(NSData *)input;

/**
 * Terminates the GCDTask. First it will request SIGINT, then it will force SIGTERM after 10 seconds.
 */
- (void)requestTermination;

/**
 * Calls waitUntilExit on the currently executing internal NSTask.
 */
- (void)waitUntilExit;

@end