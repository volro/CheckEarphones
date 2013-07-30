//
//  CEViewController.h
//  CheckEarphones
//
//  Created by Bohdan Orlov on 4/22/13.
//  Copyright (c) 2013 WiseEngineering. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "CPTBarPlot.h"

@class MPMusicPlayerController;

@interface CEViewController : UIViewController <CPTBarPlotDataSource, CPTPlotDelegate>

@property(nonatomic, strong) MPMusicPlayerController *musicPlayer;
@property(nonatomic, strong) NSMutableArray *dBData;
@property(nonatomic, strong) UIImage *microphoneImage;
@property(nonatomic, strong) UIColor *dbColor;

- (IBAction)volumeSliderChanged:(id)sender;
- (IBAction)sliderChanged:(UISlider *)frequencySlider;
- (IBAction)togglePlay:(UIButton *)selectedButton;
- (void)stop;

@end
