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

#import "BBCenteredScrollView.h"



#pragma mark -

@implementation BBCenteredScrollView


#pragma mark Creation

- (instancetype)initWithFrame:(CGRect)frame andContentView:(UIView*)content
{
    self = [super initWithFrame:frame];
    if (self != nil) [self setContent:content];

    return self;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self != nil) [self setContent:[[UIView alloc] initWithFrame:frame]];

    return self;
}


#pragma mark UIView

- (void)setFrame:(CGRect)frame
{
    [super setFrame:frame];
    [self centerContent];
}

- (void)setBounds:(CGRect)bounds
{
    // This magic little line fixes *A LOT* of jerkiness when resizing the frame using animations.
    [UIView setAnimationBeginsFromCurrentState:YES];

    [super setBounds:bounds];
    [self centerContent];
}


#pragma mark UIScrollView

- (void)zoomToRect:(CGRect)rect withDuration:(NSTimeInterval)duration completion:(void (^)(BOOL finished))completion
{
    UIViewAnimationOptions options = UIViewAnimationOptionBeginFromCurrentState;
    [UIView animateWithDuration:duration delay:0 options:options animations:^{
        [super zoomToRect:rect animated:NO];
    } completion:completion];
}

- (void)setZoomScale:(float)scale withDuration:(NSTimeInterval)duration completion:(void (^)(BOOL finished))completion
{
    UIViewAnimationOptions options = UIViewAnimationOptionBeginFromCurrentState;
    [UIView animateWithDuration:duration delay:0 options:options animations:^{
        [super setZoomScale:scale animated:NO];
    } completion:completion];
}


#pragma mark Properties

- (void)setContent:(UIView*)content
{
    _content = content;
    [self addSubview:_content];
    [self setContentSize:_content.bounds.size];

    [self centerContent];
}


#pragma mark Private helpers

- (void)centerContent
{
    CGSize boundsSize = self.bounds.size;
    CGRect frameToCenter = _content.frame;

    if (frameToCenter.size.width < boundsSize.width) {
        frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) / 2.0;
    } else {
        frameToCenter.origin.x = 0;
    }

    if (frameToCenter.size.height < boundsSize.height) {
        frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) / 2.0;
    } else {
        frameToCenter.origin.y = 0;
    }

    _content.frame = frameToCenter;
}

@end
