//
//  ViewController.m
//  DetectFaces-OC
//
//  Created by 陈江林 on 2019/9/4.
//  Copyright © 2019 陈江林. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
@interface ViewController ()<AVCaptureMetadataOutputObjectsDelegate>
@property(nonatomic,strong) AVCaptureSession *captureSession;
@property(nonatomic, strong)AVCaptureMetadataOutput *metadataOutput;
@property(nonatomic, strong)AVCaptureDeviceInput *activeVideoInput;
@property(nonatomic, strong)AVCaptureStillImageOutput *imageOutput;
@property(nonatomic, strong)NSMutableDictionary *faceLayers;
@property(nonatomic, strong)AVCaptureVideoPreviewLayer *previewLayer;
@property(nonatomic, strong)CALayer *overlayLayer;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    self.captureSession = [[AVCaptureSession alloc] init];
    self.captureSession.sessionPreset = AVCaptureSessionPresetHigh;
    
    AVCaptureDevice *videoDevice = [self cameraWithPosition:AVCaptureDevicePositionFront];
    
    AVCaptureDeviceInput *videoInput =
    [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:nil];
    if (videoInput) {
        if ([self.captureSession canAddInput:videoInput]) {
            [self.captureSession addInput:videoInput];
            self.activeVideoInput = videoInput;
        } else {
            
        }
    }
    
    // Setup the still image output
    self.imageOutput = [[AVCaptureStillImageOutput alloc] init];
    //self.imageOutput.outputSettings = @{AVVideoCodecKey : AVVideoCodecJPEG};
    
    if ([self.captureSession canAddOutput:self.imageOutput]) {
        [self.captureSession addOutput:self.imageOutput];
    } else {
        
    }
    
    // 添加元数据输出捕捉
    self.metadataOutput = [[AVCaptureMetadataOutput alloc] init];
    if ([self.captureSession canAddOutput:self.metadataOutput]) {
        [self.captureSession addOutput:self.metadataOutput];
        // 添加新的捕捉会话输出
        
        NSArray *metadataObjectTypes = @[AVMetadataObjectTypeFace];
        self.metadataOutput.metadataObjectTypes = metadataObjectTypes;
        //指定输出的元数据类型。
        
        dispatch_queue_t mainqueue = dispatch_get_main_queue();
        [self.metadataOutput setMetadataObjectsDelegate:self queue:mainqueue];
        //有新的元数据被检测到时，会都回调代理AVCaptureMetadataOutputObjectsDelegate中的方法
        //可以自定义系列的调度队列，不过由于人脸检测用到硬件加速，而且许多人物都要在主线程中执行，所以需要为这个参数指定主队列。
    }
    self.previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.captureSession];
    self.previewLayer.frame = self.view.frame;
    self.faceLayers = [NSMutableDictionary dictionary];
    // 存放人脸数据:@{faceId:layer}
    
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    
    self.overlayLayer = [CALayer layer];
    self.overlayLayer.frame = self.view.bounds;
    self.overlayLayer.sublayerTransform = THMakePerspectiveTransform(10000);
    //设置sublayerTransform属性为CATransform3D，可以对所有子层应用视角转换。
    [self.previewLayer addSublayer:self.overlayLayer];
    
    [self.view.layer addSublayer:self.previewLayer];

    [self startSession];

}
- (AVCaptureDevice *)cameraWithPosition:(AVCaptureDevicePosition)position{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for ( AVCaptureDevice *device in devices )
        if ( device.position == position ){
            return device;
        }
    return nil;
}
static CATransform3D THMakePerspectiveTransform(CGFloat eyePosition) {
    CATransform3D transform = CATransform3DIdentity;
    transform.m34 = -1.0/eyePosition;
    return transform;
    
    // CoreAnimation中所使用的transformation matrix类型，用于进行缩放和旋转等转换。
    // 设置m34可以应用视角转换，即让子层绕Y轴旋转。
}

- (void)startSession {
    if (![self.captureSession isRunning]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.captureSession startRunning];
        });
    }
}

- (void)stopSession {
    if ([self.captureSession isRunning]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.captureSession stopRunning];
        });
    }
}

#pragma  -- mark AVCaptureMetadataOutputObjectsDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputMetadataObjects:(NSArray *)metadataObjects
       fromConnection:(AVCaptureConnection *)connection {
    
    //metadataObjects 就是人脸检测结果的元数据，
    //包含多个人脸数据信息，可以做相应处理，
    // 比如将要实现的，在人脸上画框标记。
    NSArray *transformedFaces = [self transformedFacesFromFaces:metadataObjects];
    // Listing 7.11
    
    
    NSMutableArray *lostFaces = [self.faceLayers.allKeys mutableCopy];
    for (AVMetadataFaceObject *face in transformedFaces) {
        NSNumber *faceId = @(face.faceID);
        [lostFaces removeObject:faceId];
        // 如果对应faceId还在，将它从要删除视图的数组中移除。
        
        CALayer *layer = self.faceLayers[faceId];
        // 查找faceId对应的Layer
        if (!layer) {
            //如果没有对应layer，说明是新加入的faceId，需要新建对应来layer
            layer = [self makeFaceLayer];
            [self.overlayLayer addSublayer:layer];
            self.faceLayers[faceId] = layer;
        }
        layer.transform = CATransform3DIdentity;
        //对每个人脸图层，先将他的tansform属性设置为CATransform3DIdentity
        //然后重新设置之前的用过的变换
        
        layer.frame = face.bounds;
        
        //添加在for循环之中，创建重置完layer.transform之后。
            
            if (face.hasRollAngle) {
                //检测人脸是否具有有效的倾斜角，如果没有获取属性会有异常。
                //如果有rollAngle，则获取相应的CATransform3D
                //将它与标识变换关联在一起，并设置图层的transform属性
                CATransform3D t = [self transformForRollAngle:face.rollAngle];
                
                layer.transform = CATransform3DConcat(layer.transform, t);
            }
        
        if (face.hasYawAngle) {
            
            //检测人脸是否具有有效的偏转角，如果没有获取属性会有异常。
            //如果有hasYawAngle，则获取相应的CATransform3D
            //将它与标识变换关联在一起，并设置图层的transform属性
            CATransform3D t = [self transformForYawAngle:face.hasYawAngle];
            layer.transform = CATransform3DConcat(layer.transform, t);
        }
        
    }
    
    // 删除已经移除人脸对应的图层
    for (NSNumber *faceId in lostFaces) {
        CALayer *layer = self.faceLayers[faceId];
        [layer removeFromSuperlayer];
        [self.faceLayers removeObjectForKey:faceId];
    }
    
}
- (NSArray *)transformedFacesFromFaces:(NSArray *)faces {
    
    // Listing 7.11
    NSMutableArray *transformedFaces = [[NSMutableArray alloc] init];
    for (AVMetadataObject *face  in faces) {
        AVMetadataObject *transformedFace = [self.previewLayer transformedMetadataObjectForMetadataObject:face];
        //将设备坐标空间的人脸对象转化为视图空间对象集合
        
        [transformedFaces addObject:transformedFace];
        //得到一个由AVMetadataFaceObject实例组成的集合，其中有创建用户界面所需要的坐标点
        
    }
    return transformedFaces;
    
}
// 创建标记人脸的方框
- (CALayer *)makeFaceLayer {
    
    CALayer *layer= [CALayer layer];
    layer.contents = (__bridge id _Nullable)([UIImage imageNamed:@"new-face"].CGImage);
    layer.borderWidth = 5.0f;
    layer.borderColor = [UIColor colorWithRed:0.188 green:0.517 blue:0.877 alpha:1.0].CGColor;
    return layer;
    
}
// Rotate around Z-axis
- (CATransform3D)transformForRollAngle:(CGFloat)rollAngleInDegrees {
    
    
    CGFloat rollAngleInRadians = THDegreesToRadians(rollAngleInDegrees);
    //从对象得到rollAngle的单位是度，需要转换为弧度制。
    //将转换结果赋值给CATransform3DMakeRotation函数
    //x,y,z轴对应参数分别以0,0,1，得到的就是绕Z轴的倾斜角旋转转换、
    return CATransform3DMakeRotation(rollAngleInRadians, 0.f, 0.f, 1.f);
    
}
// Rotate around Y-axis
- (CATransform3D)transformForYawAngle:(CGFloat)yawAngleInDegrees {
    
    // Listing 7.13
    
    //从对象得到hasYawAngle的单位是度，需要转换为弧度制。
    //将转换结果赋值给CATransform3DMakeRotation函数
    //x,y,z轴对应参数分别以0,-1,0，得到的就是绕Y轴的倾斜角旋转转换、
    
    CGFloat yawAngleInRadians = THDegreesToRadians(yawAngleInDegrees);
    CATransform3D yawAngleTransform = CATransform3DMakeRotation(yawAngleInRadians, 0.f, -1.f, 0.f);
    
    //由于overlayer需要应用sublayerTransform，图层hi投影到Z轴
    //人脸从一次移动到另一侧时就会出现3D效果
    return CATransform3DConcat(yawAngleTransform, [self orientationTransform]);
    
    //应用程序用户界面固定为垂直方向，不过需要为设备方向计算一个相应的旋转变换。
    //如果不这样做，会导致人脸图层的便宜效果不正确，这一转换会同其他变换关联。
    
}
- (CATransform3D)orientationTransform {
    
    // Listing 7.13
    CGFloat angle = 0.0;
    
    switch ([UIDevice currentDevice].orientation) {
        case UIDeviceOrientationPortraitUpsideDown:
            angle = M_PI;
            break;
        case UIDeviceOrientationLandscapeRight:
            angle = -M_PI;
            break;
        case UIDeviceOrientationLandscapeLeft:
            angle = M_PI;
            break;
        case UIDeviceOrientationPortrait:
            angle = 0;
            break;
            
            
        default:
            break;
    }
    
    return CATransform3DMakeRotation(angle, 0.f, 0.f, 1.f);
    //    return CATransform3DIdentity;
}
static CGFloat THDegreesToRadians(CGFloat degrees) {
    
    // Listing 7.13
    return degrees * M_PI / 180;
}



@end
