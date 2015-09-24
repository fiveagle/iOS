//
//  MeasureRootViewController.swift
//  Vaavud
//
//  Created by Gustaf Kugelberg on 30/05/15.
//  Copyright (c) 2015 Andreas Okholm. All rights reserved.
//

import UIKit
import CoreMotion
import VaavudSDK

let updatePeriod = 1.0
let countdownInterval = 3
let limitedInterval = 30

enum WindMeterModel: Int {
    case Unknown = 0
    case Mjolnir = 1
    case Sleipnir = 2
}

protocol MeasurementConsumer {
    func tick()
    
    func newWindDirection(windDirection: CGFloat)
    func newSpeed(speed: CGFloat)
    func newHeading(heading: CGFloat)

    func changedSpeedUnit(unit: SpeedUnit)
    func useMjolnir()
    
    var name: String { get }
}

class MeasureRootViewController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, WindMeasurementControllerDelegate, DBRestClientDelegate {
    private var pageController: UIPageViewController!
    private var viewControllers: [UIViewController]!
    private var displayLink: CADisplayLink!

    private let geocoder = CLGeocoder()
    
    private var altimeter: CMAltimeter?
    
    private let sdk = VaavudSDK.sharedInstance
    
    private var mjolnir: MjolnirMeasurementController?
    
    private let currentSessionUuid = UUIDUtil.generateUUID()
    
    private var currentSession: MeasurementSession? {
        return MeasurementSession.MR_findFirstByAttribute("uuid", withValue: currentSessionUuid)
    }
    
    let isSleipnirSession: Bool
    
    private var formatter = VaavudFormatter()

    @IBOutlet weak var pager: UIPageControl!
    
    @IBOutlet weak var unitButton: UIButton!
    @IBOutlet weak var readingTypeButton: UIButton!
    @IBOutlet weak var cancelButton: MeasureCancelButton!
    
    @IBOutlet weak var errorMessageLabel: UILabel!
    
    @IBOutlet weak var errorOverlayBackground: UIView!
    
    var currentConsumer: MeasurementConsumer?
    
    private var latestHeading: CGFloat = 0
    private var latestWindDirection: CGFloat = 0
    private var latestSpeed: CGFloat = 0

    private var maxSpeed: CGFloat = 0

    private var avgSpeed: CGFloat { return speedsSum/CGFloat(speedsCount) }
    private var speedsSum: CGFloat = 0
    private var speedsCount = 0
    
    private var elapsedSinceUpdate = 0.0
    
    var state = MeasureState.Done
    var timeLeft = CGFloat(countdownInterval)
    
    required init?(coder aDecoder: NSCoder) {
        isSleipnirSession = sdk.sleipnirAvailable()
        
        super.init(coder: aDecoder)
        
        state = .CountingDown(countdownInterval, Property.getAsBoolean(KEY_MEASUREMENT_TIME_UNLIMITED))
        
        let wantsSleipnir = Property.getAsBoolean(KEY_USES_SLEIPNIR)
        
        if isSleipnirSession && !wantsSleipnir {
            NSNotificationCenter.defaultCenter().postNotificationName(KEY_WINDMETERMODEL_CHANGED, object: self)
        }

        if isSleipnirSession {
            Property.setAsBoolean(true, forKey: KEY_USES_SLEIPNIR)
            sdk.windSpeedCallback = newWindSpeed
            sdk.windDirectionCallback = newWindDirection
            sdk.headingCallback = newHeading
            // fixme: handle
            do {
                try sdk.start()
            }
            catch {
                dismissViewControllerAnimated(true) {
                    print("Failed to start SDK and dismissed Measure screen")
                }
                return
            }
        }
        else {
            let mjolnirController = MjolnirMeasurementController()
            mjolnirController.start()
            mjolnir = mjolnirController
        }
        
        if let sessions = MeasurementSession.MR_findByAttribute("measuring", withValue: true) as? [MeasurementSession] {
            _ = sessions.map { $0.measuring = false }
        }
        
//        if let sessions = MeasurementSession.MR_findAll() as? [MeasurementSession] {
//            for session in sessions {
//            }
//        }
        
        NSManagedObjectContext.MR_defaultContext().MR_saveToPersistentStoreWithCompletion(nil)
        
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter = CMAltimeter()
            updateWithPressure(currentSessionUuid)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        hideVolumeHUD()
        
        let (old, flat, round) = ("OldMeasureViewController", "FlatMeasureViewController", "RoundMeasureViewController")
        let vcsNames = isSleipnirSession ? [old, flat, round] : [old, flat]
        viewControllers = vcsNames.map { self.storyboard!.instantiateViewControllerWithIdentifier($0) }
        currentConsumer = (viewControllers.first as! MeasurementConsumer)

        if !isSleipnirSession { _ = viewControllers.map { ($0 as! MeasurementConsumer).useMjolnir() } }
        
        pager.numberOfPages = viewControllers.count
        
        pageController = storyboard?.instantiateViewControllerWithIdentifier("PageViewController") as? UIPageViewController
        pageController.dataSource = self
        pageController.delegate = self
        pageController.view.frame = view.bounds
        pageController.setViewControllers([viewControllers[0]], direction: .Forward, animated: false, completion: nil)
        
        addChildViewController(pageController)
        view.addSubview(pageController.view)
        pageController.didMoveToParentViewController(self)
        
        view.bringSubviewToFront(pager)
        view.bringSubviewToFront(unitButton)
        view.bringSubviewToFront(readingTypeButton)
        view.bringSubviewToFront(errorOverlayBackground)
        view.bringSubviewToFront(cancelButton)
        
        cancelButton.setup()
        
        displayLink = CADisplayLink(target: self, selector: Selector("tick:"))
        displayLink.addToRunLoop(NSRunLoop.mainRunLoop(), forMode: NSRunLoopCommonModes)
        
        unitButton.setTitle(formatter.windSpeedUnit.localizedString, forState: .Normal)
        
        LocationManager.sharedInstance().start()
        
        if Property.isMixpanelEnabled() {
            Mixpanel.sharedInstance().track("Measure Screen")
        }
        
        if let mjolnir = mjolnir {
            mjolnir.delegate = self
        }
    }
    
    @IBAction func tappedUnit(sender: UIButton) {
        formatter.windSpeedUnit = formatter.windSpeedUnit.next
        unitButton.setTitle(formatter.windSpeedUnit.localizedString, forState: .Normal)
        currentConsumer?.changedSpeedUnit(formatter.windSpeedUnit)
    }
    
    @IBAction func tappedCancel(sender: MeasureCancelButton) {
        switch state {
        case .CountingDown:
            stop(true)
        case .Limited:
            stop(true)
            save(true)
            mixpanelSend("Cancelled")
        case .Unlimited:
            stop(false)
            save(false)
            mixpanelSend("Stopped")
        case .Done:
            break
        }
    }
    
    func tick(link: CADisplayLink) {
        currentConsumer?.tick()
        
        if state.running {
            speedsCount++
            speedsSum += latestSpeed
            elapsedSinceUpdate += link.duration
        
            if elapsedSinceUpdate > updatePeriod {
                elapsedSinceUpdate = 0
                updateSession()
            }
        }
        
        switch state {
        case let .CountingDown(_, unlimited):
            if timeLeft < 0 {
                if unlimited {
                    state = .Unlimited
                }
                else {
                    state = .Limited(limitedInterval)
                    timeLeft = CGFloat(limitedInterval)
                }
                start()
            }
            else {
                timeLeft -= CGFloat(link.duration)
            }
        case .Limited:
            if timeLeft < 0 {
                timeLeft = 0
                state = .Done
                stop(false)
                save(false)
                mixpanelSend("Ended")
            }
            else {
                timeLeft -= CGFloat(link.duration)
            }
        case .Unlimited:
            timeLeft = 0
        case .Done:
            break
        }
        
        cancelButton.update(timeLeft, state: state)
    }

    func hasValidLocation(session: MeasurementSession) -> CLLocationCoordinate2D? {
        if let lat = session.latitude?.doubleValue, long = session.longitude?.doubleValue {
            let loc = CLLocationCoordinate2D(latitude: lat, longitude: long)
            if LocationManager.isCoordinateValid(loc) {
                return loc
            }
        }
        
        return nil
    }
    
    func updateWithLocation(session: MeasurementSession) {
        let loc = LocationManager.sharedInstance().latestLocation
        
        if LocationManager.isCoordinateValid(loc) {
            (session.latitude, session.longitude) = (loc.latitude, loc.longitude)
        }
    }
    
    func updateWithGeocode(session: MeasurementSession) {
        if let lat = session.latitude?.doubleValue, long = session.longitude?.doubleValue {
            geocoder.reverseGeocodeLocation(CLLocation(latitude: lat, longitude: long)) { placemarks, error in
                dispatch_async(dispatch_get_main_queue()) {
                    if error == nil {
                        if let first = placemarks?.first,
                            let s = (try? NSManagedObjectContext.MR_defaultContext().existingObjectWithID(session.objectID)) as? MeasurementSession {
                                s.geoLocationNameLocalized = first.thoroughfare ?? first.locality ?? first.country
                                let userInfo = ["objectID" : s.objectID, "geoLocationNameLocalized" : true]
                                NSManagedObjectContext.MR_defaultContext().MR_saveToPersistentStoreWithCompletion { s, e in
                                    NSNotificationCenter.defaultCenter().postNotificationName(KEY_SESSION_UPDATED, object: self, userInfo: userInfo)
                                }
                        }
                    }
                    else {
                        print("Geocode failed with error: \(error)")
                    }
                }
            }
        }
    }
    
    func updateWithWindchill(session: MeasurementSession) {
        if let kelvin = session.sourcedTemperature, ms = session.windSpeedAvg ?? session.sourcedWindSpeedAvg, chill = windchill(kelvin.floatValue, ms.floatValue) {
            session.windChill = chill
            NSManagedObjectContext.MR_defaultContext().MR_saveToPersistentStoreWithCompletion { s, e in
                let userInfo = ["objectID" : session.objectID, "windChill" : true]
                NSNotificationCenter.defaultCenter().postNotificationName(KEY_SESSION_UPDATED, object: self, userInfo: userInfo)
            }
        }
        else {
            print("WINDCHILL ERROR: \(session.sourcedTemperature, session.windSpeedAvg, session.sourcedWindSpeedAvg)")
        }
    }

    func updateWithSourcedData(session: MeasurementSession) {
        let objectId = session.objectID
        let loc = hasValidLocation(session) ?? LocationManager.sharedInstance().latestLocation
        ServerUploadManager.sharedInstance().lookupForLat(loc.latitude, long: loc.longitude, success: { t, d, p in
            if let session = (try? NSManagedObjectContext.MR_defaultContext().existingObjectWithID(objectId)) as? MeasurementSession {
                session.sourcedTemperature = t ?? nil
                session.sourcedPressureGroundLevel = p ?? nil
                session.sourcedWindDirection = d ?? nil
                
                let userInfo = ["objectID" : objectId, "sourcedTemperature" : t != nil, "sourcedPressureGroundLevel" : p != nil, "sourcedWindDirection" : d != nil]
                
                NSManagedObjectContext.MR_defaultContext().MR_saveToPersistentStoreWithCompletion { s, e in
                    NSNotificationCenter.defaultCenter().postNotificationName(KEY_SESSION_UPDATED, object: self, userInfo: userInfo)
                }
            }
            }, failure: { error in print("<<<<SOURCED LOOKUP>>>> FAILED \(error)") })
    }
    
    func updateWithPressure(uuid: String) {
        altimeter?.startRelativeAltitudeUpdatesToQueue(NSOperationQueue.mainQueue()) {
            altitudeData, error in
            if let session = MeasurementSession.MR_findFirstByAttribute("uuid", withValue: uuid) {
                let userInfo = ["objectId" : session.objectID, "pressure" : true]
                NSManagedObjectContext.MR_defaultContext().MR_saveToPersistentStoreWithCompletion { s, e in
                    NSNotificationCenter.defaultCenter().postNotificationName(KEY_SESSION_UPDATED, object: self, userInfo: userInfo)
                }
            }
        }
    }
    
    func changedValidity(isValid: Bool, dynamicsIsValid: Bool) {
        if !isValid {
            currentConsumer?.newSpeed(0)
        }
        
        UIView.animateWithDuration(0.2) {
            self.errorOverlayBackground.alpha = dynamicsIsValid ? 0 : 1
        }
    }
    
    func start() {
        elapsedSinceUpdate = 0
        
        let model: WindMeterModel = isSleipnirSession ? .Sleipnir : .Mjolnir
        
        let session = MeasurementSession.MR_createEntity()
        session.uuid = currentSessionUuid
        session.device = Property.getAsString(KEY_DEVICE_UUID)
        session.windMeter = model.rawValue
        session.startTime = NSDate()
        session.timezoneOffset = NSTimeZone.localTimeZone().secondsFromGMTForDate(session.startTime)
        session.endTime = session.startTime
        session.measuring = true
        session.uploaded = false
        session.startIndex = 0
        session.privacy = 1
        
        updateWithLocation(session)
        updateWithSourcedData(session)
        
        mixpanelSend("Started")
    }
    
    func updateSession() {
        let now = NSDate()
        
        if let mjolnir = mjolnir where !mjolnir.isValidCurrentStatus {
            return
        }
        
        if let session = currentSession where session.measuring.boolValue {
            updateWithLocation(session)
            
            session.endTime = now
            session.windSpeedMax = maxSpeed
            session.windSpeedAvg = avgSpeed
            if isSleipnirSession { session.windDirection = mod(latestWindDirection, 360) }

            let point = MeasurementPoint.MR_createEntity()
            point.session = session
            point.time = now
            point.windSpeed = latestSpeed
            if isSleipnirSession { point.windDirection = mod(latestWindDirection, 360) }
        }
        else {
            print("ROOT: updateSession - ERROR: No current session")
            // Stopped by model, stop?
        }
    }
    
    func save(userCancelled: Bool) {
        let cancel = userCancelled || avgSpeed == 0
        
        if let session = currentSession where session.measuring.boolValue {
            session.measuring = false
            session.endTime = NSDate()
            session.windSpeedMax = maxSpeed
            session.windSpeedAvg = avgSpeed
            if isSleipnirSession { session.windDirection = mod(latestWindDirection, 360) }
            
            let windspeeds = speeds(session)
            if windspeeds.count > 5 { session.gustiness = gustiness(windspeeds) }
            
            if cancel { session.MR_deleteEntity() }
        
            updateWithLocation(session)
            updateWithGeocode(session)
            updateWithWindchill(session)
            
            NSManagedObjectContext.MR_defaultContext().MR_saveToPersistentStoreWithCompletion {
                success, error in
                ServerUploadManager.sharedInstance().triggerUpload()
                
                if success {
                    print("ROOT: save - Saved and uploaded after measuring ============================")
                }
                else if error != nil {
                    print("ROOT: save - Failed to save session after measuring with error: \(error.localizedDescription)")
                }
                else {
                    print("ROOT: save - Failed to save session after measuring with no error message")
                }
                
                if !cancel {
                    NSNotificationCenter.defaultCenter().postNotificationName(KEY_OPEN_LATEST_SUMMARY, object: self, userInfo: ["uuid" : session.uuid])
                }
            }
        
            if !cancel && DBSession.sharedSession().isLinked(), let appDelegate = UIApplication.sharedApplication().delegate as? AppDelegate {
                print("ROOT: save - dropbox was linked, uploading")
                appDelegate.uploadToDropbox(session)
            }
        }
    }
    
    func mixpanelSend(action: String) {
        if !Property.isMixpanelEnabled() { return }
        
        MixpanelUtil.updateMeasurementProperties(false)
        
        let model = isSleipnirSession ? "Sleipnir" : "Mjolnir"
        var properties: [NSObject : AnyObject] = ["Action" : action, "Wind Meter" : model]
        
        let event: String
        
        if action == "Started" {
            event = "Start Measurement"
        }
        else {
            event = "Stop Measurement"
            
            if let start = currentSession?.startTime, let duration = currentSession?.endTime?.timeIntervalSinceDate(start) {
                properties["Duration"] = duration
            }
            
            properties["Avg Wind Speed"] = currentSession?.windSpeedAvg?.floatValue
            properties["Max Wind Speed"] = currentSession?.windSpeedMax?.floatValue
            properties["Measure Screen Type"] = currentConsumer?.name
        }
        
        Mixpanel.sharedInstance().track(event, properties: properties)
    }
    
    func stop(cancelled: Bool) {
        if isSleipnirSession {
            sdk.stop()
        }
        else if let mjolnir = mjolnir {
            mjolnir.stop()
        }

        altimeter?.stopRelativeAltitudeUpdates()
        
        reportToUrlSchemeCaller(cancelled)
        
        dismissViewControllerAnimated(true) {
            self.pageController.view.removeFromSuperview()
            self.pageController.removeFromParentViewController()
            _ = self.viewControllers.map { $0.view.removeFromSuperview() }
            _ = self.viewControllers.map { $0.removeFromParentViewController() }
            self.viewControllers = []
            self.currentConsumer = nil
            self.displayLink.invalidate()
        }
    }
    
    func reportToUrlSchemeCaller(cancelled: Bool) {
        if let appDelegate = UIApplication.sharedApplication().delegate as? AppDelegate,
            x = appDelegate.xCallbackSuccess,
            encoded = x.stringByAddingPercentEncodingWithAllowedCharacters(.URLQueryAllowedCharacterSet()) {
                appDelegate.xCallbackSuccess = nil
                
                if cancelled, let url = NSURL(string:encoded + "?x-source=Vaavud&x-cancelled=cancel") {
                    UIApplication.sharedApplication().openURL(url)
                }
                else if let url = NSURL(string:encoded + "?x-source=Vaavud&windSpeedAvg=\(avgSpeed)&windSpeedMax=\(maxSpeed)") {
                    UIApplication.sharedApplication().openURL(url)
                }
        }
    }

    // MARK: Mjolnir Callback
    func addSpeedMeasurement(currentSpeed: NSNumber!, avgSpeed: NSNumber!, maxSpeed: NSNumber!) {
        newWindSpeed(WindSpeedEvent(time: NSDate(), speed: currentSpeed.doubleValue))
    }
    
    // MARK: SDK Callbacks
    
    func newWindDirection(windDirection: NSNumber!) {
        latestWindDirection = CGFloat(windDirection.floatValue)
        currentConsumer?.newWindDirection(latestWindDirection)
    }
    
    func newWindDirection(event: WindDirectionEvent) {
        latestWindDirection = CGFloat(event.globalDirection)
        currentConsumer?.newWindDirection(latestWindDirection)
    }
    
    func newWindSpeed(event: WindSpeedEvent) {
        latestSpeed = CGFloat(event.speed)
        currentConsumer?.newSpeed(latestSpeed)
        if latestSpeed > maxSpeed { maxSpeed = latestSpeed }
    }
    
    func newHeading(event: HeadingEvent) {
        latestHeading = CGFloat(event.heading)
        currentConsumer?.newHeading(latestHeading)
    }
    
    override func prefersStatusBarHidden() -> Bool {
        return true
    }

    override func supportedInterfaceOrientations() -> UIInterfaceOrientationMask {
       return [.Portrait, .PortraitUpsideDown]
    }
    
    func changeConsumer(mc: MeasurementConsumer) {
        mc.newSpeed(latestSpeed)
        mc.changedSpeedUnit(formatter.windSpeedUnit)
        if isSleipnirSession {
            mc.newWindDirection(latestWindDirection)
            mc.newHeading(latestHeading)
        }
        currentConsumer = mc
    }
    
    func pageViewController(pageViewController: UIPageViewController, willTransitionToViewControllers pendingViewControllers: [UIViewController]) {
        if let mc = pendingViewControllers.last as? MeasurementConsumer {
            changeConsumer(mc)
        }
    }
    
    func pageViewController(pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        
        if let vc = pageViewController.viewControllers?.last, mc = vc as? MeasurementConsumer {
            if let current = viewControllers.indexOf(vc) {
                pager.currentPage = current
            }
            changeConsumer(mc)
            
            let alpha: CGFloat = mc is MapMeasurementViewController ? 0 : 1
            UIView.animateWithDuration(0.3) {
                self.readingTypeButton.alpha = alpha
                self.unitButton.alpha = alpha
            }
        }
    }
    
    func pageViewController(pageViewController: UIPageViewController, viewControllerAfterViewController viewController: UIViewController) -> UIViewController? {
        if let current = viewControllers.indexOf(viewController) {
            let next = mod(current + 1, viewControllers.count)
            return viewControllers[next]
        }
        
        return nil
    }
    
    func pageViewController(pageViewController: UIPageViewController, viewControllerBeforeViewController viewController: UIViewController) -> UIViewController? {

        if let current = viewControllers.indexOf(viewController) {
            let previous = mod(current - 1, viewControllers.count)
            return viewControllers[previous]
        }
        
        return nil
    }
    
    // MARK: Debug
    
    @IBAction func debugPanned(sender: UIPanGestureRecognizer) {
//        let y = sender.locationInView(view).y
//        let x = view.bounds.midX - sender.locationInView(view).x
//        let dx = sender.translationInView(view).x/2
//        let dy = sender.translationInView(view).y/20
//        
//        newWindDirection(latestWindDirection + dx)
//        newSpeed(max(0, latestSpeed - dy))
//        
//        sender.setTranslation(CGPoint(), inView: view)
    }
}

func speeds(session: MeasurementSession) -> [Float] {
    var speeds = [Float]()
    
    if let points = session.points {
        for p in points {
            if let p = p as? MeasurementPoint, s = p.windSpeed?.floatValue {
                speeds.append(s)
            }
        }
    }

    return speeds
}

func windchill(temp: Float, _ windspeed: Float) -> Float? {
    let celsius = temp - 273.15
    let kmh = windspeed*3.6
    
    if celsius > 10 || kmh < 4.8 {
        return nil
    }

    let k: Float = 13.12
    let a: Float = 0.6215
    let b: Float = -11.37
    let c: Float = 0.3965
    let d: Float = 0.16

    return 273.15 + k + a*celsius + b*pow(kmh, d) + c*celsius*pow(kmh, d)
}

func gustiness(speeds: [Float]) -> Float {
    let n = Float(speeds.count)
    let mean = speeds.reduce(0, combine: +)/n
    let variance = speeds.reduce(0) { $0 + ($1 - mean)*($1 - mean) }/(n - 1)
    
    return variance/mean
}

