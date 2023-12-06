//
//  AppDelegate.m
//  whisper.objc
//
//  Created by Georgi Gerganov on 23.10.22.
//

#import "AppDelegate.h"
#import "ViewController.h"
#import <Carbon/Carbon.h>
#import "AudioTranscriber.h"

@interface AppDelegate ()

@property (strong, nonatomic) NSStatusItem *statusItem;
@property (strong, nonatomic) NSWindowController *mainWindowController;
@property (assign, nonatomic) BOOL isWindowVisible;
@property (strong, nonatomic) NSMutableDictionary *menuDataStore;
@property (strong, nonatomic) AudioTranscriber *audioTranscriber;

@end

@implementation AppDelegate

OSStatus MyHotKeyHandler(EventHandlerCallRef nextHandler, EventRef anEvent, void *userData) {
    EventHotKeyID hotKeyID;
    GetEventParameter(anEvent, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(hotKeyID), NULL, &hotKeyID);
    int l = hotKeyID.id;
    switch (l) {
        case 1: // This is the hotkey ID
            [(__bridge AppDelegate *)userData startAction];
            break;
        default:
            break;
    }
    return noErr;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [self addMenuBarItem];
    [self loadStoryboard];
    [self registerHotKey];
    
    // Initialize the AudioTranscriber property
    self.audioTranscriber = [[AudioTranscriber alloc] init];
    self.audioTranscriber.delegate = self;
}

- (void)addMenuBarItem {
    // https://stackoverflow.com/questions/3409985/how-to-create-a-menubar-application-for-mac
    // https://github.com/nippysaurus/WeatherRock/blob/master/BrissyBomAppDelegate.m#L59
    // https://developer.apple.com/documentation/uikit/uicommand/adding_menus_and_shortcuts_to_the_menu_bar_and_user_interface
    // https://developer.apple.com/videos/play/wwdc2022/10061/
    // Create status bar item
    NSStatusBar *statusBar = [NSStatusBar systemStatusBar];
    _statusItem = [statusBar statusItemWithLength:NSVariableStatusItemLength];
    _statusItem.button.image = [NSImage imageNamed:NSImageNameTouchBarAudioInputTemplate];
    
    // Create menu for status bar item
    NSMenu *menu = [[NSMenu alloc] init];
    NSMenuItem *startItem = [menu addItemWithTitle:@"Start" action:@selector(startAction) keyEquivalent:@"c"];
    [startItem setKeyEquivalentModifierMask: NSEventModifierFlagCommand | NSEventModifierFlagOption];
    
    [menu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@""];
    
    [_statusItem setMenu:menu];
}

- (void)startAction {
     // Get the frontmost application name
    NSString *frontmostApp = [[NSWorkspace sharedWorkspace] frontmostApplication].localizedName;
    
    // Pass the frontmost application name to loadMenuData and get the menu options
    NSArray *menuOptions = [self loadMenuDataForApp:frontmostApp];

    // [self showWindowAction];
    
    [self.audioTranscriber toggleRecordingWithCompletion:^(NSString *transcribedText) {
        // Handle the transcribed text
        if (![transcribedText isEqualToString:@""]) {
            NSLog(@"Transcribed Text: %@", transcribedText);
        }
    }];

    // reason transcription query with menuOptions
    
    // perform click
    //    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    //        [self clickMenuOption:@"4,1"];
    //    });
    
    // provide feedback
}

- (NSArray *)loadMenuDataForApp:(NSString *)appName {
    // https://github.com/BenziAhamed/Menu-Bar-Search
    // https://github.com/BalliAsghar/menu-bar-search-raycast
    NSArray *menuOptions = [self.menuDataStore objectForKey:appName];

    if (!menuOptions) {
        NSDictionary *menuData = [self getMenuOptions];
        NSString *retrievedAppName = [menuData objectForKey:@"appName"];
        menuOptions = [menuData objectForKey:@"menuOptions"];

        if (!self.menuDataStore) {
            self.menuDataStore = [[NSMutableDictionary alloc] init];
        }
    
        [self.menuDataStore setObject:menuOptions forKey:retrievedAppName];
    }

    // NSLog(@"Menu Options: %@", menuOptions);

    return  menuOptions;
}

- (void)showWindowAction {
    if (self.isWindowVisible) {
        [self.mainWindowController close];
    } else {
        [self.mainWindowController showWindow:self];
    }
    self.isWindowVisible = !self.isWindowVisible;
}

- (void)loadStoryboard {
    // Load the main storyboard
    NSStoryboard *storyboard = [NSStoryboard storyboardWithName:@"Storyboard" bundle:nil];
    
    // Instantiate the main window controller
    self.mainWindowController = [storyboard instantiateControllerWithIdentifier:@"MainWindowController"];
}

- (void)registerHotKey {
    // https://eastmanreference.com/complete-list-of-applescript-key-codes
    // https://github.com/sindresorhus/KeyboardShortcuts
    EventHotKeyRef myHotKeyRef;
    EventHotKeyID myHotKeyID;
    EventTypeSpec eventType;
    eventType.eventClass = kEventClassKeyboard;
    eventType.eventKind = kEventHotKeyPressed;
    myHotKeyID.signature = 'mhk1';
    myHotKeyID.id = 1;
    RegisterEventHotKey(8, cmdKey + optionKey, myHotKeyID, GetApplicationEventTarget(), 0, &myHotKeyRef);
    InstallApplicationEventHandler(&MyHotKeyHandler, 1, &eventType, (__bridge void *)(self), NULL);
}

- (NSDictionary *)getMenuOptions {
    NSDictionary *options = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
    BOOL accessibilityEnabled = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);

    if (!accessibilityEnabled) {
        NSLog(@"Accessibility API is disabled");
    }
    
    NSString *pathToBinary = [[NSBundle mainBundle] pathForResource:@"menu" ofType:@""];
    
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:pathToBinary];
    
    NSArray *arguments = [NSArray arrayWithObjects:@"-async", nil];
    [task setArguments:arguments];
    
    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    
    NSFileHandle *file = [pipe fileHandleForReading];
    
    [task launch];
    
    NSData *data = [file readDataToEndOfFile];

    // NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    // NSLog(@"%@", output);

    NSError *error = nil;
    NSArray *output = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&error];

    NSMutableArray *result = [[NSMutableArray alloc] init];
    NSString *appName = @"";

    if (error) {
        NSLog(@"Error parsing JSON: %@", error);
    } else {
        for (NSDictionary *item in output) {
            NSMutableDictionary *newItem = [[NSMutableDictionary alloc] init];
            newItem[@"path"] = item[@"subtitle"];
            newItem[@"title"] = item[@"title"];
            newItem[@"arg"] = item[@"arg"];
            [result addObject:newItem];
            if ([item objectForKey:@"appDisplayName"]) {
                appName = item[@"appDisplayName"];
            }
        }
    }
    
    return @{@"menuOptions": result, @"appName": appName};
}

- (void)clickMenuOption:(NSString *)arg {
    NSDictionary *options = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
    BOOL accessibilityEnabled = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
    
    if (!accessibilityEnabled) {
        NSLog(@"Accessibility API is disabled");
    }
    
    NSString *pathToBinary = [[NSBundle mainBundle] pathForResource:@"menu" ofType:@""];
    
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:pathToBinary];
    
    NSArray *arguments = [NSArray arrayWithObjects:@"-click", arg, nil];
    [task setArguments:arguments];
    
    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    
    [task launch];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    [self.mainWindowController.window makeKeyAndOrderFront:self];
    return NO;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

#pragma mark - AudioTranscriberDelegate Methods

- (void)audioTranscriberDidStartCapturing:(AudioTranscriber *)transcriber {
    // Update UI to reflect that recording has started
    // For example, change the menu item image or play a sound
    NSLog(@"Recording has started");
}

- (void)audioTranscriberDidStopCapturing:(AudioTranscriber *)transcriber {
    // Update UI to reflect that recording has stopped
    // For example, revert the menu item image or play a different sound
    NSLog(@"Recording has stopped");
}


@end
