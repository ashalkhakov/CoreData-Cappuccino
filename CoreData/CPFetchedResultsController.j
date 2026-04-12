//
//  CPFetchedResultsController.j
//
//  Cappuccino counterpart to Apple's NSFetchedResultsController.
//
//  Monitors a CPManagedObjectContext for changes and keeps a sorted,
//  optionally-sectioned result set in sync.  Delegates are notified of
//  individual insertions, deletions, moves and updates so that table/
//  outline views can be updated incrementally.
//

@import <Foundation/Foundation.j>
@import "CPManagedObjectContext.j"
@import "CPFetchRequest.j"
@import "CPManagedObject.j"
@import "CPEntityDescription.j"

// ---------------------------------------------------------------------------
// Change-type constants (mirror NSFetchedResultsChangeType)
// ---------------------------------------------------------------------------

CPFetchedResultsChangeInsert = 1;
CPFetchedResultsChangeDelete = 2;
CPFetchedResultsChangeMove   = 3;
CPFetchedResultsChangeUpdate = 4;


// CPIndexPath is provided by Cappuccino's Foundation (CPIndexPath.j).
// We use two-element index paths: index 0 = section, index 1 = row.
// Factory: [CPIndexPath indexPathWithIndexes:[CPArray arrayWithObjects:section, row, nil]]
// Access:  [ip indexAtPosition:0]  →  section
//          [ip indexAtPosition:1]  →  row

// ---------------------------------------------------------------------------
// CPFetchedResultsSectionInfo — describes one section
// ---------------------------------------------------------------------------

/*!
    Describes a single section within the fetched results.
    Vended by CPFetchedResultsController's \c sections property.
*/
@implementation CPFetchedResultsSectionInfo : CPObject
{
    CPString       _name       @accessors(property=name);
    CPString       _indexTitle @accessors(property=indexTitle);
    CPMutableArray _objects    @accessors(property=objects);
}

- (id)initWithName:(CPString)aName
{
    if ((self = [super init]))
    {
        _name       = (aName !== nil && aName !== undefined) ? aName : @"";
        _indexTitle = _name;
        _objects    = [[CPMutableArray alloc] init];
    }
    return self;
}

- (CPInteger)numberOfObjects
{
    return [_objects count];
}

@end


// ---------------------------------------------------------------------------
// CPFetchedResultsController
// ---------------------------------------------------------------------------

/*!
    Tracks a fetch request against a managed object context and maintains a
    sorted, optionally-sectioned array of results.

    Usage:
    @code
        var frc = [CPFetchedResultsController
                      fetchedResultsControllerWithFetchRequest:req
                                          managedObjectContext:context
                                            sectionNameKeyPath:nil
                                                     cacheName:nil];
        frc.delegate = self;
        var err = nil;
        [frc performFetch:@ref(err)];
    @endcode

    The delegate may implement any subset of the informal protocol:
    @code
        - (void)controllerWillChangeContent:(CPFetchedResultsController)controller;
        - (void)controllerDidChangeContent:(CPFetchedResultsController)controller;
        - (void)controller:(CPFetchedResultsController)controller
           didChangeObject:(id)object
               atIndexPath:(CPIndexPath)indexPath
             forChangeType:(CPInteger)type
              newIndexPath:(CPIndexPath)newIndexPath;
        - (void)controller:(CPFetchedResultsController)controller
          didChangeSection:(CPFetchedResultsSectionInfo)sectionInfo
                   atIndex:(CPInteger)sectionIndex
             forChangeType:(CPInteger)type;
    @endcode
*/
@implementation CPFetchedResultsController : CPObject
{
    CPFetchRequest          _fetchRequest          @accessors(property=fetchRequest);
    CPManagedObjectContext  _managedObjectContext  @accessors(property=managedObjectContext);
    CPString                _sectionNameKeyPath    @accessors(property=sectionNameKeyPath);
    CPString                _cacheName             @accessors(property=cacheName);

    id                      _delegate              @accessors(property=delegate);

    // Internal state — nil until -performFetch: succeeds
    CPMutableArray          _fetchedObjects;
    CPMutableArray          _sections;
    BOOL                    _hasFetched;

    // Tracks objects inserted into the context but not yet saved.  Update
    // notifications for these objects are handled silently (re-sort only,
    // no delegate callbacks) because the initial insert callback already
    // covers the logical "one insert" operation.
    CPMutableSet            _recentlyInserted;
}

// ---------------------------------------------------------------------------
// Init / dealloc
// ---------------------------------------------------------------------------

+ (CPFetchedResultsController)fetchedResultsControllerWithFetchRequest:(CPFetchRequest)aRequest
                                                  managedObjectContext:(CPManagedObjectContext)aContext
                                                    sectionNameKeyPath:(CPString)aSectionKeyPath
                                                             cacheName:(CPString)aCacheName
{
    return [[self alloc] initWithFetchRequest:aRequest
                         managedObjectContext:aContext
                           sectionNameKeyPath:aSectionKeyPath
                                    cacheName:aCacheName];
}

- (id)initWithFetchRequest:(CPFetchRequest)aRequest
      managedObjectContext:(CPManagedObjectContext)aContext
        sectionNameKeyPath:(CPString)aSectionKeyPath
                 cacheName:(CPString)aCacheName
{
    if ((self = [super init]))
    {
        _fetchRequest         = aRequest;
        _managedObjectContext = aContext;
        _sectionNameKeyPath   = aSectionKeyPath;
        _cacheName            = aCacheName;
        _hasFetched           = NO;
        _fetchedObjects       = nil;
        _sections             = nil;
        _recentlyInserted     = [[CPMutableSet alloc] init];

        [[CPNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(_contextObjectsDidChange:)
                   name:CPManagedObjectContextObjectsDidChangeNotification
                 object:_managedObjectContext];

        [[CPNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(_contextDidSave:)
                   name:CPManagedObjectContextDidSaveNotification
                 object:_managedObjectContext];
    }
    return self;
}

- (void)dealloc
{
    [[CPNotificationCenter defaultCenter]
        removeObserver:self
                  name:CPManagedObjectContextObjectsDidChangeNotification
                object:_managedObjectContext];
    [[CPNotificationCenter defaultCenter]
        removeObserver:self
                  name:CPManagedObjectContextDidSaveNotification
                object:_managedObjectContext];
    [super dealloc];
}

// ---------------------------------------------------------------------------
// Fetching
// ---------------------------------------------------------------------------

/*!
    Execute the fetch request and populate \c fetchedObjects.

    @param error  On failure this ref is set to a CPError.
    @return YES on success, NO on failure.
*/
- (BOOL)performFetch:(@ref)error
{
    var results = [_managedObjectContext executeFetchRequest:_fetchRequest
                                                       error:error];
    if (results === nil)
        return NO;

    _fetchedObjects = [CPMutableArray arrayWithArray:results];
    _hasFetched     = YES;
    [self _rebuildSections];

    if (   _delegate
        && [_delegate respondsToSelector:@selector(controllerDidChangeContent:)]
       )
        [_delegate controllerDidChangeContent:self];

    return YES;
}

/*!
    Async variant of performFetch:.

    Uses executeStoreFetchRequestAsync:completionHandler: so that HTTP-backed
    stores do not block the browser UI.

    @param handler  JS function(success BOOL, error CPError).
*/
- (void)performFetchAsync:(Function)handler
{
    var self_ = self;
    [_managedObjectContext executeStoreFetchRequestAsync:_fetchRequest
                                      completionHandler:function(results, fetchError) {
        if (fetchError !== nil || results === nil)
        {
            if (handler) handler(NO, fetchError);
            return;
        }
        self_._fetchedObjects = [CPMutableArray arrayWithArray:results];
        self_._hasFetched     = YES;
        [self_ _rebuildSections];
        if (   self_._delegate
            && [self_._delegate respondsToSelector:@selector(controllerDidChangeContent:)]
           )
            [self_._delegate controllerDidChangeContent:self_];
        if (handler) handler(YES, nil);
    }];
}

// ---------------------------------------------------------------------------
// Accessing results
// ---------------------------------------------------------------------------

/*!
    The objects matching the fetch request in the order dictated by the sort
    descriptors.  Returns \c nil until \c performFetch: has been called
    successfully.
*/
- (CPArray)fetchedObjects
{
    return _hasFetched ? _fetchedObjects : nil;
}

/*!
    An array of CPFetchedResultsSectionInfo objects.
    Returns \c nil until \c performFetch: has been called successfully.
*/
- (CPArray)sections
{
    return _hasFetched ? _sections : nil;
}

/*!
    Returns the object at the given index path, or nil.
*/
- (id)objectAtIndexPath:(CPIndexPath)indexPath
{
    if (!_hasFetched || indexPath === nil)
        return nil;

    var sectionIdx = [indexPath indexAtPosition:0];
    if (sectionIdx < 0 || sectionIdx >= [_sections count])
        return nil;

    var section = [_sections objectAtIndex:sectionIdx];
    var rowIdx  = [indexPath indexAtPosition:1];
    var objs    = [section objects];
    if (rowIdx < 0 || rowIdx >= [objs count])
        return nil;

    return [objs objectAtIndex:rowIdx];
}

/*!
    Returns the index path of \c anObject in the receiver's results, or nil
    if \c anObject is not in the fetched results.
*/
- (CPIndexPath)indexPathForObject:(id)anObject
{
    if (!_hasFetched || anObject === nil)
        return nil;

    for (var s = 0; s < [_sections count]; s++)
    {
        var section = [_sections objectAtIndex:s];
        var objs    = [section objects];
        var row     = [objs indexOfObject:anObject];
        if (row !== CPNotFound)
            return [CPIndexPath indexPathWithIndexes:[CPArray arrayWithObjects:s, row, nil]];
    }
    return nil;
}

/*!
    Returns an array of section title strings (the \c indexTitle of each
    section).
*/
- (CPArray)sectionIndexTitles
{
    if (!_hasFetched)
        return nil;

    var titles = [[CPMutableArray alloc] init];
    for (var i = 0; i < [_sections count]; i++)
        [titles addObject:[[_sections objectAtIndex:i] indexTitle]];
    return titles;
}

// ---------------------------------------------------------------------------
// Context notification handler
// ---------------------------------------------------------------------------

- (void)_contextObjectsDidChange:(CPNotification)notification
{
    if (!_hasFetched)
        return;

    var userInfo  = [notification userInfo];
    var inserted  = [userInfo objectForKey:CPDInsertedObjectsKey]  || [CPSet set];
    var updated   = [userInfo objectForKey:CPDUpdatedObjectsKey]   || [CPSet set];
    var deleted   = [userInfo objectForKey:CPDDeletedObjectsKey]   || [CPSet set];

    // ---- Classify objects --------------------------------------------------

    var toInsert       = [[CPMutableArray alloc] init]; // objects to add to results
    var toDelete       = [[CPMutableArray alloc] init]; // objects to remove
    var toUpdate       = [[CPMutableArray alloc] init]; // already tracked, may move
    var toSilentUpdate = [[CPMutableArray alloc] init]; // updates for recently-inserted (unsaved) objects

    // Newly inserted objects in context that now match the predicate
    var insEnum = [inserted objectEnumerator];
    var obj;
    while ((obj = [insEnum nextObject]))
    {
        if (   [self _objectMatchesFetchRequest:obj]
            && [_fetchedObjects indexOfObject:obj] === CPNotFound
           )
            [toInsert addObject:obj];
    }

    // Updated objects — may enter, leave, or stay in results
    var updEnum = [updated objectEnumerator];
    while ((obj = [updEnum nextObject]))
    {
        var trackedIdx = [_fetchedObjects indexOfObject:obj];
        var matches    = [self _objectMatchesFetchRequest:obj];
        if (trackedIdx !== CPNotFound && !matches)
            [toDelete addObject:obj];   // no longer satisfies predicate
        else if (trackedIdx === CPNotFound && matches)
            [toInsert addObject:obj];   // now satisfies predicate
        else if (trackedIdx !== CPNotFound && matches)
        {
            // If this object was inserted but not yet saved, re-sort silently
            // instead of firing extra willChange/didChange cycles.
            if ([_recentlyInserted containsObject:obj])
                [toSilentUpdate addObject:obj];
            else
                [toUpdate addObject:obj];   // still in results, may have moved
        }
    }

    // Deleted objects that were in our results
    var delEnum = [deleted objectEnumerator];
    while ((obj = [delEnum nextObject]))
    {
        if ([_fetchedObjects indexOfObject:obj] !== CPNotFound)
            [toDelete addObject:obj];
    }

    // ---- Handle silent re-sorts for recently-inserted objects ---------------
    // These are attribute-only changes on objects we inserted in this session
    // (before save).  We keep _fetchedObjects sorted but don't notify the
    // delegate — the original insert notification already covered them.
    for (var i = 0; i < [toSilentUpdate count]; i++)
    {
        var silentObj  = [toSilentUpdate objectAtIndex:i];
        var currentIdx = [_fetchedObjects indexOfObject:silentObj];
        var desiredIdx = [self _sortedInsertionIndexForObject:silentObj
                                             usingDescriptors:[_fetchRequest sortDescriptors]
                                                       inArray:_fetchedObjects
                                             excludingObject:silentObj];
        if (desiredIdx !== currentIdx)
        {
            [_fetchedObjects removeObjectAtIndex:currentIdx];
            var insertIdx = (desiredIdx > currentIdx) ? desiredIdx - 1 : desiredIdx;
            [_fetchedObjects insertObject:silentObj atIndex:insertIdx];
        }
    }

    // Nothing to do?
    if (   [toInsert count] === 0
        && [toDelete count] === 0
        && [toUpdate count] === 0
       )
        return;

    // ---- Notify: will change -----------------------------------------------

    if (   _delegate
        && [_delegate respondsToSelector:@selector(controllerWillChangeContent:)]
       )
        [_delegate controllerWillChangeContent:self];

    // ---- Apply deletions (high index first) --------------------------------

    // Sort by current index descending to avoid index shifting issues
    var deletesSorted = [toDelete sortedArrayUsingFunction:function(a, b) {
        var ia = [_fetchedObjects indexOfObject:a];
        var ib = [_fetchedObjects indexOfObject:b];
        return ib - ia; // descending
    } context:nil];

    for (var i = 0; i < [deletesSorted count]; i++)
    {
        var delObj = [deletesSorted objectAtIndex:i];
        var oldIP  = [self indexPathForObject:delObj];
        [self _removeObjectFromFetchedObjects:delObj];
        [_recentlyInserted removeObject:delObj];
        if (   _delegate
            && [_delegate respondsToSelector:@selector(controller:didChangeObject:atIndexPath:forChangeType:newIndexPath:)]
           )
            [_delegate controller:self
                  didChangeObject:delObj
                      atIndexPath:oldIP
                    forChangeType:CPFetchedResultsChangeDelete
                     newIndexPath:nil];
    }

    // ---- Apply insertions (binary-search, sorted) --------------------------

    for (var i = 0; i < [toInsert count]; i++)
    {
        var insObj = [toInsert objectAtIndex:i];
        [self _insertObjectIntoFetchedObjects:insObj];
        [_recentlyInserted addObject:insObj];
        var newIP = [self indexPathForObject:insObj];
        if (   _delegate
            && [_delegate respondsToSelector:@selector(controller:didChangeObject:atIndexPath:forChangeType:newIndexPath:)]
           )
            [_delegate controller:self
                  didChangeObject:insObj
                      atIndexPath:nil
                    forChangeType:CPFetchedResultsChangeInsert
                     newIndexPath:newIP];
    }

    // ---- Process updates (move vs update) ----------------------------------

    for (var i = 0; i < [toUpdate count]; i++)
    {
        var updObj = [toUpdate objectAtIndex:i];
        var oldIP  = [self indexPathForObject:updObj];

        // Compute where the object *should* be given its current values
        var desiredIdx = [self _sortedInsertionIndexForObject:updObj
                                             usingDescriptors:[_fetchRequest sortDescriptors]
                                                       inArray:_fetchedObjects
                                             excludingObject:updObj];
        var currentIdx = [_fetchedObjects indexOfObject:updObj];

        if (desiredIdx !== currentIdx)
        {
            // Move: remove and re-insert at the correct position
            [_fetchedObjects removeObjectAtIndex:currentIdx];
            // Adjust desired index if it shifted due to the removal
            var insertIdx = desiredIdx;
            if (desiredIdx > currentIdx)
                insertIdx = desiredIdx - 1;
            [_fetchedObjects insertObject:updObj atIndex:insertIdx];

            var newIP = [self indexPathForObject:updObj];
            if (   _delegate
                && [_delegate respondsToSelector:@selector(controller:didChangeObject:atIndexPath:forChangeType:newIndexPath:)]
               )
                [_delegate controller:self
                      didChangeObject:updObj
                          atIndexPath:oldIP
                        forChangeType:CPFetchedResultsChangeMove
                         newIndexPath:newIP];
        }
        else
        {
            if (   _delegate
                && [_delegate respondsToSelector:@selector(controller:didChangeObject:atIndexPath:forChangeType:newIndexPath:)]
               )
                [_delegate controller:self
                      didChangeObject:updObj
                          atIndexPath:oldIP
                        forChangeType:CPFetchedResultsChangeUpdate
                         newIndexPath:oldIP];
        }
    }

    // ---- Rebuild sections and fire section callbacks -----------------------

    // Snapshot the old sections BEFORE rebuilding so we can pass the correct
    // section info object to the delete callback.
    var oldSections = _sections ? [CPArray arrayWithArray:_sections] : [CPArray array];
    var oldSectionNames = [[CPMutableArray alloc] init];
    for (var i = 0; i < [oldSections count]; i++)
        [oldSectionNames addObject:[[oldSections objectAtIndex:i] name]];

    [self _rebuildSections];

    var newSectionNames = [[CPMutableArray alloc] init];
    for (var i = 0; i < [_sections count]; i++)
        [newSectionNames addObject:[[_sections objectAtIndex:i] name]];

    if (   _delegate
        && [_delegate respondsToSelector:@selector(controller:didChangeSection:atIndex:forChangeType:)]
       )
    {
        // Deleted sections — use the old section info from the snapshot
        for (var i = 0; i < [oldSectionNames count]; i++)
        {
            var sname = [oldSectionNames objectAtIndex:i];
            if ([newSectionNames indexOfObject:sname] === CPNotFound)
            {
                var oldInfo = [oldSections objectAtIndex:i];
                [_delegate controller:self
                     didChangeSection:oldInfo
                               atIndex:i
                         forChangeType:CPFetchedResultsChangeDelete];
            }
        }

        // Inserted sections
        for (var i = 0; i < [newSectionNames count]; i++)
        {
            var sname = [newSectionNames objectAtIndex:i];
            if ([oldSectionNames indexOfObject:sname] === CPNotFound)
            {
                [_delegate controller:self
                     didChangeSection:[_sections objectAtIndex:i]
                               atIndex:i
                         forChangeType:CPFetchedResultsChangeInsert];
            }
        }
    }

    // ---- Notify: did change ------------------------------------------------

    if (   _delegate
        && [_delegate respondsToSelector:@selector(controllerDidChangeContent:)]
       )
        [_delegate controllerDidChangeContent:self];
}

- (void)_contextDidSave:(CPNotification)notification
{
    // The context was saved — objects previously tracked as "recently inserted"
    // are now persisted, so subsequent update notifications for them should be
    // treated as normal updates and reported to the delegate.
    [_recentlyInserted removeAllObjects];
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/*!
    Returns YES if \c anObject belongs to the entity specified by the fetch
    request and satisfies any predicate set on the fetch request.
*/
- (BOOL)_objectMatchesFetchRequest:(id)anObject
{
    if (![anObject isKindOfClass:[CPManagedObject class]])
        return NO;

    var requestEntity = [_fetchRequest entity];
    if (requestEntity !== nil && ![[anObject entity] isEqual:requestEntity])
        return NO;

    var predicate = [_fetchRequest predicate];
    if (predicate !== nil && ![predicate evaluateWithObject:anObject])
        return NO;

    return YES;
}

/*!
    Insert \c anObject into \c _fetchedObjects at the position dictated by the
    fetch request's sort descriptors (binary-search insertion).
*/
- (void)_insertObjectIntoFetchedObjects:(id)anObject
{
    var idx = [self _sortedInsertionIndexForObject:anObject
                                  usingDescriptors:[_fetchRequest sortDescriptors]
                                            inArray:_fetchedObjects
                                  excludingObject:nil];
    [_fetchedObjects insertObject:anObject atIndex:idx];
}

/*!
    Remove the first occurrence of \c anObject from \c _fetchedObjects.
*/
- (void)_removeObjectFromFetchedObjects:(id)anObject
{
    var idx = [_fetchedObjects indexOfObject:anObject];
    if (idx !== CPNotFound)
        [_fetchedObjects removeObjectAtIndex:idx];
}

/*!
    Binary-search for the insertion index that maintains sort order.

    When \c excludingObject is non-nil the object is logically removed from
    the array before computing the insertion position (used when repositioning
    an existing object after an update).

    Returns an index in [0, count] suitable for insertObject:atIndex:.
*/
- (CPInteger)_sortedInsertionIndexForObject:(id)anObject
                           usingDescriptors:(CPArray)descriptors
                                     inArray:(CPArray)array
                           excludingObject:(id)excluded
{
    if (descriptors === nil || [descriptors count] === 0)
        return [array count];

    var lo = 0;
    var hi = [array count];

    while (lo < hi)
    {
        var mid    = Math.floor((lo + hi) / 2);
        var midObj = [array objectAtIndex:mid];
        if (midObj === excluded || (excluded !== nil && [midObj isEqual:excluded]))
        {
            // Skip excluded object — step past it
            if (mid + 1 < hi)
                mid = mid + 1;
            else
            {
                hi = mid;
                break;
            }
            midObj = [array objectAtIndex:mid];
        }

        var order = CPOrderedSame;
        for (var d = 0; d < [descriptors count]; d++)
        {
            var desc    = [descriptors objectAtIndex:d];
            var sortKey = [desc key];
            var aVal    = [anObject valueForKeyPath:sortKey];
            var mVal    = [midObj   valueForKeyPath:sortKey];
            if (aVal === nil || aVal === undefined ||
                mVal === nil || mVal === undefined)
                break;
            // NOTE: Cappuccino uses compareObject:withObject: rather than Apple's compareObject:toObject:
            order = [desc compareObject:anObject withObject:midObj];
            if (order !== CPOrderedSame)
                break;
        }

        if (order === CPOrderedAscending)
            hi = mid;
        else
            lo = mid + 1;
    }

    return lo;
}

/*!
    Rebuild \c _sections by grouping \c _fetchedObjects according to
    \c _sectionNameKeyPath.  When \c _sectionNameKeyPath is nil a single
    unnamed section is created.
*/
- (void)_rebuildSections
{
    _sections = [[CPMutableArray alloc] init];

    if (_fetchedObjects === nil || [_fetchedObjects count] === 0)
    {
        if (_sectionNameKeyPath === nil)
        {
            // Keep one empty section so consumers always see at least one section
            [_sections addObject:[[CPFetchedResultsSectionInfo alloc] initWithName:@""]];
        }
        return;
    }

    if (_sectionNameKeyPath === nil)
    {
        var section = [[CPFetchedResultsSectionInfo alloc] initWithName:@""];
        [section setObjects:[CPMutableArray arrayWithArray:_fetchedObjects]];
        [_sections addObject:section];
        return;
    }

    var currentName    = nil;
    var currentSection = nil;

    for (var i = 0; i < [_fetchedObjects count]; i++)
    {
        var obj       = [_fetchedObjects objectAtIndex:i];
        var sectionName = [obj valueForKeyPath:_sectionNameKeyPath];
        if (sectionName === nil || sectionName === undefined)
            sectionName = @"";

        if (currentSection === nil || ![currentName isEqual:sectionName])
        {
            currentSection = [[CPFetchedResultsSectionInfo alloc] initWithName:sectionName];
            currentName    = sectionName;
            [_sections addObject:currentSection];
        }

        [[currentSection objects] addObject:obj];
    }
}

@end
