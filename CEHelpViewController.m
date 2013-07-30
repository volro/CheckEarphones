//
//  CEHelpViewController.m
//  CheckEarphones
//
//  Created by Bohdan Orlov on 4/29/13.
//  Copyright (c) 2013 WiseEngineering. All rights reserved.
//

#import "CEHelpViewController.h"
#import "CEViewController.h"

@interface CEHelpViewController ()

- (IBAction)back:(id)sender;
- (IBAction)showMicrophone:(id)sender;
- (IBAction)imageViewTap:(id)sender;
@property (weak, nonatomic) IBOutlet UIImageView *microphoneImageView;
@end

@implementation CEHelpViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)back:(id)sender {
    [self.presentingViewController dismissModalViewControllerAnimated:YES];
}

- (IBAction)showMicrophone:(id)sender {
    self.microphoneImageView.hidden = NO;
    self.microphoneImageView.alpha = 0.0;
    [UIView animateWithDuration:0.3 animations:^{
        self.microphoneImageView.alpha = 1.0;
    }];
    self.microphoneImageView.image = [(CEViewController *)self.presentingViewController microphoneImage];
}

- (IBAction)imageViewTap:(id)sender {

    [UIView animateWithDuration:0.3 animations:^{
        self.microphoneImageView.alpha = 0.0;
    } completion:^(BOOL finished) {
        self.microphoneImageView.hidden = YES;
    }];

}
- (void)viewDidUnload {
    [self setMicrophoneImageView:nil];
    [super viewDidUnload];
}
@end
