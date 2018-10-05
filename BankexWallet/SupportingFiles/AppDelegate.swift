//
//  AppDelegate.swift
//  BankexWallet
//
//  Created by Alexander Vlasov on 26.01.2018.
//  Copyright © 2018 Alexander Vlasov. All rights reserved.
//

import UIKit
import CoreData
import Fabric
import Crashlytics
import Amplitude_iOS
import Firebase
import UserNotifications
import FirebaseMessaging
import FirebaseInstanceID
import PushKit
import CoreSpotlight

enum ShortcutIdentifier:String {
    case send
    case receive
    
    init?(identifer:String) {
        guard let identity = identifer.components(separatedBy: ".").last else {
            return nil
        }
        self.init(rawValue: identity)
    }
}


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    static var isAlreadyLaunchedOnce = false // Used to avoid 2 FIRApp configure

    var window: UIWindow?
    var navigationVC:UINavigationController?
    var currentViewController:UIViewController?
    var service = RecipientsAddressesServiceImplementation()
    var keyService = SingleKeyServiceImplementation()
    var selectedContact:FavoriteModel?
    let gcmMessageIDKey = "gcm.message_id"
    var selectedAddress:String {
        return keyService.selectedAddress() ?? ""
    }
    
    enum tabBarPage: Int {
        case main = 0
        case wallet = 1
        case settings = 2
    }
    
    static var initiatingTabBar: tabBarPage = .main
    
    
    
    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(handleShortcut(shortcutItem: shortcutItem))
    }
    
    func handleShortcut(shortcutItem:UIApplicationShortcutItem) -> Bool {
        let shortcutType = shortcutItem.type
        guard let shortcutIdentifier = ShortcutIdentifier(identifer:shortcutType) else { return false }
        selectPath(shortcutIdentifier)
        return true
    }
    
    func selectPath(_ identifier:ShortcutIdentifier) {
        if identifier == .send {
            showFirstTabController()
        }else if identifier == .receive {
            //From background
            if isLaunched {
            let tabvc = window?.rootViewController as! BaseTabBarController
            tabvc.selectedIndex = 0
            if let nav = tabvc.viewControllers?[0] as? BaseNavigationController {
                if let addressQRVC = storyboard().instantiateViewController(withIdentifier: "AddressQRCodeController") as? AddressQRCodeController {
                    addressQRVC.addressToGenerateQR = SingleKeyServiceImplementation().selectedAddress()
                    nav.pushViewController(addressQRVC, animated: false)
                }
            }
                //From unlaunch
            }else if !isLaunched {
                Guide.value = identifier.rawValue
            }
        }
    }
    

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        UINavigationBar.appearance().tintColor = WalletColors.mainColor
        UITextField.appearance().tintColor = WalletColors.mainColor
        UITextView.appearance().tintColor = WalletColors.mainColor
        UINavigationBar.appearance().barTintColor = UIColor.white
        

        if !AppDelegate.isAlreadyLaunchedOnce {
            FirebaseApp.configure()
            AppDelegate.isAlreadyLaunchedOnce = true
            configurePushes()
        }
        Amplitude.instance().initializeApiKey("27da55fc989fc196d40aa68b9a163e36")
        Crashlytics.start(withAPIKey: "5b2cfd1743e96d92261c59fb94482a93c8ec4e13")
        Fabric.with([Crashlytics.self])
        let initialRouter = InitialLogicRouter()
        let isOnboardingNeeded = UserDefaults.standard.value(forKey: "isOnboardingNeeded")
        if isOnboardingNeeded == nil  {
            showOnboarding()
        }
        guard let navigationController = window?.rootViewController as? UINavigationController else {
            return true
        }
        
        initialRouter.navigateToMainControllerIfNeeded(rootControler: navigationController)
        window?.backgroundColor = .white
        return true
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        UIApplication.shared.applicationIconBadgeNumber = 0
    }
    
    func configurePushes() {
        // [START set_messaging_delegate]
        Messaging.messaging().delegate = self
        // [END set_messaging_delegate]
        // Register for remote notifications. This shows a permission dialog on first run, to
        // show the dialog at a more appropriate time move this registration accordingly.
        // [START register_for_notifications]
        if #available(iOS 10.0, *) {
            // For iOS 10 display notification (sent via APNS)
            UNUserNotificationCenter.current().delegate = self
            
            let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
            UNUserNotificationCenter.current().requestAuthorization(
                options: authOptions,
                completionHandler: {_, _ in })
        } else {
            let settings: UIUserNotificationSettings =
                UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil)
            UIApplication.shared.registerUserNotificationSettings(settings)
        }
        
        UIApplication.shared.registerForRemoteNotifications()
        
        // [END register_for_notifications]
    }
    
    func showInitialVC() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let initialNav = storyboard.instantiateInitialViewController() as? UINavigationController
        self.window?.rootViewController = initialNav
        window?.makeKeyAndVisible()
    }
    
    func showOnboarding() {
        let storyboard = UIStoryboard.init(name: "Main", bundle: nil)
        let onboarding = storyboard.instantiateViewController(withIdentifier: "OnboardingPage")
        window?.rootViewController = onboarding
    }
    
    func showTabBar() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let tabBar = storyboard.instantiateViewController(withIdentifier: "MainTabController") as? BaseTabBarController
        window?.rootViewController = tabBar
        window?.makeKeyAndVisible()
    }


    func applicationWillEnterForeground(_ application: UIApplication) {
        if UserDefaults.standard.value(forKey: Keys.multiSwitch.rawValue) == nil {
            UserDefaults.standard.set(true, forKey: Keys.multiSwitch.rawValue)
        }
        if UserDefaults.standard.bool(forKey: Keys.multiSwitch.rawValue) && UserDefaults.standard.bool(forKey: "isNotFirst")  {
            showPasscode()
        }
    }
    
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([Any]?) -> Void) -> Bool {
        if userActivity.activityType == FavoriteModel.domainIdentifier || userActivity.activityType == CSSearchableItemActionType {
            if let objectID = userActivity.userInfo![CSSearchableItemActivityIdentifier] as? String {
                if let tabViewController = window?.rootViewController as? BaseTabBarController {
                    tabViewController.selectedIndex = 2
                        if let vcs = tabViewController.viewControllers, let mainNav = vcs[2] as? BaseNavigationController {
                            if let contactsVC = mainNav.viewControllers.first as? ListContactsViewController {
                                guard let contact = service.getAddressByAddress(objectID) else { return false }
                                mainNav.popToRootViewController(animated: false)
                                contactsVC.chooseContact(contact: contact)
                                return true
                            }
                        }
                }else if let initialNavBar = window?.rootViewController as? BaseNavigationController {
                    if let addr = userActivity.userInfo![CSSearchableItemActivityIdentifier] as? String,let contact = service.getAddressByAddress(addr) {
                        selectedContact = contact
                    }
                }
            }
        }
        
        
        if let incomingURL = userActivity.webpageURL {
            
            let linkHandled = DynamicLinks.dynamicLinks().handleUniversalLink(incomingURL) {
                [weak self] (dynamicLink, error) in
                if let dynamicLink = dynamicLink, let _ = dynamicLink.url {
                    self?.handleIncomingDynamicLink(dynamicLink)
                }
            }
            return linkHandled
        } else {
            return false
        }
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplicationOpenURLOptionsKey : Any] = [:]) -> Bool {
        if let dynamicLink = DynamicLinks.dynamicLinks().dynamicLink(fromCustomSchemeURL: url) {
            print("I am handling a link through the openURL method (custom scheme instead of universal)")
            self.handleIncomingDynamicLink(dynamicLink)
            return true
        } else {
            return false
        }
    }
    
    func handleIncomingDynamicLink(_ dynamicLink: DynamicLink) {
        if dynamicLink.matchType == .weak {
            print("I think your incoming link parameter is \(dynamicLink.url!) but I'm not shure")
        } else {
            guard let pathComponents = dynamicLink.url?.pathComponents else {return}
            for nextPiece in pathComponents {
                if nextPiece == "helloworld" {
                    AppDelegate.initiatingTabBar = .settings
                }
                
                // parsing
            }
            print("Incoming link parameter is \(dynamicLink.url!)")
        }
        
    }
    
    // [START receive_message]
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) {
        // If you are receiving a notification message while your app is in the background,
        // this callback will not be fired till the user taps on the notification launching the application.
        // TODO: Handle data of notification
        // With swizzling disabled you must let Messaging know about the message, for Analytics
        // Messaging.messaging().appDidReceiveMessage(userInfo)
        // Print message ID.
        if let messageID = userInfo[gcmMessageIDKey] {
            print("Message ID: \(messageID)")
        }
        
        // Print full message.
        print(userInfo)
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // If you are receiving a notification message while your app is in the background,
        // this callback will not be fired till the user taps on the notification launching the application.
        // TODO: Handle data of notification
        // With swizzling disabled you must let Messaging know about the message, for Analytics
        // Messaging.messaging().appDidReceiveMessage(userInfo)
        // Print message ID.
        if let messageID = userInfo[gcmMessageIDKey] {
            print("Message ID: \(messageID)")
        }
        
        // Print full message.
        print(userInfo)
        
        completionHandler(UIBackgroundFetchResult.newData)
    }
    // [END receive_message]
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Unable to register for remote notifications: \(error.localizedDescription)")
    }
    
    // This function is added here only for debugging purposes, and can be removed if swizzling is enabled.
    // If swizzling is disabled then this function must be implemented so that the APNs token can be paired to
    // the FCM registration token.
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("APNs token retrieved: \(deviceToken)")
        
        // With swizzling disabled you must set the APNs token here.
        // Messaging.messaging().apnsToken = deviceToken
    }

    // MARK: - Core Data stack

//    lazy var persistentContainer: NSPersistentContainer = {
//        /*
//         The persistent container for the application. This implementation
//         creates and returns a container, having loaded the store for the
//         application to it. This property is optional since there are legitimate
//         error conditions that could cause the creation of the store to fail.
//        */
//        let container = NSPersistentContainer(name: "BankexWallet")
//        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
//            if let error = error as NSError? {
//                // Replace this implementation with code to handle the error appropriately.
//                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
//                 
//                /*
//                 Typical reasons for an error here include:
//                 * The parent directory does not exist, cannot be created, or disallows writing.
//                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
//                 * The device is out of space.
//                 * The store could not be migrated to the current model version.
//                 Check the error message to determine what the actual problem was.
//                 */
//                fatalError("Unresolved error \(error), \(error.userInfo)")
//            }
//        })
//        return container
//    }()

    // MARK: - Core Data Saving support

//    func saveContext () {
//        let context = persistentContainer.viewContext
//        if context.hasChanges {
//            do {
//                try context.save()
//            } catch {
//                // Replace this implementation with code to handle the error appropriately.
//                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
//                let nserror = error as NSError
//                fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
//            }
//        }
//    }
    
    func showPasscode() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let vc = storyboard.instantiateViewController(withIdentifier: "passcodeEnterController") as? PasscodeEnterController {
            currentPasscodeViewController = vc
            window?.rootViewController?.present(vc, animated: true, completion: nil)
        }
    }
}
extension UIApplication {
    var statusBarView: UIView? {
        if responds(to: Selector(("statusBar"))) {
            return value(forKey: "statusBar") as? UIView
        }
        return nil
    }
}

// [START ios_10_message_handling]
@available(iOS 10, *)
extension AppDelegate : UNUserNotificationCenterDelegate {
    
    // Receive displayed notifications for iOS 10 devices.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        
        // With swizzling disabled you must let Messaging know about the message, for Analytics
        // Messaging.messaging().appDidReceiveMessage(userInfo)
        // Print message ID.
        if let messageID = userInfo[gcmMessageIDKey] {
            print("Message ID: \(messageID)")
        }
        
        // Print full message.
        print(userInfo)
        
        // Change this to your preferred presentation option
        completionHandler([])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        // Print message ID.
        if let messageID = userInfo[gcmMessageIDKey] {
            print("Message ID: \(messageID)")
        }
        
        // Print full message.
        print(userInfo)
        
        completionHandler()
    }
}
// [END ios_10_message_handling]

extension AppDelegate : MessagingDelegate {
    
    // [START refresh_token]
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String) {
        print("Firebase registration token: \(fcmToken)")
        
        let dataDict:[String: String] = ["token": fcmToken]
        NotificationCenter.default.post(name: Notification.Name("FCMToken"), object: nil, userInfo: dataDict)
        UserDefaults.standard.set(fcmToken, forKey: "FirebaseRegistrationToken")
        // TODO: If necessary send token to application server.
        // Note: This callback is fired at each app startup and whenever a new token is generated.
    }
    // [END refresh_token]
    // [START ios_10_data_message]
    // Receive data messages on iOS 10+ directly from FCM (bypassing APNs) when the app is in the foreground.
    // To enable direct data messages, you can set Messaging.messaging().shouldEstablishDirectChannel to true.
    func messaging(_ messaging: Messaging, didReceive remoteMessage: MessagingRemoteMessage) {
        print("Received data message: \(remoteMessage.appData)")
    }
    // [END ios_10_data_message]
}

var currentPasscodeViewController: PasscodeEnterController?





