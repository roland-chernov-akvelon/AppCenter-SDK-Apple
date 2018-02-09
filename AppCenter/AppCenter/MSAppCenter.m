#import <Foundation/Foundation.h>

#import "MSAppCenterInternal.h"
#import "MSAppCenterPrivate.h"
#import "MSAppDelegateForwarder.h"
#import "MSConstants+Internal.h"
#import "MSDeviceTracker.h"
#import "MSDeviceTrackerPrivate.h"
#import "MSHttpSender.h"
#import "MSChannelGroupDefault.h"
#import "MSChannelUnitConfiguration.h"
#import "MSChannelUnitProtocol.h"
#import "MSLogger.h"
#import "MSSessionContext.h"
#import "MSStartServiceLog.h"
#import "MSUtility.h"
#if !TARGET_OS_TV
#import "MSCustomProperties.h"
#import "MSCustomPropertiesLog.h"
#import "MSCustomPropertiesPrivate.h"
#endif

/**
 * Singleton.
 */
static MSAppCenter *sharedInstance = nil;
static dispatch_once_t onceToken;

/**
 * Base URL for HTTP Ingestion backend API calls.
 */
static NSString *const kMSDefaultBaseUrl = @"https://in-integration.dev.avalanch.es";

/**
 * Service name for initialization.
 */
static NSString *const kMSServiceName = @"AppCenter";

/**
 * The group Id for storage.
 */
static NSString *const kMSGroupId = @"AppCenter";

@implementation MSAppCenter

@synthesize installId = _installId;

+ (instancetype)sharedInstance {
  dispatch_once(&onceToken, ^{
    if (sharedInstance == nil) {
      sharedInstance = [[self alloc] init];
    }
  });
  return sharedInstance;
}

#pragma mark - public

+ (void)configureWithAppSecret:(NSString *)appSecret {
  [[self sharedInstance] configure:appSecret];
}

+ (void)start:(NSString *)appSecret withServices:(NSArray<Class> *)services {
  [[self sharedInstance] start:appSecret withServices:services];
}

+ (void)startService:(Class)service {
  [[self sharedInstance] startService:service andSendLog:YES];
}

+ (BOOL)isConfigured {
  return [[self sharedInstance] sdkConfigured];
}

+ (void)setLogUrl:(NSString *)logUrl {
  [[self sharedInstance] setLogUrl:logUrl];
}

+ (void)setEnabled:(BOOL)isEnabled {
  @synchronized([self sharedInstance]) {
    if ([[self sharedInstance] canBeUsed]) {
      [[self sharedInstance] setEnabled:isEnabled];
    }
  }
}

+ (BOOL)isEnabled {
  @synchronized([self sharedInstance]) {
    if ([[self sharedInstance] canBeUsed]) {
      return [[self sharedInstance] isEnabled];
    }
  }
  return NO;
}

+ (BOOL)isAppDelegateForwarderEnabled {
  @synchronized([self sharedInstance]) {
    return MSAppDelegateForwarder.enabled;
  }
}

+ (NSUUID *)installId {
  return [[self sharedInstance] installId];
}

+ (MSLogLevel)logLevel {
  return MSLogger.currentLogLevel;
}

+ (void)setLogLevel:(MSLogLevel)logLevel {
  MSLogger.currentLogLevel = logLevel;

  // The logger is not set at the time of swizzling but now may be a good time to flush the traces.
  [MSAppDelegateForwarder flushTraceBuffer];
}

+ (void)setLogHandler:(MSLogHandler)logHandler {
  [MSLogger setLogHandler:logHandler];
}

+ (void)setWrapperSdk:(MSWrapperSdk *)wrapperSdk {
  [[MSDeviceTracker sharedInstance] setWrapperSdk:wrapperSdk];
}

#if !TARGET_OS_TV
+ (void)setCustomProperties:(MSCustomProperties *)customProperties {
  [[self sharedInstance] setCustomProperties:customProperties];
}
#endif

/**
 * Check if the debugger is attached
 *
 * Taken from
 * https://github.com/plausiblelabs/plcrashreporter/blob/2dd862ce049e6f43feb355308dfc710f3af54c4d/Source/Crash%20Demo/main.m#L96
 *
 * @return `YES` if the debugger is attached to the current process, `NO`
 * otherwise
 */
+ (BOOL)isDebuggerAttached {
  static BOOL debuggerIsAttached = NO;

  static dispatch_once_t debuggerPredicate;
  dispatch_once(&debuggerPredicate, ^{
    struct kinfo_proc info;
    size_t info_size = sizeof(info);
    int name[4];

    name[0] = CTL_KERN;
    name[1] = KERN_PROC;
    name[2] = KERN_PROC_PID;
    name[3] = getpid();

    if (sysctl(name, 4, &info, &info_size, NULL, 0) == -1) {
      NSLog(@"[MSCrashes] ERROR: Checking for a running debugger via sysctl() failed.");
      debuggerIsAttached = false;
    }

    if (!debuggerIsAttached && (info.kp_proc.p_flag & P_TRACED) != 0)
      debuggerIsAttached = true;
  });

  return debuggerIsAttached;
}

+ (NSString *)sdkVersion {
  return [MSUtility sdkVersion];
}

+ (NSString *)logTag {
  return kMSServiceName;
}

+ (NSString *)groupId {
  return kMSGroupId;
}

#pragma mark - private

- (instancetype)init {
  if ((self = [super init])) {
    _services = [NSMutableArray new];
    _logUrl = kMSDefaultBaseUrl;
    _enabledStateUpdating = NO;
  }
  return self;
}

- (BOOL)configure:(NSString *)appSecret {
  @synchronized(self) {
    BOOL success = false;
    if (self.sdkConfigured) {
      MSLogAssert([MSAppCenter logTag], @"App Center SDK has already been configured.");
    }

    // Validate and set the app secret.
    else if ([appSecret length] == 0) {
      MSLogAssert([MSAppCenter logTag], @"AppSecret is invalid.");
    } else {
      self.appSecret = appSecret;

      // Init the main pipeline.
      [self initializeChannelGroup];
      [self applyPipelineEnabledState:self.isEnabled];
      self.sdkConfigured = YES;

      /*
       * If the loglevel hasn't been customized before and we are not running in an app store environment,
       * we set the default loglevel to MSLogLevelWarning.
       */
      if ((![MSLogger isUserDefinedLogLevel]) && ([MSUtility currentAppEnvironment] == MSEnvironmentOther)) {
        [MSAppCenter setLogLevel:MSLogLevelWarning];
      }

      // Initialize session context.
      // FIXME: It would be better to have obvious way to initialize session context instead of calling setSessionId.
      [MSSessionContext setSessionId:nil];

      success = true;
    }
    if (success) {
      MSLogInfo([MSAppCenter logTag], @"App Center SDK configured successfully.");
    } else {
      MSLogAssert([MSAppCenter logTag], @"App Center SDK configuration failed.");
    }
    return success;
  }
}

- (void)start:(NSString *)appSecret withServices:(NSArray<Class> *)services {
  @synchronized(self) {
    BOOL configured = [self configure:appSecret];
    if (configured && services) {
      MSLogVerbose([MSAppCenter logTag], @"Prepare to start services: %@", [services componentsJoinedByString:@", "]);
      NSArray *sortedServices = [self sortServices:services];
      MSLogVerbose([MSAppCenter logTag], @"Start services %@", [sortedServices componentsJoinedByString:@", "]);
      NSMutableArray<NSString *> *servicesNames = [NSMutableArray arrayWithCapacity:sortedServices.count];

      for (Class service in sortedServices) {
        if ([self startService:service andSendLog:NO]) {
          [servicesNames addObject:[service serviceName]];
        }
      }
      if ([servicesNames count] > 0) {
        [self sendStartServiceLog:servicesNames];
      } else {
        MSLogDebug([MSAppCenter logTag], @"No services have been started.");
      }
    }
  }
}

/**
 * Sort services in descending order to make sure the service with the highest priority gets initialized first.
 * This is intended to make sure Crashes gets initialized first.
 */
- (NSArray *)sortServices:(NSArray<Class> *)services {
  if (services && services.count > 1) {
    return [services sortedArrayUsingComparator:^NSComparisonResult(id clazzA, id clazzB) {
      id<MSServiceInternal> serviceA = [clazzA sharedInstance];
      id<MSServiceInternal> serviceB = [clazzB sharedInstance];
      if (serviceA.initializationPriority < serviceB.initializationPriority) {
        return NSOrderedDescending;
      } else {
        return NSOrderedAscending;
      }
    }];
  } else {
    return services;
  }
}

- (BOOL)startService:(Class)clazz andSendLog:(BOOL)sendLog {
  @synchronized(self) {

    // Check if clazz is valid class
    if (![clazz conformsToProtocol:@protocol(MSServiceCommon)]) {
      MSLogError([MSAppCenter logTag], @"Cannot start service %@. Provided value is nil or invalid.", clazz);
      return NO;
    }
    id<MSServiceInternal> service = [clazz sharedInstance];
    if (service.isAvailable) {

      // Service already works, we shouldn't send log with this service name
      return NO;
    }

    // Check if service should be disabled
    if ([self shouldDisable:[clazz serviceName]]) {
      MSLogDebug([MSAppCenter logTag], @"Environment variable to disable service has been set; not starting service %@", clazz);
      return NO;
    }

    // Set appCenterDelegate.
    [self.services addObject:service];

    // Start service with log manager.
    [service startWithChannelGroup:self.channelGroup appSecret:self.appSecret];
    
    // Disable service if AppCenter is disabled.
    if ([clazz isEnabled] && !self.isEnabled) {
      self.enabledStateUpdating = YES;
      [clazz setEnabled:NO];
      self.enabledStateUpdating = NO;
    }

    // Send start service log.
    if (sendLog) {
      [self sendStartServiceLog:@[ [clazz serviceName] ]];
    }

    // Service started.
    return YES;
  }
}

- (void)setLogUrl:(NSString *)logUrl {
  @synchronized(self) {
    _logUrl = logUrl;
    if (self.channelGroup) {
      [self.channelGroup setLogUrl:logUrl];
    }
  }
}

#if !TARGET_OS_TV
- (void)setCustomProperties:(MSCustomProperties *)customProperties {
  if (!customProperties || customProperties.properties == 0) {
    MSLogError([MSAppCenter logTag], @"Custom properties may not be null or empty");
    return;
  }
  [self sendCustomPropertiesLog:customProperties.properties];
}
#endif

- (void)setEnabled:(BOOL)isEnabled {
  self.enabledStateUpdating = YES;
  if ([self isEnabled] != isEnabled) {

    // Persist the enabled status.
    [MS_USER_DEFAULTS setObject:@(isEnabled) forKey:kMSAppCenterIsEnabledKey];
    
    // Enable/disable pipeline.
    [self applyPipelineEnabledState:isEnabled];
  }

  // Propagate enable/disable on all services.
  for (id<MSServiceInternal> service in self.services) {
    [[service class] setEnabled:isEnabled];
  }
  self.enabledStateUpdating = NO;
  MSLogInfo([MSAppCenter logTag], @"App Center SDK %@.", isEnabled ? @"enabled" : @"disabled");
}

- (BOOL)isEnabled {

  /*
   * Get isEnabled value from persistence.
   * No need to cache the value in a property, user settings already have their cache mechanism.
   */
  NSNumber *isEnabledNumber = [MS_USER_DEFAULTS objectForKey:kMSAppCenterIsEnabledKey];

  // Return the persisted value otherwise it's enabled by default.
  return (isEnabledNumber) ? [isEnabledNumber boolValue] : YES;
}

- (void)applyPipelineEnabledState:(BOOL)isEnabled {

  // Remove all notification handlers.
  [MS_NOTIFICATION_CENTER removeObserver:self];

  // Hookup to application life-cycle events.
  if (isEnabled) {
#if !TARGET_OS_OSX
    [MS_NOTIFICATION_CENTER addObserver:self
                               selector:@selector(applicationDidEnterBackground)
                                   name:UIApplicationDidEnterBackgroundNotification
                                 object:nil];
    [MS_NOTIFICATION_CENTER addObserver:self
                               selector:@selector(applicationWillEnterForeground)
                                   name:UIApplicationWillEnterForegroundNotification
                                 object:nil];
#endif
  } else {

    // Clean device history in case we are disabled.
    [[MSDeviceTracker sharedInstance] clearDevices];
  }

  // Propagate to log manager.
  [self.channelGroup setEnabled:isEnabled andDeleteDataOnDisabled:YES];
  
  // Send started services.
  if (self.startedServiceNames && isEnabled) {
    [self sendStartServiceLog:self.startedServiceNames];
    self.startedServiceNames = nil;
  }
}

- (void)initializeChannelGroup {

  // Construct log manager.
  self.channelGroup =
      [[MSChannelGroupDefault alloc] initWithAppSecret:self.appSecret installId:self.installId logUrl:self.logUrl];

  // Initialize a channel for start service logs.
  self.channelUnit = [self.channelGroup
      addChannelUnitWithConfiguration:[[MSChannelUnitConfiguration alloc] initDefaultConfigurationWithGroupId:[MSAppCenter groupId]]];
}

- (NSString *)appSecret {
  return _appSecret;
}

- (NSUUID *)installId {
  @synchronized(self) {
    if (!_installId) {

      // Check if install Id has already been persisted.
      NSString *savedInstallId = [MS_USER_DEFAULTS objectForKey:kMSInstallIdKey];
      if (savedInstallId) {
        _installId = MS_UUID_FROM_STRING(savedInstallId);
      }

      // Create a new random install Id if persistence failed.
      if (!_installId) {
        _installId = [NSUUID UUID];

        // Persist the install Id string.
        [MS_USER_DEFAULTS setObject:[_installId UUIDString] forKey:kMSInstallIdKey];
      }
    }
    return _installId;
  }
}

- (BOOL)canBeUsed {
  BOOL canBeUsed = self.sdkConfigured;
  if (!canBeUsed) {
    MSLogError([MSAppCenter logTag], @"App Center SDK hasn't been configured. You need to call [MSAppCenter "
                                     @"start:YOUR_APP_SECRET withServices:LIST_OF_SERVICES] first.");
  }
  return canBeUsed;
}

- (void)sendStartServiceLog:(NSArray<NSString *> *)servicesNames {
  if (self.isEnabled) {
    MSStartServiceLog *serviceLog = [MSStartServiceLog new];
    serviceLog.services = servicesNames;
    [self.channelUnit enqueueItem:serviceLog];
  } else {
    if (self.startedServiceNames == nil) {
      self.startedServiceNames = [NSMutableArray new];
    }
    [self.startedServiceNames addObjectsFromArray:servicesNames];
  }
}

#if !TARGET_OS_TV
- (void)sendCustomPropertiesLog:(NSDictionary<NSString *, NSObject *> *)properties {
  MSCustomPropertiesLog *customPropertiesLog = [MSCustomPropertiesLog new];
  customPropertiesLog.properties = properties;
  [self.channelUnit enqueueItem:customPropertiesLog];
}
#endif

+ (void)resetSharedInstance {
  onceToken = 0; // resets the once_token so dispatch_once will run again
  sharedInstance = nil;
}

#pragma mark - Application life cycle

#if !TARGET_OS_OSX
/**
 *  The application will go to the foreground.
 */
- (void)applicationWillEnterForeground {
  [self.channelGroup resume];
}

/**
 *  The application will go to the background.
 */
- (void)applicationDidEnterBackground {
  [self.channelGroup suspend];
}
#endif

#pragma mark - Disable services for test cloud

/**
 * Determines whether a service should be disabled.
 *
 * @param serviceName The service name to consider for disabling.
 *
 * @return YES if the service should be disabled.
 */
- (BOOL)shouldDisable:(NSString*)serviceName {
  NSDictionary *environmentVariables = [[NSProcessInfo processInfo] environment];
  NSString *disabledServices = environmentVariables[kMSDisableVariable];
  if (!disabledServices) {
    return NO;
  }
  NSMutableArray* disabledServicesList = [NSMutableArray arrayWithArray:[disabledServices componentsSeparatedByString:@","]];

  // Trim whitespace characters.
  for (NSUInteger i = 0; i < [disabledServicesList count]; ++i) {
    NSString *service = [disabledServicesList objectAtIndex:i];
    service = [service stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    [disabledServicesList replaceObjectAtIndex:i withObject:service];
  }
  return [disabledServicesList containsObject:serviceName] || [disabledServicesList containsObject:kMSDisableAll];
}

@end
