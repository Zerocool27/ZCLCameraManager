//
//  MediaFileCaptureProtocol.swift
//  ZCLCameraManagerExample
//
//  Created by fatih on 3/29/19.
//  Copyright © 2019 fatih. All rights reserved.
//

import UIKit

protocol MediaFileCaptureProtocol: NSObjectProtocol {
    func didFinishCapturingPhoto(image: UIImage?)
    func didFinishCapturingVideo(videoUrl: URL?, thumbnail: UIImage?)
    func didReceivePhotoError(error: Error?)
    func didReceiveVideoError(error: Error?)
}
