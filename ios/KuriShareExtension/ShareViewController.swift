import UIKit
import UniformTypeIdentifiers
import KuriCore
import KuriStore
import KuriObservability

final class ShareViewController: UIViewController {
    private let dimmingView = UIView()
    private let sheetContainer = UIView()
    private let headerView = UIView()
    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let contentStack = UIStackView()

    private let sourceSectionLabel = UILabel()
    private let sourceRowView = UIView()
    private let sourceIconView = UIImageView()
    private let sourceValueLabel = UILabel()

    private let taxonomySectionLabel = UILabel()
    private let taxonomyContainer = UIView()
    private let taxonomyStack = UIStackView()
    private let suggestedTagsView = KuriWrapView()
    private let selectedTagsView = KuriWrapView()
    private let tagsInputField = UITextField()

    private let contextSectionLabel = UILabel()
    private let memoTextView = KuriPlaceholderTextView()

    private let actionContainer = UIView()
    private let actionStack = UIStackView()
    private let saveButton = UIButton(type: .system)
    private let errorLabel = UILabel()
    private let statusRow = UIView()
    private let apiIndicatorView = UIView()
    private let apiStatusLabel = UILabel()
    private let versionLabel = UILabel()

    private var sheetBottomConstraint: NSLayoutConstraint?
    private var suggestedTagsHeightConstraint: NSLayoutConstraint?
    private var selectedTagsHeightConstraint: NSLayoutConstraint?
    private var tagsInputHeightConstraint: NSLayoutConstraint?
    private var loadedPayload: SharedPayload?
    private var payloadTask: Task<SharedPayload, Error>?
    private var suggestedTags: [SuggestedTag] = SuggestedTag.defaultSeedTags
    private var selectedSuggestedTags: Set<String> = []
    private var manualTags: [String] = []

    private lazy var performanceMonitor = PerformanceMonitor()
    private lazy var repository: SQLiteCaptureRepository = {
        let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.yona.kuri.shared")!
        return try! StoreEnvironment.makeRepository(baseDirectory: root)
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
        configureStyles()
        configureActions()
        registerKeyboardObservers()
        bindInitialPayloadPreview()
        loadSuggestedTags()
        refreshTaxonomyPresentation()
        refreshFooterStatus()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateSheetShadow()
        updateTaxonomyHeightsIfNeeded()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureHierarchy() {
        view.backgroundColor = .clear

        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dimmingView)

        sheetContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sheetContainer)

        headerView.translatesAutoresizingMaskIntoConstraints = false
        sheetContainer.addSubview(headerView)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(closeButton)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(titleLabel)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        sheetContainer.addSubview(scrollView)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = KuriMetrics.sectionSpacing
        contentView.addSubview(contentStack)

        let sourceSection = makeSection(label: sourceSectionLabel, body: sourceRowView)
        let taxonomySection = makeSection(label: taxonomySectionLabel, body: taxonomyContainer)
        let contextSection = makeSection(label: contextSectionLabel, body: memoTextView)
        [sourceSection, taxonomySection, contextSection].forEach { contentStack.addArrangedSubview($0) }

        sourceIconView.translatesAutoresizingMaskIntoConstraints = false
        sourceRowView.addSubview(sourceIconView)

        sourceValueLabel.translatesAutoresizingMaskIntoConstraints = false
        sourceRowView.addSubview(sourceValueLabel)

        taxonomyContainer.translatesAutoresizingMaskIntoConstraints = false
        taxonomyContainer.addSubview(taxonomyStack)

        taxonomyStack.translatesAutoresizingMaskIntoConstraints = false
        taxonomyStack.axis = .vertical
        taxonomyStack.spacing = KuriSpacing.sm
        [suggestedTagsView, selectedTagsView, tagsInputField].forEach { taxonomyStack.addArrangedSubview($0) }

        actionContainer.translatesAutoresizingMaskIntoConstraints = false
        sheetContainer.addSubview(actionContainer)

        actionStack.translatesAutoresizingMaskIntoConstraints = false
        actionStack.axis = .vertical
        actionStack.spacing = 12
        actionContainer.addSubview(actionStack)
        [saveButton, errorLabel, statusRow].forEach { actionStack.addArrangedSubview($0) }

        statusRow.translatesAutoresizingMaskIntoConstraints = false
        statusRow.addSubview(apiIndicatorView)
        statusRow.addSubview(apiStatusLabel)
        statusRow.addSubview(versionLabel)

        apiIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        apiStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        versionLabel.translatesAutoresizingMaskIntoConstraints = false

        sheetBottomConstraint = sheetContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)

        NSLayoutConstraint.activate([
            dimmingView.topAnchor.constraint(equalTo: view.topAnchor),
            dimmingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            sheetContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: KuriMetrics.sheetHorizontalInset),
            sheetContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -KuriMetrics.sheetHorizontalInset),
            sheetBottomConstraint!,
            sheetContainer.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.76),
            sheetContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 420),

            headerView.topAnchor.constraint(equalTo: sheetContainer.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: sheetContainer.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: sheetContainer.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: KuriMetrics.headerHeight),

            closeButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: KuriSpacing.lg),
            closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -KuriSpacing.lg),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            actionContainer.leadingAnchor.constraint(equalTo: sheetContainer.leadingAnchor),
            actionContainer.trailingAnchor.constraint(equalTo: sheetContainer.trailingAnchor),
            actionContainer.bottomAnchor.constraint(equalTo: sheetContainer.bottomAnchor),

            actionStack.topAnchor.constraint(equalTo: actionContainer.topAnchor, constant: 14),
            actionStack.leadingAnchor.constraint(equalTo: actionContainer.leadingAnchor, constant: KuriSpacing.lg),
            actionStack.trailingAnchor.constraint(equalTo: actionContainer.trailingAnchor, constant: -KuriSpacing.lg),
            actionStack.bottomAnchor.constraint(equalTo: actionContainer.bottomAnchor, constant: -18),

            saveButton.heightAnchor.constraint(equalToConstant: KuriMetrics.primaryButtonHeight),

            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: sheetContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: sheetContainer.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: actionContainer.topAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: KuriSpacing.lg),
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: KuriSpacing.lg),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -KuriSpacing.lg),
            contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -KuriSpacing.lg),

            sourceRowView.heightAnchor.constraint(equalToConstant: 54),
            sourceIconView.leadingAnchor.constraint(equalTo: sourceRowView.leadingAnchor, constant: 16),
            sourceIconView.centerYAnchor.constraint(equalTo: sourceRowView.centerYAnchor),
            sourceIconView.widthAnchor.constraint(equalToConstant: 16),
            sourceIconView.heightAnchor.constraint(equalToConstant: 16),
            sourceValueLabel.leadingAnchor.constraint(equalTo: sourceIconView.trailingAnchor, constant: 12),
            sourceValueLabel.trailingAnchor.constraint(equalTo: sourceRowView.trailingAnchor, constant: -14),
            sourceValueLabel.centerYAnchor.constraint(equalTo: sourceRowView.centerYAnchor),

            taxonomyStack.topAnchor.constraint(equalTo: taxonomyContainer.topAnchor, constant: 12),
            taxonomyStack.leadingAnchor.constraint(equalTo: taxonomyContainer.leadingAnchor, constant: 12),
            taxonomyStack.trailingAnchor.constraint(equalTo: taxonomyContainer.trailingAnchor, constant: -12),
            taxonomyStack.bottomAnchor.constraint(equalTo: taxonomyContainer.bottomAnchor, constant: -12),

            memoTextView.heightAnchor.constraint(equalToConstant: 156),

            apiIndicatorView.leadingAnchor.constraint(equalTo: statusRow.leadingAnchor),
            apiIndicatorView.centerYAnchor.constraint(equalTo: statusRow.centerYAnchor),
            apiIndicatorView.widthAnchor.constraint(equalToConstant: 10),
            apiIndicatorView.heightAnchor.constraint(equalToConstant: 10),

            apiStatusLabel.leadingAnchor.constraint(equalTo: apiIndicatorView.trailingAnchor, constant: 8),
            apiStatusLabel.centerYAnchor.constraint(equalTo: statusRow.centerYAnchor),

            versionLabel.leadingAnchor.constraint(greaterThanOrEqualTo: apiStatusLabel.trailingAnchor, constant: 12),
            versionLabel.trailingAnchor.constraint(equalTo: statusRow.trailingAnchor),
            versionLabel.centerYAnchor.constraint(equalTo: statusRow.centerYAnchor),
            versionLabel.topAnchor.constraint(equalTo: statusRow.topAnchor),
            versionLabel.bottomAnchor.constraint(equalTo: statusRow.bottomAnchor)
        ])

        suggestedTagsHeightConstraint = suggestedTagsView.heightAnchor.constraint(equalToConstant: 0)
        selectedTagsHeightConstraint = selectedTagsView.heightAnchor.constraint(equalToConstant: 0)
        tagsInputHeightConstraint = tagsInputField.heightAnchor.constraint(equalToConstant: 0)
        suggestedTagsHeightConstraint?.isActive = true
        selectedTagsHeightConstraint?.isActive = true
        tagsInputHeightConstraint?.isActive = true
    }

    private func configureStyles() {
        dimmingView.backgroundColor = KuriTheme.overlayDim

        sheetContainer.backgroundColor = KuriTheme.surfacePrimary
        sheetContainer.layer.borderWidth = KuriTheme.borderWidth
        sheetContainer.layer.borderColor = KuriTheme.borderSubtle.cgColor

        headerView.backgroundColor = KuriTheme.surfacePrimary
        headerView.layer.borderWidth = KuriTheme.borderWidth
        headerView.layer.borderColor = KuriTheme.borderSubtle.cgColor

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = KuriTheme.inkPrimary

        titleLabel.attributedText = KuriTypography.uppercase("Save", font: KuriTypography.heroTitle, color: KuriTheme.inkPrimary, kern: -0.6)

        sourceSectionLabel.attributedText = KuriTypography.uppercase("Source", font: KuriTypography.sectionLabel, color: KuriTheme.inkMuted, kern: 1)
        sourceRowView.backgroundColor = KuriTheme.surfaceSecondary
        sourceRowView.layer.borderWidth = KuriTheme.borderWidth
        sourceRowView.layer.borderColor = KuriTheme.borderSubtle.cgColor
        sourceIconView.image = UIImage(systemName: "link")
        sourceIconView.tintColor = KuriTheme.inkMuted
        sourceValueLabel.font = KuriTypography.mono
        sourceValueLabel.textColor = KuriTheme.inkPrimary
        sourceValueLabel.lineBreakMode = .byTruncatingTail

        taxonomySectionLabel.attributedText = KuriTypography.uppercase("Taxonomy", font: KuriTypography.sectionLabel, color: KuriTheme.inkMuted, kern: 1)
        taxonomyContainer.backgroundColor = .clear
        taxonomyContainer.layer.borderWidth = KuriTheme.borderWidth
        taxonomyContainer.layer.borderColor = KuriTheme.borderSubtle.cgColor

        suggestedTagsView.itemSpacing = KuriSpacing.sm
        suggestedTagsView.rowSpacing = KuriSpacing.sm
        selectedTagsView.itemSpacing = KuriSpacing.sm
        selectedTagsView.rowSpacing = KuriSpacing.sm

        tagsInputField.autocorrectionType = .no
        tagsInputField.autocapitalizationType = .words
        tagsInputField.returnKeyType = .done
        tagsInputField.borderStyle = .none
        tagsInputField.backgroundColor = KuriTheme.surfaceSecondary
        tagsInputField.textColor = KuriTheme.inkPrimary
        tagsInputField.tintColor = KuriTheme.inkPrimary
        tagsInputField.font = KuriTypography.bodySmall
        tagsInputField.placeholder = "Type tags, separated by commas"
        tagsInputField.delegate = self
        tagsInputField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        tagsInputField.leftViewMode = .always
        tagsInputField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        tagsInputField.rightViewMode = .always
        tagsInputField.layer.borderWidth = KuriTheme.borderWidth
        tagsInputField.layer.borderColor = KuriTheme.borderSubtle.cgColor
        tagsInputField.alpha = 0.02

        contextSectionLabel.attributedText = KuriTypography.uppercase("Context Log", font: KuriTypography.sectionLabel, color: KuriTheme.inkMuted, kern: 1)
        memoTextView.backgroundColor = .white
        memoTextView.layer.borderWidth = KuriTheme.borderWidth
        memoTextView.layer.borderColor = KuriTheme.borderSubtle.cgColor
        memoTextView.textColor = KuriTheme.inkPrimary
        memoTextView.font = KuriTypography.body
        memoTextView.placeholderText = "Add context to this capture..."
        memoTextView.textContainerInset = UIEdgeInsets(top: 16, left: 14, bottom: 16, right: 14)

        actionContainer.backgroundColor = KuriTheme.surfacePrimary
        actionContainer.layer.borderWidth = KuriTheme.borderWidth
        actionContainer.layer.borderColor = KuriTheme.borderSubtle.cgColor

        saveButton.setTitle("SAVE", for: .normal)
        saveButton.setImage(UIImage(systemName: "arrow.right"), for: .normal)
        saveButton.semanticContentAttribute = .forceRightToLeft
        saveButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: -16)
        saveButton.tintColor = KuriTheme.surfacePrimary
        saveButton.titleLabel?.font = KuriTypography.button
        saveButton.setTitleColor(KuriTheme.surfacePrimary, for: .normal)
        saveButton.backgroundColor = KuriTheme.inkPrimary
        saveButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24)
        saveButton.layer.borderWidth = KuriTheme.borderWidth
        saveButton.layer.borderColor = KuriTheme.inkPrimary.cgColor
        saveButton.configurationUpdateHandler = { button in
            button.backgroundColor = button.isEnabled ? KuriTheme.inkPrimary.withAlphaComponent(button.isHighlighted ? 0.88 : 1) : KuriTheme.inkPrimary.withAlphaComponent(0.45)
        }

        errorLabel.font = KuriTypography.caption
        errorLabel.textColor = KuriTheme.accentError
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true

        apiIndicatorView.layer.cornerRadius = 5

        apiStatusLabel.font = KuriTypography.mono
        apiStatusLabel.textColor = KuriTheme.inkMuted

        versionLabel.font = KuriTypography.mono
        versionLabel.textAlignment = .right
        versionLabel.textColor = KuriTheme.inkMuted
        versionLabel.text = "KURI V\(bundleVersionString)"

        scrollView.showsVerticalScrollIndicator = false
        scrollView.keyboardDismissMode = .interactive
    }

    private func configureActions() {
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        tagsInputField.addTarget(self, action: #selector(tagsDidChange), for: .editingChanged)

        let taxonomyTap = UITapGestureRecognizer(target: self, action: #selector(focusTagsInput))
        taxonomyTap.cancelsTouchesInView = false
        taxonomyContainer.addGestureRecognizer(taxonomyTap)
    }

    private func registerKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardNotification(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardNotification(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    private func bindInitialPayloadPreview() {
        sourceValueLabel.text = "Loading source..."
        let task = ensurePayloadTask()

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let payload = try await task.value
                loadedPayload = payload
                sourceValueLabel.text = sourcePreviewText(for: payload)
            } catch {
                sourceValueLabel.text = "No source detected"
            }
        }
    }

    private func ensurePayloadTask() -> Task<SharedPayload, Error> {
        if let payloadTask {
            return payloadTask
        }

        let task = Task {
            try await SharedPayloadLoader(inputItems: extensionContext?.inputItems ?? []).load()
        }
        payloadTask = task
        return task
    }

    private func loadSuggestedTags() {
        if let recentTags = try? repository.recentTags(limit: 6), !recentTags.isEmpty {
            suggestedTags = recentTags.map {
                let normalized = normalizedTag($0.name)
                return SuggestedTag(title: suggestedTitle(for: $0.name, normalized: normalized), normalized: normalized)
            }
        } else {
            suggestedTags = SuggestedTag.defaultSeedTags
        }
    }

    private func sourcePreviewText(for payload: SharedPayload) -> String {
        if let urlString = payload.url?.absoluteString, !urlString.isEmpty {
            return urlString
        }

        if let sharedText = payload.text?.trimmingCharacters(in: .whitespacesAndNewlines), !sharedText.isEmpty {
            return sharedText
        }

        return "No source detected"
    }

    @objc private func closeTapped() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        extensionContext?.cancelRequest(withError: error)
    }

    @objc private func focusTagsInput() {
        tagsInputField.becomeFirstResponder()
        refreshTaxonomyPresentation(animated: true)
    }

    @objc private func tagsDidChange() {
        manualTags = parsedTags(from: tagsInputField.text)
        refreshTaxonomyPresentation()
    }

    @objc private func suggestedTagTapped(_ sender: KuriTagButton) {
        let normalized = sender.tagValue
        if combinedNormalizedTags().contains(normalized) {
            selectedSuggestedTags.remove(normalized)
            manualTags.removeAll { normalizedTag($0) == normalized }
            tagsInputField.text = manualTags.joined(separator: ", ")
        } else {
            selectedSuggestedTags.insert(normalized)
        }
        refreshTaxonomyPresentation()
    }

    private func refreshTaxonomyPresentation(animated: Bool = false) {
        let normalizedSelections = combinedNormalizedTags()

        suggestedTagsView.itemViews = suggestedTags.map { tag in
            let button = KuriTagButton(title: tag.title, normalizedValue: tag.normalized)
            button.setSelectedStyle(normalizedSelections.contains(tag.normalized))
            button.addTarget(self, action: #selector(suggestedTagTapped(_:)), for: .touchUpInside)
            return button
        }

        let selectedLabels = combinedTagEntries().map { KuriTagLabel(text: $0.display) }
        selectedTagsView.itemViews = selectedLabels
        selectedTagsView.isHidden = selectedLabels.isEmpty

        let inputVisible = tagsInputField.isFirstResponder || !(tagsInputField.text ?? "").isEmpty
        tagsInputField.alpha = inputVisible ? 1 : 0.02
        tagsInputHeightConstraint?.constant = inputVisible ? KuriMetrics.inputHeight : 0

        let updateLayout = {
            self.updateTaxonomyHeightsIfNeeded()
            self.updateTaxonomyFocusState(isFocused: self.tagsInputField.isFirstResponder)
            self.view.layoutIfNeeded()
        }

        if animated {
            UIView.animate(withDuration: 0.18, animations: updateLayout)
        } else {
            updateLayout()
        }
    }

    private func updateTaxonomyHeightsIfNeeded() {
        let availableWidth = taxonomyContainer.bounds.width - 24
        guard availableWidth > 0 else { return }

        suggestedTagsHeightConstraint?.constant = max(KuriMetrics.chipHeight, suggestedTagsView.requiredHeight(for: availableWidth))
        let selectedHeight = selectedTagsView.isHidden ? 0 : max(KuriMetrics.chipHeight, selectedTagsView.requiredHeight(for: availableWidth))
        selectedTagsHeightConstraint?.constant = selectedHeight
    }

    private func combinedNormalizedTags() -> Set<String> {
        Set(selectedSuggestedTags).union(manualTags.map(normalizedTag))
    }

    private func combinedTagEntries() -> [TagEntry] {
        let normalizedSelections = combinedNormalizedTags()
        var results: [TagEntry] = []
        var seen: Set<String> = []

        for tag in suggestedTags where normalizedSelections.contains(tag.normalized) && !seen.contains(tag.normalized) {
            results.append(TagEntry(display: tag.title, rawValue: tag.title, normalized: tag.normalized))
            seen.insert(tag.normalized)
        }

        for rawTag in manualTags {
            let normalized = normalizedTag(rawTag)
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            results.append(TagEntry(display: rawTag, rawValue: rawTag, normalized: normalized))
            seen.insert(normalized)
        }

        return results
    }

    private func parsedTags(from rawValue: String?) -> [String] {
        guard let rawValue else { return [] }
        return rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    @objc private func saveTapped() {
        let span = performanceMonitor.begin(.saveTapToLocalCommit)
        setSavingState(true)

        Task { @MainActor in
            do {
                let payload: SharedPayload
                if let loadedPayload {
                    payload = loadedPayload
                } else {
                    payload = try await ensurePayloadTask().value
                    self.loadedPayload = payload
                }

                let sourceApp = SourceApp.detect(from: payload.url, fallbackText: payload.text)
                let draft = CaptureDraft(
                    sourceApp: sourceApp,
                    sourceURL: payload.url,
                    sharedText: payload.text,
                    memo: memoTextView.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    tags: combinedTagEntries().map(\.rawValue),
                    imagePayloads: payload.images
                )
                _ = try repository.save(draft)
                _ = span.end()
                let uiSpan = performanceMonitor.begin(.saveTapToSuccessUI)
                _ = uiSpan.end()
                extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            } catch {
                setSavingState(false)
                showError(error.localizedDescription)
            }
        }
    }

    private func setSavingState(_ isSaving: Bool) {
        saveButton.isEnabled = !isSaving
        closeButton.isEnabled = !isSaving
        errorLabel.isHidden = true
        saveButton.setTitle(isSaving ? "SAVING" : "SAVE", for: .normal)
    }

    private func showError(_ message: String) {
        errorLabel.text = message
        errorLabel.isHidden = false
    }

    private func refreshFooterStatus() {
        let snapshot = try? repository.snapshot()
        let isOnline = snapshot?.sessionToken != nil && snapshot?.databaseID != nil
        apiIndicatorView.backgroundColor = isOnline ? KuriTheme.accentSuccess : KuriTheme.inkMuted
        apiStatusLabel.text = isOnline ? "API: ONLINE" : "API: OFFLINE"
    }

    private var bundleVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return version
    }

    @objc private func handleKeyboardNotification(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
            let curveRaw = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
        else {
            return
        }

        let keyboardFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
        let convertedFrame = view.convert(keyboardFrame, from: nil)
        let overlap = max(0, view.bounds.maxY - convertedFrame.minY - view.safeAreaInsets.bottom)
        let bottomOffset = overlap == 0 ? 0 : -(overlap + 8)

        sheetBottomConstraint?.constant = bottomOffset
        scrollView.contentInset.bottom = overlap + 24
        scrollView.verticalScrollIndicatorInsets.bottom = overlap + 24

        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: UIView.AnimationOptions(rawValue: curveRaw << 16),
            animations: {
                self.view.layoutIfNeeded()
            }
        )
    }

    private func updateTaxonomyFocusState(isFocused: Bool) {
        taxonomyContainer.layer.borderColor = (isFocused ? KuriTheme.inkPrimary : KuriTheme.borderSubtle).cgColor
        tagsInputField.layer.borderColor = (isFocused ? KuriTheme.inkPrimary : KuriTheme.borderSubtle).cgColor
    }

    private func updateSheetShadow() {
        sheetContainer.layer.shadowColor = UIColor.black.cgColor
        sheetContainer.layer.shadowOpacity = KuriTheme.sheetShadowOpacity
        sheetContainer.layer.shadowRadius = KuriTheme.sheetShadowRadius
        sheetContainer.layer.shadowOffset = KuriTheme.sheetShadowOffset
        sheetContainer.layer.shadowPath = UIBezierPath(rect: sheetContainer.bounds).cgPath
    }

    private func makeSection(label: UILabel, body: UIView) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: [label, body])
        stack.axis = .vertical
        stack.spacing = KuriSpacing.sm
        return stack
    }

    private func normalizedTag(_ rawValue: String) -> String {
        rawValue
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func suggestedTitle(for rawValue: String, normalized: String) -> String {
        SuggestedTag.defaultSeedTags.first(where: { $0.normalized == normalized })?.title
            ?? rawValue
                .split(whereSeparator: \.isWhitespace)
                .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
                .joined(separator: " ")
    }
}

extension ShareViewController: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        refreshTaxonomyPresentation(animated: true)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        refreshTaxonomyPresentation(animated: true)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

private struct SharedPayload {
    let url: URL?
    let text: String?
    let images: [PendingImage]
}

@MainActor
private struct SharedPayloadLoader {
    let inputItems: [Any]

    func load() async throws -> SharedPayload {
        var foundURL: URL?
        var foundText: String?
        var images: [PendingImage] = []

        for case let extensionItem as NSExtensionItem in inputItems {
            for provider in extensionItem.attachments ?? [] {
                if foundURL == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    foundURL = try await provider.loadURL()
                }
                if foundText == nil, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    foundText = try await provider.loadText()
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier), let image = try await provider.loadImageData() {
                    images.append(image)
                }
            }
        }

        return SharedPayload(url: foundURL, text: foundText, images: images)
    }
}

@MainActor
private extension NSItemProvider {
    func loadURL() async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: item as? URL)
                }
            }
        }
    }

    func loadText() async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let text = item as? String {
                    continuation.resume(returning: text)
                } else if let textURL = item as? URL {
                    continuation.resume(returning: try? String(contentsOf: textURL))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func loadImageData() async throws -> PendingImage? {
        try await withCheckedThrowingContinuation { continuation in
            loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url = item as? URL, let data = try? Data(contentsOf: url) {
                    continuation.resume(returning: PendingImage(suggestedFilename: url.lastPathComponent, data: data))
                } else if let image = item as? UIImage, let data = image.pngData() {
                    continuation.resume(returning: PendingImage(suggestedFilename: "shared-image.png", data: data))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

private struct SuggestedTag {
    let title: String
    let normalized: String

    static let defaultSeedTags: [SuggestedTag] = [
        SuggestedTag(title: "Architecture", normalized: "architecture"),
        SuggestedTag(title: "Frontend", normalized: "frontend"),
        SuggestedTag(title: "Backend", normalized: "backend"),
        SuggestedTag(title: "DevOps", normalized: "devops"),
        SuggestedTag(title: "AI", normalized: "ai"),
        SuggestedTag(title: "Product", normalized: "product")
    ]
}

private struct TagEntry {
    let display: String
    let rawValue: String
    let normalized: String
}
