import Capacitor
import Foundation
import AVFoundation

extension UIImage {
    func scaled(to maxSize: CGSize) -> UIImage {
        let aspectRatio = self.size.width / self.size.height
        var newSize = CGSize(
            width: min(self.size.width, maxSize.width),
            height: min(self.size.height, maxSize.height)
        )
        
        if newSize.width < maxSize.width || newSize.height < maxSize.height {
            if aspectRatio > 1 {
                newSize = CGSize(width: maxSize.width, height: maxSize.width / aspectRatio)
            } else {
                newSize = CGSize(width: maxSize.height * aspectRatio, height: maxSize.height)
            }
        }
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { context in
            context.cgContext.interpolationQuality = .medium // Lagere kwaliteit voor snelheid
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

@objc(BarcodeScanner)
public class BarcodeScanner: CAPPlugin, AVCaptureMetadataOutputObjectsDelegate, AVCapturePhotoCaptureDelegate {

    class CameraView: UIView {
        var videoPreviewLayer: AVCaptureVideoPreviewLayer?

        func interfaceOrientationToVideoOrientation(_ orientation: UIInterfaceOrientation) -> AVCaptureVideoOrientation {
            switch orientation {
            case .portrait:
                return .portrait
            case .portraitUpsideDown:
                return .portraitUpsideDown
            case .landscapeLeft:
                return .landscapeLeft
            case .landscapeRight:
                return .landscapeRight
            default:
                return .portraitUpsideDown
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            if let sublayers = self.layer.sublayers {
                for layer in sublayers {
                    layer.frame = self.bounds
                }
            }
            
            if let interfaceOrientation = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.windowScene?.interfaceOrientation {
                self.videoPreviewLayer?.connection?.videoOrientation = interfaceOrientationToVideoOrientation(interfaceOrientation)
            }
        }

        func addPreviewLayer(_ previewLayer: AVCaptureVideoPreviewLayer?) {
            previewLayer!.videoGravity = .resizeAspectFill
            previewLayer!.frame = self.bounds
            self.layer.addSublayer(previewLayer!)
            self.videoPreviewLayer = previewLayer
        }

        func removePreviewLayer() {
            if self.videoPreviewLayer != nil {
                self.videoPreviewLayer!.removeFromSuperlayer()
                self.videoPreviewLayer = nil
            }
        }
    }

    var cameraView: CameraView!
    var captureSession: AVCaptureSession?
    var captureVideoPreviewLayer: AVCaptureVideoPreviewLayer?
    var metaOutput: AVCaptureMetadataOutput?

    var currentCamera: Int = 0
    var frontCamera: AVCaptureDevice?
    var backCamera: AVCaptureDevice?

    var isScanning: Bool = false
    var shouldRunScan: Bool = false
    var didRunCameraSetup: Bool = false
    var didRunCameraPrepare: Bool = false
    var isBackgroundHidden: Bool = false
    var previousBackgroundColor: UIColor? = UIColor.white

    var savedCall: CAPPluginCall? = nil
    var scanningPaused: Bool = false
    var lastScanResult: String? = nil

    // Voor foto-opname
    var photoCaptureSession: AVCaptureSession?
    var photoOutput: AVCapturePhotoOutput?

    enum SupportedFormat: String, CaseIterable {
        // 1D Product
        //!\ UPC_A is onderdeel van EAN_13 volgens Apple docs
        case UPC_E
        //!\ UPC_EAN_EXTENSION wordt niet ondersteund door AVFoundation
        case EAN_8
        case EAN_13
        // 1D Industrial
        case CODE_39
        case CODE_39_MOD_43
        case CODE_93
        case CODE_128
        //!\ CODABAR wordt niet ondersteund door AVFoundation
        case ITF
        case ITF_14
        // 2D
        case AZTEC
        case DATA_MATRIX
        //!\ MAXICODE wordt niet ondersteund door AVFoundation
        case PDF_417
        case QR_CODE
        //!\ RSS_14 en RSS_EXPANDED worden niet ondersteund door AVFoundation

        var value: AVMetadataObject.ObjectType {
            switch self {
            case .UPC_E: return .upce
            case .EAN_8: return .ean8
            case .EAN_13: return .ean13
            case .CODE_39: return .code39
            case .CODE_39_MOD_43: return .code39Mod43
            case .CODE_93: return .code93
            case .CODE_128: return .code128
            case .ITF: return .interleaved2of5
            case .ITF_14: return .itf14
            case .AZTEC: return .aztec
            case .DATA_MATRIX: return .dataMatrix
            case .PDF_417: return .pdf417
            case .QR_CODE: return .qr
            }
        }
    }

    var targetedFormats = [AVMetadataObject.ObjectType]()

    enum CaptureError: Error {
        case backCameraUnavailable
        case frontCameraUnavailable
        case couldNotCaptureInput(error: NSError)
    }

    public override func load() {
        self.cameraView = CameraView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height))
        self.cameraView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    private func hasCameraPermission() -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
        return status == .authorized
    }

    private func setupCamera(cameraDirection: String? = "back") -> Bool {
        do {
            var cameraDir = cameraDirection
            cameraView.backgroundColor = UIColor.clear
            self.webView!.superview!.insertSubview(cameraView, belowSubview: self.webView!)
            
            let availableVideoDevices = discoverCaptureDevices()
            for device in availableVideoDevices {
                if device.position == .back {
                    backCamera = device
                } else if device.position == .front {
                    frontCamera = device
                }
            }
            // Oudere iPods hebben geen backcamera
            if cameraDir == "back" {
                if backCamera == nil {
                    cameraDir = "front"
                }
            } else {
                if frontCamera == nil {
                    cameraDir = "back"
                }
            }
            let input: AVCaptureDeviceInput
            input = try self.createCaptureDeviceInput(cameraDirection: cameraDir)
            captureSession = AVCaptureSession()
            captureSession!.addInput(input)
            metaOutput = AVCaptureMetadataOutput()
            captureSession!.addOutput(metaOutput!)
            metaOutput!.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            captureVideoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
            cameraView.addPreviewLayer(captureVideoPreviewLayer)
            self.didRunCameraSetup = true
            return true
        } catch CaptureError.backCameraUnavailable {
            // Foutafhandeling
        } catch CaptureError.frontCameraUnavailable {
            // Foutafhandeling
        } catch CaptureError.couldNotCaptureInput {
            // Foutafhandeling
        } catch {
            // Foutafhandeling
        }
        return false
    }

    @available(swift, deprecated: 5.6, message: "New Xcode? Check if `AVCaptureDevice.DeviceType` has new types and add them accordingly.")
    private func discoverCaptureDevices() -> [AVCaptureDevice] {
        if #available(iOS 13.0, *) {
            return AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTripleCamera, .builtInDualCamera, .builtInTelephotoCamera, .builtInTrueDepthCamera, .builtInUltraWideCamera, .builtInDualWideCamera, .builtInWideAngleCamera], mediaType: .video, position: .unspecified).devices
        } else {
            return AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInDualCamera, .builtInWideAngleCamera, .builtInTelephotoCamera, .builtInTrueDepthCamera], mediaType: .video, position: .unspecified).devices
        }
    }

    private func createCaptureDeviceInput(cameraDirection: String? = "back") throws -> AVCaptureDeviceInput {
        var captureDevice: AVCaptureDevice
        if cameraDirection == "back" {
            if let backCam = backCamera {
                captureDevice = backCam
            } else {
                throw CaptureError.backCameraUnavailable
            }
        } else {
            if let frontCam = frontCamera {
                captureDevice = frontCam
            } else {
                throw CaptureError.frontCameraUnavailable
            }
        }
        do {
            return try AVCaptureDeviceInput(device: captureDevice)
        } catch let error as NSError {
            throw CaptureError.couldNotCaptureInput(error: error)
        }
    }

    private func dismantleCamera() {
        DispatchQueue.main.async {
            if self.captureSession != nil {
                self.captureSession!.stopRunning()
                self.cameraView.removePreviewLayer()
                self.captureVideoPreviewLayer = nil
                self.metaOutput = nil
                self.captureSession = nil
                self.frontCamera = nil
                self.backCamera = nil
            }
        }
        self.isScanning = false
        self.didRunCameraSetup = false
        self.didRunCameraPrepare = false

        if self.savedCall != nil && !self.shouldRunScan {
            self.savedCall = nil
        }
    }

    private func prepare(_ call: CAPPluginCall? = nil) {
        self.dismantleCamera()
        
        DispatchQueue.main.async {
            if self.setupCamera(cameraDirection: call?.getString("cameraDirection") ?? "back") {
                self.didRunCameraPrepare = true
                
                if self.shouldRunScan {
                    self.scan()
                }
            } else {
                self.shouldRunScan = false
            }
        }
    }

    private func destroy() {
        self.showBackground()
        self.dismantleCamera()
    }

    private func scan() {
        if !self.didRunCameraPrepare {
            var iOS14min = false
            if #available(iOS 14.0, *) { iOS14min = true }
            if !self.hasCameraPermission() && !iOS14min {
                // @TODO: Vraag permissie aan
            } else {
                DispatchQueue.main.async {
                    self.load()
                    self.shouldRunScan = true
                    self.prepare(self.savedCall)
                }
            }
        } else {
            self.didRunCameraPrepare = false
            self.shouldRunScan = false
            targetedFormats = []
            
            if let _targetedFormats = savedCall?.getArray("targetedFormats", String.self), !_targetedFormats.isEmpty {
                _targetedFormats.forEach { targetedFormat in
                    if let value = SupportedFormat(rawValue: targetedFormat)?.value {
                        print(value)
                        targetedFormats.append(value)
                    }
                }
                if targetedFormats.isEmpty {
                    print("The property targetedFormats was not set correctly.")
                }
            }
            
            if targetedFormats.isEmpty {
                for supportedFormat in SupportedFormat.allCases {
                    targetedFormats.append(supportedFormat.value)
                }
            }
            
            DispatchQueue.main.async {
                self.metaOutput!.metadataObjectTypes = self.targetedFormats
                self.captureSession!.startRunning()
            }
            
            self.hideBackground()
            self.isScanning = true
        }
    }

    private func hideBackground() {
        DispatchQueue.main.async {
            self.previousBackgroundColor = self.bridge?.webView!.backgroundColor
            self.bridge?.webView!.isOpaque = false
            self.bridge?.webView!.backgroundColor = UIColor.clear
            self.bridge?.webView!.scrollView.backgroundColor = UIColor.clear
            let javascript = "document.documentElement.style.backgroundColor = 'transparent'"
            self.bridge?.webView!.evaluateJavaScript(javascript)
        }
    }

    private func showBackground() {
        DispatchQueue.main.async {
            let javascript = "document.documentElement.style.backgroundColor = ''"
            self.bridge?.webView!.evaluateJavaScript(javascript) { (_, _) in
                self.bridge?.webView!.isOpaque = true
                self.bridge?.webView!.backgroundColor = self.previousBackgroundColor
                self.bridge?.webView!.scrollView.backgroundColor = self.previousBackgroundColor
            }
        }
    }

    public func metadataOutput(_ captureOutput: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if metadataObjects.isEmpty || !self.isScanning {
            return
        }
        
        let found = metadataObjects[0] as! AVMetadataMachineReadableCodeObject
        if targetedFormats.contains(found.type) {
            var jsObject = PluginCallResultData()
            
            if let value = found.stringValue {
                jsObject["hasContent"] = true
                jsObject["content"] = value
                jsObject["format"] = formatStringFromMetadata(found.type)
            } else {
                jsObject["hasContent"] = false
            }
            
            if let savedCall = savedCall {
                if savedCall.keepAlive {
                    if !scanningPaused && found.stringValue != lastScanResult {
                        lastScanResult = found.stringValue
                        savedCall.resolve(jsObject)
                    }
                } else {
                    savedCall.resolve(jsObject)
                    self.savedCall = nil
                    destroy()
                }
            } else {
                self.destroy()
            }
        }
    }

    private func formatStringFromMetadata(_ type: AVMetadataObject.ObjectType) -> String {
        switch type {
        case .upce:
            return "UPC_E"
        case .ean8:
            return "EAN_8"
        case .ean13:
            return "EAN_13"
        case .code39:
            return "CODE_39"
        case .code39Mod43:
            return "CODE_39_MOD_43"
        case .code93:
            return "CODE_93"
        case .code128:
            return "CODE_128"
        case .interleaved2of5:
            return "ITF"
        case .itf14:
            return "ITF_14"
        case .aztec:
            return "AZTEC"
        case .dataMatrix:
            return "DATA_MATRIX"
        case .pdf417:
            return "PDF_417"
        case .qr:
            return "QR_CODE"
        default:
            return type.rawValue
        }
    }

    @objc func prepare(_ call: CAPPluginCall) {
        self.prepare()
        call.resolve()
    }

    @objc func hideBackground(_ call: CAPPluginCall) {
        self.hideBackground()
        call.resolve()
    }

    @objc func showBackground(_ call: CAPPluginCall) {
        self.showBackground()
        call.resolve()
    }

    @objc func startScan(_ call: CAPPluginCall) {
        self.savedCall = call
        self.scan()
    }

    @objc func startScanning(_ call: CAPPluginCall) {
        self.savedCall = call
        self.savedCall?.keepAlive = true
        scanningPaused = false
        lastScanResult = nil
        self.scan()
    }

    @objc func pauseScanning(_ call: CAPPluginCall) {
        scanningPaused = true
        call.resolve()
    }

    @objc func resumeScanning(_ call: CAPPluginCall) {
        lastScanResult = nil
        scanningPaused = false
        call.resolve()
    }

    @objc func stopScan(_ call: CAPPluginCall) {
        if (call.getBool("resolveScan") ?? false) && self.savedCall != nil {
            var jsObject = PluginCallResultData()
            jsObject["hasContent"] = false
            savedCall?.resolve(jsObject)
            savedCall = nil
        }
        self.destroy()
        call.resolve()
    }

    @objc func checkPermission(_ call: CAPPluginCall) {
        let force = call.getBool("force") ?? false
        var savedReturnObject = PluginCallResultData()
        DispatchQueue.main.async {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                savedReturnObject["granted"] = true
            case .denied:
                savedReturnObject["denied"] = true
            case .notDetermined:
                savedReturnObject["neverAsked"] = true
            case .restricted:
                savedReturnObject["restricted"] = true
            @unknown default:
                savedReturnObject["unknown"] = true
            }
            
            if force && savedReturnObject["neverAsked"] != nil {
                savedReturnObject["asked"] = true
                AVCaptureDevice.requestAccess(for: .video) { authorized in
                    if authorized {
                        savedReturnObject["granted"] = true
                    } else {
                        savedReturnObject["denied"] = true
                    }
                    call.resolve(savedReturnObject)
                }
            } else {
                call.resolve(savedReturnObject)
            }
        }
    }

    @objc func openAppSettings(_ call: CAPPluginCall) {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else { return }
        DispatchQueue.main.async {
            if UIApplication.shared.canOpenURL(settingsUrl) {
                UIApplication.shared.open(settingsUrl, completionHandler: { _ in
                    call.resolve()
                })
            }
        }
    }

    @objc func enableTorch(_ call: CAPPluginCall) {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch, device.isTorchAvailable else { return }
        do {
            try device.lockForConfiguration()
            do {
                try device.setTorchModeOn(level: 1.0)
            } catch {
                print(error)
            }
            device.unlockForConfiguration()
        } catch {
            print(error)
        }
        call.resolve()
    }

    @objc func disableTorch(_ call: CAPPluginCall) {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch, device.isTorchAvailable else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = .off
            device.unlockForConfiguration()
        } catch {
            print(error)
        }
        call.resolve()
    }

    @objc func toggleTorch(_ call: CAPPluginCall) {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch, device.isTorchAvailable else { return }
        if device.torchMode == .on {
            self.disableTorch(call)
        } else {
            self.enableTorch(call)
        }
    }

    @objc func getTorchState(_ call: CAPPluginCall) {
        guard let device = AVCaptureDevice.default(for: .video) else { return }
        var result = PluginCallResultData()
        result["isEnabled"] = (device.torchMode == .on)
        call.resolve(result)
    }

    private func compressImageData(_ data: Data) -> Data? {
        return autoreleasepool { // Geheugenmanagement optimalisatie
            guard let image = UIImage(data: data) else { return nil }
            
            // Kleinere maximale grootte
            let maxSize = CGSize(width: 393, height: 393)
            let scaledImage = image.scaled(to: maxSize)
            
            // Snellere compressie met lagere kwaliteit
            return scaledImage.jpegData(compressionQuality: 0.4)
        }
    }

    @objc func capturePhoto(_ call: CAPPluginCall) {
        savedCall = call
        
        guard hasCameraPermission() else {
            call.reject("Camera permission required")
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            if self.photoCaptureSession == nil {
                self.photoCaptureSession = AVCaptureSession()
                self.photoCaptureSession?.sessionPreset = .vga640x480
                
                do {
                    guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, 
                        for: .video, position: .back) else {
                        call.reject("Camera unavailable")
                        return
                    }
                    
                    let input = try AVCaptureDeviceInput(device: camera)
                    self.photoCaptureSession?.addInput(input)
                    
                    self.photoOutput = AVCapturePhotoOutput()
                    guard self.photoCaptureSession!.canAddOutput(self.photoOutput!) else {
                        call.reject("Cannot add output")
                        return
                    }
                    self.photoCaptureSession?.addOutput(self.photoOutput!)
                    
                    let previewLayer = AVCaptureVideoPreviewLayer(session: self.photoCaptureSession!)
                    previewLayer.videoGravity = .resizeAspectFill
                    DispatchQueue.main.async {
                        self.cameraView.layer.addSublayer(previewLayer)
                    }
                    
                } catch {
                    call.reject("Camera setup error: \(error.localizedDescription)")
                    return
                }
            }
            
            self.photoCaptureSession?.startRunning()
            
            // Directe property assignments
            let settings = AVCapturePhotoSettings()
            settings.isHighResolutionPhotoEnabled = false
            settings.isAutoStillImageStabilizationEnabled = true
            settings.flashMode = AVCaptureDevice.FlashMode.off // Volledig gekwalificeerd pad
            
            self.photoOutput?.capturePhoto(with: settings, delegate: self)
        }
    }

    public func photoOutput(_ output: AVCapturePhotoOutput, 
        didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        
        guard error == nil, let imageData = photo.fileDataRepresentation() else {
            self.cleanupPhotoCapture()
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self,
                let compressedData = self.compressImageData(imageData) else {
                return
            }
            
            // Directe base64 conversie zonder tussenstappen
            let base64String = compressedData.base64EncodedString()
            
            DispatchQueue.main.async {
                self.savedCall?.resolve(["base64Photo": base64String])
                self.cleanupPhotoCapture()
            }
        }
    }

    private func cleanupPhotoCapture() {
        // Stop de sessie indien deze nog actief is
        if self.photoCaptureSession?.isRunning == true {
            self.photoCaptureSession?.stopRunning()
        }
    }
}
