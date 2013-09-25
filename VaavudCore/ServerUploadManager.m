//
//  ServerUploadManager.m
//  Vaavud
//
//  Created by Thomas Stilling Ambus on 19/06/2013.
//  Copyright (c) 2013 Andreas Okholm. All rights reserved.
//

#define consecutiveNetworkErrorBackOffThreshold 3
#define networkErrorBackOff 10
#define graceTimeBetweenDidBecomeActiveTasks 3600.0
#define uploadInterval 10

#import "ServerUploadManager.h"
#import "SharedSingleton.h"
#import "MeasurementSession+Util.h"
#import "VaavudAPIHTTPClient.h"
#import "Property+Util.h"
#import "AFHTTPRequestOperation.h"
#import "AlgorithmConstantsUtil.h"

@interface ServerUploadManager () {
}

@property(nonatomic) NSTimer *syncTimer;
@property(nonatomic) BOOL hasReachability;
@property(nonatomic) NSDate *lastDidBecomeActive;
@property(nonatomic) BOOL justDidBecomeActive;
@property(nonatomic) BOOL hasRegisteredDevice;
@property(nonatomic) int consecutiveNetworkErrors;
@property(nonatomic) int backoffWaitCount;

@end

@implementation ServerUploadManager

SHARED_INSTANCE

- (id) init {
    self = [super init];
    
    if (self) {
        self.consecutiveNetworkErrors = 0;
        self.backoffWaitCount = 0;
        self.hasReachability = NO;
        self.justDidBecomeActive = YES;
        self.hasRegisteredDevice = NO;

        // initialize HTTP client
        [[VaavudAPIHTTPClient sharedInstance] setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status){
            /*
             AFNetworkReachabilityStatusUnknown          = -1,
             AFNetworkReachabilityStatusNotReachable     = 0,
             AFNetworkReachabilityStatusReachableViaWWAN = 1,
             AFNetworkReachabilityStatusReachableViaWiFi = 2,
             */
            NSLog(@"[ServerUploadManager] Reachability status changed to: %d", status);

            if (status == 1 || status == 2) {
                self.hasReachability = YES;
                [self handleDidBecomeActiveTasks];
            }
            else {
                self.hasReachability = NO;
            }
        }];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillTerminate:) name:UIApplicationWillTerminateNotification object:nil];
    }
    
    return self;
}

- (void) start {
    self.syncTimer = [NSTimer scheduledTimerWithTimeInterval:uploadInterval target:self selector:@selector(checkForUnUploadedData) userInfo:nil repeats:YES];
}

// notification from the OS
- (void) appDidBecomeActive:(NSNotification*) notification {
    //NSLog(@"[ServerUploadManager] appDidBecomeActive");
    self.justDidBecomeActive = YES;
    [self handleDidBecomeActiveTasks];
}

// notification from the OS
-(void) appWillTerminate:(NSNotification*) notification {
    NSLog(@"[ServerUploadManager] appWillTerminate");
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillTerminateNotification object:nil];
}

// this is triggered by the OS informing us that the app did become active or AFNetworking telling us that reachability has changed to YES and we haven't yet executed these tasks after becoming active. Thus, if we don't have reachability when becoming active, these tasks are postponed until reachability changes to YES.
- (void) handleDidBecomeActiveTasks {
    
    if (self.lastDidBecomeActive && self.lastDidBecomeActive != nil) {
        NSTimeInterval howRecent = [self.lastDidBecomeActive timeIntervalSinceNow];
        if (abs(howRecent) < graceTimeBetweenDidBecomeActiveTasks) {
            NSLog(@"[ServerUploadManager] ignoring did-become-active due to grace period");

            self.justDidBecomeActive = NO;
        }
    }

    if (self.justDidBecomeActive == NO || self.hasReachability == NO) {
        return;
    }
    
    //NSLog(@"[ServerUploadManager] Handle did-become-active tasks");
    self.justDidBecomeActive = NO;
    self.lastDidBecomeActive = [NSDate date];

    // tasks to do follow here...
    
    // since it's awhile since we last tried to upload, clear network error counts
    self.consecutiveNetworkErrors = 0;
    self.backoffWaitCount = 0;

    // register device
    [self registerDevice];
}

- (void) triggerUpload {
    //NSLog(@"[ServerUploadManager] Trigger upload");
    [self checkForUnUploadedData];
}

- (void) checkForUnUploadedData {
    
    //NSLog(@"[ServerUploadManager, %@] checkForUnUploadedData", [NSThread currentThread]);
    
    if (!self.hasReachability) {
        return;
    }
    
    if (self.consecutiveNetworkErrors >= consecutiveNetworkErrorBackOffThreshold) {
        self.backoffWaitCount++;
        if (self.backoffWaitCount % networkErrorBackOff != 0) {
            NSLog(@"[ServerUploadManager] Backing off due to %d consecutive network errors, wait count is %d", self.consecutiveNetworkErrors, self.backoffWaitCount);
            return;
        }
    }

    // if we didn't successfully call register device yet, do this instead of uploading
    if (self.hasRegisteredDevice == NO) {
        [self registerDevice];
        return;
    }
    
    NSArray *unuploadedMeasurementSessions = [MeasurementSession MR_findByAttribute:@"uploaded" withValue:[NSNumber numberWithBool:NO]];

    if (unuploadedMeasurementSessions && [unuploadedMeasurementSessions count] > 0) {
        
        //NSLog(@"[ServerUploadManager] Found %d un-uploaded MeasurementSessions", [unuploadedMeasurementSessions count]);
        
        for (MeasurementSession *measurementSession in unuploadedMeasurementSessions) {

            NSNumber *pointCount = [NSNumber numberWithUnsignedInteger:[measurementSession.points count]];

            //NSLog(@"[ServerUploadManager] Found non-uploaded MeasurementSession with uuid=%@, startTime=%@, startIndex=%@, endIndex=%@, pointCount=%@", measurementSession.uuid, measurementSession.startTime, measurementSession.startIndex, measurementSession.endIndex, pointCount);

            if ([measurementSession.measuring boolValue] == YES) {
                
                // if an unuploaded 
                NSTimeInterval howRecent = [measurementSession.endTime timeIntervalSinceNow];
                if (abs(howRecent) > 3600.0) {
                    //NSLog(@"[ServerUploadManager] Found old MeasurementSession (%@) that is still measuring - setting it to not measuring", measurementSession.uuid);
                    // TODO: we ought to force the controller to stop if it is still in started mode. Or should we remove this altogether?
                    measurementSession.measuring = [NSNumber numberWithBool:NO];
                    [[NSManagedObjectContext MR_defaultContext] MR_saveToPersistentStoreWithCompletion:nil];
                }
            }
            
            if ([measurementSession.startIndex intValue] == [pointCount intValue]) {

                if ([measurementSession.measuring boolValue] == NO) {
                    //NSLog(@"[ServerUploadManager] Found MeasurementSession (%@) that is not measuring and has no new points, so setting it as uploaded", measurementSession.uuid);
                    measurementSession.uploaded = [NSNumber numberWithBool:YES];
                    [[NSManagedObjectContext MR_defaultContext] MR_saveToPersistentStoreWithCompletion:nil];
                }
                else {
                    //NSLog(@"[ServerUploadManager] Found MeasurementSession that is not uploaded, is still measuring, but has no new points, so skipping");
                }
            }
            else {
                
                //NSLog(@"[ServerUploadManager] Uploading MeasurementSession (%@)", measurementSession.uuid);
                
                NSNumber *newEndIndex = pointCount;
                NSString *uuid = measurementSession.uuid;
                measurementSession.endIndex = newEndIndex;

                NSDictionary *parameters = [measurementSession toDictionary];
                
                [[VaavudAPIHTTPClient sharedInstance] postPath:@"/api/measure" parameters:parameters success:^(AFHTTPRequestOperation *operation, id responseObject) {
                    
                    NSLog(@"[ServerUploadManager] Got successful response uploading");
                    
                    // clear consecutive errors since we got a successful reponse
                    self.consecutiveNetworkErrors = 0;
                    self.backoffWaitCount = 0;
                    
                    // lookup MeasurementSession again since it might have changed while uploading
                    MeasurementSession *msession = [MeasurementSession MR_findFirstByAttribute:@"uuid" withValue:uuid];
                    msession.startIndex = newEndIndex;
                    [[NSManagedObjectContext MR_defaultContext] MR_saveToPersistentStoreWithCompletion:nil];
                    
                } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                    long statusCode = (long)operation.response.statusCode;
                    NSLog(@"[ServerUploadManager] Got error status code %ld uploading: %@", statusCode, error);
                    
                    self.consecutiveNetworkErrors++;

                    // check for unauthorized
                    if (statusCode == 401) {
                        // try to re-register
                        self.hasRegisteredDevice = NO;
                    }
                }];
                
                // stop iterating since we did process a measurement session to ensure that we don't spam the server in case the user has a lot of unuploaded measurement sessions
                break;
            }
        }
    }
    else {
        //NSLog(@"[ServerUploadManager] Found no uploading MeasurementSession");
    }
}

- (void) registerDevice {

    NSLog(@"[ServerUploadManager] Register device");
    self.hasRegisteredDevice = NO;

    NSDictionary *parameters = [Property getDeviceDictionary];
    
    [[VaavudAPIHTTPClient sharedInstance] postPath:@"/api/device/register" parameters:parameters success:^(AFHTTPRequestOperation *operation, id responseObject) {
        
        //NSLog(@"[ServerUploadManager] Got successful response registering device");
        self.hasRegisteredDevice = YES;
        
        // clear consecutive errors since we got a successful reponse
        self.consecutiveNetworkErrors = 0;
        self.backoffWaitCount = 0;

        // remember the authToken we got from the server as response
        NSString *authToken = [responseObject objectForKey:@"authToken"];
        if (authToken && authToken != nil && authToken != (id)[NSNull null] && ([authToken length] > 0)) {
            //NSLog(@"[ServerUploadManager] Got authToken");
            [Property setAsString:authToken forKey:KEY_AUTH_TOKEN];
            [[VaavudAPIHTTPClient sharedInstance] setAuthToken:authToken];
        }
        else {
            NSLog(@"[ServerUploadManager] Got no authToken");
        }
        
        // set algorithm parameters
        BOOL hasSetParameters = NO;
        
        NSString *algorithm = [responseObject objectForKey:@"algorithm"];
        if (algorithm && algorithm != nil && algorithm != (id)[NSNull null] && ([algorithm length] > 0)) {
            [Property setAsInteger:[AlgorithmConstantsUtil getAlgorithmFromString:algorithm] forKey:KEY_ALGORITHM];
            hasSetParameters = YES;
        }
        
        NSNumber *frequencyStart = [self doubleValue:responseObject forKey:@"frequencyStart"];
        if (frequencyStart != nil) {
            [Property setAsDouble:frequencyStart forKey:KEY_FREQUENCY_START];
            hasSetParameters = YES;
        }

        NSNumber *frequencyFactor = [self doubleValue:responseObject forKey:@"frequencyFactor"];
        if (frequencyFactor != nil) {
            [Property setAsDouble:frequencyFactor forKey:KEY_FREQUENCY_FACTOR];
            hasSetParameters = YES;
        }

        NSNumber *fftLength = [self integerValue:responseObject forKey:@"fftLength"];
        if (fftLength != nil) {
            [Property setAsInteger:fftLength forKey:KEY_FFT_LENGTH];
            hasSetParameters = YES;
        }

        NSNumber *fftDataLength = [self integerValue:responseObject forKey:@"fftDataLength"];
        if (fftDataLength != nil) {
            [Property setAsInteger:fftDataLength forKey:KEY_FFT_DATA_LENGTH];
            hasSetParameters = YES;
        }

        if (hasSetParameters) {
            NSLog(@"[ServerUploadManager] Setting algorithm parameters from server: algorithm=%@, frequencyStart=%@, frequencyFactor=%@, fftLength=%@, fftDataLength=%@", [Property getAsInteger:KEY_ALGORITHM], [Property getAsDouble:KEY_FREQUENCY_START], [Property getAsDouble:KEY_FREQUENCY_FACTOR], [Property getAsInteger:KEY_FFT_LENGTH], [Property getAsInteger:KEY_FFT_DATA_LENGTH]);
        }
        
        // only trigger upload once we get OK from server for registering device, otherwise the device could be unregistered when uploading
        [self triggerUpload];

    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"[ServerUploadManager] Got error registering device: %@", error);
        self.hasRegisteredDevice = NO;
        self.consecutiveNetworkErrors++;
    }];
}

-(NSNumber*) doubleValue:(id) responseObject forKey:(NSString*) key {
    NSString *value = [responseObject objectForKey:key];
    if (value && value != nil && value != (id)[NSNull null] && ([value length] > 0)) {
        return [NSNumber numberWithDouble:[value doubleValue]];
    }
    return nil;
}

-(NSNumber*) integerValue:(id) responseObject forKey:(NSString*) key {
    NSString *value = [responseObject objectForKey:key];
    if (value && value != nil && value != (id)[NSNull null] && ([value length] > 0)) {
        return [NSNumber numberWithInt:[value doubleValue]];
    }
    return nil;
}

@end
