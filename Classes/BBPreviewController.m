//
// Copyright 2013 BiasedBit
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//
//  Created by Bruno de Carvalho (@biasedbit, http://biasedbit.com)
//  Copyright (c) 2013 BiasedBit. All rights reserved.
//

#import "BBPreviewController.h"



#pragma mark - Constants

NSString* const kBBPreviewControllerErrorDomain = @"com.biasedbit.BBPreviewController";
NSInteger const kBBpreviewControllerErrorCodeCannotLoadMovie = 1000;
NSInteger const kBBpreviewControllerErrorCodeCannotLoadImage = 1001;

CGFloat const kBBPreviewControllerDefaultMaxZoomScale = 1.5;



#pragma mark - Macros


#define BBPreviewControllerFPEquals(a, b) fabs(a - b) <= 0.0001



#pragma mark -

@interface BBPreviewController () <UIWebViewDelegate, UIScrollViewDelegate, UIDocumentInteractionControllerDelegate>
@end



#pragma mark -

@implementation BBPreviewController
{
    BOOL _webViewIsLoading; // is webview currently loading a page request (encapsulates all sub-requests)

    CGSize _imageSize; // the size of the image to display, required to update the zoom factor when orientation changes
    UIWebView* _webView; // ref required to call stopLoading if this controller gets dismissed while loading

    UIDocumentInteractionController* _openInThrowawayController;
    UIInterfaceOrientation _previousOrientation;

    CGFloat _lastMinimumZoomScale;
    CGSize _lastViewport;
}


#pragma mark UIViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    _contentType = BBPreviewContentTypeNone;
    _webViewIsLoading = NO;
    _imageSize = CGSizeZero;
    _animatedGifFrameDuration = 0.06;

    _previousOrientation = self.interfaceOrientation;
}

- (void)viewDidDisappear:(BOOL)animated
{
    if ([self isBeingDismissed] || [self isMovingFromParentViewController]) {
        if (_moviePlayer != nil) {
            [_moviePlayer stop];
        } else if ((_webView != nil) && _webViewIsLoading) {
            [_webView stopLoading];
        }
    }

    [super viewDidDisappear:animated];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return interfaceOrientation != UIInterfaceOrientationMaskPortraitUpsideDown;
}

- (BOOL)shouldAutorotate
{
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)orientation duration:(NSTimeInterval)duration
{
    [super willAnimateRotationToInterfaceOrientation:orientation duration:duration];

    if (UIInterfaceOrientationIsPortrait(_previousOrientation) &&
        UIInterfaceOrientationIsPortrait(orientation)) return;

    if (UIInterfaceOrientationIsLandscape(_previousOrientation) &&
        UIInterfaceOrientationIsLandscape(orientation)) return;

    [self adjustImageToContentViewWithDuration:duration force:NO];
    _previousOrientation = orientation;
}


#pragma mark UIWebViewDelegate

- (void)webViewDidStartLoad:(UIWebView*)webView
{
    if (_webViewIsLoading) return;

    // We do our own webview loading tracking because webviews can potentially shoot a ton of delegate calls per url
    _webViewIsLoading = YES;

    if ([self hasContent]) [self notifyDelegateOfPageLoadStart];
}

- (void)webViewDidFinishLoad:(UIWebView*)webView
{
    if ([webView isLoading]) return;

    _webViewIsLoading = NO;

    if ([self hasContent]) {
        [self notifyDelegateOfPageLoadEnd];
    } else {
        if ([webView.request.URL isFileURL]) [self contentLoaded:BBPreviewContentTypeDocument];
        else [self contentLoaded:BBPreviewContentTypeUrl];
    }
}

- (void)webView:(UIWebView*)webView didFailLoadWithError:(NSError*)error
{
    if ([webView isLoading]) return;

    _webViewIsLoading = NO;

    if ([self hasContent]) [self notifyDelegateOfPageLoadError:error];
    else [self notifyDelegateOfContentLoadError:error];
}


#pragma mark UIScrollViewDelegate

- (UIView*)viewForZoomingInScrollView:(UIScrollView*)scrollView
{
    return [[scrollView subviews] objectAtIndex:0]; // The UIImageView
}


#pragma mark UIDocumentInteractionControllerDelegate

- (UIViewController*)documentInteractionControllerViewControllerForPreview:(UIDocumentInteractionController*)controller
{
    return self;
}

- (void)documentInteractionControllerDidDismissOpenInMenu:(UIDocumentInteractionController*)controller
{
    _openInThrowawayController = nil;
}


#pragma mark Interface

- (BOOL)canOtherAppOpenFileAtPath:(NSString*)pathToFile
{
    NSURL* url = [NSURL fileURLWithPath:pathToFile];
    UIDocumentInteractionController* controller = [UIDocumentInteractionController interactionControllerWithURL:url];
    return [controller presentOpenInMenuFromRect:CGRectZero inView:nil animated:NO];
}

- (BOOL)presentOpenInMenuForFileAtPath:(NSString*)pathToFile animated:(BOOL)animated
{
    NSURL* url = [NSURL fileURLWithPath:pathToFile];
    _openInThrowawayController = [UIDocumentInteractionController interactionControllerWithURL:url];
    _openInThrowawayController.delegate = self;

    return [_openInThrowawayController presentOpenInMenuFromRect:CGRectZero inView:self.view animated:YES];
}

- (BOOL)hasContent
{
    return _contentType > BBPreviewContentTypeNone;
}

- (BOOL)loadWebPageAtUrl:(NSString*)url
{
    if ([self hasContent]) return NO;

    UIWebView* webView = [[UIWebView alloc] initWithFrame:[self contentView].bounds];
    webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    webView.backgroundColor = [UIColor clearColor];
    webView.scalesPageToFit = YES;
    webView.delegate = self;
    [[self contentView] addSubview:webView];

    NSURL* urlForRequest = [NSURL URLWithString:url];
    NSURLRequest* request = [NSURLRequest requestWithURL:urlForRequest];
    [webView loadRequest:request];

    return YES;
}

- (BOOL)loadImage:(UIImage*)image
{
    if ([self hasContent]) return NO;

    UIImageView* imageView = [[UIImageView alloc] initWithImage:image];
    _imageSize = image.size;
    _scrollView = [[BBCenteredScrollView alloc] initWithFrame:[self contentView].bounds andContentView:imageView];
    [[self contentView] addSubview:_scrollView];

    _scrollView.delegate = self;
    _scrollView.alwaysBounceHorizontal = YES;
    _scrollView.alwaysBounceVertical = YES;
    _scrollView.contentSize = imageView.bounds.size;
    _scrollView.maximumZoomScale = kBBPreviewControllerDefaultMaxZoomScale;
    _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self adjustImageToContentViewWithDuration:0 force:YES];

    _imageZoomDoubleTapRecognizer = [[UITapGestureRecognizer alloc]
                                     initWithTarget:self action:@selector(handleImageZoomDoubleTap:)];
    _imageZoomDoubleTapRecognizer.numberOfTouchesRequired = 1;
    _imageZoomDoubleTapRecognizer.numberOfTapsRequired = 2;
    [_scrollView addGestureRecognizer:_imageZoomDoubleTapRecognizer];

    [self contentLoaded:BBPreviewContentTypeImage];

    return YES;
}

- (BOOL)loadImageAtPath:(NSString*)pathToImage
{
    if ([self hasContent]) return NO;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        UIImage* image = [self readImageAtPath:pathToImage];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (image == nil) {
                NSError* error = [NSError errorWithDomain:kBBPreviewControllerErrorDomain
                                                     code:kBBpreviewControllerErrorCodeCannotLoadImage
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Could not load image"}];
                [self notifyDelegateOfContentLoadError:error];
            } else {
                [self loadImage:image];
            }
        });
    });

    return YES;
}

- (BOOL)loadMediaAtPath:(NSString*)path
{
    if ([self hasContent]) return NO;

    NSURL* url = [NSURL fileURLWithPath:path];
    _moviePlayer = [[MPMoviePlayerController alloc] initWithContentURL:url];
    _moviePlayer.allowsAirPlay = YES;
    _moviePlayer.shouldAutoplay = NO;
    _moviePlayer.controlStyle = MPMovieControlStyleDefault;
    _moviePlayer.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    [self registerMoviePlayerNotificationHandlers:_moviePlayer];
    [_moviePlayer prepareToPlay];

    [_moviePlayer.view setFrame:[self contentView].bounds];
    [[self contentView] addSubview:_moviePlayer.view];

    return YES;
}

- (BOOL)loadDocumentAtPath:(NSString*)path
{
    if ([self hasContent]) return NO;

    UIWebView* webView = [[UIWebView alloc] initWithFrame:[self contentView].bounds];
    webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    webView.backgroundColor = [UIColor clearColor];
    webView.scalesPageToFit = YES;
    webView.delegate = self;
    [[self contentView] addSubview:webView];

    NSURL* urlForRequest = [NSURL fileURLWithPath:path];
    NSURLRequest* request = [NSURLRequest requestWithURL:urlForRequest];
    [webView loadRequest:request];

    return YES;
}

- (BOOL)loadPlainTextDocumentAtPath:(NSString*)path truncateIfBiggerThanSize:(NSUInteger)truncationThreshold
                   truncationNotice:(NSString*)truncationNotice
{
    if ([self hasContent]) return NO;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError* error = nil;
        NSData* data = [self readUpToBytes:truncationThreshold fromFileAtPath:path
                          truncateWithText:truncationNotice error:&error];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (error != nil) {
                [self notifyDelegateOfContentLoadError:error];
            } else {
                UIWebView* webView = [[UIWebView alloc] initWithFrame:[self contentView].bounds];
                webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                webView.backgroundColor = [UIColor clearColor];
                webView.scalesPageToFit = YES;
                webView.delegate = self;
                [[self contentView] addSubview:webView];

                [webView loadData:data MIMEType:@"text/plain"
                 textEncodingName:@"utf-8" baseURL:[NSURL URLWithString:@"/"]];
            }
        });
    });

    return YES;
}

- (void)unloadContent
{
    if (![self hasContent]) return;

    switch (_contentType) {
        case BBPreviewContentTypeMedia:
            [_moviePlayer stop];
            [self unregisterMoviePlayerNotificationHandlers:_moviePlayer];
            break;

        case BBPreviewContentTypeImage:
            _imageZoomDoubleTapRecognizer = nil;
            break;

        default:
            break;
    }

    _contentType = BBPreviewContentTypeNone;
    for (UIView* contentSubview in [self contentView].subviews) {
        [contentSubview removeFromSuperview];
    }
}

- (void)adjustImageToContentViewWithDuration:(NSTimeInterval)duration force:(BOOL)force
{
    if (_scrollView == nil) return;

    CGSize viewport = [self contentView].bounds.size;
    [self adjustImageToViewport:viewport duration:duration force:force];
}

- (void)adjustImageToViewport:(CGSize)viewport duration:(NSTimeInterval)duration force:(BOOL)force
{
    if (_scrollView == nil) return;

    CGFloat nextScale;
    BOOL imageIsBiggerThanViewport = (_imageSize.width > viewport.width) || (_imageSize.height > viewport.height);
    if (imageIsBiggerThanViewport) {
        CGFloat widthRatio = viewport.width / _imageSize.width;
        CGFloat heightRatio = viewport.height / _imageSize.height;
        nextScale = MIN(widthRatio, heightRatio);
    } else {
        nextScale = 1;
    }

    BOOL viewportHasGrown = (_lastViewport.width < viewport.width) || (_lastViewport.height < viewport.height);
    BOOL isAtMinimumZoomScale = BBPreviewControllerFPEquals(_scrollView.zoomScale, _scrollView.minimumZoomScale);
    BOOL willChangeScale = !BBPreviewControllerFPEquals(nextScale, _lastMinimumZoomScale);

    BOOL canChangeZoomScale;
    if (viewportHasGrown) {
        BOOL willBecomeUnderMinimumZoomScale = _scrollView.zoomScale < nextScale;
        canChangeZoomScale = isAtMinimumZoomScale || willBecomeUnderMinimumZoomScale;
    } else {
        canChangeZoomScale = isAtMinimumZoomScale;
    }

    canChangeZoomScale &= willChangeScale;
    canChangeZoomScale |= force;

    _scrollView.minimumZoomScale = nextScale;
    _lastMinimumZoomScale = nextScale;
    _lastViewport = viewport;

    if (canChangeZoomScale) [_scrollView setZoomScale:nextScale withDuration:duration completion:nil];
}

- (UIView*)contentView
{
    return self.view;
}

- (void)contentLoaded:(BBPreviewContentType)type
{
    _contentType = type;
    [self notifyDelegateOfSuccessfulContentLoad];
}


#pragma mark Private helpers

- (BOOL)imageIsSmallerThanCurrentViewport
{
    return (_lastViewport.width > _imageSize.width) && (_lastViewport.height > _imageSize.height);
}

- (void)handleImageZoomDoubleTap:(UITapGestureRecognizer*)recognizer
{
    BBCenteredScrollView* scrollView = (BBCenteredScrollView*)recognizer.view;
    // Already zoomed, fallback to minimum zoom scale
    if (scrollView.zoomScale > scrollView.minimumZoomScale) {
        [scrollView setZoomScale:scrollView.minimumZoomScale animated:YES];
    } else if ([self imageIsSmallerThanCurrentViewport]) {
        [scrollView setZoomScale:scrollView.maximumZoomScale animated:YES];
    } else {
        CGPoint location = [recognizer locationInView:scrollView.content];
        [scrollView zoomToRect:CGRectMake(location.x, location.y, 0, 0) animated:YES];
    }
}

- (UIImage*)readImageAtPath:(NSString*)path
{
#ifdef __IMAGEIO__
    if ([[path pathExtension] isEqualToString:@"gif"]) {
        // All credit for this goes to Rob Mayoff - https://github.com/mayoff/uiimage-from-animated-gif
        NSData* data = [NSData dataWithContentsOfFile:path];
        CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
        size_t count = CGImageSourceGetCount(source);
        NSMutableArray* images = [NSMutableArray arrayWithCapacity:count];

        for (size_t i = 0; i < count; i++) {
            CGImageRef image = CGImageSourceCreateImageAtIndex(source, i, NULL);
            if (image == NULL) continue;

            [images addObject:[UIImage imageWithCGImage:image]];
            CGImageRelease(image);
        }
        CFRelease(source);

        if ([images count] == 0) return nil;

        NSTimeInterval duration;
        if (_animatedGifDuration == 0) {
            duration = [images count] * _animatedGifFrameDuration;
        } else {
            duration = _animatedGifDuration;
        }

        return [UIImage animatedImageWithImages:images duration:duration];
    }
#else
    #warning ImageIO not found, animated GIFs won't be supported.
    // Be sure to "#import <ImageIO/ImageIO.h>" on your precompiled prefix header and link against ImageIO.framework.
#endif

    return [UIImage imageWithContentsOfFile:path];
}

- (NSData*)readUpToBytes:(NSUInteger)length fromFileAtPath:(NSString*)path
        truncateWithText:(NSString*)text error:(NSError**)error
{
    // All credit for this idea goes to Adam Wulf
    id attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:error];
    if (attributes == nil) return nil;

    unsigned long long fileSize = [attributes fileSize];
    if (fileSize == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:kBBPreviewControllerErrorDomain code:NSFileReadCorruptFileError
                                     userInfo:@{NSLocalizedDescriptionKey: @"File is empty."}];
        }
        return nil;
    }

    // Peachy, file is under the limit; read it all and return.
    if (fileSize <= length) return [NSData dataWithContentsOfFile:path options:0 error:error];

    // File size exceeds max amount; read up to X bytes and truncate with message.
    NSData* truncatedData = [self readBytes:length fromFileAtPath:path error:error];
    if ((text == nil) || (truncatedData == nil)) return truncatedData;

    // Successfully read `length` bytes, now append the truncation message.
    NSMutableData* truncatedDataWithMessage = [NSMutableData dataWithData:truncatedData];
    NSData* messageData = [[@"\n\n" stringByAppendingString:text] dataUsingEncoding:NSUTF8StringEncoding];
    [truncatedDataWithMessage appendData:messageData];

    return truncatedDataWithMessage;
}

- (NSData*)readBytes:(NSUInteger)length fromFileAtPath:(NSString*)path error:(NSError**)error
{
    NSFileHandle* fileHandle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (fileHandle == nil) {
        // Should never happen since this method is only called after the file existence and size have been assessed.
        if (error != NULL) {
            *error = [NSError errorWithDomain:kBBPreviewControllerErrorDomain code:NSFileNoSuchFileError
                                     userInfo:@{NSLocalizedDescriptionKey: @"No such file."}];
        }
        return nil;
    }

    NSData* truncatedData = nil;
    @try {
        truncatedData = [fileHandle readDataOfLength:length];
    } @catch (NSException* exception) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:kBBPreviewControllerErrorDomain code:NSFileReadUnknownError
                                     userInfo:[exception userInfo]];
        }
    } @finally {
        [fileHandle closeFile];
    }

    return truncatedData;
}


#pragma mark Private helpers - notifications

- (void)registerMoviePlayerNotificationHandlers:(MPMoviePlayerController*)moviePlayer
{
    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(handleMoviePlayerLoadStateChangeNotification:)
     name:MPMoviePlayerLoadStateDidChangeNotification object:moviePlayer];

    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(handleMoviePlayerPlaybackFinishedNotification:)
     name:MPMoviePlayerPlaybackDidFinishNotification object:moviePlayer];
}

- (void)unregisterMoviePlayerNotificationHandlers:(MPMoviePlayerController*)moviePlayer
{
    [[NSNotificationCenter defaultCenter]
     removeObserver:self name:MPMoviePlayerLoadStateDidChangeNotification object:moviePlayer];
}

- (void)handleMoviePlayerLoadStateChangeNotification:(NSNotification*)notification
{
    MPMoviePlayerController* moviePlayer = [notification object];
    [self unregisterMoviePlayerNotificationHandlers:moviePlayer];

    [self contentLoaded:BBPreviewContentTypeMedia];
}

- (void)handleMoviePlayerPlaybackFinishedNotification:(NSNotification*)notification
{
    MPMoviePlayerController* moviePlayer = [notification object];
    [self unregisterMoviePlayerNotificationHandlers:moviePlayer];

    NSInteger reason = [[notification userInfo] integerForKey:MPMoviePlayerPlaybackDidFinishReasonUserInfoKey];
    if (reason == MPMovieFinishReasonPlaybackError) {
        NSError* error = [NSError errorWithDomain:@"com.biasedbit" code:kBBpreviewControllerErrorCodeCannotLoadMovie
                                         userInfo:@{NSLocalizedDescriptionKey: @"Could not load movie"}];
        [self notifyDelegateOfContentLoadError:error];
    }
}


#pragma mark Private helpers - delegate notifications

- (void)notifyDelegateOfSuccessfulContentLoad
{
    if ((_delegate != nil) &&
        [_delegate respondsToSelector:@selector(previewControllerDidFinishLoadingContent:)]) {
        [_delegate previewControllerDidFinishLoadingContent:self];
    }
}

- (void)notifyDelegateOfContentLoadError:(NSError*)error
{
    if ((_delegate != nil) &&
        [_delegate respondsToSelector:@selector(previewController:didFailLoadingContentWithError:)]) {
        [_delegate previewController:self didFailLoadingContentWithError:error];
    }
}

- (void)notifyDelegateOfPageLoadStart
{
    if (_delegate == nil) return;
    if (![_delegate respondsToSelector:@selector(previewControllerDidStartLoadingWebPage:)]) return;

    [_delegate previewControllerDidStartLoadingWebPage:self];
}

- (void)notifyDelegateOfPageLoadEnd
{
    if (_delegate == nil) return;
    if (![_delegate respondsToSelector:@selector(previewControllerDidFinishLoadingWebPage:)]) return;

    [_delegate previewControllerDidFinishLoadingWebPage:self];
}

- (void)notifyDelegateOfPageLoadError:(NSError*)error
{
    if (_delegate == nil) return;
    if (![_delegate respondsToSelector:@selector(previewController:didFailLoadingWebPageWithError:)]) return;

    [_delegate previewController:self didFailLoadingWebPageWithError:error];
}

@end
