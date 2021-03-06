//
//  PhotoAlbumViewController.swift
//  VirtualTourist
//
//  Created by Andre Sanches Bocato on 15/03/19.
//  Copyright © 2019 Andre Sanches Bocato. All rights reserved.
//

import UIKit
import MapKit
import CoreData
import CoreLocation

class PhotoAlbumViewController: UIViewController {
    
    // MARK: - IBOutlets
    
    @IBOutlet private weak var collectionView: UICollectionView! {
        didSet {
            collectionView.delegate = self
            collectionView.dataSource = self
            collectionView.showLoadingBackgroundView()
        }
    }
    @IBOutlet private weak var mapView: MKMapView! {
        didSet {
            mapView.isUserInteractionEnabled = false
        }
    }
    @IBOutlet private weak var barButton: UIBarButtonItem!
    
    // MARK: - Properties
    
    var mapPin: MapPin!
    
    private var pages: Int?
    private var perPage: Int?
    
    var fetchedResultsController: NSFetchedResultsController<PersistedPhoto>? {
        didSet {
            fetchedResultsController?.delegate = self
        }
    }
    var dataController: DataController!
    
    // MARK: - IBActions
    
    @IBAction private func barButtonDidReceiveTouchUpInside(_ sender: Any) {
        deleteAllObjectsAndReloadRandomPage()
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        fetchedResultsController = NSFetchedResultsController<PersistedPhoto>()
        configureNSFetchedResultsController(with: mapPin!)
        loadViewData()
        loadMapData()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        mapPin = nil
    }
    
    // MARK: - Functions
    
    private func loadMapData() {
        let coordinate = CLLocationCoordinate2D(latitude: mapPin.latitude, longitude: mapPin.longitude)
        let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 2500, longitudinalMeters: 2500)
        mapView.setMapCenterAndRegion(using: coordinate, region: region)
        
        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        mapView.addAnnotation(annotation)
        mapView.selectAnnotation(annotation, animated: true)
    }
    
    private func loadViewData() {
        configureNSFetchedResultsController(with: mapPin)
        
        guard let pinPhotos = mapPin.photos, pinPhotos.count > 0 else {
            downloadAlbumForPin(mapPin, page: getRandomPage())
            return
        }
        
    }
    
    private func deletePhoto(withID id: String,
                             at indexPath: IndexPath) {
        
        dataController.deletePersistedPhoto(withID: id, context: .view, onSuccess: { [weak self] in
            debugPrint("\(indexPath) deleted")
            
            DispatchQueue.main.async { self?.collectionView.reloadData() }
            
            }, onFailure: { (persistenceError) in
                ErrorHelper.logPersistenceError(persistenceError)
                
        })
    }
    
    private func deleteAllObjectsAndReloadRandomPage() {
        if let objectsToDelete = fetchedResultsController?.fetchedObjects, objectsToDelete.count > 0 {
            dataController.deletePersistedPhotos(objectsToDelete, context: .view, onSuccess: { [weak self] in
                guard let mapPin = self?.mapPin, let randomPage = self?.getRandomPage() else { return }
                self?.downloadAlbumForPin(mapPin, page: randomPage)
                
                }, onFailure: { (persistenceError) in
                    ErrorHelper.logPersistenceError(persistenceError)
                    AlertHelper.showAlert(inController: self, title: "Failed", message: "Failed to delete photos.", style: .default)
            })
        } else {
            self.downloadAlbumForPin(mapPin, page: getRandomPage())
        }
    }
    
    private func downloadAlbumForPin(_ pin: MapPin,
                                     page: Int){
        
        let coordinate = CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)
        
        FlickrService().searchAlbum(inCoordinate: coordinate, page: page, onSuccess: { [weak self] (albumSearchResponse) in
            
            guard let flickrPhotos = albumSearchResponse?.photos?.photo else { return }
            
            self?.pages = albumSearchResponse?.photos?.pages
            self?.perPage = albumSearchResponse?.photos?.perPage
            
            self?.dataController.convertAndPersist(flickrPhotos, mapPin: pin, context: .view, onSuccess: { (persistedPhotoArray) in
                
                persistedPhotoArray
                    .filter { $0.data == nil }
                    .forEach { self?.downloadBackupPhoto($0) }
                
                DispatchQueue.main.async { self?.collectionView.reloadData() }
                
            }, onFailure: { (persistenceError) in
                ErrorHelper.logPersistenceError(persistenceError)
                AlertHelper.showAlert(inController: self, title: "No album", message: "Could not fetch an album for given pin location.", style: .default)
                
            })
            
            }, onFailure: { (error) in
                ErrorHelper.logServiceError(error as? ServiceError)
                AlertHelper.showAlert(inController: self, title: "Download failed", message: "Failed to download album for current pin coordinate.", style: .default)
                
        })
    }
    
    // MARK: - Configuration Functions
    
    private func configureNSFetchedResultsController(with mapPin: MapPin) {
        let fetchRequest: NSFetchRequest<PersistedPhoto> = PersistedPhoto.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "mapPin == %@", mapPin)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: dataController.viewContext, sectionNameKeyPath: nil, cacheName: nil)
        
        do {
            try fetchedResultsController?.performFetch()
            
        } catch let error {
            debugPrint("fetchedResultsController error:\n\(error)")
            
            AlertHelper.showAlert(inController: self, title: "Error", message: "Could not find selected Map Pin on local database.", style: .default, rightAction: UIAlertAction(title: "Retry", style: .default, handler: { (action) in
                self.navigationController?.popViewController(animated: true)
            }))
        }
    }
    
    private func configureCell(_ cell: AlbumViewCell,
                               at indexPath: IndexPath) {
        
        guard let photoFromPinAlbum = fetchedResultsController?.object(at: indexPath) else { return }
        
        collectionView.hideBackgroudViews()
        
        if let imageData = photoFromPinAlbum.data {
            cell.configureWith(imageData)
        } else {
            guard let url = photoFromPinAlbum.imageURL() else { return }
            downloadBackupPhoto(from: url, for: cell, photoFromPinAlbum)
        }
    }
    
    // MARK: - Helper Functions
    
    private func downloadBackupPhoto(from url: String,
                                     for cell: AlbumViewCell,
                                     _ photo: PersistedPhoto) {
        
        FlickrService().getPhotoData(fromURL: url, onSuccess: { [weak self] (data) in
            guard let imageData = data else {
                cell.configureWithNoImage()
                return
            }
            
            self?.dataController.updatePersistedPhotoData(withObjectID: photo.objectID, data: imageData, context: .view, onSuccess: {
                cell.configureWith(imageData)
                
            }, onFailure: { (persistenceError) in
                ErrorHelper.logPersistenceError(persistenceError)
                cell.configureWithNoImage()
            })
            
            }, onFailure: { (error) in
                AlertHelper.showAlert(inController: self, title: "Request failed", message: "The photo could not be downloaded.", style: .default)
                ErrorHelper.logServiceError(error as? ServiceError)
                cell.configureWithNoImage()
                
        })
    }
    
    private func downloadBackupPhoto(_ photo: PersistedPhoto) {
        guard let url = photo.imageURL() else { return }
        FlickrService().getPhotoData(fromURL: url, onSuccess: { [weak self] (imageData) in
            
            if let imageData = imageData {
                self?.dataController.updatePersistedPhotoData(withObjectID: photo.objectID, data: imageData, context: .background, onSuccess: {
                    
                }, onFailure: { (persistenceError) in
                    ErrorHelper.logPersistenceError(persistenceError)
                })
            }
            
            }, onFailure: { (error) in
                ErrorHelper.logServiceError(error as? ServiceError)
        })
    }
    
    private func getRandomPage() -> Int {
        guard let pages = pages, let perPage = perPage else { return 1 }
        return Int(arc4random_uniform(UInt32(min(pages,4000/perPage)))+1)
    }
    
}

// MARK: - Extensions

extension PhotoAlbumViewController: UICollectionViewDataSource {
    
    // MARK: - UICollectionView Data Source Methods
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        guard let numberOfSections = fetchedResultsController?.sections?.count, numberOfSections > 0 else {
            collectionView.showEmptyBackgroundView(message: "No sections.")
            return 0
        }
        collectionView.hideBackgroudViews()
        return numberOfSections
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let numberOfItemsInSection = fetchedResultsController?.sections?[section].numberOfObjects, numberOfItemsInSection > 0 else {
            collectionView.showEmptyBackgroundView(message: "No items.")
            return 0
        }
        collectionView.hideBackgroudViews()
        return numberOfItemsInSection
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "AlbumViewCell", for: indexPath) as! AlbumViewCell
        
        configureCell(cell, at: indexPath)
        
        return cell
    }
}

extension PhotoAlbumViewController: UICollectionViewDelegate {
    
    // MARK: - UICollectioView Delegate Methods
    
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        return fetchedResultsController?.object(at: indexPath) != nil
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let id = fetchedResultsController?.object(at: indexPath).id else { return }
        deletePhoto(withID: id, at: indexPath)
    }
    
}

extension PhotoAlbumViewController: UICollectionViewDelegateFlowLayout {
    
    // MARK: - Collection View Flow Layout Delegate
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let size = (collectionView.bounds.width/3) - 2
        return CGSize(width: size, height: size)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 2
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return 2
    }
}

extension PhotoAlbumViewController: NSFetchedResultsControllerDelegate {
    
    // MARK: - NSFetchedResultsControllerDelegate Methods
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .delete: debugPrint("deleted")
        case .update: debugPrint("updated")
        case .insert: debugPrint("inserted") //DispatchQueue.main.async { self.collectionView.reloadData() }
        default: return
        }
    }
    
}
