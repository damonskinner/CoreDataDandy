//
//  CoreDataDandy.swift
//  CoreDataDandy
//
//  Created by Noah Blake on 6/20/15.
//  Copyright © 2015 Fuzz Productions, LLC. All rights reserved.
//
//  This code is distributed under the terms and conditions of the MIT license.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
//  IN THE SOFTWARE.

import CoreData

/// `CoreDataDandy` provides an interface to the majority of the module's features, which include Core Data
/// bootstrapping, main and background-threaded context management, convenient `NSFetchRequests`, 
/// database inserts, database deletes, and `NSManagedObject` deserialization.
public class CoreDataDandy {
	// MARK: - Properties -
	/// A singleton encapsulating much of CoreDataDandy's base functionality.
	private static let defaultDandy = CoreDataDandy()
	/// The default implementation of Dandy. Subclasses looking to extend or alter Dandy's functionality
	/// should override this getter and provide a new instance.
	public class var sharedDandy: CoreDataDandy {
		return defaultDandy
	}
	/// A manager of the NSManagedObjectContext, NSPersistentStore, and NSPersistentStoreCoordinator.
	/// Accessing this property directly is generaly discouraged - it is intended for use within the module alone.
	public var coordinator: PersistentStackCoordinator!
	
	// MARK: - Initialization-
	/// Bootstraps the application's core data stack.
	///
	/// - parameter managedObjectModelName: The name of the .xcdatamodel file
	/// - parameter completion: A completion block executed on initialization completion
	public class func wakeWithMangedObjectModel(managedObjectModelName: String, completion: (() -> Void)? = nil) -> CoreDataDandy {
		EntityMapper.clearCache()
		sharedDandy.coordinator = PersistentStackCoordinator(managedObjectModelName: managedObjectModelName,
												persistentStoreConnectionCompletion: completion)
		return sharedDandy
	}
	
	// MARK: -  Deinitialization -
	/// Removes all cached data from the application without endangering future database
	/// interactions.
	public func tearDown() {
		coordinator.resetManageObjectContext()
		
		do {
			try NSFileManager.defaultManager().removeItemAtURL(PersistentStackCoordinator.persistentStoreURL)
		} catch {
			log(message("Failed to delete persistent store"))
		}
		
		coordinator.resetPersistentStore()
		EntityMapper.clearCache()
		save()
	}
	
	// MARK: - Inserts -
	/// Inserts a new managed object from the specified entity name. In general, this function should not be invoked
	/// directly, as its incautious use is likely to lead to database use.
	///
	/// - parameter entity: The name of the requested entity
	///
	/// - returns: A managed object if one could be inserted for the specified Entity.
	public func insertManagedObjectForEntity(entityName: String) -> NSManagedObject? {
		if let entityDescription = NSEntityDescription.forEntity(entityName) {
			// Ignore this insert if the entity is a singleton and a pre-existing insert exists.
			if entityDescription.primaryKey == SINGLETON {
				if let singleton = singletonForEntity(entityName) {
					return singleton
				}
			}
			// Otherwise, insert a new managed object
			return NSManagedObject(entity: entityDescription, insertIntoManagedObjectContext: coordinator.mainContext)
		}
		else {
			log(message("NSEntityDescriptionNotFound for entity named " + entityName + ". No object will be returned"))
			return nil
		}
	}
	
	/// MARK: - Upserts -
	/// This function performs upserts differently depending on whether the entity is marked as unique or not.
	///
	/// If the entity is marked as unique (either through an @primaryKey decoration or an xcdatamode constraint), the
	/// primaryKeyValue is extracted and an upsert is performed through
	/// `uniqueManagedObjectForEntity(_:, primaryKeyValue:) -> NSManagedObject?`. 
	///
	/// Otherwise, an insert is performed and a managed object is written to from the json provided.
	///
	/// - parameter entity: The name of the requested entity
	/// - parameter json: A dictionary to map into the returned object's attributes and relationships
	///
	/// - returns: A managed object if one could be created.
	public func managedObjectForEntity(entityName: String, fromJSON json: [String: AnyObject]) -> NSManagedObject? {
		guard let entityDescription = NSEntityDescription.forEntity(entityName) else {
			log(message("Could not retrieve NSEntityDescription or for entity named \(entityName)"))
			return nil
		}
		
		let isUniqueEntity = entityDescription.primaryKey != nil
		if isUniqueEntity {
			if let primaryKeyValue = entityDescription.primaryKeyValueFromJSON(json) {
				return uniqueManagedObjectForEntity(entityDescription, primaryKeyValue: primaryKeyValue, fromJSON: json)
			} else {
				log(message("Could not retrieve primary key from json \(json)."))
				return nil
			}
		}
		
		if let managedObject = insertManagedObjectForEntity(entityName) {
			return ObjectFactory.buildObject(managedObject, fromJSON: json)
		}
		
		return nil
	}
	/// Attempts to build an array of managed objects from a json array. Through recursion, behaves identically to
	/// managedObjectForEntity(_:, _:) -> NSManagedObject?.
	///
	/// - parameter entity: The name of the requested entity
	/// - parameter json: An array to map into the returned objects' attributes and relationships
	///
	/// - returns: An array of managed objects if one could be created.
	public func managedObjectsForEntity(entityName: String, fromJSON json: [[String:AnyObject]]) -> [NSManagedObject]? {
		var managedObjects = [NSManagedObject]()
		for object in json {
			if let managedObject = managedObjectForEntity(entityName, fromJSON: object) {
				managedObjects.append(managedObject)
			}
		}
		return (managedObjects.count > 0) ? managedObjects: nil
	}
	
	// MARK: - Unique objects -
	/// Attempts to fetch an `NSManagedObject` of the specified entity name matching the primary key provided.
	/// - If no property on the entity's `NSEntityDescription` is marked with the @primaryKey identifier, a warning
	/// is issued and no managed object is returned.
	/// - If an object matching the primaryKey is found, it is returned. Otherwise a new object is inserted and returned.
	/// - If more than one object is fetched for this primaryKey, a warning is issued and one is returned.
	///
	/// - parameter entity: The name of the requested entity.
	/// - parameter primaryKeyValue: The value of the unique object's primary key
	public func uniqueManagedObjectForEntity(entityName: String, primaryKeyValue: AnyObject) -> NSManagedObject? {
		// Return an object if one exists. Otherwise, attempt to insert one.
		if let object = fetchUniqueObjectForEntity(entityName, primaryKeyValue: primaryKeyValue, emitResultCountWarnings: false) {
			return object
		} else if let entityDescription = NSEntityDescription.forEntity(entityName),
			let primaryKey = entityDescription.primaryKey {
			let object = insertManagedObjectForEntity(entityName)
			let convertedPrimaryKeyValue: AnyObject? = CoreDataValueConverter.convertValue(primaryKeyValue, forEntity: entityDescription, property: primaryKey)
			object?.setValue(convertedPrimaryKeyValue, forKey: primaryKey)
			return object
		}
		return nil
	}
	/// Invokes `uniqueManagedObjectForEntity(_:, primaryKeyValue:) -> NSManagedObject?`, then attempts to write values from
	/// the provided JSON into the returned object.
	///
	/// - parameter entityDescription: The `NSEntityDescription` of the requested entity
	/// - parameter primaryKeyValue: The value of the unique object's primary key
	/// - parameter json: A dictionary to map into the returned object's attributes and relationships
	///
	/// - returns: A managed object if one could be created.
	private func uniqueManagedObjectForEntity(entityDescription: NSEntityDescription, primaryKeyValue: AnyObject, fromJSON json: [String: AnyObject]) -> NSManagedObject? {
		if let object = uniqueManagedObjectForEntity(entityDescription.name ?? "", primaryKeyValue: primaryKeyValue) {
			ObjectFactory.buildObject(object, fromJSON: json)
			return object
		} else {
			log(message("Could not upsert managed object for entity description \(entityDescription), primary key \(primaryKeyValue), json \(json)."))
			return nil
		}
	}
	
	// MARK: - Fetches -
	/// Attempts to fetch a unique object of a given entity with a primary key value matching the passed in parameter.
	/// Because this function first verifies the existence of a given `NSEntityDescription`, its fetch request
	/// cannot throw. As such, the exception is caught and silences within its implementation to simplify the function
	/// invocation.
	///
	/// - parameter entity: The name of the fetched entity
	/// - parameter primaryKeyValue: The value of unique object's primary key.
	///
	/// - returns: If the fetch was successful, the fetched NSManagedObject.
	public func fetchUniqueObjectForEntity(entityName: String, primaryKeyValue: AnyObject) -> NSManagedObject? {
		return fetchUniqueObjectForEntity(entityName, primaryKeyValue: primaryKeyValue, emitResultCountWarnings: true)
	}
	/// A private version of `fetchUniqueObjectForEntity(_:_:) used for toggling warnings that would be of no interest
	/// to the user. The warning accompanying an upsert request that begins by yielding a fetch of 0 results, for instance,
	/// is silenced.
	///
	/// - parameter entity: The name of the fetched entity
	/// - parameter primaryKeyValue: The value of unique object's primary key.
	/// - parameter emitResultCountWarnings: When true, fetch results without exactly one object emit warnings.
	///
	/// - returns: If the fetch was successful, the fetched NSManagedObject.
	private func fetchUniqueObjectForEntity(entityName: String, primaryKeyValue: AnyObject, emitResultCountWarnings: Bool) -> NSManagedObject? {
		let entityDescription = NSEntityDescription.forEntity(entityName)
		if let entityDescription = entityDescription {
			if entityDescription.primaryKey == SINGLETON {
				if let singleton = singletonForEntity(entityName) {
					return singleton
				}
			}
			else {
				if let predicate = primaryPredicateForEntity(entityDescription, primaryKeyValue: primaryKeyValue) {
					var results: [NSManagedObject]? = nil
					do  {
						results = try fetchObjectsForEntity(entityName, predicate: predicate)
					} catch {
						log(message("Your unique fetch for entity named \(entityName) with primary key \(primaryKeyValue) raised an exception. This is a serious error that should be resolved immediately."))
					}
					if results?.count == 0 && emitResultCountWarnings {
						log(message("Your unique fetch for entity named \(entityName) with primary key \(primaryKeyValue) returned no results."))
					}
					else if results?.count > 1 && emitResultCountWarnings {
						log(message("Your unique fetch for entity named \(entityName) with primary key \(primaryKeyValue) returned multiple results. This is a serious error that should be resolved immediately."))
					}
					return results?.first
				}
				else {
					log(message("Failed to produce predicate for \(entityName) with primary key \(primaryKeyValue)."))
				}
			}
			log(message("A unique NSManaged for entity named \(entityName) could not be retrieved for primaryKey \(primaryKeyValue). No object will be returned"))
			return nil
		}
		else {
			log(message("NSEntityDescriptionNotFound for entity named \(entityName). No object will be returned"))
			return nil
		}
	}
	/// A wrapper around NSFetchRequest.
	///
	/// - parameter entity: The name of the fetched entity
	///
	/// - throws: If the ensuing NSManagedObjectContext's executeFetchRequest() throws, the exception will be passed.
	/// - returns: If the fetch was successful, the fetched NSManagedObjects.
	public func fetchObjectsForEntity(entityName: String) throws -> [NSManagedObject]? {
		return try fetchObjectsForEntity(entityName, predicate: nil)
	}
	/// A simple wrapper around NSFetchRequest.
	///	
	/// - parameter entity: The name of the fetched entity
	/// - parameter predicate: The predicate used to filter results
	///
	/// - throws: If the ensuing NSManagedObjectContext's executeFetchRequest() throws, the exception will be passed.
	///
	/// - returns: If the fetch was successful, the fetched NSManagedObjects.
	public func fetchObjectsForEntity(entityName: String, predicate: NSPredicate?) throws -> [NSManagedObject]? {
		let request = NSFetchRequest(entityName: entityName)
		request.predicate = predicate
		let results = try coordinator.mainContext.executeFetchRequest(request)
		return results as? [NSManagedObject]
	}
	
	// MARK: - Saves and Deletes -
	/// Save the current state of the `NSManagedObjectContext` to disk and optionally receive notice of the save
	/// operation's completion.
	///
	/// - parameter completion: An optional closure that is invoked when the save operation complete. If the save operation
	/// 	resulted in an error, the error is returned.
	public func save(completion:((error: NSError?) -> Void)? = nil) {
		/**
		Note: http://www.openradar.me/21745663. Currently, there is no way to throw out of performBlock. If one arises,
		this code should be refactored to throw.
		*/
		if !coordinator.mainContext.hasChanges && !coordinator.privateContext.hasChanges {
			if let completion = completion {
				completion(error: nil)
			}
			return
		}
		coordinator.mainContext.performBlockAndWait({[unowned self] in
			do {
				try self.coordinator.mainContext.save()
			} catch {
				log(message( "Failed to save main context."))
				completion?(error: error as NSError)
				return
			}
			
			self.coordinator.privateContext.performBlock({ [unowned self] in
				do {
					try self.coordinator.privateContext.save()
					completion?(error: nil)
				}
				catch {
					log(message( "Failed to save private context."))
					completion?(error: error as NSError)
				}
				})
			})
	}
	/// Delete a managed object.
	///
	/// - parameter object: The object to be deleted.
	/// - parameter completion: An optional closure that is invoked when the deletion is complete.
	public func deleteManagedObject(object: NSManagedObject, completion: (() -> Void)? = nil) {
		if let context = object.managedObjectContext {
			context.performBlock({
				context.deleteObject(object)
				completion?()
			})
		}
	}
	
	// MARK: - Private helpers -
	/// Attempts to return a predicate which may be used to fetch a unique version of an object.
	///
	/// - parameter entity: The name of the singleton entity
	///
	/// - returns: The singleton for this entity if one could be found.
	private func singletonForEntity(entityName: String) -> NSManagedObject? {
		// Validate the entity description to ensure fetch safety
		if let entityDescription = NSEntityDescription.entityForName(entityName, inManagedObjectContext: coordinator.mainContext) {
			do {
				if let results = try fetchObjectsForEntity(entityName) {
					if results.count == 1 {
						return results.first
					} else if results.count == 0 {
						return NSManagedObject(entity: entityDescription, insertIntoManagedObjectContext: coordinator.mainContext)
					} else {
						log(message("Failed to fetch unique instance of entity named " + entityName + "."))
						return nil

					}
				}
			}
				catch {
					log(message("Your singleton fetch for entity named \(entityName) raised an exception. This is a serious error that should be resolved immediately."))
			}
		}
		log(message("Failed to fetch unique instance of entity named " + entityName + "."))
		return nil
	}
	/// Returns a predicate that may be used to fetch unique objects
	private func primaryPredicateForEntity(entity: NSEntityDescription, primaryKeyValue: AnyObject) -> NSPredicate? {
			if	let primaryKey = entity.primaryKey,
				let value: AnyObject = CoreDataValueConverter.convertValue(primaryKeyValue, forEntity: entity, property: primaryKey) {
				return NSPredicate(format: "%K = %@", argumentArray: [primaryKey, value])
		}
		return nil
	}
}
// MARK: - Convenience accessors -
/// A lazy global for more succinct access to CoreDataDandy's sharedDandy.
public let Dandy: CoreDataDandy = CoreDataDandy.sharedDandy
