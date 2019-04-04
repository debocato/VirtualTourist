//
//  ViewController.swift
//  VirtualTourist
//
//  Created by Andre Sanches Bocato on 15/03/19.
//  Copyright © 2019 Andre Sanches Bocato. All rights reserved.
//
// @TODO: when the user drops the pin on the map, start downloading the images immediately without waiting for the user to navigate to the collection view.

import UIKit
import MapKit
import CoreData

class TravelLocationsViewController: UIViewController {

    // MARK: - IBOutlets
    
    @IBOutlet private weak var mapView: MKMapView! {
        didSet {
            mapView.delegate = self
            mapView.isZoomEnabled = true
            mapView.isScrollEnabled = true
        }
    }
    @IBOutlet private weak var longPressGestureRecognizer: UILongPressGestureRecognizer! {
        didSet {
            longPressGestureRecognizer.delegate = self
        }
    }

    // MARK: - Properties
    
    private var currentPin: MapPin?
    private var pinView: MKPinAnnotationView?
    
    private var currentAnnotation: MKAnnotation? = nil
    private var annotations: [MKAnnotation]?
    
    var fetchedResultsController: NSFetchedResultsController<MapPin>? {
        didSet {
            fetchedResultsController?.delegate = self
        }
    }
    var dataController: DataController!
    
    // MARK: - IBActions
    
    @IBAction private func longPressGestureRecognizerDidReceiveActionEvent(_ sender: UILongPressGestureRecognizer) {
        switch sender.state {
        case .began:
            updatePinForLongPressGesture(sender)
            break
        case .ended:
            persistCurrentAnnotation()
            break
        default: return
        }
    }
    
    // MARK: - Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        fetchedResultsController = NSFetchedResultsController<MapPin>()
        configureNSFetchedResultsController()
        
        loadMapData()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }
    
    // MARK: - Navigation
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let photoAlbumViewController = segue.destination as? PhotoAlbumViewController,
            segue.destination is PhotoAlbumViewController else { return }
        
        if segue.identifier == "AlbumSegue", let pin = currentPin {
            photoAlbumViewController.mapPin = pin
            photoAlbumViewController.dataController = dataController
        }
    }
    
    // MARK: - Functions
    
    private func loadMapData() {
        // @TODO: fetch map center
        // @TODO: fetch zoom level
        // @TODO: fetch persisted annotations array
    }
    
    private func updatePinForLongPressGesture(_ longPressGestureRecognizer: UILongPressGestureRecognizer) {
        let touchPoint = longPressGestureRecognizer.location(in: mapView)
        let newCoordinates = mapView.convert(touchPoint, toCoordinateFrom: mapView)
        guard let currentAnnotation = currentAnnotation else {
            createAnnotation(with: newCoordinates)
            return
        }
        if (currentAnnotation.coordinate.latitude, currentAnnotation.coordinate.longitude) != (newCoordinates.latitude, newCoordinates.longitude) {
            createAnnotation(with: newCoordinates)
        }
    }
    
    private func createAnnotation(with coordinate: CLLocationCoordinate2D) {
        let newAnnotation = MKPointAnnotation()
        newAnnotation.coordinate = coordinate
        currentAnnotation = newAnnotation
        mapView.addAnnotation(newAnnotation)
        annotations?.append(newAnnotation)
        // @TODO: persist annotation
    }
    
    private func persistCurrentAnnotation() {
        guard let coordinate = currentAnnotation?.coordinate else { return }
        
        dataController.addMapPin(at: coordinate, context: .view, onSuccess: { (pin) in
            debugPrint("successfully persisted \(pin)")
            
            self.currentPin = pin
            self.downloadAlbumForCurrentPin()
            
        }, onFailure: { (error) in
            AlertHelper.showAlert(inController: self, title: "Failed to save", message: "Could not save current annotation", style: .default)
            ErrorHelper.logPersistenceError(error!)
            
        }, onCompletion: {
            self.currentAnnotation = nil
        })
    }
    
    private func downloadAlbumForCurrentPin() {
        guard let pin = currentPin else {
            debugPrint("pin is nil")
            return
        }
        
        // @TODO: startLoading()
        self.pinView!.isUserInteractionEnabled = false
        
        let coordinate = CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)
        
        FlickrService().searchAlbum(inCoordinate: coordinate, page: 1, onSuccess: { [weak self] (albumSearchResponse) in // @TODO: change page number to random page from album response's pages
            guard let flickrPhotos = albumSearchResponse?.photos?.photo, let pin = self?.currentPin else { return }
            
            self?.dataController.convertAndPersist(flickrPhotos, mapPin: pin, context: .view, onSuccess: { (persistedPhotoArray) in
                debugPrint("successfully converted, persisted photos array (flickr -> persisted) and assigned to pin (id = \(pin.id!)")
                
                for photo in persistedPhotoArray {
                    if photo.data == nil {
                        self?.downloadBackupPhoto(photo)
                    }
                }
                
            }, onFailure: { (error) in
                ErrorHelper.logPersistenceError(error!)
                AlertHelper.showAlert(inController: self!, title: "No album", message: "Could not fetch an album for given pin location.", style: .default)
                
            }, onCompletion: nil)
            
        }, onFailure: { (error) in
            ErrorHelper.logServiceError(error as! ServiceError)
            AlertHelper.showAlert(inController: self, title: "Download failed", message: "Failed to download album for current pin coordinate.", style: .default)
            
        }, onCompletion: {
            // @TODO: stopLoading()
            self.pinView!.isUserInteractionEnabled = true
        })
    }
    
    private func configureNSFetchedResultsController() {
        let fetchRequest: NSFetchRequest<MapPin> = MapPin.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: dataController.viewContext, sectionNameKeyPath: nil, cacheName: "mapPin")
        
        do {
            try fetchedResultsController?.performFetch()
            
        } catch let error {
            debugPrint("fetchedResultsController error:\n\(error)")
            
            AlertHelper.showAlert(inController: self, title: "Error", message: "Could not find selected Map Pin on local database.", style: .default, rightAction: UIAlertAction(title: "Retry", style: .default, handler: { (action) in
                self.navigationController?.popViewController(animated: true)
            }))
        }
    }
    
    private func downloadBackupPhoto(_ photo: PersistedPhoto) {
        debugPrint("PersistedPhoto with id = \(photo.objectID) has no data. GETing it from Flickr...")
        guard let url = photo.imageURL() else { return }
        FlickrService().getPhotoData(fromURL: url, onSuccess: { [weak self] (imageData) in
            // @TODO: create [Data]?
            if let imageData = imageData {
                self?.dataController.updatePersistedPhotoData(withObjectID: photo.objectID, data: imageData, context: .background, onSuccess: {
                    debugPrint("sucessfully assigned data to PersistedPhoto with id = (\(photo.objectID))")
                    
                }, onFailure: { (persistenceError) in
                    ErrorHelper.logPersistenceError(persistenceError!)
                    
                }, onCompletion: nil)
            }
            
            }, onFailure: { (error) in
                ErrorHelper.logServiceError(error as! ServiceError)
                
        }, onCompletion: nil)
    }
}

// MARK: - Extensions

extension TravelLocationsViewController: MKMapViewDelegate {
    
    // MARK: - MKMapView Delegate Methods
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        pinView = mapView.dequeueReusableAnnotationView(withIdentifier: "pin") as? MKPinAnnotationView
        
        if let pin = pinView {
            pin.annotation = annotation
        } else {
            pinView = MKPinAnnotationView(annotation: annotation, reuseIdentifier: "pin")
            pinView?.canShowCallout = true
        }
        
        return pinView
    }

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        performSegue(withIdentifier: "AlbumSegue", sender: self)
        mapView.deselectAnnotation(view.annotation, animated: true)
    }
    
}

extension TravelLocationsViewController: UIGestureRecognizerDelegate {
    
    // MARK: - UIGestureRecognizer Delegate Methods
    
}

extension TravelLocationsViewController: NSFetchedResultsControllerDelegate {

    // MARK: - NSFetchedResultsControllerDelegate Methods

}
