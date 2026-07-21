//
//  DODownloadViewController.m
//  Dopamine
//
//  Created by tomt000 on 07/02/2024.
//

#import "DODownloadViewController.h"
#import "DOUpdateCircleView.h"
#import "DOUIManager.h"

@interface DODownloadViewController ()

@property (strong, nonatomic) DOUpdateCircleView *circleView;
@property (strong, nonatomic) NSString *urlString;
@property (copy, nonatomic) void (^downloadCallback)(NSURL *file);

@property (nonatomic, retain) UILabel *titleLabel;
@property (nonatomic, retain) UILabel *descriptionLabel;

@end

@implementation DODownloadViewController

- (id)initWithUrl:(NSString *)urlString callback:(void (^)(NSURL *file))callback {
    self = [super init];
    if (self) {
        self.urlString = urlString;
        self.downloadCallback = callback;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    UIStackView *stackView = [[UIStackView alloc] init];
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.alignment = UIStackViewAlignmentCenter;
    stackView.distribution = UIStackViewDistributionEqualSpacing;
    stackView.spacing = 10;
    stackView.translatesAutoresizingMaskIntoConstraints = NO;

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.text = DOLocalizedString(@"Update_Status_Downloading");
    self.titleLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightMedium];
    self.titleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:1.0];

    self.descriptionLabel = [[UILabel alloc] init];
    self.descriptionLabel.text = DOLocalizedString(@"Update_Status_Subtitle_Please_Wait");
    self.descriptionLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightRegular];
    self.descriptionLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.5];
    self.descriptionLabel.textAlignment = NSTextAlignmentCenter;
    self.descriptionLabel.numberOfLines = 0;

    self.circleView = [[DOUpdateCircleView alloc] initWithFrame:CGRectNull];
    self.circleView.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *spacer = [[UIView alloc] init];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;

    [stackView addArrangedSubview:self.titleLabel];
    [stackView addArrangedSubview:self.descriptionLabel];
    [stackView addArrangedSubview:spacer];
    [stackView addArrangedSubview:self.circleView];

    [NSLayoutConstraint activateConstraints:@[
        [self.circleView.widthAnchor constraintEqualToConstant:150],
        [self.circleView.heightAnchor constraintEqualToConstant:150],
        [spacer.heightAnchor constraintEqualToConstant:20]
    ]];   

    [self.view addSubview:stackView];

    [NSLayoutConstraint activateConstraints:@[
        [stackView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [stackView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [stackView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:0.8]
    ]];

    [self startDownload];
}

- (void)startDownload {
    NSURL *url = [NSURL URLWithString:self.urlString];
    if (!url) {
        NSLog(@"Invalid URL");
        return;
    }

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDownloadTask *downloadTask = [session downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"Download error: %@", error.localizedDescription);
            return;
        }

        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths objectAtIndex:0];
        NSString *destinationPath = [documentsDirectory stringByAppendingPathComponent:[location lastPathComponent]];
        NSURL *destinationURL = [NSURL fileURLWithPath:destinationPath];

        NSError *fileError;
        [[NSFileManager defaultManager] moveItemAtURL:location toURL:destinationURL error:&fileError];
        if (fileError) {
            NSLog(@"File moving error: %@", fileError.localizedDescription);
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.downloadCallback) {
                self.downloadCallback(destinationURL);
                [self startBlinking];
            }
        });
    }];

    [downloadTask resume];

    [self trackDownloadProgress:downloadTask];
}

- (void)trackDownloadProgress:(NSURLSessionDownloadTask *)downloadTask {
    [NSTimer scheduledTimerWithTimeInterval:(1.0/60.0) repeats:YES block:^(NSTimer * _Nonnull timer) {
        if (self.circleView.progress >= 0.99) {
            [timer invalidate];
            self.circleView.progress = 1.0;
            return;
        }

        [downloadTask countOfBytesExpectedToReceive];
        if (downloadTask.countOfBytesExpectedToReceive > 0) {
            float progress = (float) downloadTask.countOfBytesReceived / (float) downloadTask.countOfBytesExpectedToReceive;
            if (self.circleView.progress < progress) {
                self.circleView.progress += (progress - self.circleView.progress) * 0.25;
            }
        }
    }];
}

- (void)startBlinking {
    self.titleLabel.text = DOLocalizedString(@"Update_Status_Installing");
    self.descriptionLabel.text = DOLocalizedString(@"Update_Status_Subtitle_Restart_Soon");
    [UIView animateWithDuration:0.5 delay:0 options:UIViewAnimationOptionAutoreverse | UIViewAnimationOptionRepeat | UIViewAnimationOptionAllowUserInteraction animations:^{
        self.circleView.alpha = 0.7;
    } completion:nil];
}

#pragma mark - Status Bar

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}


@end
