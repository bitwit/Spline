//
//  RGMRecordingViewController.m
//  Spline
//
//  Created by Ryder Mackay on 2013-05-11.
//  Copyright (c) 2013 Ryder Mackay. All rights reserved.
//

#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>
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
        NSLog(@" sample duration %f", seconds);
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
        self.recording = NO;
        [self stop:nil];
    }
}

- (void)updateProgress {
    float progress = (float) (self.currentVideoLength / self.maxVideoLength);
    if (progress > 1)
        progress = 1;
    NSLog(@"Setting progress %f", progress);
    [self.lengthView setProgress:progress];
}

#pragma mark - IBActions

- (IBAction)stop:(id)sender {
    if (!self.isReady) {
        return;
    }

    [self.session stopRunning];
    [self composeAssetsFromURLs:self.URLs];
}

- (void)composeAssetsFromURLs:(NSArray *)URLs; {
    AVMutableComposition *composition = [AVMutableComposition composition];
    CMTime insertPoint = kCMTimeZero;

    AVMutableCompositionTrack *videoTrack = [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    AVMutableCompositionTrack *audioTrack = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];

    for (NSURL *URL in URLs) {
        AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:URL options:@{AVURLAssetPreferPreciseDurationAndTimingKey : @YES}];

        CMTime duration;
        if (CMTimeGetSeconds(asset.duration) <= CMTimeGetSeconds(self.sampleDuration)){
            duration = asset.duration;

        } else {
            duration = CMTimeSubtract(asset.duration, self.sampleDuration); //remove last sample
        }

        AVAssetTrack *assetVideoTrack;
        AVAssetTrack *assetAudioTrack;
        @try{
            assetVideoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0];
            assetAudioTrack = [[asset tracksWithMediaType:AVMediaTypeAudio] objectAtIndex:0];
        }
        @catch(NSException *e){
            NSLog(@"Error getting asset tracks");
            continue;
        }

        NSError *error;
        if (![videoTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, duration) ofTrack:assetVideoTrack atTime:insertPoint error:&error]) {
            NSLog(@"error inserting track: %@", error);
        }

        if (![audioTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, duration) ofTrack:assetAudioTrack atTime:insertPoint error:&error]) {
            NSLog(@"error inserting track: %@", error);
        } else {
            insertPoint = CMTimeAdd(insertPoint, duration);
        }
    }

    NSString *filename = [[[NSUUID UUID] UUIDString] stringByAppendingPathExtension:@"mp4"];
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSURL *URL = [NSURL fileURLWithPath:[docs stringByAppendingPathComponent:filename]];

    self.exportSession = [AVAssetExportSession exportSessionWithAsset:composition presetName:AVAssetExportPresetHighestQuality];
    self.exportSession.outputFileType = AVFileTypeMPEG4;
    self.exportSession.outputURL = URL;
    [self.exportSession exportAsynchronouslyWithCompletionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [self dismissViewControllerAnimated:YES completion:nil];
        });
    }];

    [self showProgressWithSession:self.exportSession];
}

- (void)showProgressWithSession:(AVAssetExportSession *)exportSession {
    switch (exportSession.status) {
        case AVAssetExportSessionStatusWaiting:
        case AVAssetExportSessionStatusExporting:
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
    self.recording = YES;
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {

}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [self stopRecording];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [self stopRecording];
}

- (void)stopRecording {
    self.recording = NO;
    self.ready = NO;

    RGMSampleWriter *writerReference = self.sampleWriter;
    [self.sampleWriter finish:^{
        [self.URLs addObject:writerReference.URL];
        self.ready = YES;
        [self.oldSampleWriters removeObject:writerReference];
    }];

    [self.oldSampleWriters addObject:writerReference];
    self.sampleWriter = nil;
}

@end
