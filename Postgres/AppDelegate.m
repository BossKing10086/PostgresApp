// AppDelegate.m
//
// Created by Mattt Thompson (http://mattt.me/)
// Copyright (c) 2012 Heroku (http://heroku.com/)
// 
// Portions Copyright (c) 1996-2012, The PostgreSQL Global Development Group
// Portions Copyright (c) 1994, The Regents of the University of California
//
// Permission to use, copy, modify, and distribute this software and its
// documentation for any purpose, without fee, and without a written agreement
// is hereby granted, provided that the above copyright notice and this
// paragraph and the following two paragraphs appear in all copies.
//
// IN NO EVENT SHALL THE UNIVERSITY OF CALIFORNIA BE LIABLE TO ANY PARTY FOR
// DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES, INCLUDING
// LOST PROFITS, ARISING OUT OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION,
// EVEN IF THE UNIVERSITY OF CALIFORNIA HAS BEEN ADVISED OF THE POSSIBILITY OF
// SUCH DAMAGE.
//
// THE UNIVERSITY OF CALIFORNIA SPECIFICALLY DISCLAIMS ANY WARRANTIES,
// INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
// FITNESS FOR A PARTICULAR PURPOSE. THE SOFTWARE PROVIDED HEREUNDER IS ON AN
// "AS IS" BASIS, AND THE UNIVERSITY OF CALIFORNIA HAS NO OBLIGATIONS TO
// PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS.

#import <ServiceManagement/ServiceManagement.h>
#import "AppDelegate.h"
#import "PostgresServer.h"
#import "PostgresStatusMenuItemViewController.h"

#ifdef SPARKLE
#import <Sparkle/Sparkle.h>
#import "PFMoveApplication.h"
#endif

static NSString * const kPostgresAppWebsiteURLString = @"http://postgresapp.com/documentation";
static NSUInteger const kPostgresAppDefaultPort = 5432;

static NSString * const kPostgresAutomaticallyOpenDocumentationPreferenceKey = @"com.heroku.postgres.preference.open-documentation-at-start";

static BOOL PostgresIsHelperApplicationSetAsLoginItem() {
    BOOL flag = NO;
    NSArray *jobs = (__bridge NSArray *)SMCopyAllJobDictionaries(kSMDomainUserLaunchd);
    for (NSDictionary *job in jobs) {
        if ([[job valueForKey:@"Label"] isEqualToString:@"com.heroku.PostgresHelper"]) {
            flag = YES;
        }
    }
    
    CFRelease((__bridge CFMutableArrayRef)jobs);
    
    return flag;
}


@implementation AppDelegate {
    __strong NSStatusItem *_statusBarItem;
}
@synthesize postgresStatusMenuItemViewController = _postgresStatusMenuItemViewController;
@synthesize statusBarMenu = _statusBarMenu;
@synthesize postgresStatusMenuItem = _postgresStatusMenuItem;
@synthesize automaticallyOpenDocumentationMenuItem = _automaticallyOpenDocumentationMenuItem;
@synthesize automaticallyStartMenuItem = _automaticallyStartMenuItem;
@synthesize checkForUpdatesMenuItem = _checkForUpdatesMenuItem;

- (void)awakeFromNib {
    _statusBarItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    _statusBarItem.highlightMode = YES;
    _statusBarItem.menu = self.statusBarMenu;
    _statusBarItem.image = [NSImage imageNamed:@"pg-elephant-status-item"];
    _statusBarItem.alternateImage = [NSImage imageNamed:@"pg-elephant-status-item-highlight"];
    
    [self.postgresStatusMenuItem setEnabled:NO];    
    self.postgresStatusMenuItem.view = self.postgresStatusMenuItemViewController.view;
    [self.postgresStatusMenuItemViewController startAnimatingWithTitle:NSLocalizedString(@"Postgres: Starting Up", nil)];
}

#pragma mark - NSApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
#ifdef SPARKLE
    PFMoveToApplicationsFolderIfNecessary();
    [self.checkForUpdatesMenuItem setEnabled:YES];
    [self.checkForUpdatesMenuItem setHidden:NO];
#endif
    
    [[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:kPostgresAutomaticallyOpenDocumentationPreferenceKey]];
    [self.automaticallyOpenDocumentationMenuItem setState:[[NSUserDefaults standardUserDefaults] boolForKey:kPostgresAutomaticallyOpenDocumentationPreferenceKey]];
    [self.automaticallyStartMenuItem setState:PostgresIsHelperApplicationSetAsLoginItem() ? NSOnState : NSOffState];
    
    [[PostgresServer sharedServer] startOnPort:kPostgresAppDefaultPort terminationHandler:^(NSUInteger status) {
        if (status == 0) {
            [self.postgresStatusMenuItemViewController stopAnimatingWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Postgres: Running on Port %u", nil), kPostgresAppDefaultPort] wasSuccessful:YES];
        } else {
            [self.postgresStatusMenuItemViewController stopAnimatingWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Postgres: Could not start on Port %u", nil), kPostgresAppDefaultPort] wasSuccessful:NO];
        }
    }];

    [NSApp activateIgnoringOtherApps:YES];
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kPostgresAutomaticallyOpenDocumentationPreferenceKey]) {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:kPostgresAppWebsiteURLString]];
    }
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {    
    [[PostgresServer sharedServer] stopWithTerminationHandler:^(NSUInteger status) {
        [sender replyToApplicationShouldTerminate:YES];
    }];
    
    // Set a timeout interval for postgres shutdown
    static NSTimeInterval const kTerminationTimeoutInterval = 3.0;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kTerminationTimeoutInterval * NSEC_PER_SEC), dispatch_get_main_queue(), ^(void){
        [sender replyToApplicationShouldTerminate:YES];
    });
    
    return NSTerminateLater;
}

#pragma mark - IBAction

- (IBAction)selectAbout:(id)sender {
    // Bring application to foreground to have about window display on top of other windows
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp orderFrontStandardAboutPanel:nil];
}

- (IBAction)selectDocumentation:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:kPostgresAppWebsiteURLString]];
}

- (IBAction)selectAutomaticallyOpenDocumentation:(id)sender {
    [self.automaticallyOpenDocumentationMenuItem setState:![self.automaticallyOpenDocumentationMenuItem state]];

    [[NSUserDefaults standardUserDefaults] setBool:self.automaticallyOpenDocumentationMenuItem.state == NSOnState forKey:kPostgresAutomaticallyOpenDocumentationPreferenceKey];
}

- (IBAction)selectAutomaticallyStart:(id)sender {
    [self.automaticallyStartMenuItem setState:![self.automaticallyStartMenuItem state]];
    
    NSURL *helperApplicationURL = [[[NSBundle mainBundle] bundleURL] URLByAppendingPathComponent:@"Contents/Library/LoginItems/PostgresHelper.app"];
    if (LSRegisterURL((__bridge CFURLRef)helperApplicationURL, true) != noErr) {
        NSLog(@"LSRegisterURL Failed");
    }
    
    if (!SMLoginItemSetEnabled((__bridge CFStringRef)@"com.heroku.PostgresHelper", [self.automaticallyStartMenuItem state] == NSOnState)) {
        NSLog(@"SMLoginItemSetEnabled Failed");
    }
}

- (IBAction)checkForUpdates:(id)sender {
#ifdef SPARKLE
    [[SUUpdater sharedUpdater] setSendsSystemProfile:YES];
    [[SUUpdater sharedUpdater] checkForUpdates:sender];
#endif
}


@end
