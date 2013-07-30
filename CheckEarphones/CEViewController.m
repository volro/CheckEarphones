//
//  CEViewController.m
//  CheckEarphones
//
//  Created by Bohdan Orlov on 4/22/13.
//  Copyright (c) 2013 WiseEngineering. All rights reserved.
//


#import "CEViewController.h"
#import "CorePlot-CocoaTouch.h"
#import "UIDeviceHardware.h"
#import "SVProgressHUD.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <Foundation/Foundation.h>

static const int dBOffset = 100;
static void *selfP;

@interface CEViewController (){
@public
    double frequency;
    double sampleRate;
    double theta;
    AudioComponentInstance toneUnit;
}

@property (strong, nonatomic) AVAudioRecorder *recorder;
@property (strong, nonatomic) CPTXYGraph *graph, *dBGraph;
@property (strong, nonatomic) NSMutableArray *data;

@property (weak, nonatomic) IBOutlet CPTGraphHostingView *graphHostingView;
@property (weak, nonatomic) IBOutlet CPTGraphHostingView *dBGraphHostingView;
@property (weak, nonatomic) IBOutlet UISlider *volumeSlider;
@property (weak, nonatomic) IBOutlet UISlider *dBSlider;
@property (weak, nonatomic) IBOutlet UILabel *dBLabel;

@property (weak, nonatomic) IBOutlet UILabel *frequencyLabel;
@property (weak, nonatomic) IBOutlet UIButton *playButton;
@property (weak, nonatomic) IBOutlet UISlider *frequencySlider;
@property (weak, nonatomic) IBOutlet UIImageView *micIcon;
@property (weak, nonatomic) IBOutlet UILabel *micLabel;

@end



OSStatus RenderTone(
        void *inRefCon,
        AudioUnitRenderActionFlags 	*ioActionFlags,
        const AudioTimeStamp 		*inTimeStamp,
        UInt32 						inBusNumber,
        UInt32 						inNumberFrames,
        AudioBufferList 			*ioData)

{
    // Fixed amplitude is good enough for our purposes
    const double amplitude = 10000

    ;

    // Get the tone parameters out of the view controller
    CEViewController *viewController =
            (__bridge CEViewController *)inRefCon;
    double theta = viewController->theta;
    double theta_increment = 2.0 * M_PI * viewController->frequency / viewController->sampleRate;

    // This is a mono tone generator so we only need the first buffer
    const int channel = 0;
    Float32 *buffer = (Float32 *)ioData->mBuffers[channel].mData;

    // Generate the samples
    for (UInt32 frame = 0; frame < inNumberFrames; frame++)
    {
        buffer[frame] = sin(theta) * amplitude;

        theta += theta_increment;
        if (theta > 2.0 * M_PI)
        {
            theta -= 2.0 * M_PI;
        }
    }

    // Store the theta back in the view controller
    viewController->theta = theta;
    return noErr;
}

void ToneInterruptionListener(void *inClientData, UInt32 inInterruptionState)
{
    CEViewController *viewController =
            (__bridge CEViewController *)inClientData;

    [viewController stop];
}


@implementation CEViewController



- (void)viewDidLoad
{
    [super viewDidLoad];
    selfP = (__bridge void *)self;
    NSDictionary* recorderSettings = [NSDictionary dictionaryWithObjectsAndKeys:
    [NSNumber numberWithInt:kAudioFormatAppleIMA4],AVFormatIDKey,
    [NSNumber numberWithInt:44100],AVSampleRateKey,
    [NSNumber numberWithInt:1],AVNumberOfChannelsKey,
    [NSNumber numberWithInt:16],AVLinearPCMBitDepthKey,
    [NSNumber numberWithBool:NO],AVLinearPCMIsBigEndianKey,
    [NSNumber numberWithBool:NO],AVLinearPCMIsFloatKey,
    nil];
    NSError* error = nil;

    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"tmp.caf"]];
    self.recorder = [[AVAudioRecorder alloc] initWithURL:url settings:recorderSettings error:&error];

    self.recorder.meteringEnabled = YES;



    [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(updateDBs) userInfo:nil repeats:YES];
	// Do any additional setup after loading the view, typically from a nib.

    [self sliderChanged:self.frequencySlider];
    sampleRate = 44100;

    OSStatus result = AudioSessionInitialize(NULL, NULL, ToneInterruptionListener, (__bridge void *)self);
    if (result == kAudioSessionNoError)
    {
        UInt32 sessionCategory = kAudioSessionCategory_PlayAndRecord;
        AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(sessionCategory), &sessionCategory);

    }
    AudioSessionSetActive(true);

    self.musicPlayer = [MPMusicPlayerController applicationMusicPlayer];

    [self generateBarPlot];
    [self generateScateredPlot];

    [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(volumeChanged:)
                   name:@"AVSystemController_SystemVolumeDidChangeNotification"
                 object:nil];
    AudioSessionAddPropertyListener(kAudioSessionProperty_AudioRouteChange, audioSessionPropertyListener, nil);
    
    
    [self.volumeSlider setMinimumTrackImage:[[UIImage imageNamed:@"minTrack"] resizableImageWithCapInsets:UIEdgeInsetsMake(0, 15, 0, 15) ] forState:UIControlStateNormal];
    [self.volumeSlider setMaximumTrackImage:[[UIImage imageNamed:@"maxTrack"] resizableImageWithCapInsets:UIEdgeInsetsMake(0, 15, 0, 15) ] forState:UIControlStateNormal];
    [self.volumeSlider setThumbImage:[UIImage imageNamed:@"thumb"] forState:UIControlStateNormal ];
    [self.volumeSlider setThumbImage:[UIImage imageNamed:@"thumb"] forState:UIControlStateHighlighted ];
    
    [self.playButton setBackgroundImage:[[UIImage imageNamed:@"buttonNormal"] stretchableImageWithLeftCapWidth:30 topCapHeight:0] forState:UIControlStateNormal];
    [self.playButton setBackgroundImage:[[UIImage imageNamed:@"buttonPressed"] stretchableImageWithLeftCapWidth:30 topCapHeight:0] forState:UIControlStateHighlighted];
   
    NSString *device = [[[UIDeviceHardware alloc] init] platformString];
    if ([device rangeOfString:@"Simulator"].location != NSNotFound) {
        [[[UIAlertView alloc] initWithTitle:@"Run this app on a device!" message:nil delegate:nil cancelButtonTitle:nil otherButtonTitles:nil, nil] show];
    }
}

- (void)volumeChanged:(id)volumeChanged {
    self.volumeSlider.value = self.musicPlayer.volume * 16.0;
    [self sliderChanged:self.volumeSlider];

}

- (void)viewDidAppear:(BOOL)animated {
    self.volumeSlider.value = self.musicPlayer.volume * 16.0;
    checkWhetherHeadsetIsPluggedIn();
}

- (void) updateDBs{
    if (self.recorder.isRecording){
        
        [self.recorder updateMeters];
        
        int dB =  [self.recorder averagePowerForChannel:0];
        if (dB >  0)
            dB = dB * -2;


        NSUInteger index = (NSUInteger) floor(self.musicPlayer.volume * 16) ;
        if (index < self.data.count+1)
            self.data[index] = @(8 / pow(2.0, MAX(0.0, (dBOffset + dB - 85) / 3.0)));
        if(self.dBData.count > 16)
            [self.dBData removeObjectAtIndex:0];
        [self.dBData addObject:@(dBOffset + dB)];
        [self.graph reloadData];
        [self.dBGraph reloadData];

        self.volumeSlider.value = self.musicPlayer.volume * 16.0;
        [self sliderChanged:self.volumeSlider];

        if (self.musicPlayer.volume >= 1){
            [self togglePlay:self.playButton];
            self.volumeSlider.value = self.data.count - [[[self.data reverseObjectEnumerator] allObjects] indexOfObject:@8] -1;
            [self sliderChanged:self.volumeSlider];
        }
        else
            self.musicPlayer.volume += 1.0 / 16.0;
        

        self.dBSlider.maximumValue = dBOffset;
        self.dBSlider.value = dBOffset + dB;
        self.dBSlider.minimumTrackTintColor = [UIColor colorWithHue:0.5 - ((float)(dBOffset + dB) / (float) dBOffset) / 2.0 saturation:1.0 brightness:0.7 alpha:1];
        self.dBLabel.text = [NSString stringWithFormat:@"%d dB",dBOffset + dB];
        self.dBLabel.textColor = self.dbColor;
    }
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewDidUnload {
    [self setDBSlider:nil];
    [self setDBLabel:nil];

    AudioSessionSetActive(false);

    [self setGraphHostingView:nil];
    [self setVolumeSlider:nil];
    [self setDBGraphHostingView:nil];
    [self setMicLabel:nil];
    [self setMicIcon:nil];
    [super viewDidUnload];
}
- (void)generateBarPlot
{


    //Create graph and set it as host view's graph
    self.graph = [[CPTXYGraph alloc] initWithFrame:self.graphHostingView.bounds];
    [self.graphHostingView setHostedGraph:self.graph];

    //[self.graph applyTheme:[CPTTheme themeNamed:kCPTStocksTheme]];
    //set graph padding and theme
    self.graph.plotAreaFrame.paddingTop = 20.0f;
    self.graph.plotAreaFrame.paddingRight = 20.0f;
    self.graph.plotAreaFrame.paddingBottom = 60.0f;
    self.graph.plotAreaFrame.paddingLeft = 30.0f;
    self.graph.plotAreaFrame.borderWidth = 0;
    self.graph.borderWidth = 0;
    self.graph.axisSet.borderWidth = 0;
    self.graph.paddingTop = 0;
    self.graph.paddingRight = 0;
    self.graph.paddingBottom = 0;
    self.graph.paddingLeft = 0;


    //set axes ranges
    CPTXYPlotSpace *plotSpace = (CPTXYPlotSpace *)self.graph.defaultPlotSpace;
    plotSpace.xRange = [CPTPlotRange plotRangeWithLocation:
            CPTDecimalFromFloat(0)
                                                    length:CPTDecimalFromFloat(16)];
    plotSpace.yRange = [CPTPlotRange plotRangeWithLocation:
            CPTDecimalFromFloat(0)
                                                    length:CPTDecimalFromFloat(8)];

    CPTXYAxisSet *axisSet = (CPTXYAxisSet *)self.graph.axisSet;
    //set axes' title, labels and their text styles
    CPTMutableTextStyle *textStyle = [CPTMutableTextStyle textStyle];
    textStyle.fontName = @"Helvetica";
    textStyle.fontSize = 14;
    textStyle.color = [CPTColor colorWithCGColor:[self colorWithHexString:@"394c5d" alpha:1].CGColor];

    axisSet.xAxis.title = @"Volume";
    axisSet.yAxis.title = @"Hours";
    axisSet.xAxis.titleTextStyle = textStyle;
    axisSet.yAxis.titleTextStyle = textStyle;
    axisSet.xAxis.titleOffset = 40.0f;
    axisSet.yAxis.titleOffset = -25.0f;
    axisSet.xAxis.labelTextStyle = textStyle;
    axisSet.xAxis.labelOffset = 3.0f;
    axisSet.yAxis.labelTextStyle = textStyle;
    axisSet.yAxis.labelOffset = 3.0f;
    //set axes' line styles and interval ticks
    CPTMutableLineStyle *lineStyle = [CPTMutableLineStyle lineStyle];
    lineStyle.lineColor = [CPTColor colorWithCGColor:[self colorWithHexString:@"394c5d" alpha:1].CGColor];
    lineStyle.lineWidth = 2.0f;
    axisSet.xAxis.axisLineStyle = lineStyle;
    axisSet.yAxis.axisLineStyle = lineStyle;
    axisSet.xAxis.majorTickLineStyle = lineStyle;
    axisSet.yAxis.majorTickLineStyle = lineStyle;
    axisSet.xAxis.majorIntervalLength = CPTDecimalFromFloat(2.0f);
    axisSet.yAxis.majorIntervalLength = CPTDecimalFromFloat(1.0f);
    axisSet.xAxis.majorTickLength = 7.0f;
    axisSet.yAxis.majorTickLength = 7.0f;
    axisSet.xAxis.minorTickLineStyle = lineStyle;
    axisSet.yAxis.minorTickLineStyle = lineStyle;
    axisSet.xAxis.minorTicksPerInterval = 1;
    axisSet.yAxis.minorTicksPerInterval = 1;
    axisSet.xAxis.minorTickLength = 5.0f;
    axisSet.yAxis.minorTickLength = 5.0f;
    NSNumberFormatter *newFormatter = [[NSNumberFormatter alloc] init];
    newFormatter.minimumIntegerDigits = 1;
    newFormatter.maximumFractionDigits = 0;

    axisSet.xAxis.labelFormatter = newFormatter;
    axisSet.yAxis.labelFormatter = newFormatter;

    // Create bar plot and add it to the graph
    CPTBarPlot *plot = [[CPTBarPlot alloc] init] ;
    plot.dataSource = self;
    plot.delegate = self;
    plot.barWidth = [[NSDecimalNumber decimalNumberWithString:@"1.0"]
            decimalValue];
    plot.barOffset = [[NSDecimalNumber decimalNumberWithString:@"0.0"]
            decimalValue];
    plot.barCornerRadius = 0.0;
    // Remove bar outlines
    CPTMutableLineStyle *borderLineStyle = [CPTMutableLineStyle lineStyle];
    borderLineStyle.lineColor = [CPTColor clearColor];
    plot.lineStyle = borderLineStyle;
    // Identifiers are handy if you want multiple plots in one graph
    plot.identifier = @"plot";
    [self.graph addPlot:plot];

}
- (void)generateScateredPlot
{


    //Create graph and set it as host view's graph
    self.dBGraph = [[CPTXYGraph alloc] initWithFrame:self.dBGraphHostingView.bounds];
    [self.dBGraphHostingView setHostedGraph:self.dBGraph];

    //[self.dBGraph applyTheme:[CPTTheme themeNamed:kCPTDarkGradientTheme]];
    //set graph padding and theme
    self.dBGraph.plotAreaFrame.paddingTop = 5.0f;
    self.dBGraph.plotAreaFrame.paddingRight = 20.0f;
    self.dBGraph.plotAreaFrame.paddingBottom = 5.0f;
    self.dBGraph.plotAreaFrame.paddingLeft = 30.0f;
    self.dBGraph.plotAreaFrame.borderWidth = 0;
    self.dBGraph.borderWidth = 0;
    self.dBGraph.axisSet.borderWidth = 0;


    self.dBGraph.paddingTop = 0;
    self.dBGraph.paddingRight = 0;
    self.dBGraph.paddingBottom = 0;
    self.dBGraph.paddingLeft = 0;


    //set axes ranges
    CPTXYPlotSpace *plotSpace = (CPTXYPlotSpace *)self.dBGraph.defaultPlotSpace;
    plotSpace.xRange = [CPTPlotRange plotRangeWithLocation:
            CPTDecimalFromFloat(0)
                                                    length:CPTDecimalFromFloat(16)];
    plotSpace.yRange = [CPTPlotRange plotRangeWithLocation:
            CPTDecimalFromFloat(30)
                                                    length:CPTDecimalFromFloat(75)];

    CPTXYAxisSet *axisSet = (CPTXYAxisSet *)self.dBGraph.axisSet;
    //set axes' title, labels and their text styles
    CPTMutableTextStyle *textStyle = [CPTMutableTextStyle textStyle];
    textStyle.fontName = @"Helvetica";
    textStyle.fontSize = 10;
    textStyle.color = [CPTColor colorWithCGColor:[self colorWithHexString:@"394c5d" alpha:1].CGColor];

    axisSet.yAxis.labelTextStyle = textStyle;
    axisSet.yAxis.labelOffset = 0.0f;
    //set axes' line styles and interval ticks
    CPTMutableLineStyle *lineStyle = [CPTMutableLineStyle lineStyle];
    lineStyle.lineColor = [CPTColor colorWithCGColor:[self colorWithHexString:@"394c5d" alpha:1].CGColor];
    lineStyle.lineWidth = 2.0f;
    axisSet.xAxis.axisLineStyle = lineStyle;

    axisSet.yAxis.axisLineStyle = lineStyle;
    axisSet.xAxis.majorTickLineStyle = lineStyle;
    axisSet.yAxis.majorTickLineStyle = lineStyle;
    axisSet.xAxis.majorIntervalLength = CPTDecimalFromFloat(2.0f);
    axisSet.yAxis.majorIntervalLength = CPTDecimalFromFloat(10.0f);
    axisSet.xAxis.majorTickLength = 7.0f;
    axisSet.yAxis.majorTickLength = 7.0f;
    axisSet.xAxis.minorTickLineStyle = lineStyle;
    axisSet.yAxis.minorTickLineStyle = lineStyle;
    axisSet.xAxis.minorTicksPerInterval = 1;
    axisSet.yAxis.minorTicksPerInterval = 1;
    axisSet.xAxis.minorTickLength = 5.0f;
    axisSet.yAxis.minorTickLength = 0.0f;
    NSNumberFormatter *newFormatter = [[NSNumberFormatter alloc] init];
    newFormatter.minimumIntegerDigits = 1;
    newFormatter.maximumFractionDigits = 0;

    lineStyle.lineWidth = 1.0f;
    lineStyle.lineColor = [CPTColor colorWithCGColor:[self colorWithHexString:@"394c5d" alpha:0.5].CGColor];
    axisSet.yAxis.majorGridLineStyle = lineStyle;
    axisSet.xAxis.labelFormatter = newFormatter;
    axisSet.yAxis.labelFormatter = newFormatter;


    // Create bar plot and add it to the graph
    CPTScatterPlot *plot = [[CPTScatterPlot alloc] init] ;
    plot.dataSource = self;
    plot.delegate = self;


    CPTMutableLineStyle *borderLineStyle = [CPTMutableLineStyle lineStyle];
    borderLineStyle.lineColor = [CPTColor colorWithCGColor:[self colorWithHexString:@"394c5d" alpha:1].CGColor];
    borderLineStyle.lineWidth = 3;
    plot.dataLineStyle = borderLineStyle;
    // Identifiers are handy if you want multiple plots in one graph
    plot.identifier = @"dBplot";
    [self.dBGraph addPlot:plot];
}

-(NSUInteger)numberOfRecordsForPlot:(CPTPlot *)plot
{
    if ( [plot.identifier isEqual:@"plot"] )
        return self.data.count;
    if ( [plot.identifier isEqual:@"dBplot"] )
        return self.dBData.count;

    return 0;
}

-(NSNumber *)numberForPlot:(CPTPlot *)plot field:(NSUInteger)fieldEnum recordIndex:(NSUInteger)index
{
    if ( [plot.identifier isEqual:@"plot"] )
    {
        if(fieldEnum == CPTBarPlotFieldBarLocation)
            return @(index);
        else if(fieldEnum ==CPTBarPlotFieldBarTip){
            if (index == 0)
                return 0;
            return self.data[index];
        }
    }
    if ( [plot.identifier isEqual:@"dBplot"] )
    {

        if(fieldEnum == CPTScatterPlotFieldX)
            return @(16 - index+1);
        else if(fieldEnum ==CPTScatterPlotFieldY){
            if (index == 0)
                return 0;
            return self.dBData[self.dBData.count - index];
        }
    }
    return [NSNumber numberWithFloat:0];
}
-(CPTFill *)barFillForBarPlot:(CPTBarPlot *)barPlot
                  recordIndex:(NSUInteger)index
{
    if ( [barPlot.identifier isEqual:@"plot"] )
    {
        CPTFill *fill = [CPTFill fillWithColor:[CPTColor colorWithCGColor:[[UIColor colorWithHue:0.0 + 0.5 * [self.data[index] floatValue] / 8 saturation:1.0 brightness:0.7 alpha:1.0] CGColor]]];
        return fill;

    }
    return [CPTFill fillWithColor:[CPTColor colorWithComponentRed:1.0 green:1.0 blue:1.0 alpha:1.0]];
}

- (IBAction)volumeSliderChanged:(id)sender {
    self.musicPlayer.volume = self.volumeSlider.value / 16.0;
    [self sliderChanged:self.volumeSlider];
}

- (IBAction)sliderChanged:(UISlider *)slider
{
    if (slider == self.volumeSlider){
        slider.value = round(slider.value);

        int i = (int) slider.value ;

        if (i < self.data.count)
            self.dbColor = [UIColor colorWithHue:0.0 + 0.5 * [self.data[i] floatValue] / 8 saturation:1.0 brightness:0.7 alpha:1.0];

    }
    else{
        frequency = slider.value;
        self.frequencyLabel.text = [NSString stringWithFormat:@"%4.1f Hz", frequency];
    }
}

- (void)createToneUnit
{
    // Configure the search parameters to find the default playback output unit
    // (called the kAudioUnitSubType_RemoteIO on iOS but
    // kAudioUnitSubType_DefaultOutput on Mac OS X)
    AudioComponentDescription defaultOutputDescription;
    defaultOutputDescription.componentType = kAudioUnitType_Output;
    defaultOutputDescription.componentSubType = kAudioUnitSubType_RemoteIO;
    defaultOutputDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    defaultOutputDescription.componentFlags = 0;
    defaultOutputDescription.componentFlagsMask = 0;

    // Get the default playback output unit
    AudioComponent defaultOutput = AudioComponentFindNext(NULL, &defaultOutputDescription);
    NSAssert(defaultOutput, @"Can't find default output");

    // Create a new unit based on this that we'll use for output
    OSErr err = AudioComponentInstanceNew(defaultOutput, &toneUnit);
    NSAssert1(toneUnit, @"Error creating unit: %ld", err);

    // Set our tone rendering function on the unit
    AURenderCallbackStruct input;
    input.inputProc = RenderTone;
    input.inputProcRefCon = (__bridge void *)self;
    err = AudioUnitSetProperty(toneUnit,
            kAudioUnitProperty_SetRenderCallback,
            kAudioUnitScope_Input,
            0,
            &input,
            sizeof(input));


    NSAssert1(err == noErr, @"Error setting callback: %ld", err);

    // Set the format to 32 bit, single channel, floating point, linear PCM
    const int four_bytes_per_float = 4;
    const int eight_bits_per_byte = 8;
    AudioStreamBasicDescription streamFormat;
    streamFormat.mSampleRate = sampleRate;
    streamFormat.mFormatID = kAudioFormatLinearPCM;
    streamFormat.mFormatFlags =
            kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved;
    streamFormat.mBytesPerPacket = four_bytes_per_float;
    streamFormat.mFramesPerPacket = 1;
    streamFormat.mBytesPerFrame = four_bytes_per_float;
    streamFormat.mChannelsPerFrame = 2;
    streamFormat.mBitsPerChannel = four_bytes_per_float * eight_bits_per_byte;
    err = AudioUnitSetProperty (toneUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            0,
            &streamFormat,
            sizeof(AudioStreamBasicDescription));
    NSAssert1(err == noErr, @"Error setting stream format: %ld", err);
}

- (IBAction)togglePlay:(UIButton *)selectedButton
{
    if (toneUnit)
    {
        [self stopPlay:selectedButton];

    }
    else
    {
        if([AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio].count == 0){
            NSLog(@"No input devices");
            return;
        }

        if([[[AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio] componentsJoinedByString:@" "] rangeOfString:@"Microphone"].location == NSNotFound){
            NSLog(@"External microphone");
        }
        UInt32 routeSize = sizeof (CFStringRef);
        CFStringRef route;

        OSStatus error = AudioSessionGetProperty (kAudioSessionProperty_AudioRoute,
                &routeSize,
                &route
        );
        if([(__bridge NSString*)route rangeOfString:@"Speaker"].location != NSNotFound){
            [SVProgressHUD showErrorWithStatus:@"Plug in headphones"];
            return;
        }


        self.data = [NSMutableArray arrayWithCapacity:16];
        self.dBData = [NSMutableArray arrayWithCapacity:16];
        self.musicPlayer.volume = 0.0;
        self.volumeSlider.value = self.musicPlayer.volume;
        [self.recorder record];
        [self createToneUnit];

        // Stop changing parameters on the unit
        OSErr err = AudioUnitInitialize(toneUnit);
        NSAssert1(err == noErr, @"Error initializing unit: %ld", err);

        // Start playback
        err = AudioOutputUnitStart(toneUnit);
        NSAssert1(err == noErr, @"Error starting unit: %ld", err);

        [selectedButton setTitle:NSLocalizedString(@"Stop", nil) forState:0];
    }
}

- (void)stopPlay:(UIButton *)selectedButton {
    [self.recorder stop];
    AudioOutputUnitStop(toneUnit);
    AudioUnitUninitialize(toneUnit);
    AudioComponentInstanceDispose(toneUnit);
    toneUnit = nil;

    [selectedButton setTitle:NSLocalizedString(@"Test", nil) forState:0];

}


BOOL checkWhetherHeadsetIsPluggedIn() {
    UInt32 routeSize = sizeof (CFStringRef);
    CFStringRef route;

    OSStatus error = AudioSessionGetProperty (kAudioSessionProperty_AudioRoute,
            &routeSize,
            &route
    );
    NSLog(@"%@", route);
    
    CEViewController *controller = (__bridge CEViewController *)selfP;
    
    [controller stopPlay:[controller playButton]];
    
    if([(__bridge NSString*)route rangeOfString:@"Microphone"].location != NSNotFound){
        //iphone 4s/5 mic is on bottom, use the left one.
        //iphone 3g mic is on bottom, use the right one.
        //ipad on the middle of top edge
        //ipod next to the camera
        NSString *device = [[[UIDeviceHardware alloc] init] platformString];
       
        if ([device rangeOfString:@"iPod"].location != NSNotFound){
                [controller micLabel].text = @"Active mic is next to the camera";
                if ([device rangeOfString:@"iPod Touch 5G"].location != NSNotFound)
                    [controller setMicrophoneImage:[UIImage imageNamed:@"iPod.jpg"]];
                else
                    [controller setMicrophoneImage:[UIImage imageNamed:@"iPodOld.png"]];
            }
        else if ([device rangeOfString:@"iPad"].location != NSNotFound){
            [controller micLabel].text = @"Active mic is on the middle of top edge";
            if ([device rangeOfString:@"iPad Mini"].location != NSNotFound)
                [controller setMicrophoneImage: [UIImage imageNamed:@"iPadMini.jpg"]];
            else
                [controller setMicrophoneImage: [UIImage imageNamed:@"iPadRetina.jpg"]];
        }
        else if ([device rangeOfString:@"iPhone 3"].location != NSNotFound){
            [controller micLabel].text = @"Active mic is right grill on the bottom edge";
            [controller setMicrophoneImage:[UIImage imageNamed:@"iPhone3.png"]];
        }
        else if ([device rangeOfString:@"iPhone 4"].location != NSNotFound || [device rangeOfString:@"iPhone 5"].location != NSNotFound){
            [(__bridge CEViewController *)selfP micLabel].text = @"Active mic is left grill on the bottom edge";
            if ([device rangeOfString:@"iPhone 5"].location != NSNotFound)
                [controller setMicrophoneImage:[UIImage imageNamed:@"iPhone5.jpg"]];
            else
                [controller setMicrophoneImage:[UIImage imageNamed:@"iPhone4.png"]];
        }
    }
    else{
        [controller micLabel].text = @"Active mic is on headphones";
        [controller setMicrophoneImage:[UIImage imageNamed:@"headphones.jpg"]];
    }

    return (!error && (route != NULL) && ([(__bridge NSString*)route rangeOfString:@"Head"].location != NSNotFound));
}

void audioSessionPropertyListener(void* inClientData, AudioSessionPropertyID inID,
        UInt32 inDataSize, const void* inData) {
    

    // Determines the reason for the route change, to ensure that it is not
    //      because of a category change.
    CFDictionaryRef routeChangeDictionary = inData;
    CFNumberRef routeChangeReasonRef = CFDictionaryGetValue (routeChangeDictionary,CFSTR (kAudioSession_AudioRouteChangeKey_Reason));

    SInt32 routeChangeReason;
    CFNumberGetValue (routeChangeReasonRef, kCFNumberSInt32Type, &routeChangeReason);

    // "Old device unavailable" indicates that a headset was unplugged, or that the
    //  device was removed from a dock connector that supports audio output.
    //if (routeChangeReason != kAudioSessionRouteChangeReason_OldDeviceUnavailable)
    //    return;

    checkWhetherHeadsetIsPluggedIn();
}
- (void)stop
{
    if (toneUnit)
    {
        [self togglePlay:self.playButton];
    }
}


- (UIColor*)colorWithHexString:(NSString*)hex alpha:(float)alpha{
    NSString *cString = [[hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    
    // String should be 6 or 8 characters
    if ([cString length] < 6) return [UIColor grayColor];
    
    // strip 0X if it appears
    if ([cString hasPrefix:@"0X"]) cString = [cString substringFromIndex:2];
    
    if ([cString length] != 6) return  [UIColor grayColor];
    
    // Separate into r, g, b substrings
    NSRange range;
    range.location = 0;
    range.length = 2;
    NSString *rString = [cString substringWithRange:range];
    
    range.location = 2;
    NSString *gString = [cString substringWithRange:range];
    
    range.location = 4;
    NSString *bString = [cString substringWithRange:range];
    
    // Scan values
    unsigned int r, g, b;
    [[NSScanner scannerWithString:rString] scanHexInt:&r];
    [[NSScanner scannerWithString:gString] scanHexInt:&g];
    [[NSScanner scannerWithString:bString] scanHexInt:&b];
    
    return [UIColor colorWithRed:((float) r / 255.0f)
                           green:((float) g / 255.0f)
                            blue:((float) b / 255.0f)
                           alpha:alpha];
    
}

@end
