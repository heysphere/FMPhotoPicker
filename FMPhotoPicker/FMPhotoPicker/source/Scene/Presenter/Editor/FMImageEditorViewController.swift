//
//  FMImageEditorViewController.swift
//  FMPhotoPicker
//
//  Created by c-nguyen on 2018/02/27.
//  Copyright © 2018 Tribal Media House. All rights reserved.
//

import UIKit

let kContentFrameSpacing: CGFloat = 22.0

// MARK: - Delegate protocol

public protocol FMImageEditorViewControllerDelegate: class {
    func fmImageEditorViewController(_ editor: FMImageEditorViewController, didFinishEdittingPhotoWith photo: UIImage)
}

public class FMImageEditorViewController: UIViewController {
    private weak var headerView: UIView!
    private weak var bottomViewContainer: UIView!
    private weak var subMenuContainer: UIView!

    private weak var cancelButton: UIButton!
    private weak var doneButton: UIButton!

    private weak var filterMenuButton: UIButton!
    private weak var cropMenuButton: UIButton!

    private weak var headerViewTopConstraint: NSLayoutConstraint!
    private weak var bottomViewContainerBottomConstraint: NSLayoutConstraint!

    private weak var menuContainerTopConstraint: NSLayoutConstraint!
    private weak var bottomMenuContainerBottomConstraint: NSLayoutConstraint!

    public var didEndEditting: (@escaping () -> Void) -> Void = { _ in }
    public var delegate: FMImageEditorViewControllerDelegate?

    private let isAnimatedPresent: Bool

    private lazy var filterSubMenuView: FMFiltersMenuView? = {
        guard let availableFilters = config.availableFilters else { return nil }

        let filterSubMenuView = FMFiltersMenuView(
            withImage: originalThumb.resize(toSizeInPixel: kFilterPreviewImageSize),
            appliedFilter: fmPhotoAsset.getAppliedFilter(),
            availableFilters: availableFilters
        )
        filterSubMenuView.didSelectFilter = { [unowned self] filter in
            self.selectedFilter = filter
            FMLoadingView.shared.show()
            DispatchQueue.global(qos: .utility).async {
                let output = filter.filter(image: self.originalImage)
                DispatchQueue.main.sync {
                    self.cropView.image = output
                    FMLoadingView.shared.hide()
                }
            }
        }
        return filterSubMenuView
    }()

    private lazy var cropSubMenuView: FMCropMenuView? = {
        guard let availableCrops = config.availableCrops else { return nil }

        let cropSubMenuView = FMCropMenuView(appliedCrop: selectedCrop, availableCrops: availableCrops, config: config)
        cropSubMenuView.didSelectCrop = { [unowned self] crop in
            self.selectedCrop = crop
            self.cropView.crop = crop
        }
        cropSubMenuView.didReceiveCropControl = { [unowned self] cropControl in
            switch cropControl {
            case .resetAll:
                self.cropView.resetAll()
            case .rotate:
                self.cropView.rotate()
            case .resetFrameWithoutChangeRatio:
                self.cropView.resetFrameWithoutChangeRatio()
            }
        }
        return cropSubMenuView
    }()

    private var cropView: FMCropView!

    public var fmPhotoAsset: FMPhotoAsset

    // the original thumbnail image
    // used to preview filters
    private var originalThumb: UIImage

    // the full size image that is applied filter
    private var filteredImage: UIImage

    // the original image without any filter or crop
    private var originalImage: UIImage

    private var selectedFilter: FMFilterable
    private var selectedCrop: FMCroppable

    private var config: FMPhotoPickerConfig

    // MARK: - Init

    public init(config: FMPhotoPickerConfig, fmPhotoAsset: FMPhotoAsset, filteredImage: UIImage, originalThumb: UIImage) {
        self.config = config

        self.fmPhotoAsset = fmPhotoAsset

        self.originalThumb = originalThumb

        // set to filteredImage until the load original image done
        originalImage = filteredImage

        self.filteredImage = filteredImage

        selectedFilter = fmPhotoAsset.getAppliedFilter()
        selectedCrop = fmPhotoAsset.getAppliedCrop()

        isAnimatedPresent = false

        super.init(nibName: nil, bundle: nil)

        view.backgroundColor = kBackgroundColor

        modalPresentationStyle = .fullScreen
    }

    public init(config: FMPhotoPickerConfig, sourceImage: UIImage) {
        self.config = config

        var forceCropType: FMCroppable?
        if config.forceCropEnabled, let firstCrop = config.availableCrops?.first {
            forceCropType = firstCrop
        }
        let fmPhotoAsset = FMPhotoAsset(sourceImage: sourceImage, forceCropType: forceCropType)
        self.fmPhotoAsset = fmPhotoAsset

        originalThumb = sourceImage

        originalImage = sourceImage
        filteredImage = sourceImage

        selectedFilter = fmPhotoAsset.getAppliedFilter()
        selectedCrop = fmPhotoAsset.getAppliedCrop()

        isAnimatedPresent = true

        super.init(nibName: nil, bundle: nil)

        fmPhotoAsset.requestThumb { image in
            self.originalThumb = image!
        }

        view.backgroundColor = kBackgroundColor

        modalPresentationStyle = .fullScreen
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        view = UIView()
        view.backgroundColor = .white
        setupView()
    }

    // MARK: - Life cycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        if config.availableCrops == nil, config.availableFilters == nil {
            fatalError("Plase set at least one crop option or one filter option in order to use the editor")
        }

        filterSubMenuView?.isHidden = config.availableFilters == nil
        cropSubMenuView?.isHidden = config.availableFilters != nil || config.availableCrops == nil

        cropView = FMCropView(
            image: filteredImage,
            appliedCrop: fmPhotoAsset.getAppliedCrop(),
            appliedCropArea: fmPhotoAsset.getAppliedCropArea()
        )
        cropView.foregroundView.eclipsePreviewEnabled = config.eclipsePreviewEnabled
        cropView.isCropping = false

        view.addSubview(cropView)
        view.sendSubviewToBack(cropView)

        filterSubMenuView?.insert(toView: subMenuContainer)
        cropSubMenuView?.insert(toView: subMenuContainer)

        // convert crop/filter icon to tint
        let filterTintIcon = UIImage(named: "icon_filter", in: .current, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate)
        filterMenuButton.setImage(filterTintIcon, for: .normal)

        let cropTintIcon = UIImage(named: "icon_crop", in: .current, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate)
        cropMenuButton.setImage(cropTintIcon, for: .normal)

        // default color
        filterMenuButton.setTitleColor(kSelectedColor, for: .normal)
        filterMenuButton.tintColor = kSelectedColor

        cropMenuButton.setTitleColor(kBlackColor, for: .normal)
        cropMenuButton.tintColor = kBlackColor

        // get full size original image without any crop or filter applied
        fmPhotoAsset.requestFullSizePhoto(cropState: .original, filterState: .original) { [weak self] image in
            guard let self = self,
                let image = image else { return }
            self.originalImage = image
            self.cropView.foregroundView.compareView.image = image
        }

        if !isAnimatedPresent {
            // Hide entire view view until the crop view image is located
            // Because the crop view's frame is restore when view did appear
            // It's neccssary to hide the initial view until the view's position restore is completed
            // It will make the transition become more natural and smooth
            view.isHidden = true
        }

        // set buttons title
        cancelButton.setTitle(config.strings["editor_button_cancel"], for: .normal)
        cancelButton.titleLabel!.font = UIFont.boldSystemFont(ofSize: config.titleFontSize)

        doneButton.setTitle(config.strings["editor_button_done"], for: .normal)
        doneButton.titleLabel!.font = UIFont.boldSystemFont(ofSize: config.titleFontSize)

        filterMenuButton.setTitle(config.strings["editor_menu_filter"], for: .normal)
        filterMenuButton.titleLabel!.font = UIFont.boldSystemFont(ofSize: config.titleFontSize)

        cropMenuButton.setTitle(config.strings["editor_menu_crop"], for: .normal)
        cropMenuButton.titleLabel!.font = UIFont.boldSystemFont(ofSize: config.titleFontSize)

        filterMenuButton.isHidden = config.availableFilters == nil
        cropMenuButton.isHidden = config.availableCrops == nil
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if config.availableCrops != nil && config.availableFilters == nil {
            openCropsMenu()
        }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cropView.frame = view.frame

        if #available(iOS 11.0, *) {
            bottomMenuContainerBottomConstraint.constant = -view.safeAreaInsets.bottom
            menuContainerTopConstraint.constant = view.safeAreaInsets.top
        }
    }

    // MARK: - IBActions

    @IBAction func onTapDone(_ sender: Any) {
        cropView.isCropping = false

        cropView.contentFrame = contentFrameFullScreen()
        cropView.moveCropBoxToAspectFillContentFrame {
            // get crop data:
            let cropArea = self.cropView.getCropArea()

            self.fmPhotoAsset.apply(
                filter: self.selectedFilter,
                crop: self.selectedCrop,
                cropArea: cropArea
            )

            if let delegate = self.delegate {
                // In case that FMImageEditorViewController is used as standard-alone tool
                self.fmPhotoAsset.requestFullSizePhoto(cropState: .edited, filterState: .edited) { image in
                    if let image = image {
                        delegate.fmImageEditorViewController(self, didFinishEdittingPhotoWith: image)
                    }
                }
            } else {
                // notify PresenterViewController to update it's image
                self.didEndEditting {
                    self.dismiss(animated: self.isAnimatedPresent)
                }
            }
        }

        hideAnimatedMenu {}
    }

    @IBAction func onTapCancel(_ sender: Any) {
        self.dismiss(animated: self.isAnimatedPresent, completion: nil)
    }

    @IBAction func onTapOpenFilter(_ sender: Any) {
        openFiltersMenu()
    }

    @IBAction func onTapOpenCrop(_ sender: Any) {
        openCropsMenu()
    }

    private func openFiltersMenu() {
        filterMenuButton.tintColor = kSelectedColor
        filterMenuButton.setTitleColor(kSelectedColor, for: .normal)
        cropMenuButton.tintColor = kBlackColor
        cropMenuButton.setTitleColor(kBlackColor, for: .normal)

        showAnimatedFilterMenu()

        cropView.contentFrame = contentFrameFilter()
        cropView.moveCropBoxToAspectFillContentFrame()
        cropView.isCropping = false

        // enable foreground touches to control show/hide compareView
        cropView.foregroundView.isEnabledTouches = true

        filterSubMenuView?.image = cropView.getCroppedThumbImage()
    }

    private func openCropsMenu() {
        cropMenuButton.tintColor = kSelectedColor
        cropMenuButton.setTitleColor(kSelectedColor, for: .normal)
        filterMenuButton.tintColor = kBlackColor
        filterMenuButton.setTitleColor(kBlackColor, for: .normal)

        showAnimatedCropMenu()

        cropView.contentFrame = contentFrameCrop()
        cropView.moveCropBoxToAspectFillContentFrame()
        cropView.isCropping = true

        // disable foreground touches to return control to scrollview
        cropView.foregroundView.isEnabledTouches = false
    }

    // MARK: - Animation

    private func showAnimatedCropMenu() {
        guard cropSubMenuView?.isHidden == true else { return }

        subMenuContainer?.isHidden = false
        cropSubMenuView?.isHidden = false

        cropSubMenuView?.alpha = 0
        UIView.animate(
            withDuration: kEnteringAnimationDuration,
            animations: {
                self.cropSubMenuView?.alpha = 1
                self.filterSubMenuView?.alpha = 0
            },
            completion: { _ in
                self.filterSubMenuView?.isHidden = true
            }
        )
    }

    private func showAnimatedFilterMenu() {
        guard filterSubMenuView?.isHidden == true else { return }

        subMenuContainer.isHidden = false
        filterSubMenuView?.isHidden = false

        filterSubMenuView?.alpha = 0
        UIView.animate(
            withDuration: kEnteringAnimationDuration,
            animations: {
                self.filterSubMenuView?.alpha = 1
                self.cropSubMenuView?.alpha = 0

            },
            completion: { _ in
                self.cropSubMenuView?.isHidden = true
            }
        )
    }

    private func showAnimatedMenu() {
        headerViewTopConstraint.constant = -headerView.frame.height
        bottomViewContainerBottomConstraint.constant = bottomViewContainer.frame.height

        view.layoutIfNeeded()

        headerViewTopConstraint.constant = 0
        bottomViewContainerBottomConstraint.constant = 0

        headerView.alpha = 0
        bottomViewContainer.alpha = 0
        UIView.animate(
            withDuration: kEnteringAnimationDuration,
            delay: 0,
            options: .curveEaseOut,
            animations: {
                self.headerView.alpha = 1
                self.bottomViewContainer.alpha = 1
                self.view.layoutIfNeeded()
            },
            completion: nil
        )
    }

    private func hideAnimatedMenu(completion: (() -> Void)?) {
        headerViewTopConstraint.constant = 0
        bottomViewContainerBottomConstraint.constant = 0

        view.layoutIfNeeded()

        headerViewTopConstraint.constant = -headerView.frame.height
        bottomViewContainerBottomConstraint.constant = bottomViewContainer.frame.height

        UIView.animate(
            withDuration: kLeavingAnimationDuration,
            delay: 0,
            options: .curveEaseOut,
            animations: {
                self.headerView.alpha = 0
                self.bottomViewContainer.alpha = 0
                self.view.layoutIfNeeded()
            },
            completion: { _ in
                completion?()
            }
        )
    }

    /// Returns a frame that will be used as the bound for the cropped image in the crop mode.
    private func contentFrameCrop() -> CGRect {
        let x: CGFloat = kContentFrameSpacing
        let y: CGFloat = kContentFrameSpacing + headerView.frame.height
        let width: CGFloat = view.bounds.width - 2 * kContentFrameSpacing
        let height: CGFloat = view.bounds.height
            - bottomViewContainer.frame.height
            - headerView.frame.height
            - 2 * kContentFrameSpacing

        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Returns a frame that will be used as the bound for the image in the filter mode.
    private func contentFrameFilter() -> CGRect {
        let x: CGFloat = 0
        let y: CGFloat = headerView.frame.height
        let width: CGFloat = view.bounds.width
        let height: CGFloat = view.bounds.height - bottomViewContainer.frame.height - headerView.frame.height

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func contentFrameFullScreen() -> CGRect {
        return view.bounds
    }
}

private extension FMImageEditorViewController {
    func setupView() {
        let headerView = UIView()
        self.headerView = headerView
        headerView.backgroundColor = .white

        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)
        headerViewTopConstraint = headerView.topAnchor.constraint(equalTo: view.topAnchor)
        NSLayoutConstraint.activate([
            headerViewTopConstraint,
            headerView.leftAnchor.constraint(equalTo: view.leftAnchor),
            headerView.rightAnchor.constraint(equalTo: view.rightAnchor),
        ])

        let headerSeparator = UIView()
        headerSeparator.backgroundColor = kBorderColor

        headerSeparator.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(headerSeparator)
        NSLayoutConstraint.activate([
            headerSeparator.leftAnchor.constraint(equalTo: headerView.leftAnchor),
            headerSeparator.rightAnchor.constraint(equalTo: headerView.rightAnchor),
            headerSeparator.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            headerSeparator.heightAnchor.constraint(equalToConstant: 1),
        ])

        let menuContainer = UIView()

        menuContainer.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(menuContainer)
        menuContainerTopConstraint = menuContainer.topAnchor.constraint(equalTo: headerView.topAnchor)
        NSLayoutConstraint.activate([
            menuContainerTopConstraint,
            menuContainer.leftAnchor.constraint(equalTo: headerView.leftAnchor),
            menuContainer.rightAnchor.constraint(equalTo: headerView.rightAnchor),
            menuContainer.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            menuContainer.heightAnchor.constraint(equalToConstant: 44),
        ])

        let cancelButton = UIButton(type: .custom)
        self.cancelButton = cancelButton
        cancelButton.setTitleColor(kBlackColor, for: .normal)
        cancelButton.addTarget(self, action: #selector(onTapCancel(_:)), for: .touchUpInside)

        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        menuContainer.addSubview(cancelButton)
        NSLayoutConstraint.activate([
            cancelButton.leftAnchor.constraint(equalTo: menuContainer.leftAnchor, constant: 16),
            cancelButton.centerYAnchor.constraint(equalTo: menuContainer.centerYAnchor),
        ])

        let doneButton = UIButton(type: .custom)
        self.doneButton = doneButton
        doneButton.setTitleColor(kBlackColor, for: .normal)
        doneButton.addTarget(self, action: #selector(onTapDone(_:)), for: .touchUpInside)

        doneButton.translatesAutoresizingMaskIntoConstraints = false
        menuContainer.addSubview(doneButton)
        NSLayoutConstraint.activate([
            doneButton.rightAnchor.constraint(equalTo: menuContainer.rightAnchor, constant: -16),
            doneButton.centerYAnchor.constraint(equalTo: menuContainer.centerYAnchor),
            doneButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ])

        let bottomViewContainer = UIView()
        self.bottomViewContainer = bottomViewContainer
        bottomViewContainer.backgroundColor = .white

        bottomViewContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomViewContainer)
        bottomViewContainerBottomConstraint = bottomViewContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        NSLayoutConstraint.activate([
            bottomViewContainerBottomConstraint,
            bottomViewContainer.rightAnchor.constraint(equalTo: view.rightAnchor),
            bottomViewContainer.leftAnchor.constraint(equalTo: view.leftAnchor),
        ])

        let bottomMenuContainer = UIStackView()
        bottomMenuContainer.axis = .horizontal
        bottomMenuContainer.distribution = .fillEqually
        bottomMenuContainer.translatesAutoresizingMaskIntoConstraints = false
        bottomViewContainer.addSubview(bottomMenuContainer)
        bottomMenuContainerBottomConstraint = bottomMenuContainer.bottomAnchor.constraint(equalTo: bottomViewContainer.bottomAnchor)
        NSLayoutConstraint.activate([
            bottomMenuContainerBottomConstraint,
            bottomMenuContainer.leftAnchor.constraint(equalTo: bottomViewContainer.leftAnchor),
            bottomMenuContainer.rightAnchor.constraint(equalTo: bottomViewContainer.rightAnchor),
            bottomMenuContainer.heightAnchor.constraint(equalToConstant: 40),
        ])

        let filterMenuButton = UIButton(type: .custom)
        self.filterMenuButton = filterMenuButton
        filterMenuButton.addTarget(self, action: #selector(onTapOpenFilter(_:)), for: .touchUpInside)
        filterMenuButton.titleEdgeInsets = .init(top: 0, left: 4, bottom: 0, right: -4)

        filterMenuButton.translatesAutoresizingMaskIntoConstraints = false
        bottomMenuContainer.addArrangedSubview(filterMenuButton)

        let cropMenuButton = UIButton(type: .custom)
        self.cropMenuButton = cropMenuButton
        cropMenuButton.addTarget(self, action: #selector(onTapOpenCrop(_:)), for: .touchUpInside)
        cropMenuButton.titleEdgeInsets = .init(top: 0, left: 4, bottom: 0, right: -4)

        cropMenuButton.translatesAutoresizingMaskIntoConstraints = false
        bottomMenuContainer.addArrangedSubview(cropMenuButton)

        let subMenuContainer = UIView()
        self.subMenuContainer = subMenuContainer
        subMenuContainer.backgroundColor = .white

        subMenuContainer.translatesAutoresizingMaskIntoConstraints = false
        bottomViewContainer.addSubview(subMenuContainer)
        NSLayoutConstraint.activate([
            subMenuContainer.topAnchor.constraint(equalTo: bottomViewContainer.topAnchor),
            subMenuContainer.leftAnchor.constraint(equalTo: bottomViewContainer.leftAnchor),
            subMenuContainer.rightAnchor.constraint(equalTo: bottomViewContainer.rightAnchor),
            subMenuContainer.bottomAnchor.constraint(equalTo: bottomMenuContainer.topAnchor),
            subMenuContainer.heightAnchor.constraint(equalToConstant: 64),
        ])

        let subMenuSeparator = UIView()
        subMenuSeparator.backgroundColor = kBorderColor

        subMenuSeparator.translatesAutoresizingMaskIntoConstraints = false
        subMenuContainer.addSubview(subMenuSeparator)
        NSLayoutConstraint.activate([
            subMenuSeparator.leftAnchor.constraint(equalTo: subMenuContainer.leftAnchor),
            subMenuSeparator.rightAnchor.constraint(equalTo: subMenuContainer.rightAnchor),
            subMenuSeparator.topAnchor.constraint(equalTo: subMenuContainer.topAnchor),
            subMenuSeparator.heightAnchor.constraint(equalToConstant: 1),
        ])
    }
}
