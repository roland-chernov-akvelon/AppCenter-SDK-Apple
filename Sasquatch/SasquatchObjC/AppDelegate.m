// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <CoreLocation/CoreLocation.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <Photos/Photos.h>
#import <UserNotifications/UserNotifications.h>

#import "AppCenterDelegateObjC.h"
#import "AppDelegate.h"
#import "Constants.h"
#import "Sasquatch-Swift.h"

#if GCC_PREPROCESSOR_MACRO_PUPPET
#import "AppCenter.h"
#import "AppCenterAnalytics.h"
#import "AppCenterCrashes.h"
#import "AppCenterDataStorage.h"
#import "AppCenterDistribute.h"
#import "AppCenterIdentity.h"
#import "AppCenterPush.h"

// Internal ones
#import "MSAnalyticsInternal.h"
#else
@import AppCenter;
@import AppCenterAnalytics;
@import AppCenterCrashes;
@import AppCenterDataStorage;
@import AppCenterDistribute;
@import AppCenterIdentity;
@import AppCenterPush;
#endif

enum StartupMode { APPCENTER, ONECOLLECTOR, BOTH, NONE, SKIP };

@interface AppDelegate () <
#if GCC_PREPROCESSOR_MACRO_PUPPET
    MSAnalyticsDelegate,
#endif
    MSCrashesDelegate, MSDistributeDelegate, MSPushDelegate, UNUserNotificationCenterDelegate, CLLocationManagerDelegate>

@property(nonatomic) MSAnalyticsResult *analyticsResult;
@property(nonatomic) API_AVAILABLE(ios(10.0)) void (^notificationPresentationCompletionHandler)(UNNotificationPresentationOptions options);
@property(nonatomic) void (^notificationResponseCompletionHandler)(void);
@property(nonatomic) CLLocationManager *locationManager;

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

#if GCC_PREPROCESSOR_MACRO_PUPPET
  self.analyticsResult = [MSAnalyticsResult new];
  [MSAnalytics setDelegate:self];

  for (UIViewController *controller in [(UITabBarController *)self.window.rootViewController viewControllers]) {
    if ([controller isKindOfClass:[MSAnalyticsViewController class]]) {
      [(MSAnalyticsViewController *)controller setAnalyticsResult:self.analyticsResult];
    }
  }
  [MSIdentity setConfigUrl:kMSIntConfigUrl];
#endif

// Customize App Center SDK.
#pragma clang diagnostic ignored "-Wpartial-availability"
  if ([[NSProcessInfo processInfo] operatingSystemVersion].majorVersion >= 10) {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    center.delegate = self;
  }
#pragma clang diagnostic pop
  [MSPush setDelegate:self];
  [MSDistribute setDelegate:self];
  [MSAppCenter setLogLevel:MSLogLevelVerbose];

  // Set max storage size.
  NSNumber *storageMaxSize = [[NSUserDefaults standardUserDefaults] objectForKey:kMSStorageMaxSizeKey];
  if (storageMaxSize) {
    [MSAppCenter setMaxStorageSize:storageMaxSize.integerValue
                 completionHandler:^(BOOL success) {
                   dispatch_async(dispatch_get_main_queue(), ^{
                     if (success) {
                       long realStorageSize = (long)(ceil([storageMaxSize doubleValue] / kMSStoragePageSize) * kMSStoragePageSize);
                       [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithLong:realStorageSize]
                                                                 forKey:kMSStorageMaxSizeKey];
                     } else {

                       // Remove invalid value.
                       [[NSUserDefaults standardUserDefaults] removeObjectForKey:kMSStorageMaxSizeKey];

                       // Show alert.
                       UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Warning!"
                                                                                                message:@"The maximum size of the internal "
                                                                                                        @"storage could not be set."
                                                                                         preferredStyle:UIAlertControllerStyleAlert];
                       [alertController addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                       [self.window.rootViewController presentViewController:alertController animated:YES completion:nil];
                     }
                   });
                 }];
  }

  NSString *logUrl = [[NSUserDefaults standardUserDefaults] objectForKey:kMSLogUrl];
  if (logUrl) {
    [MSAppCenter setLogUrl:logUrl];
  }

  // Start App Center SDK.
  NSArray<Class> *services =
      @ [[MSAnalytics class], [MSCrashes class], [MSDataStore class], [MSDistribute class], [MSIdentity class], [MSPush class]];
  NSInteger startTarget = [[NSUserDefaults standardUserDefaults] integerForKey:kMSStartTargetKey];
#if GCC_PREPROCESSOR_MACRO_PUPPET
  NSString *appSecret = [[NSUserDefaults standardUserDefaults] objectForKey:kMSAppSecret] ?: kMSPuppetAppSecret;
#else
  NSString *appSecret = [[NSUserDefaults standardUserDefaults] objectForKey:kMSAppSecret] ?: kMSObjcAppSecret;
#endif
  switch (startTarget) {
  case APPCENTER:
    [MSAppCenter start:appSecret withServices:services];
    break;
  case ONECOLLECTOR:
    [MSAppCenter start:[NSString stringWithFormat:@"target=%@", kMSObjCTargetToken] withServices:services];
    break;
  case BOTH:
    [MSAppCenter start:[NSString stringWithFormat:@"appsecret=%@;target=%@", appSecret, kMSObjCTargetToken] withServices:services];
    break;
  case NONE:
    [MSAppCenter startWithServices:services];
    break;
  }

  // Setup location manager.
  self.locationManager = [[CLLocationManager alloc] init];
  self.locationManager.delegate = self;
  self.locationManager.desiredAccuracy = kCLLocationAccuracyKilometer;
  [self.locationManager requestWhenInUseAuthorization];

  // Set user id.
  NSString *userId = [[NSUserDefaults standardUserDefaults] objectForKey:kMSUserIdKey];
  if (userId) {
    [MSAppCenter setUserId:userId];
  }

  // Set delegates.
  [self crashes];
  [self setAppCenterDelegate];
  return YES;
}

- (void)requestLocation {
  if (CLLocationManager.locationServicesEnabled) {
    [self.locationManager requestLocation];
  }
}

#pragma mark - Application life cycle

- (void)applicationWillResignActive:(UIApplication *)application {
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
}

- (void)applicationWillTerminate:(UIApplication *)application {
}

#pragma mark - Private

- (void)crashes {
  if ([MSCrashes hasCrashedInLastSession]) {
    MSErrorReport *errorReport = [MSCrashes lastSessionCrashReport];
    NSLog(@"We crashed with Signal: %@", errorReport.signal);
    MSDevice *device = [errorReport device];
    NSString *osVersion = [device osVersion];
    NSString *appVersion = [device appVersion];
    NSString *appBuild = [device appBuild];
    NSLog(@"OS Version is: %@", osVersion);
    NSLog(@"App Version is: %@", appVersion);
    NSLog(@"App Build is: %@", appBuild);
  }

  [MSCrashes setDelegate:self];
  [MSCrashes setUserConfirmationHandler:(^(NSArray<MSErrorReport *> *errorReports) {
               // Use MSAlertViewController to show a dialog to the user where they can choose if they want to provide a crash report.
               UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Sorry about that!"
                                                                                        message:@"Do you want to send an anonymous crash "
                                                                                                @"report so we can fix the issue?"
                                                                                 preferredStyle:UIAlertControllerStyleAlert];

               // Add a "Don't send"-Button and call the notifyWithUserConfirmation-callback with MSUserConfirmationDontSend
               [alertController addAction:[UIAlertAction actionWithTitle:@"Don't send"
                                                                   style:UIAlertActionStyleCancel
                                                                 handler:^(UIAlertAction *action) {
                                                                   [MSCrashes notifyWithUserConfirmation:MSUserConfirmationDontSend];
                                                                 }]];

               // Add a "Send"-Button and call the notifyWithUserConfirmation-callback with MSUserConfirmationSend
               [alertController addAction:[UIAlertAction actionWithTitle:@"Send"
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^(UIAlertAction *action) {
                                                                   [MSCrashes notifyWithUserConfirmation:MSUserConfirmationSend];
                                                                 }]];

               // Add a "Always send"-Button and call the notifyWithUserConfirmation-callback with MSUserConfirmationAlways
               [alertController addAction:[UIAlertAction actionWithTitle:@"Always send"
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^(UIAlertAction *action) {
                                                                   [MSCrashes notifyWithUserConfirmation:MSUserConfirmationAlways];
                                                                 }]];

               // Show the alert controller.
               [self.window.rootViewController presentViewController:alertController animated:YES completion:nil];

               return YES;
             })];
}

- (void)setAppCenterDelegate {
  AppCenterDelegateObjC *appCenterDel = [[AppCenterDelegateObjC alloc] init];
  for (UIViewController *controller in [(UITabBarController *)self.window.rootViewController viewControllers]) {
    id<AppCenterProtocol> sasquatchController = (id<AppCenterProtocol>)controller;
    sasquatchController.appCenter = appCenterDel;
  }
}

#if GCC_PREPROCESSOR_MACRO_PUPPET
#pragma mark - MSAnalyticsDelegate

- (void)analytics:(MSAnalytics *)analytics willSendEventLog:(MSEventLog *)eventLog {
  [self.analyticsResult willSendWithEventLog:eventLog];
  [NSNotificationCenter.defaultCenter postNotificationName:kUpdateAnalyticsResultNotification object:self.analyticsResult];
}

- (void)analytics:(MSAnalytics *)analytics didSucceedSendingEventLog:(MSEventLog *)eventLog {
  [self.analyticsResult didSucceedSendingWithEventLog:eventLog];
  [NSNotificationCenter.defaultCenter postNotificationName:kUpdateAnalyticsResultNotification object:self.analyticsResult];
}

- (void)analytics:(MSAnalytics *)analytics didFailSendingEventLog:(MSEventLog *)eventLog withError:(NSError *)error {
  [self.analyticsResult didFailSendingWithEventLog:eventLog withError:error];
  [NSNotificationCenter.defaultCenter postNotificationName:kUpdateAnalyticsResultNotification object:self.analyticsResult];
}
#endif

#pragma mark - MSCrashesDelegate

- (BOOL)crashes:(MSCrashes *)crashes shouldProcessErrorReport:(MSErrorReport *)errorReport {
  NSLog(@"Should process error report with: %@", errorReport.exceptionReason);
  return YES;
}

- (void)crashes:(MSCrashes *)crashes willSendErrorReport:(MSErrorReport *)errorReport {
  NSLog(@"Will send error report with: %@", errorReport.exceptionReason);
}

- (void)crashes:(MSCrashes *)crashes didSucceedSendingErrorReport:(MSErrorReport *)errorReport {
  NSLog(@"Did succeed error report sending with: %@", errorReport.exceptionReason);
}

- (void)crashes:(MSCrashes *)crashes didFailSendingErrorReport:(MSErrorReport *)errorReport withError:(NSError *)error {
  NSLog(@"Did fail sending report with: %@, and error: %@", errorReport.exceptionReason, error.localizedDescription);
}

- (NSArray<MSErrorAttachmentLog *> *)attachmentsWithCrashes:(MSCrashes *)crashes forErrorReport:(MSErrorReport *)errorReport {
  NSMutableArray *attachments = [[NSMutableArray alloc] init];

  // Text attachment.
  NSString *text = [[NSUserDefaults standardUserDefaults] objectForKey:@"textAttachment"];
  if (text != nil && text.length > 0) {
    MSErrorAttachmentLog *textAttachment = [MSErrorAttachmentLog attachmentWithText:text filename:@"user.log"];
    [attachments addObject:textAttachment];
  }

  // Binary attachment.
  NSURL *referenceUrl = [[NSUserDefaults standardUserDefaults] URLForKey:@"fileAttachment"];
  if (referenceUrl) {
    PHAsset *asset = [[PHAsset fetchAssetsWithALAssetURLs:@[ referenceUrl ] options:nil] lastObject];
    if (asset) {
      PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
      options.synchronous = YES;
      [[PHImageManager defaultManager]
          requestImageDataForAsset:asset
                           options:options
                     resultHandler:^(NSData *_Nullable imageData, NSString *_Nullable dataUTI, __unused UIImageOrientation orientation,
                                     __unused NSDictionary *_Nullable info) {
                       CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,
                                                                               (__bridge CFStringRef)[dataUTI pathExtension], nil);
                       NSString *MIMEType = (__bridge_transfer NSString *)UTTypeCopyPreferredTagWithClass(UTI, kUTTagClassMIMEType);
                       CFRelease(UTI);
                       MSErrorAttachmentLog *binaryAttachment = [MSErrorAttachmentLog attachmentWithBinary:imageData
                                                                                                  filename:dataUTI
                                                                                               contentType:MIMEType];
                       [attachments addObject:binaryAttachment];
                       NSLog(@"Add binary attachment with %tu bytes", [imageData length]);
                     }];
    }
  }
  return attachments;
}

#pragma mark - MSDistributeDelegate

- (BOOL)distribute:(MSDistribute *)distribute releaseAvailableWithDetails:(MSReleaseDetails *)details {

  if ([[[NSUserDefaults new] objectForKey:kSASCustomizedUpdateAlertKey] isEqual:@1]) {

    // Show a dialog to the user where they can choose if they want to update.
    UIAlertController *alertController =
        [UIAlertController alertControllerWithTitle:NSLocalizedStringFromTable(@"distribute_alert_title", @"Sasquatch", @"")
                                            message:NSLocalizedStringFromTable(@"distribute_alert_message", @"Sasquatch", @"")
                                     preferredStyle:UIAlertControllerStyleAlert];

    // Add a "Yes"-Button and call the notifyUpdateAction-callback with MSUpdateActionUpdate
    [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTable(@"distribute_alert_yes", @"Sasquatch", @"")
                                                        style:UIAlertActionStyleCancel
                                                      handler:^(UIAlertAction *action) {
                                                        [MSDistribute notifyUpdateAction:MSUpdateActionUpdate];
                                                      }]];

    // Add a "No"-Button and call the notifyUpdateAction-callback with MSUpdateActionPostpone
    [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTable(@"distribute_alert_no", @"Sasquatch", @"")
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction *action) {
                                                        [MSDistribute notifyUpdateAction:MSUpdateActionPostpone];
                                                      }]];

    // Show the alert controller.
    [self.window.rootViewController presentViewController:alertController animated:YES completion:nil];
    return YES;
  }
  return NO;
}

#pragma mark - Push callbacks

// iOS 10 and later, called when a notification is delivered to an app that is in the foreground.
// When this callback is called, this disables the other callback that MSPush handles.
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler API_AVAILABLE(ios(10.0)) {
  self.notificationPresentationCompletionHandler = completionHandler;
}

// iOS 10 and later, asks the delegate to process the user's response to a delivered notification.
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    didReceiveNotificationResponse:(UNNotificationResponse *)response
             withCompletionHandler:(void (^)(void))completionHandler API_AVAILABLE(ios(10.0)) {
  self.notificationResponseCompletionHandler = completionHandler;
}

- (void)push:(MSPush *)push didReceivePushNotification:(MSPushNotification *)pushNotification {

  // Alert in foreground if requested from custom data.
  if (self.notificationPresentationCompletionHandler && [pushNotification.customData[@"presentation"] isEqual:@"alert"]) {
    self.notificationPresentationCompletionHandler(UNNotificationPresentationOptionAlert);
    self.notificationPresentationCompletionHandler = nil;
    return;
  }

  // Create and show a popup from the notification payload.
  NSString *title = pushNotification.title ?: @"";
  NSString *message = pushNotification.message;
  NSMutableString *customData = nil;
  for (NSString *key in pushNotification.customData) {
    ([customData length] == 0) ? customData = [NSMutableString new] : [customData appendString:@", "];
    [customData appendFormat:@"%@: %@", key, pushNotification.customData[key]];
  }
  if (UIApplication.sharedApplication.applicationState == UIApplicationStateBackground) {
    NSLog(@"Notification received in background (silent push), title: \"%@\", "
          @"message: "
          @"\"%@\", custom data: \"%@\"",
          title, message, customData);
  } else {
    NSString *stateMessage;
    if ([[NSProcessInfo processInfo] operatingSystemVersion].majorVersion < 10) {
      stateMessage = @"";
    } else if (self.notificationResponseCompletionHandler) {
      stateMessage = @"Tapped notification\n";
    } else {
      stateMessage = @"Received in foreground\n";
    }
    message = [NSString stringWithFormat:@"%@%@%@%@", stateMessage, (message ? message : @""), (message && customData ? @"\n" : @""),
                                         (customData ? customData : [@"" mutableCopy])];
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title
                                                                             message:message
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self.window.rootViewController presentViewController:alertController animated:YES completion:nil];
  }

  // Call notification completion handlers.
  if (self.notificationResponseCompletionHandler) {
    self.notificationResponseCompletionHandler();
    self.notificationResponseCompletionHandler = nil;
  }
  if (self.notificationPresentationCompletionHandler) {
    self.notificationPresentationCompletionHandler(UNNotificationPresentationOptionNone);
    self.notificationPresentationCompletionHandler = nil;
  }
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
  if (status == kCLAuthorizationStatusAuthorizedWhenInUse) {
    [manager requestLocation];
  }
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
  CLLocation *location = [locations lastObject];
  CLGeocoder *geocoder = [[CLGeocoder alloc] init];
  [geocoder reverseGeocodeLocation:location
                 completionHandler:^(NSArray *placemarks, NSError *error) {
                   if (placemarks.count == 0 || error)
                     return;
                   CLPlacemark *placemark = [placemarks firstObject];
                   [MSAppCenter setCountryCode:placemark.ISOcountryCode];
                 }];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
  NSLog(@"Failed to find user's location: %@", error.localizedDescription);
}

@end
