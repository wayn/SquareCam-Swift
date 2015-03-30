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

class ViewController: UIViewController, UIGestureRecognizerDelegate,  AVCaptureAudioDataOutputSampleBufferDelegate {
    
    // used for KVO observation of the @"capturingStillImage" property to perform flash bulb animation
    let AVCaptureStillImageIsCapturingStillImageContext = "AVCaptureStillImageIsCapturingStillImageContext"
    
    func DegreesToRadians(degrees : CGFloat) -> CGFloat {
        return (degrees * CGFloat(M_PI / 180))
    }
    
    // MARK: Properites
    
    @IBOutlet weak var previewView : UIView!
    @IBOutlet weak var camerasControl : UISegmentedControl!
    
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
        
        setupAVCapture()
        square = UIImage(named: "squarePNG")
        
        var detectorOptions = [CIDetectorAccuracy: CIDetectorAccuracyLow]
        faceDetector = CIDetector(ofType: CIDetectorTypeFace, context: nil, options: detectorOptions)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    // MARKS: Actions
    
    @IBAction func takePicture (sender : UIBarButtonItem!) {
        
    }
    
    @IBAction func switchCameras (sender : UISegmentedControl!) {
        
    }
    
    @IBAction func handlePinchGesture (sender : UIGestureRecognizer!) {
        
    }
    
    @IBAction func toggleFaceDetection (sender : UISwitch!) {
        
    }
    
    // Setup functions
    
    func setupAVCapture() {
        
        var error : NSError?
        
        var session : AVCaptureSession = AVCaptureSession()
        session.sessionPreset = AVCaptureSessionPreset640x480
        
        // Select a video device, make an input
        var device : AVCaptureDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo)
        var deviceInput : AVCaptureDeviceInput = AVCaptureDeviceInput.deviceInputWithDevice(device, error:&error) as AVCaptureDeviceInput
        
        isUsingFrontFacingCamera = false
        
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
        
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
        }
        videoDataOutput.connectionWithMediaType(AVMediaTypeVideo).enabled = true
        
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
        let attachments : [NSObject: AnyObject] = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, pixelBuffer, CMAttachmentMode( kCMAttachmentMode_ShouldPropagate)).takeRetainedValue()
        
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
        
        var imageOptions : NSDictionary = [CIDetectorImageOrientation : NSNumber(integer: exifOrientation)]
        
        var features = faceDetector.featuresInImage(ciImage, options: imageOptions)
        
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
        
        var subLayers : NSArray = previewLayer.sublayers
        var subLayersCount = subLayers.count
        var currentSublayer = 0
        var featuresCount = features.count
        var currentFeature = 0
        
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        
        // hide all the face layers
        for layer in subLayers as [CALayer] {
            if (layer.name == "FaceLayer") {
                layer.hidden = true
            }
        }
        
        if ( features.count == 0 || !detectFaces ) {
            CATransaction.commit()
            return
        }
        
        var parentFrameSize : CGSize = previewView.frame.size
        var gravity : NSString = previewLayer.videoGravity
    }
    
    // find where the video box is positioned within the preview layer based on the video size and gravity
    func videoPreviewBoxForGravity(gravity : NSString, frameSize : CGSize, apertureSize : CGSize) {
        
    }
}

