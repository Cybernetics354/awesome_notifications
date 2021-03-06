//
//  NotificationSender.swift
//  awesome_notifications
//
//  Created by Rafael Setragni on 05/09/20.
//

import Foundation

@available(iOS 10.0, *)
class NotificationSenderAndScheduler {

    public static let TAG: String = "NotificationSender"

    private var createdSource:      NotificationSource?
    private var appLifeCycle:       NotificationLifeCycle?
    private var pushNotification:   PushNotification?
    private var content:            UNMutableNotificationContent?

    private var created:    Bool = false
    private var scheduled:  Bool = false
    
    private var completion: ((Bool, UNMutableNotificationContent?, Error?) -> ())?
    
    public func send(
        createdSource: NotificationSource,
        pushNotification: PushNotification?,
        content: UNMutableNotificationContent?,
        completion: @escaping (Bool, UNMutableNotificationContent?, Error?) -> ()
    ) throws {
        self.content = content
        try send(
            createdSource: createdSource,
            pushNotification: pushNotification,
            completion: completion
        )
    }
    
    public func send(
        createdSource: NotificationSource,
        pushNotification: PushNotification?,
        completion: @escaping (Bool, UNMutableNotificationContent?, Error?) -> ()
    ) throws {
        
        self.completion = completion

        if (pushNotification == nil){
            throw PushNotificationError.invalidRequiredFields(msg: "PushNotification not valid")
        }

        NotificationBuilder.isNotificationAllowed(completion: { (allowed) in
            
            do{
                if (allowed){
                    self.appLifeCycle = SwiftAwesomeNotificationsPlugin.getApplicationLifeCycle()

                    try pushNotification!.validate()

                    // Keep this way to future thread running
                    self.createdSource = createdSource
                    self.appLifeCycle = SwiftAwesomeNotificationsPlugin.appLifeCycle
                    self.pushNotification = pushNotification

                    self.execute()
                }
                else {
                    throw PushNotificationError.notificationNotAuthorized
                }
            } catch {
                completion(false, nil, error)
            }
        })
    }

    private func execute(){
        DispatchQueue.global(qos: .background).async {
            
            let notificationReceived:NotificationReceived? = self.doInBackground()

            DispatchQueue.main.async {
                self.onPostExecute(receivedNotification: notificationReceived)
            }
        }
    }
    
    /// AsyncTask METHODS BEGIN *********************************

    private func doInBackground() -> NotificationReceived? {
        
        do {

            if (pushNotification != nil){

                var receivedNotification: NotificationReceived? = nil

                if(pushNotification!.content!.createdDate == nil){
                    pushNotification!.content!.createdSource = self.createdSource
                    pushNotification!.content!.createdDate = DateUtils.getUTCDate()
                    created = true
                }

                if(pushNotification!.content!.createdLifeCycle == nil){
                    pushNotification!.content!.createdLifeCycle = self.appLifeCycle
                }

                if (
                    !StringUtils.isNullOrEmpty(pushNotification!.content!.title) ||
                    !StringUtils.isNullOrEmpty(pushNotification!.content!.body)
                ){

                    if(pushNotification!.content!.displayedLifeCycle == nil){
                        pushNotification!.content!.displayedLifeCycle = appLifeCycle
                    }

                    pushNotification!.content!.displayedDate = DateUtils.getUTCDate()

                    pushNotification = showNotification(pushNotification!)

                    // Only save DisplayedMethods if pushNotification was created and displayed successfully
                    if(pushNotification != nil){

                        scheduled = pushNotification?.schedule != nil
                        
                        receivedNotification = NotificationReceived(pushNotification!.content)

                        receivedNotification!.displayedLifeCycle = receivedNotification!.displayedLifeCycle == nil ?
                            appLifeCycle : receivedNotification!.displayedLifeCycle
                    }

                } else {
                    receivedNotification = NotificationReceived(pushNotification!.content);
                }

                return receivedNotification;
            }

        } catch {
            completion?(false, nil, error)
        }

        pushNotification = nil
        return nil
    }

    private func onPostExecute(receivedNotification:NotificationReceived?) {

        // Only broadcast if pushNotification is valid
        if(receivedNotification != nil){
            
            completion!(true, content, nil)

            if(created){
                SwiftAwesomeNotificationsPlugin.createEvent(notificationReceived: receivedNotification!)
            }
            
            DisplayedManager.saveDisplayed(received: receivedNotification!)
        }
        else {
            completion?(false, nil, nil)
        }
    }

    /// AsyncTask METHODS END *********************************

    public func showNotification(_ pushNotification:PushNotification) -> PushNotification? {

        do {
            
            return try NotificationBuilder.createNotification(pushNotification, content: content)

        } catch {
            
        }
        
        return nil
    }

    public static func cancelNotification(id:Int) -> Bool {
        NotificationBuilder.cancelNotification(id: id)
        debugPrint("Notification cancelled")
        return true
    }
    
    public static func cancelSchedule(id:Int) -> Bool {
        NotificationBuilder.cancelScheduledNotification(id: id)
        ScheduleManager.cancelScheduled(id: id)
        debugPrint("Schedule cancelled")
        return true
    }
    
    public static func cancelAllSchedules() -> Bool {
        NotificationBuilder.cancellAllScheduledNotifications()
        ScheduleManager.cancelAllSchedules()
        debugPrint("All notifications scheduled was cancelled")
        return true
    }

    public static func cancelAllNotifications() -> Bool {
        NotificationBuilder.cancellAllScheduledNotifications()
        NotificationBuilder.cancellAllNotifications()
        ScheduleManager.cancelAllSchedules()
        debugPrint("All notifications was cancelled")
        return true
    }

}
