//
//  KalPlayerViewController.m
//  HelloWorld
//
//  Created by Eliza Sapir on 9/11/13.
//
//

// Copyright (c) 2013 Kaltura, Inc. All rights reserved.
// License: http://corp.kaltura.com/terms-of-use
//

static NSString *AppConfigurationFileName = @"AppConfigurations";

static NSString *PlayerPauseNotification = @"playerPauseNotification";
static NSString *ToggleFullscreenNotification = @"toggleFullscreenNotification";

static NSString *IsFullScreenKey = @"isFullScreen";

#import "KPViewController.h"
#import "KPShareManager.h"
#import "NSDictionary+Strategy.h"
#import "KPBrowserViewController.h"
#import "KPPlayerDatasourceHandler.h"
#import "NSString+Utilities.h"
#import "DeviceParamsHandler.h"
#import "KPIMAPlayerViewController.h"
#import "KPlayerController.h"

#include <sys/types.h>
#include <sys/sysctl.h>


typedef NS_ENUM(NSInteger, KPActionType) {
    KPActionTypeShare,
    KPActionTypeOpenHomePage,
    KPActionTypeSkip
};

@interface KPViewController() <KPIMAAdsPlayerDatasource, KPlayerEventsDelegate>{
    // Player Params
    BOOL isFullScreen, isPlaying, isResumePlayer;
    CGRect originalViewControllerFrame;
    CGAffineTransform fullScreenPlayerTransform;
    UIDeviceOrientation prevOrientation, deviceOrientation;
    NSString *playerSource;
    NSDictionary *appConfigDict;
//    BOOL openFullScreen;
    UIButton *btn;
    BOOL isCloseFullScreenByTap;
    BOOL isFullScreenToggled;
    // AirPlay Params
    MPVolumeView *volumeView;
    NSArray *prevAirPlayBtnPositionArr;
    
    BOOL isJsCallbackReady;
    
    
    
    BOOL showChromecastBtn;
    
    NSDictionary *nativeActionParams;
    
    NSMutableArray *callBackReadyRegistrations;
    //KPKalturaPlayWithAdsSupport *IMAPlayer;
    NSURL *videoURL;
    CGRect embedFrame;
}

@property (nonatomic, copy) NSMutableDictionary *kPlayerEventsDict;
@property (nonatomic, copy) NSMutableDictionary *kPlayerEvaluatedDict;
@property (nonatomic, strong) KPShareManager *shareManager;
@property (nonatomic, strong) KPlayerController *playerController;
@end

@implementation KPViewController 
@synthesize webView, player;
@synthesize nativComponentDelegate;

+ (void)setLogLevel:(KPLogLevel)logLevel {
    @synchronized(self) {
        KPLogManager.KPLogLevel = logLevel;
    }
}

//- (instancetype)initWithFrame:(CGRect)frame {
//    self = [super init];
//    if (self) {
//        [self.view setFrame:frame];
//        originalViewControllerFrame = frame;
//        return self;
//    }
//    return nil;
//}
//
//- (instancetype)initWithFrame:(CGRect)frame forView:(UIView *)parentView {
//    self = [self initWithFrame:frame];
//    if (self) {
//        [parentView addSubview:self.view];
//        return self;
//    }
//    return nil;
//}

- (instancetype)initWithURL:(NSURL *)url {
    self = [super init];
    if (self) {
        videoURL = url;
        return self;
    }
    return nil;
}

- (UIView *)playerViewForParentViewController:(UIViewController *)parentViewController
                                        frame:(CGRect)frame {
    if (parentViewController && [parentViewController isKindOfClass:[UIViewController class]]) {
        [parentViewController addChildViewController:self];
        self.view.frame = embedFrame;
        [self.view addObserver:self
                    forKeyPath:@"frame"
                       options:NSKeyValueObservingOptionNew
                       context:nil];
        return self.view;
    }
    return nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([object isEqual:(self.view)] && [keyPath isEqualToString:@"frame"]) {
        [self.view.layer.sublayers.firstObject setFrame:(CGRect){CGPointZero, self.view.frame.size}];
        self.webView.frame = (CGRect){CGPointZero, self.view.frame.size};
    }
}

- (NSMutableDictionary *)players {
    if (!_players) {
        _players = [NSMutableDictionary new];
    }
    return _players;
}

- (NSMutableDictionary *)kPlayerEventsDict {
    if (!_kPlayerEventsDict) {
        _kPlayerEventsDict = [NSMutableDictionary new];
    }
    return _kPlayerEventsDict;
}

- (NSMutableDictionary *)kPlayerEvaluatedDict {
    if (!_kPlayerEvaluatedDict) {
        _kPlayerEvaluatedDict = [NSMutableDictionary new];
    }
    return _kPlayerEvaluatedDict;
}

- (NSString *) platform {
    size_t size;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    char *machine = malloc(size);
    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    NSString *platform = [NSString stringWithUTF8String:machine];
    free(machine);
    return platform;
}

- (void)viewDidLoad {
    KPLogTrace(@"Enter");
    appConfigDict = extractDictionary(AppConfigurationFileName, @"plist");
    setUserAgent();
    [self initPlayerParams];
    // Observer for pause player notifications
    [ [NSNotificationCenter defaultCenter] addObserver: self
                                              selector: @selector(pause)
                                                  name: PlayerPauseNotification
                                                object: nil ];
    
    
    
    
    // Pinch Gesture Recognizer - Player Enter/ Exit FullScreen mode
    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self
                                                                                action:@selector(didPinchInOut:)];
    [self.view addGestureRecognizer:pinch];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(handleEnteredBackground:)
                                                 name: UIApplicationDidEnterBackgroundNotification
                                               object: nil];
//    [self didLoad];
//    [KPViewController sharedChromecastDeviceController];
//    __weak KPViewController *weakSelf = self;
//    [self registerReadyEvent:^{
//        weakSelf.webView.entryId = @"1_gtjr7duj";
//    }];
    
    [super viewDidLoad];
    KPLogTrace(@"Exit");
}

//- (void)viewDidAppear:(BOOL)animated {
//    KPLogTrace(@"Enter");
//    [super viewDidAppear:animated];
//    if( [[NSUserDefaults standardUserDefaults] objectForKey: @"iframe_url"] != nil ) {
//        return;
//    }
//    
//    // Before player appears the user must set the kaltura iframe url
//    if ( kalPlayerViewControllerDelegate && [kalPlayerViewControllerDelegate respondsToSelector: @selector(getInitialKIframeUrl)] ) {
//        NSURL *url = [kalPlayerViewControllerDelegate getInitialKIframeUrl];
//        [self setWebViewURL: [NSString stringWithFormat: @"%@", url]];
//    } else {
//        KPLogError(@"Delegate MUST be set and respond to selector -getInitialKIframeUrl");
//        return;
//    }
//    KPLogTrace(@"Exit");
//}

- (void)handleEnteredBackground: (NSNotification *)not {
    KPLogTrace(@"Enter");
    self.sendNotification(nil, @"doPause");
    KPLogTrace(@"Exit");
}


//- (id<KalturaPlayer>)getPlayerByClass: (Class<KalturaPlayer>)class {
//    NSString *playerName = NSStringFromClass(class);
//    id<KalturaPlayer> newKPlayer = self.players[playerName];
//    
//    if ( newKPlayer == nil ) {
//        newKPlayer = [[class alloc] init];
//        self.players[playerName] = newKPlayer;
//        // if player is created for the first time add observer to all relevant notifications
//        [newKPlayer bindPlayerEvents];
//    }
//    
//    if ( [self player] ) {
//        
//        KPLogInfo(@"%f", [[self player] currentPlaybackTime]);
//        [newKPlayer copyParamsFromPlayer: [self player]];
//    }
//    
//    return newKPlayer;
//}

- (void)viewWillAppear:(BOOL)animated {
    KPLogTrace(@"Enter");
    //CGRect playerViewFrame = CGRectMake( 0, 0, self.view.frame.size.width, self.view.frame.size.height );
    
    
    // Initialize NAtive Player
    if (!_playerController) {
        _playerController = [[KPlayerController alloc] initWithPlayerClassName:PlayerClassName];
        [_playerController addPlayerToView:self.view];
        [_playerController.player setDelegate:self];
    }
    // Initialize HTML layer (controls)
    if (!self.webView) {
        self.webView = [[KPControlsWebView alloc] initWithFrame:(CGRect){CGPointZero, self.view.frame.size}];
        self.webView.playerControlsWebViewDelegate = self;
        [self.webView loadRequest:[NSURLRequest requestWithURL:videoURL]];
        [self.view addSubview:self.webView];
    }
    [super viewWillAppear:NO];
    
    KPLogTrace(@"Exit");
}

- (void)viewDidDisappear:(BOOL)animated {
    KPLogTrace(@"Enter");
    
    isResumePlayer = YES;
    [super viewDidDisappear:animated];
    
    KPLogTrace(@"Exit");
}

#pragma mark - WebView Methods

//- (void)setWebViewURL: (NSString *)iframeUrl {
//    KPLogTrace(@"Enter");
//    [[NSUserDefaults standardUserDefaults] setObject: iframeUrl forKey:@"iframe_url"];
//    
////    iframeUrl = [iframeUrl stringByAddingPercentEscapesUsingEncoding: NSUTF8StringEncoding];
//    
//    
//    /// Add the idfa to the iframeURL
//    [ [self webView] loadRequest: [ NSURLRequest requestWithURL: [NSURL URLWithString: iframeUrl.appendVersion] ] ];
//    KPLogTrace(@"Exit");
//}

- (void)changeMedia:(NSString *)mediaID {
    NSString *name = [NSString stringWithFormat:@"'{\"entryId\":\"%@\"}'", mediaID];
    [self sendNotification:@"changeMedia" forName:name];
}


- (void)load {
    [self.webView loadRequest:[KPPlayerDatasourceHandler videoRequest:self.datasource]];
}


#pragma mark - Player Methods

-(void)initPlayerParams {
    KPLogTrace(@"Enter");
    isFullScreen = NO;
    isPlaying = NO;
    isResumePlayer = NO;
    isFullScreenToggled = NO;
    KPLogTrace(@"Exit");
}

//- (void)play {
//    KPLogTrace(@"Enter");
//    
//    [[self player] play];
//    
//    KPLogTrace(@"Exit");
//}
//
//- (void)pause {
//    
//    KPLogTrace(@"Enter");
//    [[self player] pause];
//    
//    KPLogTrace(@"Exit");
//}
//
//- (void)stop {
//    
//    KPLogTrace(@"Enter");
//    [[self player] stop];
//    
//    KPLogTrace(@"Exit");
//}

- (void)doNativeAction {
    KPLogTrace(@"Enter");

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    SEL nativeAction = NSSelectorFromString(nativeActionParams.actionType);
    [self performSelector:nativeAction withObject:nil];
#pragma clang diagnostic pop
    KPLogTrace(@"Exit");
}

- (void)share {
    KPLogTrace(@"Enter");
    self.shareManager = [KPShareManager new];
    self.shareManager.datasource = nativeActionParams;
    __weak KPViewController *weakSelf = self;
    UIViewController *shareController = [self.shareManager shareWithCompletion:^(KPShareResults result,
                                                                            KPShareError *shareError) {
        if (shareError.error) {
            KPLogError(@"%@", shareError.error.description);
        }
        weakSelf.shareManager = nil;
    }];
    [self presentViewController:shareController animated:YES completion:nil];
    KPLogTrace(@"Exit");
}

- (void)openURL {
    KPLogTrace(@"Enter");
    KPBrowserViewController *browser = [KPBrowserViewController currentBrowser];
    browser.url = nativeActionParams.openURL;
    [self presentViewController:browser animated:YES completion:nil];
    KPLogTrace(@"Exit");
}

#pragma Kaltura Player External API - KDP API

- (void)registerReadyEvent:(void (^)())handler {
    KPLogTrace(@"Enter");
    if (isJsCallbackReady) {
        handler();
    } else {
        if (!callBackReadyRegistrations) {
            callBackReadyRegistrations = [NSMutableArray new];
        }
        if (handler) {
            [callBackReadyRegistrations addObject:handler];
        }
    }
    KPLogTrace(@"Exit");
}

- (void(^)(void(^)()))registerReadyEvent {
    KPLogTrace(@"Enter");
    __weak KPViewController *weakSelf = self;
    return ^(void(^readyCallback)()){
        [weakSelf registerReadyEvent:readyCallback];
        KPLogTrace(@"Exit");
    };
}

- (void)notifyJsReady {
    
    KPLogTrace(@"Enter");
    isJsCallbackReady = YES;
    NSArray *registrations = callBackReadyRegistrations.copy;
    for (void(^handler)() in registrations) {
        handler();
        [callBackReadyRegistrations removeObject:handler];
    }
    callBackReadyRegistrations = nil;
    KPLogTrace(@"Exit");
}

- (void)addEventListener:(NSString *)event
                 eventID:(NSString *)eventID
                 handler:(void (^)(NSString *))handler {
    KPLogTrace(@"Enter");
    __weak KPViewController *weakSelf = self;
    [self registerReadyEvent:^{
        NSMutableArray *listenerArr = self.kPlayerEventsDict[event];
        if (!listenerArr) {
            listenerArr = [NSMutableArray new];
        }
        [listenerArr addObject:@{eventID: handler}];
        self.kPlayerEventsDict[event] = listenerArr;
        if (listenerArr.count == 1 && !event.isToggleFullScreen) {
            [weakSelf.webView addEventListener:event];
        }
        KPLogTrace(@"Exit");
    }];
}

- (void(^)(NSString *, NSString *, void(^)(NSString *)))addEventListener {
    KPLogTrace(@"Enter");
    __weak KPViewController *weakSelf = self;
    return ^(NSString *event, NSString *eventID, void(^completion)()){
        [weakSelf addEventListener:event eventID:eventID handler:completion];
        KPLogTrace(@"Exit");
    };
}

- (void)notifyKPlayerEvent: (NSArray *)arr {
    KPLogTrace(@"Enter");
    NSString *eventName = arr[0];
    NSArray *listenersArr = self.kPlayerEventsDict[ eventName ];
    
    if ( listenersArr != nil ) {
        for (NSDictionary *eDict in listenersArr) {
            ((void(^)(NSString *))eDict.allValues.lastObject)(eventName);
        }
    }
    KPLogTrace(@"Exit");
}


- (void)removeEventListener:(NSString *)event
                    eventID:(NSString *)eventID {
    KPLogTrace(@"Enter");
    NSMutableArray *listenersArr = self.kPlayerEventsDict[event];
    if ( listenersArr == nil || [listenersArr count] == 0 ) {
        KPLogInfo(@"No such event to remove");
        return;
    }
    NSArray *temp = listenersArr.copy;
    for (NSDictionary *dict in temp) {
        if ([dict.allKeys.lastObject isEqualToString:eventID]) {
            [listenersArr removeObject:dict];
        }
    }
    if ( !listenersArr.count ) {
        listenersArr = nil;
        if (!event.isToggleFullScreen) {
            [self.webView removeEventListener:event];
        }
    }
    KPLogTrace(@"Exit");
}

- (void(^)(NSString *, NSString *))removeEventListener {
    KPLogTrace(@"Enter");
    __weak KPViewController *weakSelf = self;
    return ^(NSString *event, NSString *eventID) {
        [weakSelf removeEventListener:event eventID:eventID];
        KPLogTrace(@"Exit");
    };
}

- (void)asyncEvaluate:(NSString *)expression
         expressionID:(NSString *)expressionID
              handler:(void(^)(NSString *))handler {
    KPLogTrace(@"Enter");
    self.kPlayerEvaluatedDict[expressionID] = handler;
    [self.webView evaluate:expression evaluateID:expressionID];
    KPLogTrace(@"Exit");
}

- (void(^)(NSString *, NSString *, void(^)(NSString *)))asyncEvaluate {
    KPLogTrace(@"Enter");
    __weak KPViewController *weakSelf = self;
    return ^(NSString *expression, NSString *expressionID, void(^handler)(NSString *value)) {
        [weakSelf asyncEvaluate:expression expressionID:expressionID handler:handler];
        KPLogTrace(@"Exit");
    };
}

- (void)notifyKPlayerEvaluated: (NSArray *)arr {
    KPLogTrace(@"Enter");
    if (arr.count == 2) {
        ((void(^)(NSString *))self.kPlayerEvaluatedDict[arr[0]])(arr[1]);
    } else if (arr.count < 2) {
        KPLogDebug(@"Missing Evaluation Params");
    }
    KPLogTrace(@"Exit");
}

- (void)sendNotification:(NSString *)notification forName:(NSString *)notificationName {
    KPLogTrace(@"Enter");
    if ( !notification || [ notification isKindOfClass: [NSNull class] ] ) {
        notification = @"null";
    }
    [self.webView sendNotification:notification withName:notificationName];
    KPLogTrace(@"Exit");
}

- (void(^)(NSString *, NSString *))sendNotification {
    KPLogTrace(@"Enter");
    __weak KPViewController *weakSelf = self;
    return ^(NSString *notification, NSString *notificationName){
        [weakSelf sendNotification:notification forName:notificationName];
        KPLogTrace(@"Exit");
    };
}

- (void)setKDPAttribute:(NSString *)pluginName
           propertyName:(NSString *)propertyName
                  value:(NSString *)value {
    KPLogTrace(@"Enter");
    [self.webView setKDPAttribute:pluginName propertyName:propertyName value:value];
    KPLogTrace(@"Exit");
}

- (void(^)(NSString *, NSString *, NSString *))setKDPAttribute {
    KPLogTrace(@"Enter");
    __weak KPViewController *weakSelf = self;
    return ^(NSString *pluginName, NSString *propertyName, NSString *value) {
        [weakSelf setKDPAttribute:pluginName propertyName:propertyName value:value];
        KPLogTrace(@"Exit");
    };
}

- (void)triggerEvent:(NSString *)event withValue:(NSString *)value {
    KPLogTrace(@"Enter");
    [self.webView triggerEvent:event withValue:value];
    KPLogTrace(@"Exit");
}

- (void(^)(NSString *, NSString *))triggerEvent {
    KPLogTrace(@"Enter");
    __weak KPViewController *weakSelf = self;
    return ^(NSString *event, NSString *value){
        [weakSelf triggerEvent:event withValue:value];
        KPLogTrace(@"Exit");
    };
}


#pragma mark - Player Layout & Fullscreen Treatment

//- (void)updatePlayerLayout {
//    
//    KPLogTrace(@"Enter");
//    //Update player layout
//    //[self.webView updateLayout];
//    self.triggerEvent(@"updateLayout", nil);
//    // FullScreen Treatment
//    [ [NSNotificationCenter defaultCenter] postNotificationName: @"toggleFullscreenNotification"
//                                                         object:self
//                                                       userInfo: @{IsFullScreenKey: @(isFullScreen)} ];
//    
//    KPLogTrace(@"Exit");
//}
//
////- (void)setOrientationTransform: (CGFloat) angle{
//    KPLogTrace(@"Enter");
//    // UIWindow frame in ios 8 different for Landscape mode
//    if( isIOS(8) && !isFullScreenToggled ) {
//        [self.view setTransform: CGAffineTransformIdentity];
//        return;
//    }
//    
//    isFullScreenToggled = NO;
//    if ( isFullScreen ) {
//        // Init Transform for Fullscreen
//        fullScreenPlayerTransform = CGAffineTransformMakeRotation( ( angle * M_PI ) / 180.0f );
//        fullScreenPlayerTransform = CGAffineTransformTranslate( fullScreenPlayerTransform, 0.0, 0.0);
//        
//        self.view.center = [[UIApplication sharedApplication] delegate].window.center;
//        [self.view setTransform: fullScreenPlayerTransform];
//        
//        // Add Mask Support to WebView & Player
//        self.player.view.autoresizingMask = UIViewAutoresizingFlexibleWidth |UIViewAutoresizingFlexibleHeight;
//        self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth |UIViewAutoresizingFlexibleHeight;
//    }else{
//        [self.view setTransform: CGAffineTransformIdentity];
//    }
//    
//    KPLogTrace(@"Exit");
//}

//- (void)checkDeviceStatus{
//    KPLogTrace(@"Enter");
//    deviceOrientation = [[UIDevice currentDevice] orientation];
//    if ( isIpad || openFullScreen ) {
//        if (deviceOrientation == UIDeviceOrientationUnknown) {
//            if ( _statusBarOrientation == UIDeviceOrientationLandscapeLeft ) {
//                [self setOrientationTransform: 90];
//            }else if(_statusBarOrientation == UIDeviceOrientationLandscapeRight){
//                [self setOrientationTransform: -90];
//            }else if(_statusBarOrientation == UIDeviceOrientationPortrait){
//                [self setOrientationTransform: 180];
//                [self.view setTransform: CGAffineTransformIdentity];
//            }else if (_statusBarOrientation == UIDeviceOrientationPortraitUpsideDown){
//                [self setOrientationTransform: -180];
//            }
//        }else{
//            if ( deviceOrientation == UIDeviceOrientationLandscapeLeft ) {
//                [self setOrientationTransform: 90];
//            }else if(deviceOrientation == UIDeviceOrientationLandscapeRight){
//                [self setOrientationTransform: -90];
//            }else if(deviceOrientation == UIDeviceOrientationPortrait){
//                [self setOrientationTransform: 180];
//                [self.view setTransform: CGAffineTransformIdentity];
//            }else if (deviceOrientation == UIDeviceOrientationPortraitUpsideDown){
//                [self setOrientationTransform: -180];
//            }
//        }
//    }else{
//        if (deviceOrientation == UIDeviceOrientationUnknown ||
//            deviceOrientation == UIDeviceOrientationPortrait ||
//            deviceOrientation == UIDeviceOrientationPortraitUpsideDown ||
//            deviceOrientation == UIDeviceOrientationFaceDown ||
//            deviceOrientation == UIDeviceOrientationFaceUp) {
//            [self setOrientationTransform: 90];
//        }else{
//            if ( deviceOrientation == UIDeviceOrientationLandscapeLeft ) {
//                [self setOrientationTransform: 90];
//            }else if( deviceOrientation == UIDeviceOrientationLandscapeRight ){
//                [self setOrientationTransform: -90];
//            }
//        }
//    }
//    KPLogTrace(@"Exit");
//}

//- (void)checkOrientationStatus{
//    KPLogTrace(@"Enter");
//    isCloseFullScreenByTap = NO;
//    
//    // Handle rotation issues when player is playing
//    if ( isPlaying ) {
//        [self closeFullScreen];
//        [self openFullScreen: openFullScreen];
//        if ( isFullScreen ) {
//            [self checkDeviceStatus];
//        }
//        
//        if ( !isIpad && (deviceOrientation == UIDeviceOrientationPortrait || deviceOrientation == UIDeviceOrientationPortraitUpsideDown) ) {
//            if ( !openFullScreen ) {
//                [self closeFullScreen];
//            }
//        }
//    }else {
//        [self closeFullScreen];
//    }
//    KPLogTrace(@"Exit");
//}

//- (void)setNativeFullscreen {
//    KPLogTrace(@"Enter");
//    [UIApplication sharedApplication].statusBarHidden = YES;
//    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
//    [[NSNotificationCenter defaultCenter] addObserver:self
//                                             selector:@selector(deviceOrientationDidChange)
//                                                 name:UIDeviceOrientationDidChangeNotification
//                                               object:nil];
//    
//    // Disable fullscreen button if the player is set to fullscreen by default
//    self.registerReadyEvent(^{
//        if ([self respondsToSelector:@selector(setKDPAttribute:propertyName:value:)]) {
//            self.setKDPAttribute(@"fullScreenBtn", @"visible", @"false");
//        }
//    });
//    KPLogTrace(@"Exit");
//}
//
//- (void)deviceOrientationDidChange {
//    KPLogTrace(@"Enter");
//    CGRect mainFrame;
//    
//    if ( _deviceOrientation == UIDeviceOrientationFaceDown || _deviceOrientation == UIDeviceOrientationFaceUp ) {
//        return;
//    }
//    
//    if ( isIOS(8) ) {
//        mainFrame = CGRectMake( screenOrigin.x, screenOrigin.y, screenSize.width, screenSize.height ) ;
//    } else if(UIDeviceOrientationIsLandscape(_deviceOrientation)){
//        mainFrame = CGRectMake( screenOrigin.x, screenOrigin.y, screenSize.height, screenSize.width ) ;
//    } else {
//        mainFrame = CGRectMake( screenOrigin.x, screenOrigin.y, screenSize.width, screenSize.height ) ;
//    }
//    
//    [self.view setFrame: mainFrame];
//    
//    [UIApplication sharedApplication].statusBarHidden = YES;
//    
//    [self.player.view setFrame: CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height)];
//    [self.webView setFrame: self.player.view.frame];
//    [ self.view setTransform: fullScreenPlayerTransform ];
//    self.triggerEvent(@"enterfullscreen", nil);
//    self.triggerEvent(@"updateLayout", nil);
//    [self checkDeviceStatus];
//    KPLogTrace(@"Exit");
//}

//- (void)openFullscreen {
//    KPLogTrace(@"Enter");
//    if ( !isFullScreen ) {
//        [self toggleFullscreen];
//    }
//    KPLogTrace(@"Exit");
//}
//
//- (void)closeFullscreen {
//    KPLogTrace(@"Enter");
//    if ( isFullScreen ) {
//        [self toggleFullscreen];
//    }
//    KPLogTrace(@"Exit");
//}
//
//- (void)toggleFullscreen {
//    KPLogTrace(@"Enter");
//    if (self.kPlayerEventsDict[KPlayerEventToggleFullScreen]) {
//        NSArray *listenersArr = self.kPlayerEventsDict[ KPlayerEventToggleFullScreen ];
//        if ( listenersArr != nil ) {
//            for (NSDictionary *eDict in listenersArr) {
//                ((void(^)())eDict.allValues.lastObject)(eDict.allKeys.firstObject);
//            }
//        }
//    } else {
//        [self updatePlayerLayout];
//        isCloseFullScreenByTap = YES;
//        isFullScreenToggled = YES;
//        
//        if ( !isFullScreen ) {
//            [self openFullScreen: openFullScreen];
//            [self checkDeviceStatus];
//        } else{
//            [self closeFullScreen];
//        }
//    }
//    KPLogTrace(@"Exit");
//}

//- (void)openFullScreen: (BOOL)openFullscreen{
//    KPLogTrace(@"Enter");
//    isFullScreen = YES;
//    
//    CGRect mainFrame;
//    openFullScreen = openFullscreen;
//    
//    if ( isIpad || openFullscreen ) {
//        if ( isDeviceOrientation(UIDeviceOrientationUnknown) ) {
//            if (UIDeviceOrientationPortrait == _statusBarOrientation || UIDeviceOrientationPortraitUpsideDown == _statusBarOrientation) {
//                mainFrame = CGRectMake( screenOrigin.x, screenOrigin.y, screenSize.width, screenSize.height ) ;
//            }else if(UIDeviceOrientationIsLandscape(_statusBarOrientation)){
//                mainFrame = CGRectMake( screenOrigin.x, screenOrigin.y, screenSize.height, screenSize.width ) ;
//            }
//        }else{
//            if ( UIDeviceOrientationPortrait == _deviceOrientation || UIDeviceOrientationPortraitUpsideDown == _deviceOrientation ) {
//                mainFrame = CGRectMake( screenOrigin.x, screenOrigin.y, screenSize.width, screenSize.height ) ;
//            }else if(UIDeviceOrientationIsLandscape(_deviceOrientation)){
//                mainFrame = CGRectMake( screenOrigin.x, screenOrigin.y, screenSize.height, screenSize.width ) ;
//            }
//      }
//    }else{
//        mainFrame = CGRectMake( screenOrigin.x, screenOrigin.y, screenSize.height, screenSize.width ) ;
//    }
//    
//    [self.view setFrame: mainFrame];
//    
//    [UIApplication sharedApplication].statusBarHidden = YES;
//
//    [self.player.view setFrame: CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height)];
//    [self.webView setFrame: self.player.view.bounds];
//    [ self.view setTransform: fullScreenPlayerTransform ];
//    
//    self.triggerEvent(@"enterfullscreen", nil);
//    [self updatePlayerLayout];
//    KPLogTrace(@"Exit");
//}
//
//- (void)closeFullScreen{
//    KPLogTrace(@"Enter");
//    if ( openFullScreen && isCloseFullScreenByTap ) {
////        [self stop];
//    }
//    
//    CGRect originalFrame = CGRectMake( 0, 0, originalViewControllerFrame.size.width, originalViewControllerFrame.size.height );
//    isFullScreen = NO;
//    
//    [self.view setTransform: CGAffineTransformIdentity];
//    self.view.frame = originalViewControllerFrame;
//    self.player.view.frame = originalFrame;
//    self.webView.frame = [[[self player] view] frame];
//    
//    [UIApplication sharedApplication].statusBarHidden = NO;
//    
//    self.triggerEvent(@"exitfullscreen", nil);
//    [self updatePlayerLayout];
//    KPLogTrace(@"Exit");
//}

// "pragma clang" is attached to prevent warning from “PerformSelect may cause a leak because its selector is unknown”
- (void)handleHtml5LibCall:(NSString*)functionName callbackId:(int)callbackId args:(NSArray*)args{
       KPLogTrace(@"Enter");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    if ( [args count] > 0 ) {
        functionName = [NSString stringWithFormat:@"%@:", functionName];
    }
    SEL selector = NSSelectorFromString(functionName);
    if ([self respondsToSelector:selector]) {
        KPLogDebug(@"html5 call::%@ %@",functionName, args);
        [self performSelector:selector withObject:args];
    } else if ([_playerController.player respondsToSelector:selector]) {
        [_playerController.player performSelector:selector withObject:args];
    }
    
#pragma clang diagnostic pop
    
    KPLogTrace(@"Exit");
}

#pragma mark KPlayerEventsDelegate
- (void)eventName:(NSString *)event value:(NSString *)value {
    [self.webView triggerEvent:event withValue:value];
}

//- (void)bindPlayerEvents{
//    KPLogTrace(@"Enter");
//    if ( self ) {
////        [[self player] bindPlayerEvents];
//        NSArray *kPlayerEvents = @[@"canplay",
//                                   @"durationchange",
//                                   @"loadedmetadata",
//                                   @"play",
//                                   @"pause",
//                                   @"ended",
//                                   @"seeking",
//                                   @"seeked",
//                                   @"timeupdate",
//                                   @"progress",
//                                   @"fetchNativeAdID"];
//        
//        for (id kPlayerEvent in kPlayerEvents) {
//            [[NSNotificationCenter defaultCenter] addObserver: self
//                                                      selector: @selector(triggerKPlayerNotification:)
//                                                          name: kPlayerEvent
//                                                        object: nil];
//        }
//    }
//    KPLogTrace(@"Exit");
//}

- (void)triggerKPlayerNotification: (NSNotification *)note{
    KPLogTrace(@"Enter");
    isPlaying = note.name.isPlay || (!note.name.isPause && !note.name.isStop);
    [self.webView triggerEvent:note.name withValue:note.userInfo[note.name]];
    KPLogDebug(@"%@\n%@", note.name, note.userInfo[note.name]);
    KPLogTrace(@"Exit");
}

- (void)setAttribute: (NSArray*)args{
    KPLogTrace(@"Enter");
    NSString *attributeName = [args objectAtIndex:0];
    NSString *attributeVal = args[1];
    
    switch ( attributeName.attributeEnumFromString ) {
        case src:
            _playerController.src = attributeVal;
            break;
        case currentTime:
            _playerController.currentPlayBackTime = [attributeVal doubleValue];
            break;
        case visible:
            [self visible: attributeVal];
            break;
#if !(TARGET_IPHONE_SIMULATOR)
//        case wvServerKey:
//            if ( [[self player] respondsToSelector:@selector(setWideVideConfigurations)] ) {
//                [[self player] setWideVideConfigurations];
//            }
//            if ( [[self player] respondsToSelector:@selector(initWV:andKey:)]) {
//                [[self player] initWV: playerSource andKey: attributeVal];
//            }
//
//            break;
            _playerController.drmID = attributeVal;
#endif
        case nativeAction:
            nativeActionParams = [NSJSONSerialization JSONObjectWithData:[attributeVal dataUsingEncoding:NSUTF8StringEncoding]
                                                                 options:0
                                                                   error:nil];
            break;
        case doubleClickRequestAds: {
            [self.player pause];
            __weak KPViewController *weakSelf = self;
            KPIMAPlayerViewController *imaPlayer = [[KPIMAPlayerViewController alloc] initWithParent:self];
            [imaPlayer loadIMAAd:attributeVal eventsListener:^(NSDictionary *adEventParams) {
                if (adEventParams) {
                    [weakSelf.webView triggerEvent:adEventParams.allKeys.firstObject withJSON:adEventParams.allValues.firstObject];
                } else {
                    [imaPlayer destroy];
                }
                
            }];
            
        }
            break;
        default:
            break;
    }
    KPLogTrace(@"Exit");
}


- (void)resizePlayerView:(CGRect)newFrame {
    KPLogTrace(@"Enter");
    originalViewControllerFrame = newFrame;
    if ( !isFullScreen ) {
        self.view.frame = originalViewControllerFrame;
        self.player.view.frame = newFrame;
        self.webView.frame = self.player.view.frame;
    }
    KPLogTrace(@"Exit");
}

- (void)setPlayerFrame:(CGRect)playerFrame {
    KPLogTrace(@"Enter");
    if ( !isFullScreen ) {
        self.view.frame = playerFrame;
        self.player.view.frame = CGRectMake( 0, 0, playerFrame.size.width, playerFrame.size.height );
        self.webView.frame = self.player.view.frame;
    }
    KPLogTrace(@"Exit");
}

-(void)visible:(NSString *)boolVal{
    KPLogTrace(@"Enter");
    self.triggerEvent(@"visible", [NSString stringWithFormat:@"%@", boolVal]);
    KPLogTrace(@"Exit");
}

//- (void)stopAndRemovePlayer{
//    KPLogTrace(@"Enter");
//    [self visible:@"false"];
//    [[self player] stop];
//    [[self player] setContentURL:nil];
//    [[[self player] view] removeFromSuperview];
//    [[self webView] removeFromSuperview];
//    
//    if( isFullScreen ){
//        isFullScreen = NO;
//    }
//    
//    self.player = nil;
//    self.webView = nil;
//    
//    [self removeAirPlayIcon];
//    KPLogTrace(@"Exit");
//}



//- (void)doneFSBtnPressed {
//    KPLogTrace(@"Enter");
//    isCloseFullScreenByTap = YES;
//    [self closeFullScreen];
//    KPLogTrace(@"Exit");
//}



//- (void)switchPlayer:(Class)p {
//    KPLogTrace(@"Enter");
//    [[self player] stop];
//    self.player = [self getPlayerByClass: p];
//    
////    if ( [self.player isPreparedToPlay] ) {
////        [self.player play];
////    }
//    KPLogTrace(@"Exit");
//}

//-(void)showChromecastDeviceList {
//    KPLogTrace(@"Enter");
//    [ [KPViewController sharedChromecastDeviceController] chooseDevice: self];
//    KPLogTrace(@"Exit");
//}


#pragma mark -
#pragma mark Rotation methods
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return YES;
}

- (BOOL)shouldAutorotate{
    return YES;
}

-(NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAll;
    
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    
    self.webView.frame = [UIScreen mainScreen].bounds;
    [self.view.layer.sublayers[0] setFrame:self.view.frame];
}


#pragma mark -

//-(void)didPinchInOut:(UIPinchGestureRecognizer *) recongizer {
//    KPLogTrace(@"Enter");
//    if (isFullScreen && recongizer.scale < 1) {
//        [self toggleFullscreen];
//    } else if (!isFullScreen && recongizer.scale > 1) {
//        [self toggleFullscreen];
//    }
//    KPLogTrace(@"Exit");
//}

//- (void)didConnectToDevice:(GCKDevice*)device {
//    KPLogTrace(@"Enter");
//    [self switchPlayer: [KPChromecast class]];
//    self.triggerEvent(@"chromecastDeviceConnected", nil);
//    KPLogTrace(@"Exit");
//}

//- (void)didReceiveMediaStateChange {
//    KPLogTrace(@"Enter");
//    if (![self.player isKindOfClass:[KPChromecast class]]) {
//        return;
//    }
//    
//    KPChromecast *chromecastPlayer = (KPChromecast *) self.player;
//    
//    if ( [[KPViewController sharedChromecastDeviceController] playerState] == GCKMediaPlayerStatePlaying ) {
//        [chromecastPlayer triggerMediaNowPlaying];
////        [self triggerEventsJavaScript: @"play" WithValue: nil];
//    } else if ( [[KPViewController sharedChromecastDeviceController] playerState] == GCKMediaPlayerStatePaused ) {
//        [chromecastPlayer triggerMediaNowPaused];
//    }
//    KPLogTrace(@"Exit");
//}

//// Chromecast
//- (void)didLoad {
//    KPLogTrace(@"Enter");
//    showChromecastBtn = NO;
//    [[KPViewController sharedChromecastDeviceController] performScan: YES];
//    KPLogTrace(@"Exit");
//}
//
//+ (id)sharedChromecastDeviceController {
//    KPLogTrace(@"Enter");
//    static ChromecastDeviceController *chromecastDeviceController = nil;
//    static dispatch_once_t onceToken;
//
//    dispatch_once( &onceToken, ^{
//       chromecastDeviceController = [[ChromecastDeviceController alloc] init];
//    });
//    KPLogTrace(@"Exit");
//    return chromecastDeviceController;
//}
//
//- (void)didDiscoverDeviceOnNetwork {
//    KPLogTrace(@"Enter");
//    if ( [[[KPViewController sharedChromecastDeviceController] deviceScanner] devices] ) {
//        showChromecastBtn = YES;
//    }
//    KPLogTrace(@"Exit");
//}
//
//-(void)notifyLayoutReady {
//    KPLogTrace(@"Enter");
//    [self setChromecastVisiblity];
//    KPLogTrace(@"Exit");
//}
//
//- (void)setChromecastVisiblity {
//    KPLogTrace(@"Enter");
//    if ( [self respondsToSelector: @selector(setKDPAttribute:propertyName:value:)] ) {
//        self.setKDPAttribute(@"chromecast", @"visible", showChromecastBtn ? @"true": @"false");
//    }
//    KPLogTrace(@"Exit");
//}

//- (void)didDisconnect {
//    KPLogTrace(@"Enter");
//    [self switchPlayer: [KalturaPlayer class]];
//    self.triggerEvent(@"chromecastDeviceDisConnected", nil);
//    KPLogTrace(@"Exit");
//}

#pragma mark KPIMAAdsPlayerDatasource
- (NSTimeInterval)currentTime {
    return [self.player currentPlaybackTime];
}

- (CGFloat)adPlayerHeight {
    return self.webView.videoHolderHeight;
}
@end


