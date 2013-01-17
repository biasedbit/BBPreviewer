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

#import "BBCenteredScrollView.h"

#import <MediaPlayer/MediaPlayer.h>



#pragma mark -

@interface MultiContentViewController ()
    <UIWebViewDelegate, UIScrollViewDelegate, UIDocumentInteractionControllerDelegate>
@end



#pragma mark -

@implementation MultiContentViewController
{
    BOOL _hasContent; // do we currently have content?
    BOOL _webViewIsLoading; // is webview currently loading a page request (encapsulates all sub-requests)

    CGSize _imageSize; // the size of the image to display, required to update the zoom factor when orientation changes
    UIScrollView* _scrollView; // ref required to update the zoom factor when orientation changes

    UIWebView* _webView; // ref required to call stopLoading if this controller gets dismissed while loading

    MPMoviePlayerController* _moviePlayer; // ref required to stop playing when dismissing

    BOOL _hijackDocumentViewController; // should we hijack the view from UIViewController presenting the document?
    UIInterfaceOrientation _previousOrientation;
}


#pragma mark UIViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    _hasContent = NO;
    _webViewIsLoading = NO;
    _imageSize = CGSizeZero;

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

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
                                         duration:(NSTimeInterval)duration
{
    if (UIInterfaceOrientationIsPortrait(_previousOrientation) &&
        UIInterfaceOrientationIsPortrait(toInterfaceOrientation)) return;

    if (UIInterfaceOrientationIsLandscape(_previousOrientation) &&
        UIInterfaceOrientationIsLandscape(toInterfaceOrientation)) return;

    [self adjustImageToViewport:YES];
    _previousOrientation = toInterfaceOrientation;
}

- (void)presentViewController:(UIViewController*)viewControllerToPresent animated:(BOOL)animated
                   completion:(void (^)(void))completion
{
    // Since we can't display documents freely on our own view controllers, we hijack the view from the view controller
    // presentPreviewAnimated: is called on the UIDocumentInteractionController and add it as a subview of our content
    // display view.

    // Only hijack once in an attempt to maximize natural behavior on user code
    if (!_hijackDocumentViewController) {
        [super presentViewController:viewControllerToPresent animated:animated completion:completion];
        return;
    }

    [self addChildViewController:viewControllerToPresent];
    [viewControllerToPresent didMoveToParentViewController:self];
    viewControllerToPresent.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    viewControllerToPresent.view.frame = [self contentView].frame;
    [[self contentView] addSubview:viewControllerToPresent.view];

    _hijackDocumentViewController = NO;

    if (completion != nil) completion();
    [self contentLoaded];
}


#pragma mark UIWebViewDelegate

- (void)webViewDidStartLoad:(UIWebView*)webView
{
    if (_webViewIsLoading) return;

    // We do our own webview loading tracking because webviews can potentially shoot a ton of delegate calls per url
    _webViewIsLoading = YES;

    if (_hasContent) [self notifyDelegateOfPageLoadStart];
}

- (void)webViewDidFinishLoad:(UIWebView*)webView
{
    if ([webView isLoading]) return;

    _webViewIsLoading = NO;

    if (_hasContent) {
        [self notifyDelegateOfPageLoadEnd];
    } else {
        [self contentLoaded];
    }
}

- (void)webView:(UIWebView*)webView didFailLoadWithError:(NSError*)error
{
    if ([webView isLoading]) return;

    _webViewIsLoading = NO;

    if (_hasContent) [self notifyDelegateOfPageLoadError:error];
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


#pragma mark Interface

- (BOOL)loadImage:(UIImage*)image
{
    if (_hasContent) return NO;

    UIImageView* imageView = [[UIImageView alloc] initWithImage:image];
    _imageSize = image.size;
    _scrollView = [[CenteredScrollView alloc] initWithFrame:[self contentView].bounds andContentView:imageView];
    [[self contentView] addSubview:_scrollView];

    _scrollView.delegate = self;
    _scrollView.alwaysBounceHorizontal = YES;
    _scrollView.alwaysBounceVertical = YES;
    _scrollView.contentSize = imageView.bounds.size;
    _scrollView.maximumZoomScale = 2;
    _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self adjustImageToViewport:NO];

    UITapGestureRecognizer* doubleTapRecognizer = [[UITapGestureRecognizer alloc]
                                                   initWithTarget:self action:@selector(handleDoubleTap:)];
    doubleTapRecognizer.numberOfTapsRequired = 2;
    [_scrollView addGestureRecognizer:doubleTapRecognizer];

    [self contentLoaded];

    return YES;
}

- (BOOL)loadImageAtPath:(NSString*)pathToImage
{
    if (_hasContent) return NO;

    dispatch_async_default_priority(^{
        UIImage* image = [UIImage imageWithContentsOfFile:pathToImage];
        dispatch_async_main(^{
            if (image == nil) {
                NSError* error = [NSError errorWithDomain:@"com.biasedbit" code:1
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
    if (_hasContent) return NO;

    NSURL* url = [NSURL fileURLWithPath:path];
    _moviePlayer = [[MPMoviePlayerController alloc] initWithContentURL:url];
    _moviePlayer.allowsAirPlay = YES;
    _moviePlayer.shouldAutoplay = NO;
    _moviePlayer.controlStyle = MPMovieControlStyleDefault;
    _moviePlayer.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    [self registerForMoviePlayerNotifications:_moviePlayer];
    [_moviePlayer prepareToPlay];

    [_moviePlayer.view setFrame:[self contentView].bounds];
    [[self contentView] addSubview:_moviePlayer.view];

    return YES;
}

- (BOOL)loadDocumentAtPath:(NSString*)path
{
    if (_hasContent) return NO;

    NSURL* url = [NSURL fileURLWithPath:path];
    UIDocumentInteractionController* controller = [UIDocumentInteractionController interactionControllerWithURL:url];
    controller.delegate = self;

    _hijackDocumentViewController = YES;
    dispatch_async_main(^{
        if (![controller presentPreviewAnimated:NO]) {
            NSError* error = [NSError errorWithDomain:@"com.biasedbit" code:1
                                             userInfo:@{NSLocalizedDescriptionKey: @"Could not load document"}];
            [self notifyDelegateOfContentLoadError:error];
            _hijackDocumentViewController = NO;
        }
    });

    return YES;
}

- (BOOL)loadWebPageAtUrl:(NSString*)url
{
    if (_hasContent) return NO;

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

- (UIView*)contentView
{
    return self.view;
}


#pragma mark Private helpers

- (void)handleDoubleTap:(UITapGestureRecognizer*)recognizer
{
    UIScrollView* scrollView = (UIScrollView*)recognizer.view;
    if (scrollView.zoomScale > scrollView.minimumZoomScale) {
        [scrollView setZoomScale:scrollView.minimumZoomScale animated:YES];
    } else {
        [scrollView setZoomScale:scrollView.maximumZoomScale animated:YES];
    }
}

- (void)adjustImageToViewport:(BOOL)animated
{
    // We should only change zoom if we're fully zoomed out (default); otherwise, the user has already touched and
    // zoomed, so that means we don't adjust zoom scale, just rotate.
    BOOL shouldChangeZoom = _scrollView.zoomScale == _scrollView.minimumZoomScale;

    CGSize viewport = [self contentView].bounds.size;
    BOOL imageIsBiggerThanViewport = (_imageSize.width > viewport.width) || (_imageSize.height > viewport.height);
    if (imageIsBiggerThanViewport) {
        CGFloat widthRatio = viewport.width / _imageSize.width;
        CGFloat heightRatio = viewport.height / _imageSize.height;
        CGFloat adjustedRatio = MIN(widthRatio, heightRatio);

        _scrollView.minimumZoomScale = adjustedRatio;
    } else {
        _scrollView.minimumZoomScale = 1;
        // When the image is smaller than the viewport we never change zoom
        shouldChangeZoom = NO;
    }

    if (shouldChangeZoom) {
        CGRect rect = CGRectMake(0, 0, _imageSize.width, _imageSize.height);
        [_scrollView zoomToRect:rect animated:animated];
    }
}

- (void)contentLoaded
{
    _hasContent = YES;
    [self notifyDelegateOfSuccessfulContentLoad];
}


#pragma mark Private helpers - notifications

- (void)registerForMoviePlayerNotifications:(MPMoviePlayerController*)moviePlayer
{
    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(handleMoviePlayerLoadStateChangeNotification:)
     name:MPMoviePlayerLoadStateDidChangeNotification object:moviePlayer];

    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(handleMoviePlayerPlaybackFinishedNotification:)
     name:MPMoviePlayerPlaybackDidFinishNotification object:moviePlayer];
}

- (void)unregisterFromMoviePlayerNotifications:(MPMoviePlayerController*)moviePlayer
{
    [[NSNotificationCenter defaultCenter]
     removeObserver:self name:MPMoviePlayerLoadStateDidChangeNotification object:moviePlayer];
}

- (void)handleMoviePlayerLoadStateChangeNotification:(NSNotification*)notification
{
    MPMoviePlayerController* moviePlayer = [notification object];
    [self unregisterFromMoviePlayerNotifications:moviePlayer];

    [self contentLoaded];
}

- (void)handleMoviePlayerPlaybackFinishedNotification:(NSNotification*)notification
{
    MPMoviePlayerController* moviePlayer = [notification object];
    [self unregisterFromMoviePlayerNotifications:moviePlayer];

    NSInteger reason = [[notification userInfo] integerForKey:MPMoviePlayerPlaybackDidFinishReasonUserInfoKey];
    if (reason == MPMovieFinishReasonPlaybackError) {
        NSError* error = [NSError errorWithDomain:@"com.biasedbit" code:1
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
