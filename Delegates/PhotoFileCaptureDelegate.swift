//
//  PhotoFileCaptureDelegate.swift
//  ZCLCameraManagerExample
//
//  Created by fatih on 3/29/19.
//  Copyright © 2019 fatih. All rights reserved.
//

import Photos
import UIKit

class PhotoFileCaptureDelegate: NSObject {
    private(set) var requestedPhotoSettings: AVCapturePhotoSettings
    private let willCapturePhotoAnimation: () -> Void
    lazy var context = CIContext()
    private let completionHandler: (PhotoFileCaptureDelegate,UIImage?,Error?) -> Void
    private var photoData: Data?
    var captureDevice : AVCaptureDevice!
    var orientation: UIDeviceOrientation?
    
    init(with requestedPhotoSettings: AVCapturePhotoSettings,
         willCapturePhotoAnimation: @escaping () -> Void,
         completionHandler: @escaping (PhotoFileCaptureDelegate,UIImage?,Error?) -> Void,
         captureDevice: AVCaptureDevice,
         orientation: UIDeviceOrientation?) {
        self.requestedPhotoSettings = requestedPhotoSettings
        self.willCapturePhotoAnimation = willCapturePhotoAnimation
        self.completionHandler = completionHandler
        self.captureDevice = captureDevice
        self.orientation = orientation
    }
    
    private func didFinish(with error: Error?) {
        completionHandler(self,nil,error)
    }
}


//MARK: Photo Capture Delegates
extension PhotoFileCaptureDelegate: AVCapturePhotoCaptureDelegate {
    /*
     This extension includes all the delegate callbacks for AVCapturePhotoCaptureDelegate protocol.
     */
    
    func photoOutput(_ captureOutput: AVCapturePhotoOutput, didFinishProcessingPhoto photoSampleBuffer: CMSampleBuffer?, previewPhoto previewPhotoSampleBuffer: CMSampleBuffer?, resolvedSettings: AVCaptureResolvedPhotoSettings, bracketSettings: AVCaptureBracketedStillImageSettings?, error: Error?){
        if let error = error {
            didFinish(with: error)
        }else if let photoSampleBuffer = photoSampleBuffer {
            photoData = AVCapturePhotoOutput.jpegPhotoDataRepresentation(forJPEGSampleBuffer: photoSampleBuffer, previewPhotoSampleBuffer: previewPhotoSampleBuffer)
        }
    }
    
    
    /// - Tag: WillCapturePhoto
    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        willCapturePhotoAnimation()
    }
    
    /// - Tag: DidFinishProcessingPhoto
    @available(iOS 11.0, *)
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        
        if let error = error {
            didFinish(with: error)
        } else {
            photoData = photo.fileDataRepresentation()
        }
    }
    /// - Tag: DidFinishCapture
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error = error {
            print("Error capturing photo: \(error)")
            didFinish(with: error)
            return
        }
        
        guard let photoData = photoData else {
            print("No photo data")
            didFinish(with: error)
            return
        }
        
        if let image = UIImage(data: photoData){
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    PHPhotoLibrary.shared().performChanges({
                        let options = PHAssetResourceCreationOptions()
                        let creationRequest = PHAssetCreationRequest.forAsset()
                        if #available(iOS 11.0, *) {
                            options.uniformTypeIdentifier = self.requestedPhotoSettings.processedFileType.map { $0.rawValue }
                            creationRequest.addResource(with: .photo, data: photoData, options: options)
                        }
                    }, completionHandler: { _, error in
                        if let error = error {
                            print("Error occurred while saving photo to photo library: \(error)")
                        }
                        self.handleOnCaptureFinish(sourceImage: image)
                    }
                    )
                } else {
                    self.handleOnCaptureFinish(sourceImage: image)
                }
            }
        }
    }
}

//MARK: Helper Methods
extension PhotoFileCaptureDelegate{
    func handleOnCaptureFinish(sourceImage: UIImage){
        var image = sourceImage
        if let dOrientation = self.orientation{
            if self.captureDevice.position == AVCaptureDevice.Position.back {
                if (dOrientation == .landscapeLeft) {
                    image = UIImage(cgImage: (image.cgImage)!, scale: image.scale, orientation: UIImage.Orientation.up)
                } else if (dOrientation == .landscapeRight) {
                    image = UIImage(cgImage: (image.cgImage)!, scale: image.scale, orientation: UIImage.Orientation.down)
                } else if (dOrientation == .portrait) {
                    image = UIImage(cgImage: (image.cgImage)!, scale: image.scale, orientation: UIImage.Orientation.right)
                } else if (dOrientation == .portraitUpsideDown) {
                    image = UIImage(cgImage: (image.cgImage)!, scale: image.scale, orientation: UIImage.Orientation.left)
                }
            } else if self.captureDevice.position == AVCaptureDevice.Position.front {
                if (dOrientation == .landscapeLeft) {
                    image = UIImage(cgImage: (image.cgImage)!, scale: image.scale, orientation: UIImage.Orientation.downMirrored)
                } else if (dOrientation == .landscapeRight) {
                    image = UIImage(cgImage: (image.cgImage)!, scale: image.scale, orientation: UIImage.Orientation.upMirrored)
                } else if (dOrientation == .portrait) {
                    image = UIImage(cgImage: (image.cgImage)!, scale: image.scale, orientation: UIImage.Orientation.leftMirrored)
                } else if (dOrientation == .portraitUpsideDown) {
                    image = UIImage(cgImage: (image.cgImage)!, scale: image.scale, orientation: UIImage.Orientation.rightMirrored)
                }
            }
        }
        completionHandler(self,image,nil)
    }
}
