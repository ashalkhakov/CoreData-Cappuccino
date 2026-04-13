//
//  CPManagedObjectID.j
//
//  Created by Raphael Bartolome on 07.10.09.
//

@import <Foundation/Foundation.j>

@class CPEntityDescription;
@class CPManagedObjectContext;
@class CPPersistentStore;

@implementation CPManagedObjectID : CPObject
{
    CPEntityDescription _entity;
    CPManagedObjectContext _context @accessors(property=context);
    CPPersistentStore _persistentStore;
    id _globalID @accessors(property=globalID);
    id _localID @accessors(setter=setLocalID:);
    BOOL _isTemporary;
}

+ (id)createLocalID
{
    return [CPString UUID];
}

- (id)initWithEntity:(CPEntityDescription) entity globalID:(id)globalID isTemporary:(BOOL)isTemporary
{
    if(self = [super init])
    {
        _entity = entity;
        if(isTemporary == YES && globalID == nil)
        {
            _isTemporary = isTemporary;
            _globalID = globalID;
            _localID = [CPManagedObjectID createLocalID];
        }
        else
        {
            _globalID = globalID;
            _localID = [CPManagedObjectID createLocalID];
            _isTemporary = isTemporary;
        }
    }
    return self;
}

// Public read-only getter
- (CPEntityDescription)entity
{
    return _entity;
}

// Internal setter (not part of the public API)
- (void)setEntity:(CPEntityDescription)entity
{
    _entity = entity;
}

// Public read-only getter
- (CPPersistentStore)persistentStore
{
    return _persistentStore;
}

// Internal setter (not part of the public API)
- (void)setPersistentStore:(CPPersistentStore)store
{
    _persistentStore = store;
}

// Public read-only getter
- (BOOL)isTemporary
{
    return _isTemporary;
}

// Internal setter (not part of the public API)
- (void)setIsTemporary:(BOOL)isTemporary
{
    _isTemporary = isTemporary;
}

// Returns a URI that provides an archivable reference to the object in the store.
// Permanent IDs: x-coredata://storeID/EntityName/pGlobalID
// Temporary IDs: x-coredata:///EntityName/tLocalID
- (CPURL)uriRepresentation
{
    var entityName = (_entity != nil) ? encodeURIComponent([_entity name]) : @"";
    if (_isTemporary)
    {
        var localPart = encodeURIComponent([self localID]);
        return [CPURL URLWithString:@"x-coredata:///" + entityName + @"/t" + localPart];
    }
    var storeID    = (_persistentStore != nil) ? encodeURIComponent([_persistentStore storeID]) : @"",
        globalPart = encodeURIComponent(_globalID || @"");
    return [CPURL URLWithString:@"x-coredata://" + storeID + @"/" + entityName + @"/p" + globalPart];
}

- (id)localID
{
    if(_localID == nil)
        _localID = [CPManagedObjectID createLocalID];
    return _localID;
}

- (BOOL)validatedLocalID
{
    if(_localID != nil && [_localID length] > 0)
        return YES;
    return NO;
}

- (BOOL)validatedGlobalID
{
    if(_globalID != nil && [_globalID length] > 0)
        return YES;
    return NO;
}

- (BOOL) isEqualToLocalID: (CPManagedObjectID) otherID
{
    if(otherID == nil || [otherID localID] == nil || ![[self localID] isEqual:[otherID localID]])
    {
      return NO;
    }
    return YES;
}

- (BOOL) isEqualToGlobalID: (CPManagedObjectID) otherID
{
    if(otherID == nil || [otherID globalID] == nil || ![[self globalID] isEqual:[otherID globalID]])
    {
      return NO;
    }
    return YES;
}

- (BOOL) isEqual: (CPManagedObjectID) otherID
{
    if (otherID == nil)
        return NO;

    if ([self validatedGlobalID] && [otherID validatedGlobalID])
        return [self isEqualToGlobalID:otherID];

    if ([self validatedLocalID] && [otherID validatedLocalID])
        return [self isEqualToLocalID:otherID];

    return NO;
}

- (unsigned) hash
{
    if ([self validatedGlobalID])
        return [[self globalID] hash];
    return [[self localID] hash];
}

- (void)updateWithObjectID:(CPManagedObjectID)newObjectID
{
    _globalID = [newObjectID globalID];
    _isTemporary = [newObjectID isTemporary];
    if ([self localID] == nil || [[self localID] length] <= 0)
    {
        [self setLocalID: [self createLocalID]];
    }
}

- (CPString)entityName
{
    return [_entity name];
}


- (CPNumber)_isTemporaryNumber
{
    return [CPNumber numberWithBool:_isTemporary];
}


- (CPString)stringRepresentation
{
    var result = "\n";
    result = result + "\n";
    result = result + "-CPManagedObjectID-";
    result = result + "\n***********";
    result = result + "\n";
    result = result + "localID:" + [self localID] + ";";
    result = result + "\n";
    result = result + "globalID:" + [self globalID] + ";";
    return result;
}

@end
