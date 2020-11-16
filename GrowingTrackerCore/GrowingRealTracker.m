//
// Created by xiangyang on 2020/11/10.
//

#import "GrowingRealTracker.h"
#import "GrowingBaseTrackConfiguration.h"
#import "GrowingAppLifecycle.h"
#import "GrowingLog.h"
#import "GrowingTTYLogger.h"
#import "GrowingWSLogger.h"
#import "GrowingWSLoggerFormat.h"
#import "GrowingLogMacros.h"
#import "GrowingGlobal.h"
#import "GrowingDispatchManager.h"
#import "NSString+GrowingHelper.h"
#import "NSDictionary+GrowingHelper.h"
#import "GrowingCocoaLumberjack.h"
#import "GrowingBroadcaster.h"
#import "GrowingDeviceInfo.h"
#import "GrowingVisitEvent.h"
#import "GrowingSession.h"
#import "GrowingConfigurationManager.h"
#import "GrowingEventGenerator.h"
#import "GrowingPersistenceDataProvider.h"

@interface GrowingRealTracker ()
@property(nonatomic, copy, readonly) NSDictionary *launchOptions;
@property(nonatomic, strong, readonly) GrowingBaseTrackConfiguration *configuration;

@end

@implementation GrowingRealTracker
- (instancetype)initWithConfiguration:(GrowingBaseTrackConfiguration *)configuration launchOptions:(NSDictionary *)launchOptions {
    self = [super init];
    if (self) {
        _configuration = [configuration copyWithZone:nil];
        _launchOptions = [launchOptions copy];

        [self loggerSetting];

        GrowingConfigurationManager.sharedInstance.trackConfiguration = self.configuration;
        [GrowingAppLifecycle.sharedInstance setupAppStateNotification];
        [GrowingSession startSession];
    }

    return self;
}

+ (instancetype)trackerWithConfiguration:(GrowingBaseTrackConfiguration *)configuration launchOptions:(NSDictionary *)launchOptions {
    return [[self alloc] initWithConfiguration:configuration launchOptions:launchOptions];
}

- (void)loggerSetting {
    if (self.configuration.debugEnabled) {
        [GrowingLog addLogger:[GrowingTTYLogger sharedInstance] withLevel:GrowingLogLevelDebug];
    } else {
        [GrowingLog removeLogger:[GrowingTTYLogger sharedInstance]];
        [GrowingLog addLogger:[GrowingTTYLogger sharedInstance] withLevel:GrowingLogLevelError];
    }

    [GrowingLog addLogger:[GrowingWSLogger sharedInstance] withLevel:GrowingLogLevelVerbose];
    [GrowingWSLogger sharedInstance].logFormatter = [GrowingWSLoggerFormat new];
}

- (void)trackCustomEvent:(NSString *)eventName {
    [self trackCustomEvent:eventName withAttributes:nil];
}

- (void)trackCustomEvent:(NSString *)eventName withAttributes:(NSDictionary<NSString *, NSString *> *)attributes {
    [GrowingEventGenerator generateCustomEvent:eventName attributes:attributes];
}

- (void)setLoginUserAttributes:(NSDictionary<NSString *, NSString *> *)attributes {
    [GrowingEventGenerator generateLoginUserAttributesEvent:attributes];
}

- (void)setVisitorAttributes:(NSDictionary<NSString *, NSString *> *)attributes {
    [GrowingEventGenerator generateVisitorAttributesEvent:attributes];
}

- (void)setConversionVariables:(NSDictionary<NSString *, NSString *> *)variables {
    [GrowingEventGenerator generateConversionVariablesEvent:variables];
}

- (void)setLoginUserId:(NSString *)userId {
    if (userId.length == 0 || userId.length > 1000) {
        return;
    }

    [GrowingDispatchManager trackApiSel:_cmd dispatchInMainThread:^{
        [self setUserIdValue:userId];
    }];
}

- (void)cleanLoginUserId {
    [GrowingDispatchManager trackApiSel:_cmd dispatchInMainThread:^{
        [self setUserIdValue:@""];
    }];
}

- (void)setDataCollectionEnabled:(BOOL)enabled {

}

- (NSString *)getDeviceId {
    return [GrowingDeviceInfo currentDeviceInfo].deviceIDString;
}

- (void)resetSessionIdWhileUserIdChangedFrom:(NSString *)oldValue toNewValue:(NSString *)newValue {
    // lastUserId 记录的是上一个有值的 CS1
    static NSString *kGrowinglastUserId = nil;

    // 保持 lastUserId 为最近有值的值
    if (oldValue.length > 0) {
        kGrowinglastUserId = oldValue;
    }

    // 如果 lastUserId 有值，并且新设置 CS1 也有值，当两个不同的时候，启用新的 Session 并发送 visit
    if (kGrowinglastUserId.length > 0 && newValue.length > 0 && ![kGrowinglastUserId isEqualToString:newValue]) {
        [[GrowingDeviceInfo currentDeviceInfo] resetSessionID];

        //重置session, 发 Visitor 事件
        [GrowingEventGenerator generateVisitorAttributesEventByResend];
//        if ([[GrowingCustomField shareInstance] growingVistorVar]) {
//            [[GrowingCustomField shareInstance] sendVisitorEvent:[[GrowingCustomField shareInstance] growingVistorVar]];
//        }
    }
}

- (void)setUserIdValue:(nonnull NSString *)value {
    NSString *oldValue = GrowingPersistenceDataProvider.sharedInstance.loginUserId;
//    if ([value isKindOfClass:[NSNumber class]]) {
//        value = [(NSNumber *) value stringValue];
//    }
//
//    if (![value isKindOfClass:[NSString class]] || value.length == 0) {
//        [GrowingCustomField shareInstance].userId = nil;
//    } else {
//        [GrowingCustomField shareInstance].userId = value;
//    }
//    [GrowingPersistenceDataProvider.sharedInstance setSessionId:value];
//    NSString *newValue = [GrowingCustomField shareInstance].userId;

    [self resetSessionIdWhileUserIdChangedFrom:oldValue toNewValue:value];

    // Notify userId changed
    [[GrowingBroadcaster sharedInstance] notifyEvent:@protocol(GrowingUserIdChangedMeessage)
                                          usingBlock:^(id <GrowingMessageProtocol> _Nonnull obj) {
                                              if ([obj respondsToSelector:@selector(userIdDidChangedFrom:to:)]) {
                                                  id <GrowingUserIdChangedMeessage> message = (id <GrowingUserIdChangedMeessage>) obj;
                                                  [message userIdDidChangedFrom:oldValue to:value];
                                              }
                                          }];
}

@end