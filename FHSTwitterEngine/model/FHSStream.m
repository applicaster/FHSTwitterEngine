//
//  FHSStream.m
//  FHSTwitterEngine
//
//  Created by Nathaniel Symer on 3/9/14.
//  Copyright (c) 2014 Nathaniel Symer. All rights reserved.
//

#import "FHSStream.h"
#import "FHSTwitterEngine+Requests.h"
#import "NSError+FHSTE.h"

@interface FHSStream () <NSURLConnectionDelegate>

@property (nonatomic, strong) NSURLConnection *connection;
@property (nonatomic, strong) NSMutableDictionary *params;
@property (nonatomic, strong) NSString *URL;
@property (nonatomic, strong) NSString *HTTPMethod;
@property (nonatomic, assign) float timeout;

@end

@implementation FHSStream

+ (instancetype)streamWithURL:(NSString *)url httpMethod:(NSString *)httpMethod parameters:(NSDictionary *)params timeout:(float)timeout block:(StreamBlock)block {
    return [[[self class]alloc]initWithURL:url httpMethod:httpMethod parameters:params timeout:timeout block:block];
}

- (instancetype)initWithURL:(NSString *)url httpMethod:(NSString *)httpMethod parameters:(NSDictionary *)params timeout:(float)timeout block:(StreamBlock)block {
    self = [super init];
    if (self) {
        self.timeout = timeout;
        self.URL = url;
        self.HTTPMethod = httpMethod;
        self.params = (params == nil)?[NSMutableDictionary dictionaryWithCapacity:2]:params.mutableCopy;
        _params[@"delimited"] = @"length"; // absolutely necessary
        _params[@"stall_warnings"] = @"true";
        self.block = block;
    }
    return self;
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    
    BOOL stop = NO;
    
    if (_block) {
        _block(error, &stop);
    }
    
    if (stop) {
        [self stop];
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    int bytesExpected = 0;
    NSMutableString *message = nil;

    NSString *response = [[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];

    for (NSString *part in [response componentsSeparatedByString:@"\r\n"]) {
        int length = [part intValue];

        if (length > 0) {
            message = [NSMutableString string];
            bytesExpected = length;
        }
        
        if (bytesExpected > 0 && message) {
            NSRange rangeOfCount = [message rangeOfString:@(bytesExpected).stringValue];
            if (rangeOfCount.location == 0) {
                message = [message substringFromIndex:rangeOfCount.length].mutableCopy;
            }
            
            if (message.length < bytesExpected) {
                [message appendString:part];
                
                if (message.length < bytesExpected) {
                    [message appendString:@"\r\n"];
                }
                
                if (message.length == bytesExpected) {
                    NSError *jsonError = nil;
                    id json = [NSJSONSerialization JSONObjectWithData:[message dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingMutableContainers error:&jsonError];

                    BOOL stop = NO;
                    
                    if (!jsonError) {
                        if (_block) {
                            _block(json, &stop);
                        }
                        [self keepAlive];
                    } else {
                        NSError *error = [NSError errorWithDomain:FHSErrorDomain code:406 userInfo:@{ NSUnderlyingErrorKey: jsonError, NSLocalizedDescriptionKey: @"Invalid JSON was returned from Twitter", @"json": json }];
                        if (_block) {
                            _block(error, &stop);
                        }
                    }
                    
                    if (stop) {
                        [self stop];
                    }

                    message = nil;
                    bytesExpected = 0;
                }
            }
        } else {
            [self keepAlive];
        }
    }
}

- (void)keepAlive {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(stop) object:nil];
}

- (void)stop {
    [_connection cancel];
    [_connection unscheduleFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    self.connection = nil;
}

- (void)start {
    id req = [[FHSTwitterEngine sharedEngine]streamingRequestForURL:[NSURL URLWithString:_URL] HTTPMethod:_HTTPMethod parameters:_params];
    
    if ([req isKindOfClass:[NSURLRequest class]]) {
        self.connection = [NSURLConnection connectionWithRequest:req delegate:self];
        [self performSelector:@selector(stop) withObject:nil afterDelay:_timeout];
    } else {
        if (_block) {
            _block(req, NULL);
        }
    }
}

+ (NSString *)sanitizeTrackParameter:(NSArray *)keywords {
    NSMutableArray *sanitized = [NSMutableArray arrayWithCapacity:keywords.count];
    
    for (NSString *string in keywords) {
        [sanitized addObject:[string fhs_truncatedToLength:60]];
    }
    
    return [sanitized componentsJoinedByString:@","];
}

@end
