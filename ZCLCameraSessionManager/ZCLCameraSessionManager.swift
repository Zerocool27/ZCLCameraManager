//
//  ZCLCameraSessionManager.swift
//  ZCLCameraManagerExample
//
//  Created by fatih on 3/29/19.
//  Copyright © 2019 fatih. All rights reserved.
//

import AVFoundation
import UIKit

enum SessionSetupResult {
    case success
    case notAuthorized
    case configurationFailed
}

enum FlashMode {
    case off
    case on
    case auto
}

enum VideoError: Error {
    case runtimeError(String)
}

class ZCLCameraSessionManager: NSObject {
    weak var delegate : MediaFileCaptureProtocol?
    static let shared = ZCLCameraSessionManager()
    var defaultVideoDevice: AVCaptureDevice!
    fileprivate let session = AVCaptureSession()
    fileprivate var isSessionRunning = false
    fileprivate let sessionQueue = DispatchQueue(label: "camera_session_queue") // Communicate with the session and other
    fileprivate var previewLayer: AVCaptureVideoPreviewLayer!
    @objc dynamic var videoDeviceInput: AVCaptureDeviceInput!
    var setupResult: SessionSetupResult = .notAuthorized
    fileprivate let photoOutput = AVCapturePhotoOutput()
    fileprivate var inProgressPhotoCaptureDelegates = [Int64: PhotoFileCaptureDelegate]()
    fileprivate var inProgressVideoCaptureDelegates = [String: VideoFileCaptureDelegate]()
    fileprivate var keyValueObservations = [NSKeyValueObservation]()
    fileprivate var movieFileOutput : AVCaptureMovieFileOutput?
    fileprivate var flashMode = FlashMode.auto
    fileprivate var backgroundRecordingID: UIBackgroundTaskIdentifier?
    /* OBSERVER MANAGER */
    var applicatioWillEnterForeground: NSObjectProtocol?
    var applicatioDidEnterBackground: NSObjectProtocol?
    var applicatioDidBecomeActive: NSObjectProtocol?
    var applicatioWillResignActive: NSObjectProtocol?
}

//MARK: Get Methods
extension ZCLCameraSessionManager{
    func getCameraSession() -> AVCaptureSession {
        return session
    }
    func getPreview()-> AVCaptureVideoPreviewLayer{
        return previewLayer
    }
    func getCameraDevice() -> AVCaptureDevice{
        return defaultVideoDevice
    }
    func getFlashMode() -> FlashMode{
        return flashMode
    }
}

//MARK: Setup Methods
extension ZCLCameraSessionManager{
    func initializeCameraPreview(with frame:CGRect){
        previewLayer =  AVCaptureVideoPreviewLayer(session: getCameraSession())
        previewLayer.frame = frame
        previewLayer.videoGravity = .resize
        configureSession()
    }
    private func configureSession() {
        if setupResult != .success {
            return
        }
        
        session.beginConfiguration()
        session.sessionPreset = .high
        
        // Add video input.
        do {
            // Choose the back dual camera if available, otherwise default to a wide angle camera.
            
            if let backCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                // If a rear dual camera is not available, default to the rear wide angle camera.
                defaultVideoDevice = backCameraDevice
            } else if let frontCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                // In the event that the rear wide angle camera isn't available, default to the front wide angle camera.
                defaultVideoDevice = frontCameraDevice
            }
            guard let videoDevice = defaultVideoDevice else {
                print("Default video device is unavailable.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
            
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                setupBestPresetAvailable()
                
                DispatchQueue.main.async {
                    let statusBarOrientation = UIApplication.shared.statusBarOrientation
                    var initialVideoOrientation: AVCaptureVideoOrientation = .portrait
                    if statusBarOrientation != .unknown {
                        if let videoOrientation = AVCaptureVideoOrientation(rawValue: statusBarOrientation.rawValue) {
                            initialVideoOrientation = videoOrientation
                        }
                    }
                    self.getPreview().connection?.videoOrientation = initialVideoOrientation
                }
            } else {
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        } catch {
            print("Couldn't create video device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        // Add audio input.
        do {
            let audioDevice = AVCaptureDevice.default(for: .audio)
            let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice!)
            
            if session.canAddInput(audioDeviceInput) {
                session.addInput(audioDeviceInput)
            }
        } catch {
            print("Could not create audio device input: \(error)")
        }
        
        // Add photo output.
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
        } else {
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        session.commitConfiguration()
    }
    
    func configureSessionForPhoto(completion:@escaping () -> ()){
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.removeOutput(self.movieFileOutput!)
            self.setupBestPresetAvailable()
            self.movieFileOutput = nil
            self.session.commitConfiguration()
            completion()
        }
    }
    func configureSessionForVideo(completion:@escaping (Bool) -> ()){
        sessionQueue.async {
            let movieFileOutput = AVCaptureMovieFileOutput()
            if self.session.canAddOutput(movieFileOutput) {
                self.session.beginConfiguration()
                self.session.addOutput(movieFileOutput)
                self.setupBestPresetAvailable()
                if let connection = movieFileOutput.connection(with: .video) {
                    if connection.isVideoStabilizationSupported {
                        connection.preferredVideoStabilizationMode = .auto
                    }
                }
                self.session.commitConfiguration()
                self.movieFileOutput = movieFileOutput
                completion(true)
            }else{
                completion(false)
            }
        }
    }
    
    func setupBestPresetAvailable(){
        if getCameraSession().canSetSessionPreset(.hd4K3840x2160){
            getCameraSession().sessionPreset = AVCaptureSession.Preset.hd4K3840x2160
        }else if getCameraSession().canSetSessionPreset(.hd1920x1080){
            getCameraSession().sessionPreset = AVCaptureSession.Preset.hd1920x1080
        }else {
            getCameraSession().sessionPreset = AVCaptureSession.Preset.high
        }
    }
    
    func setupObservers() {
        
        if #available(iOS 11.1, *) {
            let systemPressureStateObservation = observe(\.videoDeviceInput.device.systemPressureState, options: .new) { _, change in
                guard let systemPressureState = change.newValue else { return }
                self.setRecommendedFrameRateRangeForPressureState(systemPressureState: systemPressureState)
            }
            keyValueObservations.append(systemPressureStateObservation)
        }
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(subjectAreaDidChange),
                                               name: .AVCaptureDeviceSubjectAreaDidChange,
                                               object: videoDeviceInput.device)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionRuntimeError),
                                               name: .AVCaptureSessionRuntimeError,
                                               object: session)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionWasInterrupted),
                                               name: .AVCaptureSessionWasInterrupted,
                                               object: session)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionInterruptionEnded),
                                               name: .AVCaptureSessionInterruptionEnded,
                                               object: session)
        
        applicatioWillEnterForeground = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main, using: { notification in
            if !self.isSessionRunning{
                self.restoreSession()
            }
        })
        applicatioDidEnterBackground = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main, using: { notification in
            if self.isSessionRunning{
                self.pauseSession()
            }
            UIApplication.shared.beginBackgroundTask(expirationHandler: {
                UIApplication.shared.endBackgroundTask(UIBackgroundTaskIdentifier.invalid)
            })
            DispatchQueue.main.async {
                UIApplication.shared.endBackgroundTask(UIBackgroundTaskIdentifier.invalid)
            }
        })
        applicatioDidBecomeActive = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main, using: { notification in
            if !self.isSessionRunning{
                self.restoreSession()
            }
        })
        applicatioWillResignActive = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main, using: { notification in
            if self.isSessionRunning{
                self.pauseSession()
            }
        })
    }
    func removeObservers() {
        
        if applicatioWillEnterForeground != nil {
            NotificationCenter.default.removeObserver(applicatioWillEnterForeground!)
        }
        if applicatioDidEnterBackground != nil {
            NotificationCenter.default.removeObserver(applicatioDidEnterBackground!)
        }
        if applicatioDidBecomeActive != nil {
            NotificationCenter.default.removeObserver(applicatioDidBecomeActive!)
        }
        if applicatioWillResignActive != nil {
            NotificationCenter.default.removeObserver(applicatioWillResignActive!)
        }
        
        NotificationCenter.default.removeObserver(self)
        
        for keyValueObservation in keyValueObservations {
            keyValueObservation.invalidate()
        }
        keyValueObservations.removeAll()
    }
}

//MARK: Session Methods
extension ZCLCameraSessionManager{
    func startSession(){
        getCameraSession().startRunning()
        self.isSessionRunning = self.getCameraSession().isRunning
        setupObservers()
    }
    
    func restoreSession(){
        getCameraSession().startRunning()
        self.isSessionRunning = self.getCameraSession().isRunning
    }
    
    func pauseSession(){
        if self.isSessionRunning {
            self.getCameraSession().stopRunning()
            self.isSessionRunning = self.getCameraSession().isRunning
        }
    }
    
    func stopSession(){
        if self.isSessionRunning {
            self.getCameraSession().stopRunning()
            self.isSessionRunning = self.getCameraSession().isRunning
            removeObservers()
        }
    }
    /// - Tag: HandleInterruption
    @objc
    func sessionWasInterrupted(notification: NSNotification) {
        print("Capture session was interrupted")

        sessionQueue.async {
            self.restoreSession()
        }
    }
    
    @objc
    func sessionInterruptionEnded(notification: NSNotification) {
        print("Capture session interruption ended")
        sessionQueue.async {
            self.restoreSession()
        }
    }
    @objc
    func sessionRuntimeError(notification: NSNotification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        
        print("Capture session runtime error: \(error)")
        // If media services were reset, and the last start succeeded, restart the session.
        if error.code == .mediaServicesWereReset {
            sessionQueue.async {
                self.restoreSession()
            }
        }
    }
}

//MARK: Action Methods
extension ZCLCameraSessionManager{
    func takePhoto(for orientation : UIDeviceOrientation?){
        /*
         Retrieve the video preview layer's video orientation on the main queue before
         entering the session queue. We do this to ensure UI elements are accessed on
         the main thread and session configuration is done on the session queue.
         */
        let videoPreviewLayerOrientation = previewLayer.connection?.videoOrientation
        sessionQueue.async {
            if let photoOutputConnection = self.photoOutput.connection(with: .video) {
                photoOutputConnection.videoOrientation = videoPreviewLayerOrientation!
            }
            var photoSettings = AVCapturePhotoSettings()
            
            // Capture JPEG photos. Enable auto-flash and high-resolution photos.
            if #available(iOS 11.0, *) {
                if  self.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                    photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                }
            }
            self.autoArrangeFlashMode(for: photoSettings)
            
            photoSettings.isHighResolutionPhotoEnabled = true
            if !photoSettings.__availablePreviewPhotoPixelFormatTypes.isEmpty {
                photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: photoSettings.__availablePreviewPhotoPixelFormatTypes.first!]
            }
            self.movieFileOutput = nil
            
            let photoCaptureDelegate = PhotoFileCaptureDelegate(with: photoSettings, willCapturePhotoAnimation: {
                // Flash the screen to signal that AVCam took a photo.
                DispatchQueue.main.async {
                    self.previewLayer.opacity = 0
                    UIView.animate(withDuration: 1.0) {
                        self.previewLayer.opacity = 1
                    }
                }
            }, completionHandler: { photoCaptureProcessor,image,error in
                // When the capture is complete, remove a reference to the photo capture delegate so it can be deallocated.
                self.sessionQueue.async {
                    if let error = error{
                        self.delegate?.didReceivePhotoError(error: error)
                    }else if let image = image{
                        self.delegate?.didFinishCapturingPhoto(image: image)
                    }
                    self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = nil
                }
            },captureDevice: self.defaultVideoDevice, orientation: orientation)
            
            // The photo output keeps a weak reference to the photo capture delegate and stores it in an array to maintain a strong reference.
            self.inProgressPhotoCaptureDelegates[photoCaptureDelegate.requestedPhotoSettings.uniqueID] = photoCaptureDelegate
            self.photoOutput.capturePhoto(with: photoSettings, delegate: photoCaptureDelegate)
        }
    }
    
    func startRecordingVideo() {
        guard let movieFileOutput = self.movieFileOutput else {
            return
        }
        
        let videoUUID = UUID().uuidString
        let fileName = "\(videoUUID).mov";
        self.autoArrangeTorchMode()
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filePath = documentsURL.appendingPathComponent(fileName, isDirectory: false)
        let videoPreviewLayerOrientation = getCurrentOrientation()
        
        sessionQueue.async {
            if !movieFileOutput.isRecording {
                if UIDevice.current.isMultitaskingSupported {
                    self.backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                }
                
                if let movieFileOutputConnection = movieFileOutput.connection(with: .video){
                    movieFileOutputConnection.videoOrientation = videoPreviewLayerOrientation
                    let availableVideoCodecTypes = movieFileOutput.availableVideoCodecTypes
                    
                    if #available(iOS 11.0, *) {
                        if availableVideoCodecTypes.contains(AVVideoCodecType.h264) {
                            movieFileOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.h264], for: movieFileOutputConnection)
                        }
                    }
                    let videoCaptureDelegate = VideoFileCaptureDelegate(with: videoUUID,completionHandler: { videoCaptureProcessor,videoPath,thumbnail,error in
                        // When the capture is complete, remove a reference to the video capture delegate so it can be deallocated.
                        self.sessionQueue.async {
                            
                            if let error = error{
                                self.delegate?.didReceiveVideoError(error: error)
                            }else if let videoPath = videoPath{
                                self.delegate?.didFinishCapturingVideo(videoUrl: videoPath, thumbnail: thumbnail)
                            }
                            self.inProgressVideoCaptureDelegates[videoCaptureProcessor.uniqueVideoId] = nil
                        }
                    },captureDevice: self.defaultVideoDevice)
                    self.inProgressVideoCaptureDelegates[videoCaptureDelegate.uniqueVideoId] = videoCaptureDelegate
                    self.getCameraSession().commitConfiguration()
                    movieFileOutput.startRecording(to: filePath, recordingDelegate: videoCaptureDelegate)
                }else{
                    let error = VideoError.runtimeError("Cannot Start Recording")
                    self.delegate?.didReceiveVideoError(error: error)
                }
            } else {
                movieFileOutput.stopRecording()
            }
        }
        
    }
    
    func stopRecordingVideo() {
        sessionQueue.async {
            if let movieFileOutput = self.movieFileOutput {
                if movieFileOutput.isRecording{
                    movieFileOutput.stopRecording()
                }
            }
        }
    }
}

//MARK: Helper Methods
extension ZCLCameraSessionManager{
    
    fileprivate func autoArrangeFlashMode(for photoSettings: AVCapturePhotoSettings){
        if self.videoDeviceInput.device.isFlashAvailable {
            if self.flashMode == .auto{
                photoSettings.flashMode = .auto
            }else if self.flashMode == .off{
                photoSettings.flashMode = .off
            }else if self.flashMode == .on{
                photoSettings.flashMode = .on
            }
        }
    }
    
    fileprivate func autoArrangeTorchMode() {
        guard let device = defaultVideoDevice else { return }
        
        if device.hasTorch {
            do {
                try device.lockForConfiguration()
                if self.flashMode == .auto{
                    device.torchMode = .auto
                }else if self.flashMode == .off{
                    device.torchMode = .off
                }else if self.flashMode == .on{
                    device.torchMode = .on
                }
                device.unlockForConfiguration()
            } catch {
                print("Torch could not be used")
            }
        } else {
            print("Torch is not available")
        }
    }
    fileprivate func getCurrentOrientation() -> AVCaptureVideoOrientation {
        var videoOrientation: AVCaptureVideoOrientation!
        let orientation = UIDevice.current.orientation
        
        switch orientation {
        case .portrait:
            videoOrientation = .portrait
        case .portraitUpsideDown:
            videoOrientation = .portraitUpsideDown
        case .landscapeLeft:
            videoOrientation = .landscapeRight
        case .landscapeRight:
            videoOrientation = .landscapeLeft
        case .faceDown, .faceUp, .unknown:
            videoOrientation = .portrait
            break
        }
        return videoOrientation
    }
    
    func changeCamera(){
        var videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera],
                                                                           mediaType: .video, position: .unspecified)
        
        if #available(iOS 10.2, *) {
            videoDeviceDiscoverySession  = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera],
                                                                            mediaType: .video, position: .unspecified)
        }
        
        if #available(iOS 11.1, *){
            videoDeviceDiscoverySession  = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera,.builtInTrueDepthCamera],
                                                                            mediaType: .video, position: .unspecified)
        }
        
        sessionQueue.async {
            let currentVideoDevice = self.videoDeviceInput.device
            let currentPosition = currentVideoDevice.position
            
            let preferredPosition: AVCaptureDevice.Position
            let preferredDeviceType: AVCaptureDevice.DeviceType
            
            switch currentPosition {
            case .unspecified, .front:
                preferredPosition = .back
                if #available(iOS 10.2, *) {
                    preferredDeviceType = .builtInDualCamera
                } else {
                    preferredDeviceType = .builtInWideAngleCamera
                }
                
            case .back:
                preferredPosition = .front
                if #available(iOS 11.1, *) {
                    preferredDeviceType = .builtInTrueDepthCamera
                } else {
                    preferredDeviceType = .builtInWideAngleCamera
                }
            }
            
            let devices = videoDeviceDiscoverySession.devices
            var newVideoDevice: AVCaptureDevice? = nil
            
            // First, seek a device with both the preferred position and device type. Otherwise, seek a device with only the preferred position.
            if let device = devices.first(where: { $0.position == preferredPosition && $0.deviceType == preferredDeviceType }) {
                newVideoDevice = device
            } else if let device = devices.first(where: { $0.position == preferredPosition }) {
                newVideoDevice = device
            }
            
            if let videoDevice = newVideoDevice {
                self.defaultVideoDevice = videoDevice
                do {
                    let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                    
                    self.getCameraSession().beginConfiguration()
                    self.getCameraSession().sessionPreset = .high //REDUCE SESSION PRESET TO HIGH FOR SMOOTH TRANSITION
                    // Remove the existing device input first, since the system doesn't support simultaneous use of the rear and front cameras.
                    self.getCameraSession().removeInput(self.videoDeviceInput)
                    
                    if self.getCameraSession().canAddInput(videoDeviceInput) {
                        NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: currentVideoDevice)
                        NotificationCenter.default.addObserver(self, selector: #selector(self.subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: videoDeviceInput.device)
                        
                        self.getCameraSession().addInput(videoDeviceInput)
                        self.videoDeviceInput = videoDeviceInput
                    } else {
                        self.getCameraSession().addInput(self.videoDeviceInput)
                    }
                    if let connection = self.movieFileOutput?.connection(with: .video) {
                        if connection.isVideoStabilizationSupported {
                            connection.preferredVideoStabilizationMode = .auto
                        }
                    }
                    
                    self.getCameraSession().commitConfiguration()
                } catch {
                    print("Error occurred while creating video device input: \(error)")
                }
            }
        }
    }
    
    @objc
    func subjectAreaDidChange(notification: NSNotification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        focus(with: .continuousAutoFocus, exposureMode: .continuousAutoExposure, at: devicePoint, monitorSubjectAreaChange: false)
    }
    
    fileprivate func focus(with focusMode: AVCaptureDevice.FocusMode,
                           exposureMode: AVCaptureDevice.ExposureMode,
                           at devicePoint: CGPoint,
                           monitorSubjectAreaChange: Bool) {
        
        sessionQueue.async {
            let device = self.videoDeviceInput.device
            do {
                try device.lockForConfiguration()
                
                /*
                 Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
                 Call set(Focus/Exposure)Mode() to apply the new point of interest.
                 */
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = focusMode
                }
                
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = exposureMode
                }
                
                device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                device.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        }
    }
    func focusToPoint(point: CGPoint) {
        if let device = defaultVideoDevice {
            
            do {
                try device.lockForConfiguration()
                
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = point
                    device.focusMode = AVCaptureDevice.FocusMode.continuousAutoFocus
                }
                
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = point
                    device.exposureMode = AVCaptureDevice.ExposureMode.continuousAutoExposure
                }
                
                device.isSubjectAreaChangeMonitoringEnabled = true
                device.unlockForConfiguration()
            } catch {
                print("focusToPoint ERROR \(error)")
            }
        }
    }
    
    /// - Tag: HandleSystemPressure
    @available(iOS 11.1, *)
    fileprivate func setRecommendedFrameRateRangeForPressureState(systemPressureState: AVCaptureDevice.SystemPressureState) {
        /*
         The frame rates used here are for demonstrative purposes only for this app.
         Your frame rate throttling may be different depending on your app's camera configuration.
         */
        let pressureLevel = systemPressureState.level
        if pressureLevel == .serious || pressureLevel == .critical {
            if self.movieFileOutput == nil || self.movieFileOutput?.isRecording == false {
                do {
                    try self.videoDeviceInput.device.lockForConfiguration()
                    print("WARNING: Reached elevated system pressure level: \(pressureLevel). Throttling frame rate.")
                    self.videoDeviceInput.device.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: 20 )
                    self.videoDeviceInput.device.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: 15 )
                    self.videoDeviceInput.device.unlockForConfiguration()
                } catch {
                    print("Could not lock device for configuration: \(error)")
                }
            }
        } else if pressureLevel == .shutdown {
            print("Session stopped running due to shutdown system pressure level.")
        }
    }
    
    func toggleFlashMode(){
        //STARTING FROM AUTO TOGGLE FLASH TO NEXT MODE
        if self.flashMode == .auto {
            self.flashMode = .on
        }else if self.flashMode == .on {
            self.flashMode = .off
        }else if self.flashMode == .off {
            self.flashMode = .auto
        }
    }
    
    func shutdownFlash(){
        self.flashMode = .off
        guard let device = defaultVideoDevice else { return }
        
        if device.hasTorch {
            do {
                try device.lockForConfiguration()
                device.torchMode = .off
                device.unlockForConfiguration()
            } catch {
                print("Torch could not be used")
            }
        } else {
            print("Torch is not available")
        }
    }
}
