//
//  ViewController.swift
//  SquareCam-Swift
//
//  Created by Wayn Liu on 15/1/1.
//
//

import UIKit
import Foundation

import AVFoundation
import CoreImage
import CoreMedia
import ImageIO
import AssetsLibrary

class ViewController: UIViewController, UIGestureRecognizerDelegate,  AVCaptureVideoDataOutputSampleBufferDelegate {
    
    // used for KVO observation of the @"capturingStillImage" property to perform flash bulb animation
    let AVCaptureStillImageIsCapturingStillImageContext = "AVCaptureStillImageIsCapturingStillImageContext"
    
    func DegreesToRadians(degrees : CGFloat) -> CGFloat {
        return (degrees * CGFloat(M_PI / 180))
    }
    
    // MARK: Properites
    
    @IBOutlet weak var previewView : UIView!
    @IBOutlet weak var camerasControl : UISegmentedControl!
    @IBOutlet weak var eyeLeftLabel : UILabel!
    @IBOutlet weak var eyeRightLabel : UILabel!
    @IBOutlet weak var mouthLabel : UILabel!
    
    var previewLayer : AVCaptureVideoPreviewLayer!
    var videoDataOutput : AVCaptureVideoDataOutput!
    var detectFaces : Bool!
    var videoDataOutputQueue : dispatch_queue_t!
    var stillImageOutput : AVCaptureStillImageOutput!
    var flashView : UIView!
    var square : UIImage!
    var isUsingFrontFacingCamera : Bool!
    var faceDetector : CIDetector!
    var beginGestureScale : CGFloat!
    var effectiveScale : CGFloat!

    // MARK: View Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        
        setupAVCapture()
        square = UIImage(named: "squareBox")
        
        var detectorOptions = [CIDetectorAccuracy: CIDetectorAccuracyHigh, CIDetectorTracking: true]
        faceDetector = CIDetector(ofType: CIDetectorTypeFace, context: nil, options: detectorOptions as [NSObject : AnyObject])
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    // MARKS: Actions
    
    @IBAction func takePicture (sender : UIBarButtonItem!) {
        
    }
    
    @IBAction func switchCameras (sender : UISegmentedControl!) {
        var desiredPosition : AVCaptureDevicePosition
        desiredPosition = isUsingFrontFacingCamera == true ? AVCaptureDevicePosition.Back : AVCaptureDevicePosition.Front
        
        for d in AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo) as! [AVCaptureDevice] {
            
            if d.position == desiredPosition {
                
                previewLayer.session.beginConfiguration()
                
                var input : AVCaptureDeviceInput = AVCaptureDeviceInput.deviceInputWithDevice(d, error: nil) as! AVCaptureDeviceInput
                for oldInput in previewLayer.session.inputs as! [AVCaptureInput] {
                    previewLayer.session.removeInput(oldInput)
                }
                
                previewLayer.session.addInput(input)
                previewLayer.session.commitConfiguration()
            }
        }
        
        isUsingFrontFacingCamera = !isUsingFrontFacingCamera
    }
    
    @IBAction func handlePinchGesture (sender : UIGestureRecognizer!) {
        
    }
    
    @IBAction func toggleFaceDetection (sender : UISwitch!) {
        detectFaces = sender.on
        videoDataOutput.connectionWithMediaType(AVMediaTypeVideo).enabled = detectFaces
        if !detectFaces {
            
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                self.drawFaceBoxesForFeatures([], clap: CGRectZero, orientation: UIDeviceOrientation.Portrait)
            })
        }
    }
    
    // Setup functions
    
    func setupAVCapture() {
        
        var error : NSError?
        
        var session : AVCaptureSession = AVCaptureSession()
        session.sessionPreset = AVCaptureSessionPreset640x480
        
        // Select a video device, make an input
        var device : AVCaptureDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo)
        var deviceInput : AVCaptureDeviceInput = AVCaptureDeviceInput.deviceInputWithDevice(device, error:&error) as! AVCaptureDeviceInput
        
        isUsingFrontFacingCamera = false
        detectFaces = false
        
        if session.canAddInput(deviceInput) {
            session.addInput(deviceInput)
        }
        
        stillImageOutput = AVCaptureStillImageOutput()

        // Make a video data output
        videoDataOutput = AVCaptureVideoDataOutput()
        // we want BGRA, both CoreGraphics and OpenGL work well with 'BGRA'
        var rgbOutputSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCMPixelFormat_32BGRA as NSNumber]
        
        videoDataOutput.videoSettings = rgbOutputSettings
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        
        videoDataOutputQueue = dispatch_queue_create("VideoDataOutputQueue", DISPATCH_QUEUE_SERIAL)
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
        }
        videoDataOutput.connectionWithMediaType(AVMediaTypeVideo).enabled = false
        
        effectiveScale = 1.0
        
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.backgroundColor = UIColor.blackColor().CGColor
        previewLayer.videoGravity = AVLayerVideoGravityResizeAspect
        var rootLayer : CALayer = previewView.layer
        rootLayer.masksToBounds = true
        previewLayer.frame = rootLayer.bounds
        rootLayer.addSublayer(previewLayer)
        session.startRunning()
    }
    
    func teardownAVCapture() {
        videoDataOutput = nil
        videoDataOutputQueue = nil
        previewLayer.removeFromSuperlayer()
        previewLayer = nil
    }

    // MARK: Delegates
    
    func captureOutput(captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
        // got an image
        let pixelBuffer : CVPixelBufferRef = CMSampleBufferGetImageBuffer(sampleBuffer)
        let attachments : [NSObject: AnyObject] = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, pixelBuffer, CMAttachmentMode( kCMAttachmentMode_ShouldPropagate)).takeRetainedValue() as [NSObject : AnyObject]
        
        let ciImage : CIImage = CIImage(CVPixelBuffer: pixelBuffer, options: attachments)
        
        let curDeviceOrientation : UIDeviceOrientation = UIDevice.currentDevice().orientation
        var exifOrientation : Int
        
        enum DeviceOrientation : Int {
            case PHOTOS_EXIF_0ROW_TOP_0COL_LEFT			= 1, //   1  =  0th row is at the top, and 0th column is on the left (THE DEFAULT).
            PHOTOS_EXIF_0ROW_TOP_0COL_RIGHT			= 2, //   2  =  0th row is at the top, and 0th column is on the right.
            PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT      = 3, //   3  =  0th row is at the bottom, and 0th column is on the right.
            PHOTOS_EXIF_0ROW_BOTTOM_0COL_LEFT       = 4, //   4  =  0th row is at the bottom, and 0th column is on the left.
            PHOTOS_EXIF_0ROW_LEFT_0COL_TOP          = 5, //   5  =  0th row is on the left, and 0th column is the top.
            PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP         = 6, //   6  =  0th row is on the right, and 0th column is the top.
            PHOTOS_EXIF_0ROW_RIGHT_0COL_BOTTOM      = 7, //   7  =  0th row is on the right, and 0th column is the bottom.
            PHOTOS_EXIF_0ROW_LEFT_0COL_BOTTOM       = 8  //   8  =  0th row is on the left, and 0th column is the bottom.
        }
        
        switch curDeviceOrientation {
            
        case UIDeviceOrientation.PortraitUpsideDown:
            exifOrientation = DeviceOrientation.PHOTOS_EXIF_0ROW_LEFT_0COL_BOTTOM.rawValue
        case UIDeviceOrientation.LandscapeLeft:
            if isUsingFrontFacingCamera == true {
                exifOrientation = DeviceOrientation.PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT.rawValue
            } else {
                exifOrientation = DeviceOrientation.PHOTOS_EXIF_0ROW_TOP_0COL_LEFT.rawValue
            }
        case UIDeviceOrientation.LandscapeRight:
            if isUsingFrontFacingCamera == true {
                exifOrientation = DeviceOrientation.PHOTOS_EXIF_0ROW_TOP_0COL_LEFT.rawValue
            } else {
                exifOrientation = DeviceOrientation.PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT.rawValue
            }
        default:
            exifOrientation = DeviceOrientation.PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP.rawValue
        }
        
        var imageOptions : NSDictionary = [CIDetectorImageOrientation : NSNumber(integer: exifOrientation), CIDetectorSmile : true, CIDetectorEyeBlink : true]
        
        var features = faceDetector.featuresInImage(ciImage, options: imageOptions as [NSObject : AnyObject])
        
        // get the clean aperture
        // the clean aperture is a rectangle that defines the portion of the encoded pixel dimensions
        // that represents image data valid for display.
        var fdesc : CMFormatDescriptionRef = CMSampleBufferGetFormatDescription(sampleBuffer)
        var clap : CGRect = CMVideoFormatDescriptionGetCleanAperture(fdesc, 0)
        
        dispatch_async(dispatch_get_main_queue(), { () -> Void in
            self.drawFaceBoxesForFeatures(features, clap: clap, orientation: curDeviceOrientation)
        })
    }
    
    // called asynchronously as the capture output is capturing sample buffers, this method asks the face detector (if on)
    // to detect features and for each draw the red square in a layer and set appropriate orientation
    func drawFaceBoxesForFeatures(features : NSArray, clap : CGRect, orientation : UIDeviceOrientation) {
        
        var sublayers : NSArray = previewLayer.sublayers
        var sublayersCount : Int = sublayers.count
        var currentSublayer : Int = 0
        var featuresCount : Int = features.count
        var currentFeature : Int = 0
        
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        
        // hide all the face layers
        for layer in sublayers as! [CALayer] {
            if (layer.name != nil && layer.name == "FaceLayer") {
                layer.hidden = true
            }
        }
        
        if ( features.count == 0 || !detectFaces ) {
            CATransaction.commit()
            return
        }
        
        var parentFrameSize : CGSize = previewView.frame.size
        var gravity : NSString = previewLayer.videoGravity
        
        let previewBox : CGRect = ViewController.videoPreviewBoxForGravity(gravity, frameSize: parentFrameSize, apertureSize: clap.size)
        
        for ff in features as! [CIFaceFeature] {
            // set text on label
            var x : CGFloat = 0.0, y : CGFloat = 0.0
            if ff.hasLeftEyePosition {
                x = ff.leftEyePosition.x
                y = ff.leftEyePosition.y
                eyeLeftLabel.text = ff.leftEyeClosed ? "(\(x) \(y))" : "(\(x) \(y))" + "👀"
            }
            
            if ff.hasRightEyePosition {
                x = ff.rightEyePosition.x
                y = ff.rightEyePosition.y
                eyeRightLabel.text = ff.rightEyeClosed ? "(\(x) \(y))" : "(\(x) \(y))" + "👀"
            }
            
            if ff.hasMouthPosition {
                x = ff.mouthPosition.x
                y = ff.mouthPosition.y
                mouthLabel.text = ff.hasSmile ? "\(x) \(y)" + "😊" : "(\(x) \(y))"
            }
            
            // find the correct position for the square layer within the previewLayer
            // the feature box originates in the bottom left of the video frame.
            // (Bottom right if mirroring is turned on)
            var faceRect : CGRect = ff.bounds
            
            // flip preview width and height
            var temp : CGFloat = faceRect.width
            faceRect.size.width = faceRect.height
            faceRect.size.height = temp
            temp = faceRect.origin.x
            faceRect.origin.x = faceRect.origin.y
            faceRect.origin.y = temp
            // scale coordinates so they fit in the preview box, which may be scaled
            let widthScaleBy = previewBox.size.width / clap.size.height
            let heightScaleBy = previewBox.size.height / clap.size.width
            faceRect.size.width *= widthScaleBy
            faceRect.size.height *= heightScaleBy
            faceRect.origin.x *= widthScaleBy
            faceRect.origin.y *= heightScaleBy
            
            faceRect = CGRectOffset(faceRect, previewBox.origin.x, previewBox.origin.y)
            var featureLayer : CALayer? = nil
            // re-use an existing layer if possible
            while (featureLayer == nil) && (currentSublayer < sublayersCount) {
                
                var currentLayer : CALayer = sublayers.objectAtIndex(currentSublayer++) as! CALayer
                
                if currentLayer.name == nil {
                    continue
                }
                var name : NSString = currentLayer.name
                if name.isEqualToString("FaceLayer") {
                    featureLayer = currentLayer;
                    currentLayer.hidden = false
                }
            }
            
            // create a new one if necessary
            if featureLayer == nil {
                featureLayer = CALayer()
                featureLayer?.contents = square.CGImage
                featureLayer?.name = "FaceLayer"
                previewLayer.addSublayer(featureLayer)
            }
            
            featureLayer?.frame = faceRect
            
            currentFeature++
        }
        
        CATransaction.commit()
    }
    
    // find where the video box is positioned within the preview layer based on the video size and gravity
    class func videoPreviewBoxForGravity(gravity : NSString, frameSize : CGSize, apertureSize : CGSize) -> CGRect {
        let apertureRatio : CGFloat = apertureSize.height / apertureSize.width
        let viewRatio : CGFloat = frameSize.width / frameSize.height
        
        var size : CGSize = CGSizeZero
        if gravity.isEqualToString(AVLayerVideoGravityResizeAspectFill) {
            if viewRatio > apertureRatio {
                size.width = frameSize.width
                size.height = apertureSize.width * (frameSize.width / apertureSize.height)
            } else {
                size.width = apertureSize.height * (frameSize.height / apertureSize.width)
                size.height = frameSize.height
            }
        } else if gravity.isEqualToString(AVLayerVideoGravityResizeAspect) {
            if viewRatio > apertureRatio {
                size.width = apertureSize.height * (frameSize.height / apertureSize.width)
                size.height = frameSize.height
            } else {
                size.width = frameSize.width
                size.height = apertureSize.width * (frameSize.width / apertureSize.height)
            }
        } else if gravity.isEqualToString(AVLayerVideoGravityResize) {
            size.width = frameSize.width
            size.height = frameSize.height
        }
        
        var videoBox : CGRect = CGRectZero
        videoBox.size = size
        if size.width < frameSize.width {
            videoBox.origin.x = (frameSize.width - size.width) / 2;
        } else {
            videoBox.origin.x = (size.width - frameSize.width) / 2;
        }
        
        if size.height < frameSize.height {
            videoBox.origin.y = (frameSize.height - size.height) / 2;
        } else {
            videoBox.origin.y = (size.height - frameSize.height) / 2;
        }
        
        return videoBox
    }
}

