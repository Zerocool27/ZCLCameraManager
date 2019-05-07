//
//  VideoFileCaptureDelegate.swift
//  ZCLCameraManagerExample
//
//  Created by fatih on 3/29/19.
//  Copyright © 2019 fatih. All rights reserved.
//

import AVFoundation
import UIKit
import Photos

class VideoFileCaptureDelegate: NSObject {
    private(set) var uniqueVideoId: String
    lazy var context = CIContext()
    private let completionHandler: (VideoFileCaptureDelegate,URL?,UIImage?,Error?) -> Void
    var captureDevice : AVCaptureDevice!
    
    init(with uniqueVideoId: String,
         completionHandler: @escaping (VideoFileCaptureDelegate,URL?,UIImage?,Error?) -> Void,
         captureDevice: AVCaptureDevice) {
        self.uniqueVideoId = uniqueVideoId
        self.completionHandler = completionHandler
        self.captureDevice = captureDevice
    }
    
    private func didFinish(with error: Error?) {
        completionHandler(self,nil,nil,error)
    }
}

//MARK: Video Capture Delegates
extension VideoFileCaptureDelegate: AVCaptureFileOutputRecordingDelegate{
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            didFinish(with: error)
        }
        
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
        }) { _, error in
            
            if let error = error {
                print("Error occurred while saving video to photo library: \(error)")
            }
            
            if let thumbnail = self.getThumbnail(url: outputFileURL) {
                self.completionHandler(self,outputFileURL,thumbnail,nil)
            }else{
                self.completionHandler(self,outputFileURL,nil,nil)
            }
        }
        
    }
}

//MARK: Helper Methods
extension VideoFileCaptureDelegate{
    fileprivate func getThumbnail(url: URL) -> UIImage? {
        var image: UIImage? = nil
        do {
            let asset = AVURLAsset(url: url, options: nil)
            let imgGenerator = AVAssetImageGenerator(asset: asset)
            imgGenerator.appliesPreferredTrackTransform = true
            
            let cgImage = try imgGenerator.copyCGImage(at: CMTimeMake(value: 0, timescale: 1), actualTime: nil)
            image = UIImage(cgImage: cgImage)
        } catch {
            image = nil
        }
        return image
    }
}

