//
//  AppDelegate.m
//  whisper.objc
//
//  Created by Georgi Gerganov on 23.10.22.
//

#import "AppDelegate.h"
#import "ViewController.h"
#import <Carbon/Carbon.h>

@interface AppDelegate ()

@property (strong, nonatomic) NSStatusItem *statusItem;
@property (strong, nonatomic) NSWindowController *mainWindowController;
@property (assign, nonatomic) BOOL isWindowVisible;

@end

@implementation AppDelegate

OSStatus MyHotKeyHandler(EventHandlerCallRef nextHandler, EventRef anEvent, void *userData) {
    EventHotKeyID hotKeyID;
    GetEventParameter(anEvent, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(hotKeyID), NULL, &hotKeyID);
    int l = hotKeyID.id;
    switch (l) {
        case 1: // This is the hotkey ID
            [(__bridge AppDelegate *)userData showWindowAction];
            break;
        default:
            break;
    }
    return noErr;
}

// https://stackoverflow.com/questions/3409985/how-to-create-a-menubar-application-for-mac
// https://github.com/nippysaurus/WeatherRock/blob/master/BrissyBomAppDelegate.m#L59

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [self addMenuBarItem];
    [self loadStoryboard];
    [self registerHotKey];
}

- (void)addMenuBarItem {
    // Create status bar item
    NSStatusBar *statusBar = [NSStatusBar systemStatusBar];
    _statusItem = [statusBar statusItemWithLength:NSVariableStatusItemLength];
    [_statusItem setImage:[NSImage imageNamed:NSImageNameTouchBarAudioInputTemplate]];
    [_statusItem setHighlightMode:YES];
    
    // Create menu for status bar item
    NSMenu *menu = [[NSMenu alloc] init];
    NSMenuItem *showWindowItem = [menu addItemWithTitle:@"Show Window" action:@selector(showWindowAction) keyEquivalent:@"c"];
    [showWindowItem setKeyEquivalentModifierMask: NSEventModifierFlagCommand | NSEventModifierFlagOption];
    
    [menu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@""];
    
    [_statusItem setMenu:menu];
}

- (void)showWindowAction {
    if (self.isWindowVisible) {
        [self.mainWindowController close];
    } else {
        [self.mainWindowController showWindow:self];
    }
    self.isWindowVisible = !self.isWindowVisible;


    NSArray *menuOptions = [self getMenuOptions];
    NSLog(@"Menu Options: %@", menuOptions);

//    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//        [self clickMenuOption:@"4,1"];
//    });
}

- (void)loadStoryboard {
    // Load the main storyboard
    NSStoryboard *storyboard = [NSStoryboard storyboardWithName:@"Storyboard" bundle:nil];
    
    // Instantiate the main window controller
    self.mainWindowController = [storyboard instantiateControllerWithIdentifier:@"MainWindowController"];
}

- (void)registerHotKey {
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

- (NSArray *)getMenuOptions {
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

    if (error) {
        NSLog(@"Error parsing JSON: %@", error);
    } else {
        for (NSDictionary *item in output) {
            NSMutableDictionary *newItem = [[NSMutableDictionary alloc] init];
            newItem[@"path"] = item[@"subtitle"];
            newItem[@"title"] = item[@"title"];
            newItem[@"arg"] = item[@"arg"];
            [result addObject:newItem];
        }
    }
    
    return result;
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


@end
