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

typedef void (^InterpretationResultHandler)(NSDictionary *result);
@property (copy, nonatomic) InterpretationResultHandler interpretationResultHandler;

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
            
            // Filter menu options based on fuzzy keyword matching with transcribedText
            NSArray *relevantMenuOptions = [self filterMenuOptions:menuOptions withTranscribedText:transcribedText];
            
            NSLog(@"Menu Options: %@", relevantMenuOptions);
            
            // Call OpenAI API to interpret the transcribed text
            [self interpretTranscribedText:transcribedText
                           withMenuOptions:relevantMenuOptions
                              frontmostApp:frontmostApp
                         completionHandler:^(NSDictionary *result) {
                NSString *option = result[@"option"];
                NSString *message = result[@"message"];
                // Use the option and message as needed
                NSLog(@"Option: %@, Message: %@", option, message);
            }];
            
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

- (NSArray *)filterMenuOptions:(NSArray *)menuOptions withTranscribedText:(NSString *)transcribedText {
    // Implement fuzzy keyword matching here and return the filtered menu options
    // This is a placeholder for the actual fuzzy matching logic
    // Return the first five menu options or all if there are less than five
    NSRange range = NSMakeRange(0, MIN(menuOptions.count, 5));
    NSArray *filteredMenuOptions = [menuOptions subarrayWithRange:range];
    return filteredMenuOptions;
    return menuOptions; // Return the filtered menu options
}

- (void)interpretTranscribedText:(NSString *)transcribedText withMenuOptions:(NSArray *)menuOptions frontmostApp:(NSString *)frontmostApp completionHandler:(InterpretationResultHandler)completionHandler {
    // Prepare the data for the POST request
    NSString *apiKey = @"";
    NSString *apiEndpoint = @"https://api.openai.com/v1/chat/completions";
    NSDictionary *headers = @{@"Authorization": [NSString stringWithFormat:@"Bearer %@", apiKey],
                              @"Content-Type": @"application/json"};
    
    // Construct the system and user messages
    NSMutableArray *messages = [NSMutableArray array];
    [messages addObject:@{@"role": @"system", @"content": @"You are a helpful copilot for macOS. Your task is to interpret transcribed voice commands and recommend an action based on the current application's provided menu options. Please respond with a JSON object containing two keys - option: the recommended option; message: anything else you want to say to the user (use this when there's no clear option match or another issue)."}];
    [messages addObject:@{@"role": @"user", @"content": [NSString stringWithFormat:@"Interpret this command for %@: %@. Respond only with the menu option.", frontmostApp, transcribedText]}];
    
    // Add relevant menu options to the context if necessary
    NSMutableString *optionsContent = [NSMutableString stringWithString:@"Pick one of the following menu options: "];
    for (NSDictionary *option in menuOptions) {
        [optionsContent appendFormat:@"\n%@ > %@, ", option[@"path"], option[@"title"]];
    }
    
    [messages addObject:@{@"role": @"user", @"content": optionsContent}];
    
    NSDictionary *body = @{@"model": @"gpt-4-1106-preview",
                           @"messages": messages,
                           @"temperature": @0,
                           @"max_tokens": @50,
                           @"response_format": @{@"type": @"json_object"}};
    
    NSLog(@"%@", body);
    
    NSError *error;
    NSData *postData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&error];
    
    if (error) {
        NSLog(@"Error preparing request data: %@", error.localizedDescription);
        return;
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:apiEndpoint]];
    [request setHTTPMethod:@"POST"];
    [request setAllHTTPHeaderFields:headers];
    [request setHTTPBody:postData];
    
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        
         if (error) {
            NSLog(@"Error making API request: %@", error.localizedDescription);
            if (completionHandler) {
                completionHandler(@{@"message": error.localizedDescription});
            }
        } else {
            NSError *jsonError;
            NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            if (jsonError) {
                NSLog(@"Error parsing JSON response: %@", jsonError.localizedDescription);
                if (completionHandler) {
                    completionHandler(@{@"message": jsonError.localizedDescription});
                }
            } else {
                NSString *messageContent = jsonResponse[@"choices"][0][@"message"][@"content"];
                NSData *messageData = [messageContent dataUsingEncoding:NSUTF8StringEncoding];
                NSError *messageJsonError;
                NSDictionary *messageJson = [NSJSONSerialization JSONObjectWithData:messageData options:0 error:&messageJsonError];
                
                if (messageJsonError) {
                    // NSLog(@"Error parsing message JSON: %@", messageJsonError.localizedDescription);
                    if (completionHandler) {
                        completionHandler(@{@"message": messageJsonError.localizedDescription});
                    }
                } else {
                    // NSLog(@"Recommended Action: %@", messageJson);
                    if (completionHandler) {
                        completionHandler(messageJson);
                    }
                }
            }
        }
    }];
    [dataTask resume];
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
