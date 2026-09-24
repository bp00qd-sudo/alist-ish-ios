#import "SceneDelegate.h"
#import "AlistISH-Swift.h"

TerminalViewController *currentTerminalViewController = NULL;

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    if (![scene isKindOfClass:UIWindowScene.class])
        return;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [AlistHostFactory makeRootViewController];
    [self.window makeKeyAndVisible];
}

@end
