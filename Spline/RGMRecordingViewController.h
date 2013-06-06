//
//  RGMRecordingViewController.h
//  Spline
//
//  Created by Ryder Mackay on 2013-05-11.
//  Copyright (c) 2013 Ryder Mackay. All rights reserved.
//

#import <UIKit/UIKit.h>

@protocol RGMRecordingViewControllerDelegate <NSObject>
-(void)recordingViewControllerDidCompleteWithURL:(NSURL *)fileUrl;
@end

@interface RGMRecordingViewController : UIViewController

@property (nonatomic, weak) id<RGMRecordingViewControllerDelegate>delegate;

@end
