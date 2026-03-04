import UIKit

final class KuriWrapView: UIView {
    var itemViews: [UIView] = [] {
        didSet {
            oldValue.forEach { $0.removeFromSuperview() }
            itemViews.forEach { addSubview($0) }
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    var itemSpacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func requiredHeight(for width: CGFloat) -> CGFloat {
        guard width > 0, !itemViews.isEmpty else { return 0 }

        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for view in itemViews {
            let size = view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            if currentX > 0, currentX + size.width > width {
                currentX = 0
                currentY += rowHeight + rowSpacing
                rowHeight = 0
            }
            view.frame = CGRect(origin: CGPoint(x: currentX, y: currentY), size: size)
            currentX += size.width + itemSpacing
            rowHeight = max(rowHeight, size.height)
        }

        return currentY + rowHeight
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        _ = requiredHeight(for: bounds.width)
    }
}

class KuriPaddingLabel: UILabel {
    var insets = UIEdgeInsets(top: 11, left: 14, bottom: 11, right: 14)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}

final class KuriTagButton: UIButton {
    private let normalizedValue: String

    init(title: String, normalizedValue: String) {
        self.normalizedValue = normalizedValue
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        titleLabel?.font = KuriTypography.button
        titleLabel?.adjustsFontSizeToFitWidth = true
        layer.borderWidth = KuriTheme.borderWidth
        layer.borderColor = KuriTheme.borderSubtle.cgColor
        contentEdgeInsets = UIEdgeInsets(top: 11, left: 16, bottom: 11, right: 16)
        setTitle(title.uppercased(), for: .normal)
        setTitleColor(KuriTheme.inkPrimary, for: .normal)
        backgroundColor = .clear
        adjustsImageWhenHighlighted = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSelectedStyle(_ isSelected: Bool) {
        backgroundColor = isSelected ? KuriTheme.inkPrimary : .clear
        setTitleColor(isSelected ? KuriTheme.surfacePrimary : KuriTheme.inkPrimary, for: .normal)
        layer.borderColor = (isSelected ? KuriTheme.inkPrimary : KuriTheme.borderSubtle).cgColor
    }

    var tagValue: String {
        normalizedValue
    }
}

final class KuriTagLabel: KuriPaddingLabel {
    init(text: String) {
        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.text = text.uppercased()
        font = KuriTypography.caption
        textColor = KuriTheme.surfacePrimary
        backgroundColor = KuriTheme.inkPrimary
        layer.borderWidth = KuriTheme.borderWidth
        layer.borderColor = KuriTheme.inkPrimary.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class KuriPlaceholderTextView: UITextView {
    private let placeholderLabel = UILabel()

    var placeholderText: String = "" {
        didSet {
            placeholderLabel.text = placeholderText
        }
    }

    override var text: String! {
        didSet {
            updatePlaceholderVisibility()
        }
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.font = KuriTypography.body
        placeholderLabel.textColor = KuriTheme.inkMuted
        placeholderLabel.numberOfLines = 0
        addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -18)
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChangeNotification),
            name: UITextView.textDidChangeNotification,
            object: self
        )
        updatePlaceholderVisibility()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func textDidChangeNotification() {
        updatePlaceholderVisibility()
    }

    private func updatePlaceholderVisibility() {
        let currentText = text ?? ""
        placeholderLabel.isHidden = !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
