//
//  DataController+MapPinManager.swift
//  VirtualTourist
//
//  Created by André Sanches Bocato on 27/03/19.
//  Copyright © 2019 Andre Sanches Bocato. All rights reserved.
//

import Foundation
import CoreData
import CoreLocation

extension DataController {
    
    // MARK: - Functions
    
    /// Creates a new MapPin in Core Data using its coordinate.
    func addMapPin(at coordinate: CLLocationCoordinate2D,
                   context: CoreDataContext = .background,
                   onSuccess succeeded: @escaping ((_ mapPin: MapPin) -> Void),
                   onFailure failed: ((PersistenceError?) -> Void)? = nil,
                   onCompletion completed: (() -> Void)? = nil) {
        
        let id = generatePinID(at: coordinate)
        let currentContext: NSManagedObjectContext = context == .background ? backgroundContext : viewContext
        
        currentContext.perform {
            
            let pin = MapPin(context: currentContext)
            pin.latitude = coordinate.latitude
            pin.longitude = coordinate.longitude
            pin.id = id
            
            do {
                try currentContext.save()
                debugPrint("sucessfully persisted 'MapPin' with id = \(id)")
                succeeded(pin)
                
            } catch let error {
                debugPrint("context.save() failed with error:\n\(error)")
                failed?(PersistenceError.failedToPersist)
            }
            
            completed?()
        }
    }
    
    /// Deletes a MapPin from Core Data using its coordinate.
    func deletePin(at coordinate: CLLocationCoordinate2D,
                   context: CoreDataContext = .background,
                   onSuccess succeeded: @escaping ((_ mapPin: MapPin) -> Void),
                   onFailure failed: ((PersistenceError?) -> Void)? = nil,
                   onCompletion completed: (() -> Void)? = nil) {
        
        let id = generatePinID(at: coordinate)
        let currentContext: NSManagedObjectContext = context == .background ? backgroundContext : viewContext
        
        currentContext.perform {
            
            self.fetchMapPin(with: id, context: context, onSuccess: { (pin) in
                guard let pin = pin else {
                    debugPrint("could not find 'MapPin' with id = \(id)")
                    failed?(PersistenceError.failedToFind)
                    return
                }
                
                currentContext.delete(pin)
                do {
                    try currentContext.save()
                    debugPrint("successfully deleted 'MapPin' with id = \(id)")
                    succeeded(pin)
                    
                } catch let error {
                    debugPrint("context.save() failed with error:\n\(error)")
                    failed?(PersistenceError.failedToDelete)
                }
                
            }, onFailure: failed, onCompletion: completed)
        }
        
    }
    
    /// Fetches an array with all persisted MapPin´s in Core Data.
    func fetchAllPins(inContext context: CoreDataContext = .background,
                     onSuccess succeeded: @escaping ((_ pins: [MapPin]?) -> Void),
                     onFailure failed: ((PersistenceError?) -> Void)? = nil,
                     onCompletion completed: (() -> Void)? = nil) {
        
        let currentContext: NSManagedObjectContext = context == .background ? backgroundContext : viewContext
        
        currentContext.perform {
            
            let fetchRequest = NSFetchRequest<MapPin>(entityName: "MapPin")
            
            do {
                let result = try currentContext.fetch(fetchRequest)
                succeeded(result)
                
            } catch let error {
                debugPrint("fetchAllPins() failed with error:\n\(error)")
                failed?(PersistenceError.failedToFetchData)
            }
            
            completed?()
        }
    }
    
    /// Fetches a MapPin from Core Data using an ID.
    func fetchMapPin(with id: String,
                   context: CoreDataContext = .view,
                   onSuccess succeeded: @escaping ((_ pin: MapPin?) -> Void),
                   onFailure failed: ((PersistenceError?) -> Void)? = nil,
                   onCompletion completed: (() -> Void)? = nil) {
        
        let currentContext: NSManagedObjectContext = context == .background ? backgroundContext : viewContext
        
        currentContext.perform {
            
            let fetchRequest = NSFetchRequest<MapPin>(entityName: "MapPin")
            fetchRequest.predicate = NSPredicate(format: "id == %@", id)
            fetchRequest.fetchLimit = 1
            
            do {
                let result = try currentContext.fetch(fetchRequest)
                guard let mapPin = result.first else {
                    debugPrint("found no 'MapPin' with id = \(id)")
                    failed?(PersistenceError.failedToFind)
                    return
                }
                succeeded(mapPin)
                
            } catch let error {
                debugPrint("fetchMapPin() failed with error:\n\(error)")
                failed?(PersistenceError.failedToFind)
            }
            
            completed?()
        }
    }
    
    // MARK: - Helper Functions
    
    private func generatePinID(at coordinate: CLLocationCoordinate2D) -> String {
        let id = "\(coordinate.latitude)&\(coordinate.longitude)"
        
        debugPrint("successfully generated id = \(id)")
        
        return id
    }
    
    func getIdForPinAtCoordinate(at coordinate: CLLocationCoordinate2D) -> String {
        return generatePinID(at: coordinate)
    }
    
}
