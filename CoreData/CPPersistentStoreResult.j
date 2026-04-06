//
//  CPPersistentStoreResult.j
//
//  Mirrors NSPersistentStoreResult — an empty base class used for
//  future extensibility of persistent-store operation results.
//

@import <Foundation/Foundation.j>

/*!
    Base class for all persistent-store operation results.

    Mirrors NSPersistentStoreResult. Subclasses carry the actual
    result payload (e.g. CPAsynchronousFetchResult).
*/
@implementation CPPersistentStoreResult : CPObject

@end
