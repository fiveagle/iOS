//
//  CoreSettingsViewController.swift
//  Vaavud
//
//  Created by Gustaf Kugelberg on 11/02/15.
//  Copyright (c) 2015 Andreas Okholm. All rights reserved.
//

import Foundation

class CoreSettingsTableViewController: UITableViewController {
    @IBOutlet weak var versionLabel: UILabel!
    
    @IBOutlet weak var speedUnitControl: UISegmentedControl!
    @IBOutlet weak var directionUnitControl: UISegmentedControl!
    @IBOutlet weak var pressureUnitControl: UISegmentedControl!
    @IBOutlet weak var temperatureUnitControl: UISegmentedControl!
    @IBOutlet weak var facebookControl: UISwitch!
    
    override func viewDidLoad() {
        versionLabel.text = NSBundle.mainBundle().infoDictionary?["CFBundleShortVersionString"] as? String
        facebookControl.on = Property.getAsBoolean("enableFacebookShareDialog", defaultValue: false)
        readUnits()
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "unitsChanged:", name: "UnitChange", object: nil)
    }
    
    func unitsChanged(note: NSNotification) {
        println("==== SETTINGS unitsChanged ====")
        if note.object as? CoreSettingsTableViewController != self {
            println("==== SETTINGS UDATING ====")
            readUnits()
        }
    }
    
    func postUnitChange() {
        NSNotificationCenter.defaultCenter().postNotificationName("UnitChange", object: self)
    }
    
    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    func readUnits() {
        if let speedUnit = Property.getAsInteger("windSpeedUnit")?.integerValue {
            speedUnitControl.selectedSegmentIndex = speedUnit
        }
        if let directionUnit = Property.getAsInteger("directionUnit")?.integerValue {
            directionUnitControl.selectedSegmentIndex = directionUnit
        }
        if let pressureUnit = Property.getAsInteger("pressureUnit")?.integerValue {
            pressureUnitControl.selectedSegmentIndex = pressureUnit
        }
        if let temperatureUnit = Property.getAsInteger("temperatureUnit")?.integerValue {
            temperatureUnitControl.selectedSegmentIndex = temperatureUnit
        }
    }
    
    @IBAction func changedSpeedUnit(sender: UISegmentedControl) {
        Property.setAsInteger(sender.selectedSegmentIndex, forKey: "windSpeedUnit")
        postUnitChange()
    }
    
    @IBAction func changedDirectionUnit(sender: UISegmentedControl) {
        Property.setAsInteger(sender.selectedSegmentIndex, forKey: "directionUnit")
        postUnitChange()
    }
    
    @IBAction func changedPressureUnit(sender: UISegmentedControl) {
        Property.setAsInteger(sender.selectedSegmentIndex, forKey: "pressureUnit")
        postUnitChange()
    }
    
    @IBAction func changedTemperatureUnit(sender: UISegmentedControl) {
        Property.setAsInteger(sender.selectedSegmentIndex, forKey: "temperatureUnit")
        postUnitChange()
    }
    
    @IBAction func changedFacebookSetting(sender: UISwitch) {
        Property.setAsBoolean(sender.on, forKey: "enableFacebookShareDialog")
    }
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if let webViewController = segue.destinationViewController as? WebViewController {
            if segue.identifier == "AboutSegue" {
                //        let aboutText = NSLocalizedString("ABOUT_VAAVUD_TEXT", comment: "")
                
                let aboutText = "Vaavud is a Danish technology start-up.\n Our mission is to make the best wind meters on the planet in terms of usability, features, and third party integration.\n To learn more and to purchase a Vaavud wind meter visit Vaavud.com\n &copy; Vaavud ApS 2014, all rights reserved"
                
                webViewController.html = aboutText.html()
            }
            else if segue.identifier == "TermsSegue" {
                webViewController.url = NSURL(string: "http://vaavud.com/legal/terms.php?source=app")
            }
            else if segue.identifier == "PrivacySegue" {
                webViewController.url = NSURL(string: "http://vaavud.com/legal/privacy.php?source=app")
            }
        }
    }
}

class WebViewController: UIViewController {
    @IBOutlet weak var webView: UIWebView!
    var baseUrl = NSURL(string: "http://vaavud.com")
    var html: String?
    var url: NSURL?
    
    override func viewDidLoad() {
        load()
    }
    
    func load() {
        if let url = url {
            webView.loadRequest(NSURLRequest(URL: url))
        }
        else if let html = html {
            webView.loadHTMLString(html, baseURL: baseUrl)
        }
    }
}

extension String {
    func html() -> String {
        return "<html><head><style type='text/css'>a {color:#00aeef;text-decoration:none}\n" +
            "body {background-color:#f8f8f8;}</style></head><body>" +
            "<center style='padding-top:20px;font-family:helvetica,arial'>" +
            stringByReplacingOccurrencesOfString("\n" , withString: "<br/><br/>", options: nil) + "</center></body></html>"
    }
}





