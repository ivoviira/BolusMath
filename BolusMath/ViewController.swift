//
//  ViewController.swift
//  BolusMath
//
//  Created by Ivo Viira on 17/06/2018.
//  Copyright © 2018 Ivo Viira. All rights reserved.
//

import UIKit
import HealthKit
import CoreLocation
import Amplitude_iOS

class ViewController: UIViewController {
    
    //MARK: Properties
    @IBOutlet weak var bgEntryField: UITextField!
    @IBOutlet weak var bgLabel: UILabel!
    @IBOutlet weak var calculatedBolusValue: UILabel!
    @IBOutlet weak var carbsEntryField: UITextField!
    @IBOutlet weak var calculateBolus: UIButton!
    @IBOutlet weak var beforeSlider: UISlider!
    @IBOutlet weak var planSlider: UISlider!
    @IBOutlet weak var beforeSliderLabel: UILabel!
    @IBOutlet weak var planSliderLabel: UILabel!
    @IBOutlet weak var stepsLabel: UILabel!
    @IBOutlet weak var getHealthDataAccessButton: UIButton!
    
    
    let impact = UIImpactFeedbackGenerator()
    let healthStore = HKHealthStore()
    var oldSliderValue = 3
    
    var resetMethod = ""

    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        accessHealth()
        getSteps()
        planSliderLabel.text = "Plan for next 3h: " + planText()
        
        self.view.addGestureRecognizer(UITapGestureRecognizer(target: self.view, action: #selector(UIView.endEditing(_:))))
        self.becomeFirstResponder()
    }
    
    
    //MARK: Actions
    
    //Resets the values in the view from the reset button
    @IBAction func resetFieldsButton(_ sender: UIBarButtonItem) {
        resetMethod = "Button"
        resetFields()

    }
    
    //Holds functions to reset the math view
    func resetFields() {
        bgEntryField.text = nil
        carbsEntryField.text = nil
        calculatedBolusValue.text = "0.0 units"
        planSlider.value = 2.3
        planSliderLabel.text = "Plan for next 3h: " + planText()
        getSteps()
        impact.impactOccurred()
        Amplitude.instance().logEvent("FieldsReset")
        //Amplitude.instance().logEvent("FieldsReset", withEventProperties: "Shake")
        
    }
    
    // We are willing to become first responder to get shake motion
    override var canBecomeFirstResponder: Bool {
        get {
            return true
        }
    }
    
    // Enable detection of shake motion
    override func motionEnded(_ motion: UIEventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            resetMethod = "Shake"
            resetFields()
            
        }
    }
    
    func setBeforeSlider(steps: Float) {
        beforeSlider.value = steps
        beforeSliderLabel.text = "3h before: " + beforeText()
    }
    
    func getSteps() {
        getLastThreeHourSteps { (result) in
            DispatchQueue.main.async {
                //self.stepsLabel.text = "Last 3h steps: " + "\(result)"
                self.stepsLabel.text = "\(result)" + " steps since " + "\(self.timeStringThreeHoursAgo())"

                //Set slider value
                switch result {
                case  0..<200:
                    self.setBeforeSlider(steps: 0)
                case 200..<600:
                    self.setBeforeSlider(steps: 1)
                case 600..<2500:
                    self.setBeforeSlider(steps: 2)
                case 2500..<8000:
                    self.setBeforeSlider(steps: 3)
                    
                default:
                    self.setBeforeSlider(steps: 4)


                }

            }
        }
    }
    
    //Date formatter for the three hours before time
    func timeStringThreeHoursAgo() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .medium
        
        return "\(dateFormatter.string(from: Date() - 10800 as Date))"
    }
    
    //Showing user the health kit access
    func accessHealth() {
        let healthKitTypes: Set = [
            // access step count
            HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier.stepCount)!
        ]
        healthStore.requestAuthorization(toShare: healthKitTypes, read: healthKitTypes) { (_, _) in
            print("authrised???")
        }
        healthStore.requestAuthorization(toShare: healthKitTypes, read: healthKitTypes) { (bool, error) in
            if let e = error {
                print("oops something went wrong during authorisation \(e.localizedDescription)")
            } else {
                print("User has completed the authorization flow")
            }
        }
    }
    
    //Steps for the last three hours
    func getLastThreeHourSteps(completion: @escaping (Double) -> Void) {
        
        let stepsQuantityType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        
        let now = Date()
        let threeHoursAgo = Date() - 10800
        let predicate = HKQuery.predicateForSamples(withStart: threeHoursAgo, end: now, options: .strictStartDate)
        
        let query = HKStatisticsQuery(quantityType: stepsQuantityType, quantitySamplePredicate: predicate, options: .cumulativeSum) { (_, result, error) in
            var resultCount = 0.0
            guard let result = result else {
                print("Failed to fetch steps rate")
                completion(resultCount)
                return
            }
            if let sum = result.sumQuantity() {
                resultCount = sum.doubleValue(for: HKUnit.count())
                print(resultCount.rounded())
            }
            
            DispatchQueue.main.async {
                completion(resultCount)
            }
        }
        healthStore.execute(query)
    }
    
    @IBAction func beforeSliderValueChanged(_ sender: UISlider) {
        beforeSliderLabel.text = "3h before: " + beforeText()
        if oldSliderValue - Int(beforeSlider.value) == 0 {
            
        } else {
            impact.impactOccurred()
            oldSliderValue = Int(beforeSlider.value)
        }
        
    }
    
    
    @IBAction func planSliderValueChanged(_ sender: UISlider) {
        planSliderLabel.text = "Plan for next 3h: " + planText()
        if oldSliderValue - Int(planSlider.value) == 0 {
            
        } else {
            impact.impactOccurred()
            oldSliderValue = Int(planSlider.value)
        }
    }
    
    
    //Bolus calculation
    @IBAction func calculateBolus(_ sender: UIButton) {
        
        //let currentBGString = bgEntryField.text
        //let currentBGValue = (currentBGString! as NSString).doubleValue
        impact.impactOccurred()
        
        let carbsString = carbsEntryField.text
        let carbsValue = (carbsString! as NSString).doubleValue
        
        let expectedBGValue = 5.8
        
        let correctionBolus = doTheCorrectionMath(unitsPer10gCarbs: calcUnitsPer10gCarbs(), bgPerUnits: calcbgPerUnit(), currentBGValue:currentBGValue(), expectedBGValue: expectedBGValue)
        let carbsBolus = carbsBolusMath(unitsPer10gCarbs: calcUnitsPer10gCarbs(), carbsValue: carbsValue)
        
        
        //Set the value to screen
        calculatedBolusValue.text = bolusText(value: round(10*(correctionBolus+carbsBolus))/10) + " units"
        
        //Send Amplitude event
        Amplitude.instance().logEvent("BolusCalculated")
        
    }
    
    func currentBGValue() -> Double {
        if bgEntryField.text?.isEmpty ?? true {
            return 5.8
        } else {
            let currentBGString = bgEntryField.text
            let currentBGValue = (currentBGString! as NSString).doubleValue
            return currentBGValue
        }
    }
    
    //Return string from double
    func bolusText(value: Double) -> String {
        let valueAsString = "\(value)"
        return valueAsString
    }
    
    //Does the math for the needed correction
    func doTheCorrectionMath(unitsPer10gCarbs: Double, bgPerUnits: Double, currentBGValue: Double, expectedBGValue: Double) -> Double {
        let bolusNeeded = (currentBGValue - expectedBGValue)/bgPerUnits*unitsPer10gCarbs
        return bolusNeeded
    }
    
    //Does the math for carbs bolus
    func carbsBolusMath(unitsPer10gCarbs: Double, carbsValue: Double) -> Double {
        let carbsBolus = carbsValue/10*unitsPer10gCarbs
        return carbsBolus
    }
    
    //Calculate unitsPer10gCarbs
    func calcUnitsPer10gCarbs() -> Double {
        let values: [[Double]] = [[1.3, 1.3, 1.0, 0.8, 0.7], [1.3, 1.2, 0.9, 0.7, 0.7], [1.2, 1.0, 0.8, 0.7, 0.7], [0.8, 0.7, 0.7, 0.7, 0.7], [0.5, 0.5, 0.5, 0.5, 0.4]]
        return values[Int(beforeSlider.value)][Int(planSlider.value)]
    }
    
    //Calculate bgPerUnit
    func calcbgPerUnit() -> Double {
        let values: [[Double]] = [[2.0, 2.0, 2.5, 3.0, 3.0], [2.0, 2.5, 3.0, 3.0, 3.5], [2.0, 2.5, 3.0, 4.0, 4.0], [2,5, 3.0, 3.5, 4.0, 4.0], [3.0, 3.0, 4.0, 4.0, 5.0]]
        return values[Int(beforeSlider.value)][Int(planSlider.value)]
    }
    
    func beforeText () -> String {
        let values = ["Yawning", "Ready", "Pause", "Tired", "Dead"]
        return values[Int(beforeSlider.value)]
    }
    
    func planText () -> String {
        let values = ["Idle", "Low", "Moderate", "High", "Power"]
        return values[Int(planSlider.value)]
    }
    
    //MARK: Amplitude properties
    
    

}

