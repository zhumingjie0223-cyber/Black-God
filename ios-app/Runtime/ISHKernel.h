#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
extern NSNotificationName const ISHProcessExitedNotification;
@interface ISHKernel : NSObject
@property (class, readonly) ISHKernel *shared;
@property (nonatomic, readonly) BOOL isBooted;
@property (nonatomic, copy, nullable) NSString *nextRoot;
- (int)confineCurrentTask;
- (void)terminateGuestProcesses;
- (int)reapAndCountGuestProcesses;
- (int)bootWithRootPath:(NSString *)rootPath;
@end
NS_ASSUME_NONNULL_END
