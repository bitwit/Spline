//
//  RGMRecordingViewController.m
//  Spline
//
//  Created by Ryder Mackay on 2013-05-11.
//  Copyright (c) 2013 Ryder Mackay. All rights reserved.
//

#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import "RGMRecordingViewController.h"
#import "RGMSampleWriter.h"

typedef enum{
  kCameraInputBack = 0,
  kCamputInputFront = 1
} CameraInputType;

@interface RGMRecordingViewController () <AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>

@property(nonatomic, strong) AVCaptureSession *session;
@property(nonatomic, strong) AVCaptureAudioDataOutput *audioOutput;
@property(nonatomic, strong) AVCaptureVideoDataOutput *videoOutput;
@property(nonatomic, strong) RGMSampleWriter *sampleWriter;
@property(atomic, assign, getter = isRecording) BOOL recording;
@property(atomic, assign, getter = isReady) BOOL ready;
@property(nonatomic, strong) NSMutableArray *URLs;
@property(nonatomic, strong) AVAssetExportSession *exportSession;
@property(nonatomic, strong) UIProgressView *progressView;

- (IBAction)stop:(id)sender;

/*
* Added by KGN
* */


@property(nonatomic) BOOL isRecordingComplete;
@property(nonatomic, strong) AVCaptureDeviceInput *videoInput;
@property(nonatomic) double currentVideoLength;
@property(nonatomic) double maxVideoLength;
@property(nonatomic, strong) IBOutlet UIProgressView *lengthView;
@property(nonatomic, strong) IBOutlet UIButton *flipCam;
@property(nonatomic, strong) IBOutlet UIView *previewView;
@property(nonatomic, strong) UIView *backCameraView;
@property(nonatomic, strong) UIView *frontCameraView;
@property(nonatomic) CameraInputType currentVideoInputType;

@property(nonatomic) CMTime sampleDuration;

@property(nonatomic, strong) NSMutableArray *oldSampleWriters;


- (IBAction)flipCamera;

@end


@implementation RGMRecordingViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.URLs = [NSMutableArray new];
    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.hidden = YES;
    self.currentVideoLength = 0;
    self.maxVideoLength = 9;

    self.oldSampleWriters = [NSMutableArray array];

    [self.view addSubview:self.progressView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationFade];
    [self.lengthView setProgress:0];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    self.session = [[AVCaptureSession alloc] init];
    self.session.sessionPreset = AVCaptureSessionPreset640x480;

    [self.session beginConfiguration];

    // audio
    NSError *error;
    AVCaptureDevice *audioDevice = [AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio][0];
    AVCaptureDeviceInput *audioIn = [[AVCaptureDeviceInput alloc] initWithDevice:audioDevice error:&error];
    if (!audioIn) {
        NSLog(@"error creating audio input: %@", error);
    }
    if ([self.session canAddInput:audioIn]) {
        [self.session addInput:audioIn];
    }

    self.audioOutput = [[AVCaptureAudioDataOutput alloc] init];
    [self.audioOutput setSampleBufferDelegate:self queue:dispatch_queue_create("com.rydermackay.audioQueue", DISPATCH_QUEUE_SERIAL)];

    if ([self.session canAddOutput:self.audioOutput]) {
        [self.session addOutput:self.audioOutput];
    }

    // video
    AVCaptureDevice *videoDevice = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo][0];
    self.videoInput = [[AVCaptureDeviceInput alloc] initWithDevice:videoDevice error:&error];
    if (!self.videoInput) {
        NSLog(@"error creating video input: %@", error);
    }
    if ([self.session canAddInput:self.videoInput]) {
        [self.session addInput:self.videoInput];
    }
    self.currentVideoInputType = kCameraInputBack;

    self.videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    [self.videoOutput setSampleBufferDelegate:self queue:dispatch_queue_create("com.rydermackay.videoQueue", DISPATCH_QUEUE_SERIAL)];

    if ([self.session canAddOutput:self.videoOutput]) {
        [self.session addOutput:self.videoOutput];
    }

    AVCaptureConnection *connection = self.videoOutput.connections[0];
    [connection setVideoOrientation:AVCaptureVideoOrientationPortrait];

    [self.session commitConfiguration];

    [self.session startRunning];

    AVCaptureVideoPreviewLayer *layer = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
    layer.frame = self.previewView.layer.bounds;
    [self.previewView.layer insertSublayer:layer atIndex:0];
    self.ready = YES;
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];

    [self.session stopRunning];
    self.session = nil;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    self.progressView.bounds = CGRectMake(0, 0, 300, 0);
    [self.progressView sizeToFit];
    self.progressView.center = CGPointMake(self.view.center.x, self.view.center.y + 100);
}

- (IBAction)flipCamera {
    [self.session beginConfiguration];
    [self.session removeInput:self.videoInput];

    NSError *error;
    NSUInteger newInput = 1 - (NSUInteger)self.currentVideoInputType; //works like a boolean switch to flip between cameras
    AVCaptureDevice *videoDevice = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo][newInput];
    self.videoInput = [[AVCaptureDeviceInput alloc] initWithDevice:videoDevice error:&error];
    if (!self.videoInput) {
        NSLog(@"error creating video input: %@", error);
    }

    if ([self.session canAddInput:self.videoInput]) {
        [self.session addInput:self.videoInput];
    }
    self.currentVideoInputType = (CameraInputType)newInput;

    AVCaptureConnection *connection = self.videoOutput.connections[0];
    [connection setVideoOrientation:AVCaptureVideoOrientationPortrait];

    [self.session commitConfiguration];
}

#pragma mark - AVCaptureAudio/VideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (!self.isRecording) {
        return;
    }
    CMTime duration = CMSampleBufferGetDuration(sampleBuffer);
    self.sampleDuration = duration;
    double seconds = CMTimeGetSeconds(duration);
    if (duration.timescale != 0 && duration.value != 0) {
        self.currentVideoLength += seconds;
        [self performSelectorOnMainThread:@selector(updateProgress) withObject:nil waitUntilDone:NO];
    }

    if (!self.sampleWriter) {
        NSString *filename = [[[NSUUID UUID] UUIDString] stringByAppendingPathExtension:@"mp4"];
        NSURL *URL = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@%@", NSTemporaryDirectory(), filename]];
        self.sampleWriter = [[RGMSampleWriter alloc] initWithURL:URL];
    }

    if (captureOutput == self.audioOutput) {
        [self.sampleWriter appendSampleBuffer:sampleBuffer mediaType:AVMediaTypeAudio];
    } else if (captureOutput == self.videoOutput) {
        [self.sampleWriter appendSampleBuffer:sampleBuffer mediaType:AVMediaTypeVideo];
    }

    if (self.currentVideoLength >= self.maxVideoLength) {
        [self stopRecording];
        [self stop:nil];
    }
}

- (void)updateProgress {
    float progress = (float) (self.currentVideoLength / self.maxVideoLength);
    if (progress > 1)
        progress = 1;
    [self.lengthView setProgress:progress];
}

#pragma mark - IBActions

- (IBAction)stop:(id)sender {
    if (!self.isReady) {
        return;
    }

    self.isRecordingComplete = YES;

    [self.session stopRunning];

    if([self.URLs count] == 0){
        [self dismissViewControllerAnimated:YES completion:nil];
    }

    [self composeAssetsFromURLs:self.URLs];
}

- (void)composeAssetsFromURLs:(NSArray *)URLs; {
    AVMutableComposition *composition = [AVMutableComposition composition];
    CMTime insertPoint = kCMTimeZero;

    //AVMutableCompositionTrack *videoTrack = [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    //AVMutableCompositionTrack *audioTrack = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];

    NSUInteger clipCount = [URLs count];
    NSUInteger failureCount = 0;

    for (NSURL *URL in URLs) {

        NSLog(@"Appending track %@ at %f", [URL lastPathComponent], CMTimeGetSeconds(insertPoint));

        AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:URL options:@{AVURLAssetPreferPreciseDurationAndTimingKey : @YES}];

        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSLog(@"Asset exists? -> %d", ([fileManager fileExistsAtPath:[URL path]]));


        CMTime duration;
        if (CMTimeGetSeconds(asset.duration) <= CMTimeGetSeconds(self.sampleDuration)){
            duration = asset.duration;
        } else {
            duration = CMTimeSubtract(asset.duration, self.sampleDuration); //remove last sample
       }

        NSError *error;
        if (![composition insertTimeRange:CMTimeRangeMake(kCMTimeZero, duration) ofAsset:asset atTime:insertPoint error:&error]) {
            NSLog(@"error inserting track: %@", error);
            failureCount++;
        } else {
            insertPoint = CMTimeAdd(insertPoint, duration);
        }
    }

    NSLog(@"Failure count -> %d", failureCount);
    if(failureCount >= clipCount){
        NSLog(@"Failed to combine clips -- count: %d", failureCount);
        UIAlertView *errorAlert = [[UIAlertView alloc] initWithTitle:@"Error processing video" message:@"There was an error processing the video" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [errorAlert show];
    }


    NSString *filename = [[[NSUUID UUID] UUIDString] stringByAppendingPathExtension:@"mp4"];
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSURL *URL = [NSURL fileURLWithPath:[docs stringByAppendingPathComponent:filename]];

    self.exportSession = [AVAssetExportSession exportSessionWithAsset:composition presetName:AVAssetExportPresetMediumQuality];
    self.exportSession.shouldOptimizeForNetworkUse = YES;
    self.exportSession.outputFileType = AVFileTypeMPEG4;
    self.exportSession.outputURL = URL;
    [self.exportSession exportAsynchronouslyWithCompletionHandler:^{
        NSLog(@"Export Session Completion");
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"Dismissing Recording VC");
            [self dismissViewControllerAnimated:YES completion:nil];

            ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
            [library writeVideoAtPathToSavedPhotosAlbum:URL completionBlock:^(NSURL *assetURL, NSError *error) {
                if (error) {
                    NSLog(@"ERROR: the video failed to be written %@", [error description]);
                }
                else {
                    NSLog(@"Video SAVED - assetURL: %@", assetURL);
                }
            }];

            if(self.delegate != nil && [self.delegate respondsToSelector:@selector(recordingViewControllerDidCompleteWithURL:)]){
                [self.delegate recordingViewControllerDidCompleteWithURL:URL];
            }
        });
    }];

    [self showProgressWithSession:self.exportSession];
}

- (void)showProgressWithSession:(AVAssetExportSession *)exportSession {
    switch (exportSession.status) {
        case AVAssetExportSessionStatusWaiting:
        case AVAssetExportSessionStatusExporting:
            NSLog(@"Exporting Session progress -- %f", exportSession.progress);
            self.progressView.hidden = NO;
            [self.progressView setProgress:exportSession.progress animated:YES];
            [self performSelector:@selector(showProgressWithSession:) withObject:exportSession afterDelay:0.1 inModes:@[NSRunLoopCommonModes]];
            break;
        default:
            self.progressView.hidden = YES;
            break;
    }
}

#pragma mark - UIResponder

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {

    if(self.isRecordingComplete && self.ready) return;

    self.recording = YES;
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {

}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    if(self.isRecordingComplete) return;
    [self stopRecording];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    if(self.isRecordingComplete) return;
    [self stopRecording];
}

- (void)stopRecording {

    if(!self.ready || self.sampleWriter == nil) return;

    self.recording = NO;
    self.ready = NO;

    RGMSampleWriter *writerReference = self.sampleWriter;
    [self.oldSampleWriters addObject:writerReference];
    [self.sampleWriter finish:^{
        [self.URLs addObject:writerReference.URL];
        self.ready = YES;
        [self.oldSampleWriters removeObject:writerReference];
    }];
    self.sampleWriter = nil;
}

@end
