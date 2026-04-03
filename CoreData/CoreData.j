//
//  CoreData.j
//
//  Created by Raphael Bartolome on 15.09.09.
//

@import <Foundation/Foundation.j>

@import "CPPersistentStore.j"
@import "CPPersistentStoreType.j"
@import "CPPersistentStoreCoordinator.j"
@import "CPManagedObjectContext.j"

@import "CPManagedObjectID.j"
@import "CPManagedObject.j"
@import "CPManagedObjectModel.j"
@import "CPEntityDescription.j"
@import "CPAttributeDescription.j"
@import "CPPropertyDescription.j"
@import "CPFetchedPropertyDescription.j"
@import "CPFetchRequest.j"
@import "CPFetchRequestTemplates.j"

@import "CPCoreDataCategories/CPCoreDataCategories.j"
@import "CPCoreDataJSONSchema/CPCoreDataJSONSchema.j"
@import "NSCoreData/NSCoreData.j"

//Memory store
@import "CPCoreDataPersistentStores/MemoryStore/CPMemoryStore.j"
@import "CPCoreDataPersistentStores/MemoryStore/CPMemoryStoreType.j"

//WebDAV store
@import "CPCoreDataPersistentStores/WebDAVStore/CPWebDAVStoreType.j"
@import "CPCoreDataPersistentStores/WebDAVStore/CPWebDAVStore.j"

//HTML5 store
@import "CPCoreDataPersistentStores/HTML5Store/CPHTML5Store.j"
@import "CPCoreDataPersistentStores/HTML5Store/CPHTML5StoreType.j"

//WebObjects store
@import "CPCoreDataPersistentStores/WOStore/CPWOStore.j"
@import "CPCoreDataPersistentStores/WOStore/CPWOStoreType.j"

//HTTP incremental store (OrdersAPI cdFetch / cdSave)
@import "CPCoreDataPersistentStores/HTTPStore/CPHTTPStoreType.j"
@import "CPCoreDataPersistentStores/HTTPStore/CPHTTPPredicateEncoder.j"
@import "CPCoreDataPersistentStores/HTTPStore/CPHTTPStore.j"
