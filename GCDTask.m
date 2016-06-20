//
//  GCDTask.m
//
//  Author: Darvell Long
//  Copyright (c) 2014 Reliablehosting.com. All rights reserved.
//

#import "GCDTask.h"


#ifdef GCDTASK_DEBUG
#define GCDDebug(str, ...) NSLog(str, ##__VA_ARGS__)
#else
#define GCDDebug(str, ...)
#endif

#define GCDTASK_BUFFER_MAX 4096

@interface GCDTask ()

@property (strong) NSPipe *stdoutPipe;
@property (strong) NSPipe *stdinPipe;
@property (strong) NSPipe *stderrPipe;

@property (strong) NSTask *executingTask;

@property (strong) NSString* launchPath;
@property (strong) NSArray* arguments;

@property BOOL hasExecuted;

@property __block dispatch_source_t stdoutSource;
@property __block dispatch_source_t stderrSource;

@end

@implementation GCDTask

- (id)initWithLaunchPath:(NSString *)launchPath andArguments:(NSArray *)arguments {
    self = [super init];

    if (self) {
        _launchPath = launchPath;
        _arguments = arguments;
    }

    return self;
}

- (void)launchWithOutputBlock:(void (^)(NSData *))outputHandler
                andErrorBlock:(void (^)(NSData *))errorHandler
                     onLaunch:(void (^)())launchHandler
                       onExit:(void (^)())exitHandler {

    // Setup a local variable
    NSTask *executingTask = [[NSTask alloc] init];
 
    /* Set launch path. */
    [executingTask setLaunchPath:[_launchPath stringByStandardizingPath]];
    
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:[executingTask launchPath]]) {
        @throw [NSException exceptionWithName:@"GCDTASK_INVALID_EXECUTABLE" reason:@"There is no executable at the path set." userInfo:nil];
    }

    /* Clean then set arguments. */
    for (id arg in _arguments) {
        if([arg class] != [NSString class]) {
            NSMutableArray* cleanedArray = [[NSMutableArray alloc] init];
            /* Clean up required! */
            for (id arg in _arguments) {
                [cleanedArray addObject:[NSString stringWithFormat:@"%@",arg]];
            }

            [self setArguments:cleanedArray];
            break;
        }
    }
    
    [executingTask setArguments:_arguments];

    /* Setup pipes */
    NSPipe *stdinPipe = [NSPipe pipe];
    NSPipe *stdoutPipe = [NSPipe pipe];
    NSPipe *stderrPipe = [NSPipe pipe];
    
    [executingTask setStandardInput:stdinPipe];
    [executingTask setStandardOutput:stdoutPipe];
    [executingTask setStandardError:stderrPipe];
    
    /* Set current directory, just pass on our actual CWD. */
    /* TODO: Potentially make this changeable? Surely there's probably a nicer way to get the CWD too. */
    [executingTask setCurrentDirectoryPath:[[[NSFileManager alloc] init] currentDirectoryPath]];


    /* Ensure the pipes are non-blocking so GCD can read them correctly. */
    fcntl([stdoutPipe fileHandleForReading].fileDescriptor, F_SETFL, O_NONBLOCK);
    fcntl([stderrPipe fileHandleForReading].fileDescriptor, F_SETFL, O_NONBLOCK);
    
    /* Setup a dispatch source for both descriptors. */
    self.stdoutSource = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_READ,
        [stdoutPipe fileHandleForReading].fileDescriptor,
        0,
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
    );

    self.stderrSource = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_READ,
        [stderrPipe fileHandleForReading].fileDescriptor,
        0,
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
    );
    
    /* Set stdout source event handler to read data and send it out. */
    dispatch_source_set_event_handler(self.stdoutSource, ^ {
        void* buffer = malloc(GCDTASK_BUFFER_MAX);
        ssize_t bytesRead;
        
        do {
            errno = 0;
            bytesRead = read([stdoutPipe fileHandleForReading].fileDescriptor, buffer, GCDTASK_BUFFER_MAX);
        } while(bytesRead == -1 && errno == EINTR);
        
        if(bytesRead > 0) {
            // Create before dispatch to prevent a race condition.
            NSData* dataToPass = [NSData dataWithBytes:buffer length:bytesRead];
            dispatch_async(dispatch_get_main_queue(), ^{
                if(!_hasExecuted) {
                    if(launchHandler) {
                        launchHandler();
                    }
                    _hasExecuted = TRUE;
                }
                if(outputHandler) {
                    outputHandler(dataToPass);
                }
            });
        }
        
        if(errno != 0 && bytesRead <= 0) {
            dispatch_source_cancel(self.stdoutSource);
            dispatch_async(dispatch_get_main_queue(), ^{
                if(exitHandler) {
                    exitHandler();
                }
            });
        }

        
        free(buffer);
    });
    
    /* Same thing for stderr. */
    dispatch_source_set_event_handler(self.stderrSource, ^ {
        void* buffer = malloc(GCDTASK_BUFFER_MAX);
        ssize_t bytesRead;
        
        do {
            errno = 0;
            bytesRead = read([stderrPipe fileHandleForReading].fileDescriptor, buffer, GCDTASK_BUFFER_MAX);
        } while(bytesRead == -1 && errno == EINTR);
        
        if(bytesRead > 0) {
            NSData* dataToPass = [NSData dataWithBytes:buffer length:bytesRead];
            dispatch_async(dispatch_get_main_queue(), ^{
                if(errorHandler) {
                    errorHandler(dataToPass);
                }
            });
        }
        
        if(errno != 0 && bytesRead <= 0) {
            dispatch_source_cancel(self.stderrSource);
        }
        
        free(buffer);
    });

    
    dispatch_resume(self.stdoutSource);
    dispatch_resume(self.stderrSource);

    executingTask.terminationHandler = ^(NSTask* task) {
        dispatch_source_cancel(self.stdoutSource);
        dispatch_source_cancel(self.stderrSource);

        if(exitHandler) {
            exitHandler();
        }
    };

    // Set all our local variables to the class variables
    self.stdinPipe = stdinPipe;
    self.stdoutPipe = stdoutPipe;
    self.stderrPipe = stderrPipe;
    self.executingTask = executingTask;

    [self.executingTask launch];
}

/**
 * Converts the input to an NSData and calls writeDataToStandardInput.
 */
-(BOOL)writeStringToStandardInput:(NSString *)input {
    return [self writeDataToStandardInput:[input dataUsingEncoding:NSUTF8StringEncoding]];
}

/* Currently synchronous. TODO: Async fun! */

-(BOOL)writeDataToStandardInput:(NSData *)input {
    if (!self.stdinPipe || self.stdinPipe == nil) {
        GCDDebug(@"Standard input pipe does not exist.");
        return NO;
    }
    
    [[self.stdinPipe fileHandleForWriting] writeData:input];

    return YES;
}

/**
 * Terminates the GCDTask. First it will request SIGINT, then it will force SIGTERM after 10 seconds.
 */
- (void)requestTermination {
    [self.executingTask interrupt];

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)),
        dispatch_get_main_queue(),
        ^(void) {
            [self.executingTask terminate];
        }
    );
}

/**
 * Calls waitUntilExit on the currently executing internal NSTask.
 */
- (void)waitUntilExit {
    if (self.executingTask) {
        [self.executingTask waitUntilExit];
    }
}

@end
