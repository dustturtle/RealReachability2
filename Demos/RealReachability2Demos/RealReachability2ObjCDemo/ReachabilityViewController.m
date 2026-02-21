#import "ReachabilityViewController.h"
@import RealReachability2ObjC;

@interface ReachabilityViewController ()

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIStackView *stackView;

@property (nonatomic, strong) UILabel *statusValueLabel;
@property (nonatomic, strong) UILabel *connectionValueLabel;
@property (nonatomic, strong) UILabel *updatedValueLabel;

@property (nonatomic, strong) UISegmentedControl *modeSegmentedControl;
@property (nonatomic, strong) UITextField *timeoutField;
@property (nonatomic, strong) UITextField *httpURLField;
@property (nonatomic, strong) UITextField *icmpHostField;

@property (nonatomic, strong) UIButton *applyConfigButton;
@property (nonatomic, strong) UIButton *checkOnceButton;
@property (nonatomic, strong) UIButton *startMonitorButton;
@property (nonatomic, strong) UIButton *stopMonitorButton;
@property (nonatomic, strong) UIButton *clearLogsButton;

@property (nonatomic, strong) UITextView *logTextView;

@property (nonatomic, strong) NSMutableArray<NSString *> *logLines;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;

@property (nonatomic, assign) BOOL monitoring;
@property (nonatomic, assign) BOOL checking;

@end

@implementation ReachabilityViewController

- (void)dealloc {
    [self stopMonitoringInternal];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"RealReachability2 Demo (ObjC / 双语)";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.logLines = [NSMutableArray array];
    self.dateFormatter = [[NSDateFormatter alloc] init];
    self.dateFormatter.dateFormat = @"HH:mm:ss";

    [self buildUI];
    [self loadConfigurationIntoForm];
    [self handleStatus:RRReachabilityStatusUnknown connectionType:RRConnectionTypeNone source:@"initial"];
    [self appendLogWithSource:@"INIT" english:@"Demo loaded." chinese:@"演示页面已加载。"];
    [self updateButtonState];
}

- (void)buildUI {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;

    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;

    self.stackView = [[UIStackView alloc] init];
    self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.stackView.axis = UILayoutConstraintAxisVertical;
    self.stackView.alignment = UIStackViewAlignmentFill;
    self.stackView.distribution = UIStackViewDistributionFill;
    self.stackView.spacing = 12;

    [self.view addSubview:self.scrollView];
    [self.scrollView addSubview:self.contentView];
    [self.contentView addSubview:self.stackView];

    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:safeArea.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor],

        [self.stackView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16],
        [self.stackView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.stackView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [self.stackView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-16]
    ]];

    self.statusValueLabel = [[UILabel alloc] init];
    self.connectionValueLabel = [[UILabel alloc] init];
    self.updatedValueLabel = [[UILabel alloc] init];

    [self.stackView addArrangedSubview:[self makeKeyValueRowWithTitle:@"Status / 状态" valueLabel:self.statusValueLabel]];
    [self.stackView addArrangedSubview:[self makeKeyValueRowWithTitle:@"Connection / 连接" valueLabel:self.connectionValueLabel]];
    [self.stackView addArrangedSubview:[self makeKeyValueRowWithTitle:@"Updated / 更新时间" valueLabel:self.updatedValueLabel]];

    self.modeSegmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"并行", @"HTTP", @"ICMP"]];
    self.modeSegmentedControl.selectedSegmentIndex = 0;
    [self.stackView addArrangedSubview:[self makeLabeledContainerWithTitle:@"Probe Mode / 探测模式" content:self.modeSegmentedControl]];

    self.timeoutField = [[UITextField alloc] init];
    [self configureTextField:self.timeoutField placeholder:@"5.0"];
    self.timeoutField.keyboardType = UIKeyboardTypeDecimalPad;
    [self.stackView addArrangedSubview:[self makeLabeledContainerWithTitle:@"Timeout (s) / 超时(秒)" content:self.timeoutField]];

    self.httpURLField = [[UITextField alloc] init];
    [self configureTextField:self.httpURLField placeholder:@"https://captive.apple.com/hotspot-detect.html"];
    self.httpURLField.keyboardType = UIKeyboardTypeURL;
    self.httpURLField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [self.stackView addArrangedSubview:[self makeLabeledContainerWithTitle:@"HTTP Probe URL / HTTP 探测地址" content:self.httpURLField]];

    self.icmpHostField = [[UITextField alloc] init];
    [self configureTextField:self.icmpHostField placeholder:@"8.8.8.8"];
    self.icmpHostField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [self.stackView addArrangedSubview:[self makeLabeledContainerWithTitle:@"ICMP Host / ICMP 主机" content:self.icmpHostField]];

    self.applyConfigButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.applyConfigButton setTitle:@"Apply / 应用" forState:UIControlStateNormal];
    [self.applyConfigButton addTarget:self action:@selector(applyConfigTapped) forControlEvents:UIControlEventTouchUpInside];

    self.checkOnceButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.checkOnceButton setTitle:@"Check Once / 单次检测" forState:UIControlStateNormal];
    [self.checkOnceButton addTarget:self action:@selector(checkOnceTapped) forControlEvents:UIControlEventTouchUpInside];

    self.startMonitorButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.startMonitorButton setTitle:@"Start / 开始监听" forState:UIControlStateNormal];
    [self.startMonitorButton addTarget:self action:@selector(startMonitorTapped) forControlEvents:UIControlEventTouchUpInside];

    self.stopMonitorButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.stopMonitorButton setTitle:@"Stop / 停止监听" forState:UIControlStateNormal];
    [self.stopMonitorButton addTarget:self action:@selector(stopMonitorTapped) forControlEvents:UIControlEventTouchUpInside];

    self.clearLogsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.clearLogsButton setTitle:@"Clear / 清空日志" forState:UIControlStateNormal];
    [self.clearLogsButton addTarget:self action:@selector(clearLogsTapped) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *buttonRow1 = [[UIStackView alloc] initWithArrangedSubviews:@[self.applyConfigButton, self.checkOnceButton]];
    buttonRow1.axis = UILayoutConstraintAxisHorizontal;
    buttonRow1.distribution = UIStackViewDistributionFillEqually;
    buttonRow1.spacing = 8;

    UIStackView *buttonRow2 = [[UIStackView alloc] initWithArrangedSubviews:@[self.startMonitorButton, self.stopMonitorButton, self.clearLogsButton]];
    buttonRow2.axis = UILayoutConstraintAxisHorizontal;
    buttonRow2.distribution = UIStackViewDistributionFillEqually;
    buttonRow2.spacing = 8;

    [self.stackView addArrangedSubview:buttonRow1];
    [self.stackView addArrangedSubview:buttonRow2];

    UILabel *logsTitle = [[UILabel alloc] init];
    logsTitle.text = @"Logs / 日志";
    logsTitle.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    [self.stackView addArrangedSubview:logsTitle];

    self.logTextView = [[UITextView alloc] init];
    self.logTextView.editable = NO;
    self.logTextView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.logTextView.layer.borderWidth = 1;
    self.logTextView.layer.borderColor = [UIColor systemGray4Color].CGColor;
    self.logTextView.layer.cornerRadius = 8;
    [self.logTextView.heightAnchor constraintEqualToConstant:240].active = YES;
    [self.stackView addArrangedSubview:self.logTextView];
}

- (UIStackView *)makeKeyValueRowWithTitle:(NSString *)title valueLabel:(UILabel *)valueLabel {
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];

    valueLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    valueLabel.textColor = [UIColor secondaryLabelColor];
    valueLabel.textAlignment = NSTextAlignmentRight;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, valueLabel]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.distribution = UIStackViewDistributionFill;
    row.spacing = 8;

    [titleLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [valueLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    return row;
}

- (UIView *)makeLabeledContainerWithTitle:(NSString *)title content:(UIView *)content {
    UIView *container = [[UIView alloc] init];
    UILabel *titleLabel = [[UILabel alloc] init];

    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    content.translatesAutoresizingMaskIntoConstraints = NO;

    titleLabel.text = title;
    titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    titleLabel.textColor = [UIColor secondaryLabelColor];

    [container addSubview:titleLabel];
    [container addSubview:content];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:container.topAnchor],
        [titleLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [titleLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],

        [content.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:6],
        [content.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [content.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [content.heightAnchor constraintEqualToConstant:36]
    ]];

    return container;
}

- (void)configureTextField:(UITextField *)textField placeholder:(NSString *)placeholder {
    textField.borderStyle = UITextBorderStyleRoundedRect;
    textField.placeholder = placeholder;
    textField.autocorrectionType = UITextAutocorrectionTypeNo;
    textField.spellCheckingType = UITextSpellCheckingTypeNo;
}

- (void)loadConfigurationIntoForm {
    RRReachability *reachability = [RRReachability sharedInstance];

    switch (reachability.probeMode) {
        case RRProbeModeParallel:
            self.modeSegmentedControl.selectedSegmentIndex = 0;
            break;
        case RRProbeModeHTTPOnly:
            self.modeSegmentedControl.selectedSegmentIndex = 1;
            break;
        case RRProbeModeICMPOnly:
            self.modeSegmentedControl.selectedSegmentIndex = 2;
            break;
    }

    self.timeoutField.text = [NSString stringWithFormat:@"%.2f", reachability.timeout];
    self.httpURLField.text = reachability.httpProbeURL.absoluteString;
    self.icmpHostField.text = reachability.icmpHost;
}

- (void)applyConfigTapped {
    [self applyConfigurationFromInput];
}

- (void)checkOnceTapped {
    if (self.checking) {
        return;
    }

    self.checking = YES;
    [self updateButtonState];
    [self applyConfigurationFromInput];
    [self appendLogWithSource:@"CHECK" english:@"Running one-time check..." chinese:@"正在执行单次检测..."];

    [[RRReachability sharedInstance] checkReachabilityWithCompletion:^(RRReachabilityStatus status, RRConnectionType type) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.checking = NO;
            [self handleStatus:status connectionType:type source:@"check"];
            [self updateButtonState];
        });
    }];
}

- (void)startMonitorTapped {
    if (self.monitoring) {
        [self appendLogWithSource:@"MONITOR" english:@"Monitor is already running." chinese:@"监听已在运行。"];
        return;
    }

    [self applyConfigurationFromInput];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reachabilityChanged:)
                                                 name:kRRReachabilityChangedNotification
                                               object:[RRReachability sharedInstance]];

    [[RRReachability sharedInstance] startNotifier];
    self.monitoring = YES;
    [self appendLogWithSource:@"MONITOR" english:@"Monitor started." chinese:@"监听已启动。"];
    [self updateButtonState];
}

- (void)stopMonitorTapped {
    if (!self.monitoring) {
        [[RRReachability sharedInstance] stopNotifier];
        [self appendLogWithSource:@"MONITOR" english:@"Monitor is not running." chinese:@"监听当前未运行。"];
        return;
    }

    [self stopMonitoringInternal];
    [self appendLogWithSource:@"MONITOR" english:@"Monitor stopped." chinese:@"监听已停止。"];
    [self updateButtonState];
}

- (void)clearLogsTapped {
    [self.logLines removeAllObjects];
    self.logTextView.text = @"";
}

- (void)reachabilityChanged:(NSNotification *)notification {
    NSNumber *statusNumber = notification.userInfo[kRRReachabilityStatusKey];
    NSNumber *typeNumber = notification.userInfo[kRRConnectionTypeKey];

    RRReachabilityStatus status = statusNumber != nil ? (RRReachabilityStatus)statusNumber.integerValue : RRReachabilityStatusUnknown;
    RRConnectionType type = typeNumber != nil ? (RRConnectionType)typeNumber.integerValue : RRConnectionTypeNone;

    [self handleStatus:status connectionType:type source:@"stream"];
}

- (void)applyConfigurationFromInput {
    RRReachability *reachability = [RRReachability sharedInstance];

    RRProbeMode mode = RRProbeModeParallel;
    if (self.modeSegmentedControl.selectedSegmentIndex == 1) {
        mode = RRProbeModeHTTPOnly;
    } else if (self.modeSegmentedControl.selectedSegmentIndex == 2) {
        mode = RRProbeModeICMPOnly;
    }

    NSTimeInterval timeout = reachability.timeout;
    NSString *timeoutText = [self.timeoutField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (timeoutText.length > 0) {
        double parsed = timeoutText.doubleValue;
        if (parsed > 0) {
            timeout = parsed;
        } else {
            [self appendLogWithSource:@"CONFIG"
                              english:[NSString stringWithFormat:@"Invalid timeout. Keep previous value %.2f.", timeout]
                              chinese:[NSString stringWithFormat:@"超时输入无效，沿用之前的值 %.2f。", timeout]];
            self.timeoutField.text = [NSString stringWithFormat:@"%.2f", timeout];
        }
    }

    NSURL *url = reachability.httpProbeURL;
    NSString *rawURL = [self.httpURLField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (rawURL.length > 0) {
        NSURL *parsedURL = [NSURL URLWithString:rawURL];
        if (parsedURL != nil && parsedURL.scheme.length > 0) {
            url = parsedURL;
        } else {
            [self appendLogWithSource:@"CONFIG"
                              english:[NSString stringWithFormat:@"Invalid HTTP URL. Keep previous value %@.", url.absoluteString]
                              chinese:[NSString stringWithFormat:@"HTTP 地址无效，沿用之前的值 %@。", url.absoluteString]];
            self.httpURLField.text = url.absoluteString;
        }
    }

    NSString *host = reachability.icmpHost;
    NSString *rawHost = [self.icmpHostField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (rawHost.length > 0) {
        host = rawHost;
    } else {
        [self appendLogWithSource:@"CONFIG"
                          english:[NSString stringWithFormat:@"ICMP host is empty. Keep previous value %@.", host]
                          chinese:[NSString stringWithFormat:@"ICMP 主机为空，沿用之前的值 %@。", host]];
        self.icmpHostField.text = host;
    }

    reachability.probeMode = mode;
    reachability.timeout = timeout;
    reachability.httpProbeURL = url;
    reachability.icmpHost = host;

    [self appendLogWithSource:@"CONFIG"
                      english:[NSString stringWithFormat:@"Applied config: mode=%@, timeout=%.2f, url=%@, host=%@",
                               [self modeLabel:mode], timeout, url.absoluteString, host]
                      chinese:[NSString stringWithFormat:@"已应用配置：模式=%@，超时=%.2f，URL=%@，主机=%@",
                               [self modeLabel:mode], timeout, url.absoluteString, host]];
}

- (void)handleStatus:(RRReachabilityStatus)status connectionType:(RRConnectionType)type source:(NSString *)source {
    NSString *statusText = [self statusLabel:status];
    NSString *connectionText = [self connectionLabel:type];

    self.statusValueLabel.text = statusText;
    self.connectionValueLabel.text = connectionText;
    self.updatedValueLabel.text = [self.dateFormatter stringFromDate:[NSDate date]];

    [self appendLogWithSource:[self sourceLabel:source]
                      english:[NSString stringWithFormat:@"status=%@, connection=%@", statusText, connectionText]
                      chinese:[NSString stringWithFormat:@"状态=%@，连接=%@", statusText, connectionText]];
}

- (NSString *)statusLabel:(RRReachabilityStatus)status {
    switch (status) {
        case RRReachabilityStatusReachable:
            return @"reachable / 可达";
        case RRReachabilityStatusNotReachable:
            return @"notReachable / 不可达";
        case RRReachabilityStatusUnknown:
        default:
            return @"unknown / 未知";
    }
}

- (NSString *)connectionLabel:(RRConnectionType)type {
    switch (type) {
        case RRConnectionTypeWiFi:
            return @"wifi / 无线";
        case RRConnectionTypeCellular:
            return @"cellular / 蜂窝";
        case RRConnectionTypeWired:
            return @"wired / 有线";
        case RRConnectionTypeOther:
            return @"other / 其他";
        case RRConnectionTypeNone:
        default:
            return @"none / 无";
    }
}

- (NSString *)modeLabel:(RRProbeMode)mode {
    switch (mode) {
        case RRProbeModeParallel:
            return @"parallel / 并行";
        case RRProbeModeHTTPOnly:
            return @"httpOnly / 仅HTTP";
        case RRProbeModeICMPOnly:
            return @"icmpOnly / 仅ICMP";
    }
}

- (NSString *)sourceLabel:(NSString *)source {
    if ([source isEqualToString:@"initial"]) {
        return @"INIT";
    }
    if ([source isEqualToString:@"check"]) {
        return @"CHECK";
    }
    if ([source isEqualToString:@"stream"]) {
        return @"STREAM";
    }
    return source.uppercaseString;
}

- (void)appendLogWithSource:(NSString *)source english:(NSString *)english chinese:(NSString *)chinese {
    [self appendLog:[NSString stringWithFormat:@"[%@] %@ | %@", source, english, chinese]];
}

- (void)appendLog:(NSString *)message {
    NSString *timestamp = [self.dateFormatter stringFromDate:[NSDate date]];
    NSString *line = [NSString stringWithFormat:@"[%@] %@", timestamp, message];
    [self.logLines addObject:line];

    static const NSUInteger maxLines = 200;
    if (self.logLines.count > maxLines) {
        NSRange overflow = NSMakeRange(0, self.logLines.count - maxLines);
        [self.logLines removeObjectsInRange:overflow];
    }

    self.logTextView.text = [self.logLines componentsJoinedByString:@"\n"];
    if (self.logTextView.text.length > 0) {
        NSRange range = NSMakeRange(self.logTextView.text.length - 1, 1);
        [self.logTextView scrollRangeToVisible:range];
    }
}

- (void)updateButtonState {
    self.checkOnceButton.enabled = !self.checking;
    self.startMonitorButton.enabled = !self.monitoring;
    self.stopMonitorButton.enabled = self.monitoring;
}

- (void)stopMonitoringInternal {
    [[RRReachability sharedInstance] stopNotifier];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kRRReachabilityChangedNotification object:[RRReachability sharedInstance]];
    self.monitoring = NO;
}

@end
