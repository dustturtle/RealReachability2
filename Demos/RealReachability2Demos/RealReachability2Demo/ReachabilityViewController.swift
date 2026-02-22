import UIKit
import RealReachability2

final class ReachabilityViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stackView = UIStackView()

    private let statusValueLabel = UILabel()
    private let connectionValueLabel = UILabel()
    private let updatedValueLabel = UILabel()

    private let modeSegmentedControl = UISegmentedControl(items: ["并行", "HTTP", "ICMP"])
    private let timeoutField = UITextField()
    private let httpURLField = UITextField()
    private let icmpHostField = UITextField()
    private let periodicProbeSwitch = UISwitch()
    private let allowCellularFallbackSwitch = UISwitch()

    private let applyConfigButton = UIButton(type: .system)
    private let checkOnceButton = UIButton(type: .system)
    private let startMonitorButton = UIButton(type: .system)
    private let stopMonitorButton = UIButton(type: .system)
    private let clearLogsButton = UIButton(type: .system)

    private let logTextView = UITextView()

    private var monitorTask: Task<Void, Never>?
    private var isChecking = false

    private var logLines: [String] = []
    private let maxLogLines = 200

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    deinit {
        stopMonitoringInternal()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "RealReachability2 Demo (Swift / 双语)"
        view.backgroundColor = .systemBackground

        buildUI()
        loadConfigurationIntoForm()
        handleStatus(.unknown, secondaryReachable: false, source: "initial")
        appendLog(source: "INIT", english: "Demo loaded.", chinese: "演示页面已加载。")
        updateButtonState()
    }

    private func buildUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])

        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.spacing = 12

        stackView.addArrangedSubview(makeKeyValueRow(title: "Status / 状态", valueLabel: statusValueLabel))
        stackView.addArrangedSubview(makeKeyValueRow(title: "Connection / 连接", valueLabel: connectionValueLabel))
        stackView.addArrangedSubview(makeKeyValueRow(title: "Updated / 更新时间", valueLabel: updatedValueLabel))

        let modeContainer = makeLabeledContainer(title: "Probe Mode / 探测模式", content: modeSegmentedControl)
        modeSegmentedControl.selectedSegmentIndex = 0
        stackView.addArrangedSubview(modeContainer)

        configureTextField(timeoutField, placeholder: "5.0")
        timeoutField.keyboardType = .decimalPad
        stackView.addArrangedSubview(makeLabeledContainer(title: "Timeout (s) / 超时(秒)", content: timeoutField))

        configureTextField(httpURLField, placeholder: "https://www.gstatic.com/generate_204")
        httpURLField.keyboardType = .URL
        httpURLField.autocapitalizationType = .none
        stackView.addArrangedSubview(makeLabeledContainer(title: "HTTP Probe URL / HTTP 探测地址", content: httpURLField))

        configureTextField(icmpHostField, placeholder: "8.8.8.8")
        icmpHostField.autocapitalizationType = .none
        stackView.addArrangedSubview(makeLabeledContainer(title: "ICMP Host / ICMP 主机", content: icmpHostField))

        stackView.addArrangedSubview(makeSwitchRow(title: "Periodic Probe / 周期探测", toggle: periodicProbeSwitch))
        stackView.addArrangedSubview(makeSwitchRow(title: "Allow Cellular Fallback / 允许蜂窝兜底", toggle: allowCellularFallbackSwitch))

        applyConfigButton.setTitle("Apply / 应用", for: .normal)
        applyConfigButton.addTarget(self, action: #selector(applyConfigTapped), for: .touchUpInside)

        checkOnceButton.setTitle("Check Once / 单次检测", for: .normal)
        checkOnceButton.addTarget(self, action: #selector(checkOnceTapped), for: .touchUpInside)

        startMonitorButton.setTitle("Start / 开始监听", for: .normal)
        startMonitorButton.addTarget(self, action: #selector(startMonitorTapped), for: .touchUpInside)

        stopMonitorButton.setTitle("Stop / 停止监听", for: .normal)
        stopMonitorButton.addTarget(self, action: #selector(stopMonitorTapped), for: .touchUpInside)

        clearLogsButton.setTitle("Clear / 清空日志", for: .normal)
        clearLogsButton.addTarget(self, action: #selector(clearLogsTapped), for: .touchUpInside)

        let buttonRow1 = UIStackView(arrangedSubviews: [applyConfigButton, checkOnceButton])
        buttonRow1.axis = .horizontal
        buttonRow1.distribution = .fillEqually
        buttonRow1.spacing = 8

        let buttonRow2 = UIStackView(arrangedSubviews: [startMonitorButton, stopMonitorButton, clearLogsButton])
        buttonRow2.axis = .horizontal
        buttonRow2.distribution = .fillEqually
        buttonRow2.spacing = 8

        stackView.addArrangedSubview(buttonRow1)
        stackView.addArrangedSubview(buttonRow2)

        let logsTitle = UILabel()
        logsTitle.text = "Logs / 日志"
        logsTitle.font = .preferredFont(forTextStyle: .headline)
        stackView.addArrangedSubview(logsTitle)

        logTextView.isEditable = false
        logTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logTextView.layer.borderWidth = 1
        logTextView.layer.borderColor = UIColor.systemGray4.cgColor
        logTextView.layer.cornerRadius = 8
        logTextView.heightAnchor.constraint(equalToConstant: 240).isActive = true
        stackView.addArrangedSubview(logTextView)
    }

    private func makeKeyValueRow(title: String, valueLabel: UILabel) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .body)

        valueLabel.font = .preferredFont(forTextStyle: .body)
        valueLabel.textAlignment = .right
        valueLabel.textColor = .secondaryLabel

        let row = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .fill
        row.spacing = 8

        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return row
    }

    private func makeLabeledContainer(title: String, content: UIView) -> UIView {
        let container = UIView()
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.textColor = .secondaryLabel

        container.addSubview(titleLabel)
        container.addSubview(content)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            content.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            content.heightAnchor.constraint(equalToConstant: 36)
        ])

        return container
    }

    private func makeSwitchRow(title: String, toggle: UISwitch) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .body)

        let row = UIStackView(arrangedSubviews: [titleLabel, toggle])
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .fill
        row.spacing = 8

        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        return row
    }

    private func configureTextField(_ textField: UITextField, placeholder: String) {
        textField.borderStyle = .roundedRect
        textField.placeholder = placeholder
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
    }

    private func loadConfigurationIntoForm() {
        let config = RealReachability.shared.configuration
        switch config.probeMode {
        case .parallel:
            modeSegmentedControl.selectedSegmentIndex = 0
        case .httpOnly:
            modeSegmentedControl.selectedSegmentIndex = 1
        case .icmpOnly:
            modeSegmentedControl.selectedSegmentIndex = 2
        }

        timeoutField.text = String(format: "%.2f", config.timeout)
        httpURLField.text = config.httpProbeURL.absoluteString
        icmpHostField.text = config.icmpHost
        periodicProbeSwitch.isOn = config.periodicProbeEnabled
        allowCellularFallbackSwitch.isOn = config.allowCellularFallback
    }

    @objc
    private func applyConfigTapped() {
        _ = applyConfigurationFromInput()
    }

    @objc
    private func checkOnceTapped() {
        guard !isChecking else { return }

        isChecking = true
        updateButtonState()

        guard applyConfigurationFromInput() else {
            isChecking = false
            updateButtonState()
            return
        }

        appendLog(source: "CHECK", english: "Running one-time check...", chinese: "正在执行单次检测...")

        Task { [weak self] in
            guard let self else { return }
            let status = await RealReachability.shared.check()
            let secondaryReachable = RealReachability.shared.isSecondaryReachable

            await MainActor.run {
                self.handleStatus(status, secondaryReachable: secondaryReachable, source: "check")
                self.isChecking = false
                self.updateButtonState()
            }
        }
    }

    @objc
    private func startMonitorTapped() {
        guard monitorTask == nil else {
            appendLog(source: "MONITOR", english: "Monitor is already running.", chinese: "监听已在运行。")
            return
        }

        guard applyConfigurationFromInput() else {
            return
        }

        appendLog(source: "MONITOR", english: "Monitor started.", chinese: "监听已启动。")

        monitorTask = Task { [weak self] in
            guard let self else { return }
            for await status in RealReachability.shared.statusStream {
                if Task.isCancelled {
                    break
                }

                let secondaryReachable = RealReachability.shared.isSecondaryReachable
                await MainActor.run {
                    self.handleStatus(status, secondaryReachable: secondaryReachable, source: "stream")
                }
            }
        }

        updateButtonState()
    }

    @objc
    private func stopMonitorTapped() {
        guard monitorTask != nil else {
            RealReachability.shared.stopNotifier()
            appendLog(source: "MONITOR", english: "Monitor is not running.", chinese: "监听当前未运行。")
            return
        }

        stopMonitoringInternal()
        appendLog(source: "MONITOR", english: "Monitor stopped.", chinese: "监听已停止。")
        updateButtonState()
    }

    @objc
    private func clearLogsTapped() {
        logLines.removeAll()
        logTextView.text = ""
    }

    private func applyConfigurationFromInput() -> Bool {
        let previous = RealReachability.shared.configuration

        let mode: ProbeMode
        switch modeSegmentedControl.selectedSegmentIndex {
        case 1:
            mode = .httpOnly
        case 2:
            mode = .icmpOnly
        default:
            mode = .parallel
        }

        let allowCellularFallback = allowCellularFallbackSwitch.isOn
        if allowCellularFallback && mode == .icmpOnly {
            appendLog(
                source: "CONFIG",
                english: "Invalid config: allowCellularFallback requires HTTP participation (parallel/httpOnly).",
                chinese: "配置无效：allowCellularFallback 必须包含 HTTP 探测（并行或仅HTTP模式）。"
            )
            return false
        }

        let timeout: TimeInterval
        if let raw = timeoutField.text, let parsed = Double(raw), parsed > 0 {
            timeout = parsed
        } else {
            timeout = previous.timeout
            timeoutField.text = String(format: "%.2f", timeout)
            appendLog(
                source: "CONFIG",
                english: "Invalid timeout. Keep previous value \(String(format: "%.2f", timeout)).",
                chinese: "超时输入无效，沿用之前的值 \(String(format: "%.2f", timeout))。"
            )
        }

        let url: URL
        if let raw = httpURLField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let parsed = URL(string: raw),
           parsed.scheme != nil {
            url = parsed
        } else {
            url = previous.httpProbeURL
            httpURLField.text = url.absoluteString
            appendLog(
                source: "CONFIG",
                english: "Invalid HTTP URL. Keep previous value \(url.absoluteString).",
                chinese: "HTTP 地址无效，沿用之前的值 \(url.absoluteString)。"
            )
        }

        let host: String
        let rawHost = icmpHostField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if rawHost.isEmpty {
            host = previous.icmpHost
            icmpHostField.text = host
            appendLog(
                source: "CONFIG",
                english: "ICMP host is empty. Keep previous value \(host).",
                chinese: "ICMP 主机为空，沿用之前的值 \(host)。"
            )
        } else {
            host = rawHost
        }

        let config = ReachabilityConfiguration(
            probeMode: mode,
            timeout: timeout,
            httpProbeURL: url,
            icmpHost: host,
            icmpPort: previous.icmpPort,
            periodicProbeEnabled: periodicProbeSwitch.isOn,
            allowCellularFallback: allowCellularFallback
        )

        RealReachability.shared.configuration = config
        appendLog(
            source: "CONFIG",
            english: "Applied config: mode=\(modeLabel(mode)), timeout=\(String(format: "%.2f", timeout)), url=\(url.absoluteString), host=\(host), periodicProbe=\(periodicProbeSwitch.isOn ? "ON" : "OFF"), allowCellularFallback=\(allowCellularFallback ? "ON" : "OFF")",
            chinese: "已应用配置：模式=\(modeLabel(mode))，超时=\(String(format: "%.2f", timeout))，URL=\(url.absoluteString)，主机=\(host)，周期探测=\(periodicProbeSwitch.isOn ? "开" : "关")，蜂窝兜底=\(allowCellularFallback ? "开" : "关")"
        )

        return true
    }

    private func handleStatus(_ status: ReachabilityStatus, secondaryReachable: Bool, source: String) {
        let statusText = statusLabel(status, secondaryReachable: secondaryReachable)
        let connectionText: String

        switch status {
        case .reachable(let connectionType):
            connectionText = connectionLabel(for: connectionType)
        case .notReachable, .unknown:
            connectionText = "none / 无"
        }

        statusValueLabel.text = statusText
        connectionValueLabel.text = connectionText
        updatedValueLabel.text = dateFormatter.string(from: Date())

        appendLog(
            source: sourceLabel(source),
            english: "status=\(statusText), connection=\(connectionText), secondaryFallback=\(secondaryReachable ? "YES" : "NO")",
            chinese: "状态=\(statusText)，连接=\(connectionText)，副链路兜底=\(secondaryReachable ? "是" : "否")"
        )
    }

    private func statusLabel(_ status: ReachabilityStatus, secondaryReachable: Bool) -> String {
        switch status {
        case .reachable:
            if secondaryReachable {
                return "reachable (secondary fallback) / 可达（副链路兜底）"
            }
            return "reachable / 可达"
        case .notReachable:
            return "notReachable / 不可达"
        case .unknown:
            return "unknown / 未知"
        }
    }

    private func connectionLabel(for type: ConnectionType) -> String {
        switch type {
        case .wifi:
            return "wifi / 无线"
        case .cellular:
            return "cellular / 蜂窝"
        case .wired:
            return "wired / 有线"
        case .other:
            return "other / 其他"
        }
    }

    private func modeLabel(_ mode: ProbeMode) -> String {
        switch mode {
        case .parallel:
            return "parallel / 并行"
        case .httpOnly:
            return "httpOnly / 仅HTTP"
        case .icmpOnly:
            return "icmpOnly / 仅ICMP"
        }
    }

    private func sourceLabel(_ source: String) -> String {
        switch source {
        case "initial":
            return "INIT"
        case "check":
            return "CHECK"
        case "stream":
            return "STREAM"
        default:
            return source.uppercased()
        }
    }

    private func appendLog(source: String, english: String, chinese: String) {
        appendLog("[\(source)] \(english) | \(chinese)")
    }

    private func appendLog(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)"
        NSLog("%@", line)
        logLines.append(line)

        if logLines.count > maxLogLines {
            logLines.removeFirst(logLines.count - maxLogLines)
        }

        logTextView.text = logLines.joined(separator: "\n")
        if !logTextView.text.isEmpty {
            let range = NSRange(location: max(logTextView.text.count - 1, 0), length: 1)
            logTextView.scrollRangeToVisible(range)
        }
    }

    private func updateButtonState() {
        checkOnceButton.isEnabled = !isChecking
        startMonitorButton.isEnabled = monitorTask == nil
        stopMonitorButton.isEnabled = monitorTask != nil
    }

    private func stopMonitoringInternal() {
        monitorTask?.cancel()
        monitorTask = nil
        RealReachability.shared.stopNotifier()
        updateButtonState()
    }
}
