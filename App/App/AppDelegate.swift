//
//  AppDelegate.swift
//  TestApp
//
//  Created by Jaehong Yoo on 2020/08/28.
//  Copyright © 2020 Algorigo. All rights reserved.
//

import UIKit
import AlgorigoBleLibrary
import RxSwift

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    
    private var disposesable: Disposable? = nil

    deinit {
        disposesable?.dispose()
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        print("version:\(AlgorigoBleLibrary.version)")
        
        if #available(iOS 13, *) {
            
        } else {
            self.window = UIWindow(frame: UIScreen.main.bounds)

            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            
            let initialViewController = storyboard.instantiateInitialViewController()

            self.window?.rootViewController = initialViewController
            self.window?.makeKeyAndVisible()
        }
        
        return true
    }

    // MARK: UISceneSession Lifecycle
    @available(iOS 13.0, *)
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    @available(iOS 13.0, *)
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        print("applicationWillEnterForeground")
        disposesable?.dispose()
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        print("applicationDidEnterBackground")
        disposesable = BluetoothManager.instance.scanDevice(withServices: [ViewController.UUID_SERVICE])
            .do(onDispose: { [weak self] in
                print("AppDelegate::onDispose")
                self?.disposesable = nil
            })
            .subscribe({ (event) in
                switch event {
                case .next(let devices):
                    print("AppDelegate::devices:\(devices)")
                case .completed:
                    break
                case .error(let error):
                    print("AppDelegate::error:\(error)")
                }
            })
    }
}
