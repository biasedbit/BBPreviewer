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

//  Created by Bruno de Carvalho (@biasedbit, http://biasedbit.com)
//
//  Copyright (c) 2013 BiasedBit. All rights reserved.
//

#import "BBCenteredScrollView.h"

#import <MediaPlayer/MediaPlayer.h>



#pragma mark - Enums

typedef NS_ENUM(NSUInteger, BBPreviewContentType) {
    BBPreviewContentTypeNone = 0,
    BBPreviewContentTypeImage,
    BBPreviewContentTypeMedia,
    BBPreviewContentTypeDocument,
    BBPreviewContentTypeUrl
};


#pragma mark - Constants

extern NSString* const kBBPreviewControllerErrorDomain;
extern NSInteger const kBBpreviewControllerErrorCodeCannotLoadMovie;
extern NSInteger const kBBpreviewControllerErrorCodeCannotLoadImage;



#pragma mark - Protocols

@class BBPreviewController;

@protocol BBPreviewControllerDelegate <NSObject>

@required
- (void)previewControllerDidFinishLoadingContent:(BBPreviewController*)controller;
- (void)previewController:(BBPreviewController*)controller didFailLoadingContentWithError:(NSError*)error;

@optional
- (void)previewControllerDidStartLoadingWebPage:(BBPreviewController*)controller;
- (void)previewControllerDidFinishLoadingWebPage:(BBPreviewController*)controller;
- (void)previewController:(BBPreviewController*)controller didFailLoadingWebPageWithError:(NSError*)error;

@end



#pragma mark -

@interface BBPreviewController : UIViewController


#pragma mark Properties

@property(weak, nonatomic) id<BBPreviewControllerDelegate> delegate;

@property(assign, nonatomic, readonly) BBPreviewContentType contentType;
@property(strong, nonatomic, readonly) MPMoviePlayerController* moviePlayer;
@property(strong, nonatomic, readonly) BBCenteredScrollView* scrollView;
@property(strong, nonatomic, readonly) UITapGestureRecognizer* imageZoomDoubleTapRecognizer;

/**
 The frame duration for animated GIFs. The total duration will be the number of frames x this value.
 
 Defaults to 0.06.
 */
@property(assign, nonatomic) NSTimeInterval animatedGifFrameDuration;
/**
 The total duration for the animated GIF.
 
 Use this to override the default duration formula, `number_of_frames * <animatedGifFrameDuration>`.
 */
@property(assign, nonatomic) NSTimeInterval animatedGifDuration;


#pragma mark Interface

- (BOOL)canOtherAppOpenFileAtPath:(NSString*)pathToFile;
- (BOOL)presentOpenInMenuForFileAtPath:(NSString*)pathToFile animated:(BOOL)animated;

- (BOOL)hasContent;
- (BOOL)loadWebPageAtUrl:(NSString*)url;
- (BOOL)loadImage:(UIImage*)image;
- (BOOL)loadImageAtPath:(NSString*)pathToImage;
- (BOOL)loadMediaAtPath:(NSString*)path;
- (BOOL)loadDocumentAtPath:(NSString*)path;

/**
 Loads a plain-text document at `path` into memory and displays it using a web view. The reason why this alternative
 to `<loadDocumentAtPath:>` exists is because `UIWebView` doesn't properly handle plain text files with non-ASCII
 characters.
 
 @param path The path where the file resides.
 @param trimThreshold If the plain text file is larger than X bytes, only load up to `trimThreshold` bytes and then
 append an empty line and `trimNotice`.
 @param truncationNotice The text to append at the end of the file if the file is too big to be loaded into memory.
 Pass `nil` if you do not wish to include a notice.
 
 @return `YES` if the file can be loaded, `NO` otherwise.
 */
- (BOOL)loadPlainTextDocumentAtPath:(NSString*)path truncateIfBiggerThanSize:(NSUInteger)truncationThreshold
                   truncationNotice:(NSString*)truncationNotice;

// These two force the adjustment of the image zoom to the a given viewport
- (void)adjustImageToContentViewWithDuration:(NSTimeInterval)duration force:(BOOL)force;
- (void)adjustImageToViewport:(CGSize)viewport duration:(NSTimeInterval)duration force:(BOOL)force;

// Should be overridden by subclasses, otherwise it'll assume self.view
- (UIView*)contentView;
// To be used by subclasses, in case they want to override one of the load* methods.
- (void)contentLoaded:(BBPreviewContentType)type;

@end
