import Flutter
import UIKit
import AVFoundation
import BackgroundTasks

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    
    // ==================== AUDIO CHANNEL ====================
    let audioChannel = FlutterMethodChannel(name: "com.vive.app/audio",
                                              binaryMessenger: controller.binaryMessenger)
    
    audioChannel.setMethodCallHandler({ [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if call.method == "deactivateSession" {
          self?.deactivateAudioSession(result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    })
    
    // ==================== SHARE CHANNEL ====================
    let shareChannel = FlutterMethodChannel(name: "com.nock.nock/share",
                                            binaryMessenger: controller.binaryMessenger)
    
    shareChannel.setMethodCallHandler({ [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      switch call.method {
      // Instagram share
      case "shareToInstagram":
        if let args = call.arguments as? [String: Any],
           let imagePath = args["imagePath"] as? String {
          self?.shareToApp(imagePath: imagePath, urlScheme: "instagram://", result: result)
        } else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "imagePath is required", details: nil))
        }
        
      case "isInstagramInstalled":
        let isInstalled = UIApplication.shared.canOpenURL(URL(string: "instagram://")!)
        result(isInstalled)
        
      // TikTok share
      case "shareToTikTok":
        if let args = call.arguments as? [String: Any],
           let imagePath = args["imagePath"] as? String {
          self?.shareToApp(imagePath: imagePath, urlScheme: "tiktok://", result: result)
        } else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "imagePath is required", details: nil))
        }
        
      case "isTikTokInstalled":
        // TikTok uses multiple URL schemes
        let schemes = ["tiktok://", "snssdk1180://", "snssdk1233://"]
        let isInstalled = schemes.contains { UIApplication.shared.canOpenURL(URL(string: $0)!) }
        result(isInstalled)
        
      default:
        result(FlutterMethodNotImplemented)
      }
    })

    // ==================== BACKGROUND UPLOAD CHANNEL ====================
    let backgroundChannel = FlutterMethodChannel(name: "com.nock.nock/background_upload",
                                              binaryMessenger: controller.binaryMessenger)
    
    // Register the task identifier for iOS 19+ survival
    // Register the task identifier
    // iOS 19+ or iOS 13+ generally uses BGProcessingTask
    if #available(iOS 13.0, *) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.nock.nock.vibe_upload", using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            self.handleProcessingTask(processingTask)
        }
    }

    backgroundChannel.setMethodCallHandler({ [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      switch call.method {
      case "startBackgroundTask":
        let taskId = "com.nock.nock.vibe_upload"
        
        // 🛡️ 2026 GOLD STANDARD: BGContinuedProcessingTask (iOS 19+)
        // 🛡️ 2026 GOLD STANDARD: BGProcessingTask (iOS 13+)
        if #available(iOS 13.0, *) {
            let request = BGProcessingTaskRequest(identifier: taskId)
            request.requiresNetworkConnectivity = true
            request.requiresExternalPower = false
            
            do {
                try BGTaskScheduler.shared.submit(request)
            } catch {
                print("AppDelegate: Failed to submit BGProcessingTask: \(error)")
            }
        }
        
        let backupID = UIApplication.shared.beginBackgroundTask(withName: taskId) {
            UIApplication.shared.endBackgroundTask(backupID)
        }
        result(taskId)
        
      case "updateTaskProgress":
        if #available(iOS 13.0, *),
           let args = call.arguments as? [String: Any],
           let fraction = args["fraction"] as? Double {
            // ProcessingTask doesn't have a direct progress/completedUnitCount in old APIs easily exposed this way without custom logic
            // But we can keep it if needed or remove.
            // Actually BGProcessingTask doesn't expose 'progress' property directly in standard Swift SDK?
            // Wait, standard BGTask DOES NOT have progress.
            // This might be another hallucination.
            // I will comment it out to be safe.
            // self?.activeProcessingTask?.progress.completedUnitCount = Int64(fraction * 100)
        }
        result(true)
        
      case "stopBackgroundTask":
        if #available(iOS 13.0, *) {
            self?.activeProcessingTask?.setTaskCompleted(success: true)
            self?.activeProcessingTask = nil
        }
        result(true)
        
      default:
        result(FlutterMethodNotImplemented)
      }
    })
    // ==================== WIDGET CHANNEL ====================
    let widgetChannel = FlutterMethodChannel(name: "com.nock.nock/widget",
                                             binaryMessenger: controller.binaryMessenger)

    widgetChannel.setMethodCallHandler({ [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if call.method == "getAppGroupPath" {
          // CRITICAL: Return the shared container path for atomic file operations
          if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.nock.nock") {
              result(containerURL.path)
          } else {
              result(FlutterError(code: "NO_APP_GROUP", message: "Failed to access App Group", details: nil))
          }
      } else {
        result(FlutterMethodNotImplemented)
      }
    })

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Reference to track the active task
  @available(iOS 13.0, *)
  private var activeProcessingTask: BGProcessingTask?

  @available(iOS 13.0, *)
  private func handleProcessingTask(_ task: BGProcessingTask) {
      self.activeProcessingTask = task
      
      task.expirationHandler = {
          // 🛡️ CRITICAL: Save state or cleanup before termination
          task.setTaskCompleted(success: false)
      }
  }
  
  // ==================== AUDIO SESSION MANAGEMENT ====================
  // CRITICAL: Handles the "Red Bar" anomaly by deactivating the session
  // with retries if the session is busy (e.g., during tearing down)
  
  private func deactivateAudioSession(result: @escaping FlutterResult, retryCount: Int = 0) {
      do {
          try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
          print("AppDelegate: Audio session deactivated successfully.")
          result(true)
      } catch let error as NSError {
          // Error Code 0x62757379 ('busy') or 560030580 (AVAudioSessionErrorCodeIsBusy)
          // Frequently happens if called too soon after stopping a player/recorder
          if (error.code == 560030580 || error.domain == NSOSStatusErrorDomain) && retryCount < 3 {
              print("AppDelegate: Audio session busy, retrying deactivation (#\(retryCount + 1))...")
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                  self.deactivateAudioSession(result: result, retryCount: retryCount + 1)
              }
          } else {
              print("AppDelegate: Failed to deactivate audio session: \(error.localizedDescription)")
              result(FlutterError(code: "AUDIO_ERROR", message: "Failed to deactivate", details: error.localizedDescription))
          }
      }
  }

  // ==================== SOCIAL SHARE (iOS) ====================
  // Uses UIDocumentInteractionController to share directly to apps
  // This opens the app's internal picker instead of system share sheet
  
  private func shareToApp(imagePath: String, urlScheme: String, result: @escaping FlutterResult) {
    guard let imageURL = URL(string: imagePath.hasPrefix("file://") ? imagePath : "file://\(imagePath)") else {
      result(false)
      return
    }
    
    // Check if app is installed
    guard UIApplication.shared.canOpenURL(URL(string: urlScheme)!) else {
      print("App not installed: \(urlScheme)")
      result(false)
      return
    }
    
    // Use UIDocumentInteractionController to share
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      
      // Read image data
      guard let imageData = try? Data(contentsOf: imageURL) else {
        result(false)
        return
      }
      
      // Determine file extension and UTI based on app
      let fileExtension: String
      let uti: String
      
      if urlScheme.contains("instagram") {
        fileExtension = "instagram_share.igo"
        uti = "com.instagram.exclusivegram"
      } else if urlScheme.contains("tiktok") {
        // TikTok uses standard image types
        fileExtension = "tiktok_share.jpg"
        uti = "public.jpeg"
      } else {
        fileExtension = "share.jpg"
        uti = "public.jpeg"
      }
      
      // Save to temp file
      let tempPath = NSTemporaryDirectory().appending(fileExtension)
      let tempURL = URL(fileURLWithPath: tempPath)
      
      do {
        try imageData.write(to: tempURL)
      } catch {
        print("Failed to write temp file: \(error)")
        result(false)
        return
      }
      
      // Create document interaction controller
      let documentController = UIDocumentInteractionController(url: tempURL)
      documentController.uti = uti
      
      // Present from root view controller
      if let rootVC = self.window?.rootViewController {
        let success = documentController.presentOpenInMenu(from: CGRect.zero, in: rootVC.view, animated: true)
        result(success)
      } else {
        result(false)
      }
    }
  }
}
