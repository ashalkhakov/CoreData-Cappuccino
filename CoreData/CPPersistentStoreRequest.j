//
//  CPPersistentStoreRequest.j
//
//  Mirrors NSPersistentStoreRequest.
//

@import <Foundation/Foundation.j>

/*!
    Request-type constants, mirroring NSPersistentStoreRequestType.
*/
CPFetchRequestType             = 1;
CPSaveRequestType              = 2;
CPAsynchronousFetchRequestType = 4;

/*!
    Base class for all persistent-store requests.

    Mirrors NSPersistentStoreRequest. Concrete subclasses include
    CPFetchRequest, CPAsynchronousFetchRequest.
*/
@implementation CPPersistentStoreRequest : CPObject
{
    CPInteger _requestType    @accessors(property=requestType);
    CPArray   _affectedStores @accessors(property=affectedStores);
}

@end
