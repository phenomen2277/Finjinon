//
//  PhotoCaptureViewController.swift
//  Finjinon
//
//  Created by Sørensen, Johan on 05.06.15.
//  Copyright (c) 2015 FINN.no AS. All rights reserved.
//

import UIKit
import AVFoundation
import MobileCoreServices

public protocol PhotoCaptureViewControllerDelegate: NSObjectProtocol {
    func photoCaptureViewController(controller: PhotoCaptureViewController, didFinishEditingAssets assets: [Asset])
    func photoCaptureViewController(controller: PhotoCaptureViewController, didSelectAsset asset: Asset)
    func photoCaptureViewController(controller: PhotoCaptureViewController, didFailWithError error: NSError)
}

public class PhotoCaptureViewController: UIViewController {
    public weak var delegate: PhotoCaptureViewControllerDelegate?
    private(set) public var assets: [Asset] = []
    public var imagePickerAdapter = ImagePickerControllerAdapter()

    private let storage = PhotoStorage()
    private let captureManager = CaptureManager()
    private var previewView: UIView!
    private var captureButton: TriggerButton!
    private var collectionView: UICollectionView!
    private var containerView: UIVisualEffectView!
    private var focusIndicatorView: UIView!
    private var flashButton: UIButton!

    override public func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.blackColor()

        // TODO: Move all the boring view setup to a storyboard/xib

        previewView = UIView(frame: view.bounds)
        previewView.autoresizingMask = .FlexibleWidth | .FlexibleHeight
        view.addSubview(previewView)
        let previewLayer = captureManager.previewLayer
        previewLayer.frame = previewView.layer.bounds
        previewView.layer.addSublayer(previewLayer)

        focusIndicatorView = UIView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        focusIndicatorView.backgroundColor = UIColor.clearColor()
        focusIndicatorView.layer.borderColor = UIColor.orangeColor().CGColor
        focusIndicatorView.layer.borderWidth = 1.0
        focusIndicatorView.alpha = 0.0
        previewView.addSubview(focusIndicatorView)

        flashButton = UIButton(frame: CGRect(x: 12, y: 12, width: 70, height: 38))
        flashButton.setImage(UIImage(named: "LightningIcon"), forState: .Normal)
        flashButton.setTitle(NSLocalizedString("Off", comment:"flash off"), forState: .Normal)
        flashButton.addTarget(self, action: Selector("flashButtonTapped:"), forControlEvents: .TouchUpInside)
        flashButton.titleLabel?.font = UIFont.preferredFontForTextStyle(UIFontTextStyleFootnote)
        flashButton.tintColor = UIColor.whiteColor()
        roundifyButton(flashButton, inset: 14)

        let tapper = UITapGestureRecognizer(target: self, action: Selector("focusTapGestureRecognized:"))
        previewView.addGestureRecognizer(tapper)

        let collectionViewHeight: CGFloat = 102

        containerView = UIVisualEffectView(effect: UIBlurEffect(style: .Dark))
        containerView.frame = CGRect(x: 0, y: view.frame.height-76-collectionViewHeight, width: view.frame.width, height: 76+collectionViewHeight)
        view.addSubview(containerView)

        let layout = PhotoCollectionViewLayout()
        collectionView = UICollectionView(frame: CGRect(x: 0, y: 0, width: containerView.bounds.width, height: collectionViewHeight), collectionViewLayout: layout)

        layout.scrollDirection = .Horizontal
        let inset: CGFloat = 8
        layout.itemSize = CGSize(width: collectionView.frame.height - (inset*2), height: collectionView.frame.height - (inset*2))
        layout.sectionInset = UIEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        layout.minimumInteritemSpacing = inset
        layout.minimumLineSpacing = inset

        collectionView.backgroundColor = UIColor.clearColor()
        collectionView.alwaysBounceHorizontal = true
        containerView.contentView.addSubview(collectionView)
        collectionView.registerClass(PhotoCollectionViewCell.self, forCellWithReuseIdentifier: "PhotoCell")
        collectionView.dataSource = self
        collectionView.delegate = self

        captureButton = TriggerButton(frame: CGRect(x: (containerView.frame.width/2)-33, y: containerView.frame.height - 66 - 4, width: 66, height: 66))
        captureButton.layer.cornerRadius = 33
        captureButton.addTarget(self, action: Selector("capturePhotoTapped:"), forControlEvents: .TouchUpInside)
        containerView.contentView.addSubview(captureButton)
        captureButton.enabled = false

        let closeButton = UIButton(frame: CGRect(x: 0, y: captureButton.frame.midY - 22, width: captureButton.frame.minX, height: 44))
        closeButton.addTarget(self, action: Selector("doneButtonTapped:"), forControlEvents: .TouchUpInside)
        closeButton.setTitle(NSLocalizedString("Done", comment: ""), forState: .Normal)
        closeButton.tintColor = UIColor.whiteColor()
        containerView.contentView.addSubview(closeButton)

        let pickerButtonWidth: CGFloat = 114
        let pickerButton = UIButton(frame: CGRect(x: view.bounds.width - pickerButtonWidth - 12, y: 12, width: pickerButtonWidth, height: 38))
        pickerButton.setTitle(NSLocalizedString("Photos", comment: "Select from Photos buttont itle"), forState: .Normal)
        pickerButton.setImage(UIImage(named: "PhotosIcon"), forState: .Normal)
        pickerButton.addTarget(self, action: Selector("presentImagePickerTapped:"), forControlEvents: .TouchUpInside)
        pickerButton.titleLabel?.font = UIFont.preferredFontForTextStyle(UIFontTextStyleFootnote)
        roundifyButton(pickerButton)
        view.addSubview(pickerButton)

        previewView.alpha = 0.0
        captureManager.prepare {
            if self.captureManager.hasFlash {
                self.view.addSubview(self.flashButton)
            }

            UIView.animateWithDuration(0.2) {
                self.captureButton.enabled = true
                self.previewView.alpha = 1.0
            }
        }
    }

    public override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)

        // In case the application uses the old style for managing status bar appearance
        UIApplication.sharedApplication().setStatusBarHidden(true, withAnimation: .Slide)
    }

    public override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)

        UIApplication.sharedApplication().setStatusBarHidden(false, withAnimation: .Slide)
    }

    public override func preferredStatusBarUpdateAnimation() -> UIStatusBarAnimation {
        return .Slide
    }

    public override func prefersStatusBarHidden() -> Bool {
        return true
    }

    // MARK: - API

    // Add the initial set of images asynchronously
    public func addInitialImages(images: [UIImage]) {
        for image in images {
            storage.createAssetFromImage(image) { asset in
                self.assets.append(asset)
                self.collectionView.reloadData()
            }
        }
    }

    // MARK: - Actions

    func flashButtonTapped(sender: UIButton) {
        let mode = captureManager.nextAvailableFlashMode() ?? .Off
        captureManager.changeFlashMode(mode) {
            switch mode {
            case .Off:
                self.flashButton.setTitle(NSLocalizedString("Off", comment:"flash off"), forState: .Normal)
            case .On:
                self.flashButton.setTitle(NSLocalizedString("On", comment:"flash on"), forState: .Normal)
            case .Auto:
                self.flashButton.setTitle(NSLocalizedString("Auto", comment:"flash Auto"), forState: .Normal)
            }
        }
    }

    func presentImagePickerTapped(sender: AnyObject) {
        let updateHandler: Asset -> Void = { asset in
            self.collectionView.performBatchUpdates({
                self.assets.insert(asset, atIndex: 0)
                self.collectionView.insertItemsAtIndexPaths([NSIndexPath(forItem: 0, inSection: 0)])
                }, completion: nil)
        }

        let controller = imagePickerAdapter.viewControllerForImageSelection({ info in
            if let imageURL = info[UIImagePickerControllerMediaURL] as? NSURL, let data = NSData(contentsOfURL: imageURL) {
                self.storage.createAssetFromImageData(data, completion: updateHandler)
            } else if let assetURL = info[UIImagePickerControllerReferenceURL] as? NSURL {
                self.storage.createAssetFromAssetLibraryURL(assetURL, completion: updateHandler)
            } else if let image = info[UIImagePickerControllerOriginalImage] as? UIImage {
                self.storage.createAssetFromImage(image, completion: updateHandler)
            }
        }, completion: { cancelled in
            self.dismissViewControllerAnimated(true, completion: nil)
        })

        presentViewController(controller, animated: true, completion: nil)
    }

    func capturePhotoTapped(sender: UIButton) {
        sender.enabled = false
        UIView.animateWithDuration(0.1, animations: { self.previewView.alpha = 0.0 }, completion: { finished in
            UIView.animateWithDuration(0.1, animations: {self.previewView.alpha = 1.0})
        })

        captureManager.captureImage { (data, metadata) in
            sender.enabled = true

            self.storage.createAssetFromImageData(data) { asset in
                self.collectionView.performBatchUpdates({
                    self.assets.insert(asset, atIndex: 0)
                    self.collectionView.insertItemsAtIndexPaths([NSIndexPath(forItem: 0, inSection: 0)])
                }, completion: nil)
            }
        }
    }

    func doneButtonTapped(sender: UIButton) {
        delegate?.photoCaptureViewController(self, didFinishEditingAssets: assets)
        dismissViewControllerAnimated(true, completion: nil)
    }

    func focusTapGestureRecognized(gestureRecognizer: UITapGestureRecognizer) {
        if gestureRecognizer.state == .Ended {
            let point = gestureRecognizer.locationInView(gestureRecognizer.view)

            focusIndicatorView.center = point
            UIView.animateWithDuration(0.3, delay: 0.0, options: .BeginFromCurrentState, animations: {
                self.focusIndicatorView.alpha = 1.0
            }, completion: { finished in
                UIView.animateWithDuration(0.2, delay: 1.6, options: .BeginFromCurrentState, animations: {
                    self.focusIndicatorView.alpha = 0.0
                }, completion: nil)
            })

            captureManager.lockFocusAtPointOfInterest(point)
        }
    }

    // MARK: - UIViewController

    public override func shouldAutorotate() -> Bool {
        return false
    }

    public override func supportedInterfaceOrientations() -> Int {
        return UIInterfaceOrientation.Portrait.rawValue
    }

    // MARK: - Private methods

    func roundifyButton(button: UIButton, inset: CGFloat = 16) {
        button.tintColor = UIColor.whiteColor()

        button.backgroundColor = UIColor.blackColor().colorWithAlphaComponent(0.3)
        button.layer.borderColor = button.tintColor!.CGColor
        button.layer.borderWidth = 1.0
        button.layer.cornerRadius = button.bounds.height/2

        var insets = button.imageEdgeInsets
        insets.left -= inset
        button.imageEdgeInsets = insets
    }
}


extension PhotoCaptureViewController: UICollectionViewDataSource, PhotoCollectionViewCellDelegate {
    public func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return assets.count
    }

    public func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCellWithReuseIdentifier("PhotoCell", forIndexPath: indexPath) as! PhotoCollectionViewCell
        let asset = assets[indexPath.row]
        asset.retrieveImageWithWidth(cell.imageView.bounds.width) { image in
            cell.imageView.image = image
        }
        cell.delegate = self
        cell.asset =  asset
        return cell
    }

    func collectionViewCellDidTapDelete(cell: PhotoCollectionViewCell) {
        if let asset = cell.asset, let itemIndex = find(self.assets, asset) {
            let indexPath = NSIndexPath(forItem: itemIndex, inSection: 0)
            collectionView.performBatchUpdates({
                self.assets.removeAtIndex(indexPath.row)
                self.collectionView.deleteItemsAtIndexPaths([indexPath])
                }, completion: nil)
        }
    }
}


extension PhotoCaptureViewController: UICollectionViewDelegate {
    public func collectionView(collectionView: UICollectionView, didSelectItemAtIndexPath indexPath: NSIndexPath) {
        let asset = assets[indexPath.row]
        delegate?.photoCaptureViewController(self, didSelectAsset: asset)
    }
}
